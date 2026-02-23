from __future__ import annotations

from datetime import datetime, timedelta
import csv
import io
import json
import logging
from functools import wraps
from django.contrib import messages

# Dashboard auth (OTP + staff) — keep legacy decorator names used in this file.
from .auth import dashboard_staff_required as staff_member_required
from .auth import dashboard_login_required as login_required
from django.core.exceptions import PermissionDenied, ValidationError
from django.core.paginator import Paginator
from django.db.models import Count, Q
from django.db.models.functions import TruncDate
from django.http import HttpRequest, HttpResponse
from django.shortcuts import get_object_or_404, render
from django.shortcuts import redirect
from django.urls import reverse
from django.utils.timezone import make_aware
from django.utils import timezone
from django.views.decorators.http import require_POST

from apps.marketplace.models import ServiceRequest
from apps.marketplace.services.actions import allowed_actions, execute_action
from apps.providers.models import ProviderProfile, ProviderService, Category, SubCategory
from apps.providers.models import ProviderPortfolioItem
from apps.accounts.models import User
from apps.messaging.models import Message
from apps.reviews.models import Review
from apps.support.models import SupportTicket, SupportTicketStatus, SupportTeam
from apps.support.models import SupportTicketType
from apps.support.services import change_ticket_status, assign_ticket
from apps.billing.models import Invoice, InvoiceStatus, PaymentAttempt
from apps.verification.models import VerificationRequest, VerificationStatus, VerificationDocument
from apps.verification.services import finalize_request_and_create_invoice, activate_after_payment as activate_verification_after_payment
from apps.subscriptions.models import Subscription, SubscriptionStatus
from apps.subscriptions.services import refresh_subscription_status, activate_subscription_after_payment
from apps.promo.models import PromoRequest, PromoRequestStatus
from apps.promo.models import PromoAdPrice, PromoAdType
from apps.promo.services import quote_and_create_invoice, reject_request, activate_after_payment as activate_promo_after_payment
from apps.extras.models import ExtraPurchase, ExtraPurchaseStatus
from apps.extras.services import activate_extra_after_payment
from apps.features.checks import has_feature
from apps.features.upload_limits import user_max_upload_mb
from apps.backoffice.models import AccessLevel, Dashboard, UserAccessProfile
from apps.audit.models import AuditAction
from apps.audit.services import log_action
from apps.unified_requests.models import UnifiedRequest, UnifiedRequestStatus, UnifiedRequestType
from .forms import AcceptAssignProviderForm, CategoryForm, SubCategoryForm

# إن كانت عندك Enums استوردها (عدّل حسب مشروعك)
try:
    from apps.marketplace.models import RequestStatus, RequestType
except Exception:
    RequestStatus = None
    RequestType = None


logger = logging.getLogger(__name__)


def _bool_param(v: str | None) -> bool | None:
    if v is None:
        return None
    v = v.strip().lower()
    if v in {"1", "true", "yes", "y", "on"}:
        return True
    if v in {"0", "false", "no", "n", "off"}:
        return False
    return None


def _parse_date_yyyy_mm_dd(value: str | None):
    """Parse 'YYYY-MM-DD' to aware datetime at 00:00. Returns None if invalid."""
    if not value:
        return None
    try:
        dt = datetime.strptime(value.strip(), "%Y-%m-%d")
        return timezone.make_aware(dt, timezone.get_current_timezone())
    except Exception:
        return None


def _parse_datetime_local(value: str | None):
    """Parse HTML datetime-local value (YYYY-MM-DDTHH:MM) to aware datetime."""
    if not value:
        return None
    raw = value.strip()
    if not raw:
        return None
    for fmt in ("%Y-%m-%dT%H:%M", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M"):
        try:
            dt = datetime.strptime(raw, fmt)
            return make_aware(dt)
        except Exception:
            continue
    return None


def _csv_response(filename: str, headers: list[str], rows: list[list]):
    stream = io.StringIO()
    writer = csv.writer(stream)
    writer.writerow(headers)
    for r in rows:
        writer.writerow(r)
    resp = HttpResponse(stream.getvalue(), content_type="text/csv; charset=utf-8")
    resp["Content-Disposition"] = f'attachment; filename="{filename}"'
    return resp


def _want_csv(request: HttpRequest) -> bool:
    return (request.GET.get("export") or "").strip().lower() == "csv"


def _want_xlsx(request: HttpRequest) -> bool:
    v = (request.GET.get("export") or "").strip().lower()
    return v in {"xlsx", "excel"}


def _want_pdf(request: HttpRequest) -> bool:
    return (request.GET.get("export") or "").strip().lower() == "pdf"




def _dashboard_allowed(user, dashboard_code: str, write: bool = False) -> bool:
    if not getattr(user, "is_authenticated", False):
        return False
    if getattr(user, "is_superuser", False):
        return True
    if not getattr(user, "is_staff", False):
        return False

    ap = getattr(user, "access_profile", None)
    if not ap:
        return False

    if ap.is_revoked() or ap.is_expired():
        return False
    if write and ap.is_readonly():
        return False
    if ap.level in {"admin", "power"}:
        return True
    return ap.is_allowed(dashboard_code)


def _is_active_admin_profile(ap: UserAccessProfile) -> bool:
    if ap.level != AccessLevel.ADMIN:
        return False
    if ap.revoked_at is not None:
        return False
    if ap.expires_at and ap.expires_at <= timezone.now():
        return False
    return True


def _active_admin_profiles_count() -> int:
    now = timezone.now()
    return UserAccessProfile.objects.filter(
        level=AccessLevel.ADMIN,
        revoked_at__isnull=True,
    ).filter(
        Q(expires_at__isnull=True) | Q(expires_at__gt=now),
    ).count()


def dashboard_access_required(dashboard_code: str, write: bool = False):
    def _first_allowed_dashboard(user) -> str | None:
        candidates = [
            ("analytics", "dashboard:home"),
            ("content", "dashboard:requests_list"),
            ("billing", "dashboard:billing_invoices_list"),
            ("support", "dashboard:support_tickets_list"),
            ("verify", "dashboard:verification_requests_list"),
            ("promo", "dashboard:promo_requests_list"),
            ("subs", "dashboard:subscriptions_list"),
            ("extras", "dashboard:extras_list"),
            ("access", "dashboard:access_profiles_list"),
        ]
        for code, route in candidates:
            if _dashboard_allowed(user, code, write=False):
                return route
        return None

    def decorator(func):
        @wraps(func)
        def wrapped(request: HttpRequest, *args, **kwargs):
            if not _dashboard_allowed(request.user, dashboard_code, write=write):
                messages.error(request, "لا تملك صلاحية الوصول لهذه اللوحة.")
                fallback = _first_allowed_dashboard(request.user)
                current = getattr(getattr(request, "resolver_match", None), "view_name", "")
                if fallback and fallback != current:
                    return redirect(fallback)
                return HttpResponse("غير مصرح", status=403)
            return func(request, *args, **kwargs)
        return wrapped
    return decorator


def _status_value(name: str, fallback: str) -> str:
    """يحاول جلب قيمة الحالة من RequestStatus إن وجد، وإلا يستخدم fallback."""
    if RequestStatus:
        return getattr(RequestStatus, name, fallback)
    return fallback


def _type_value(name: str, fallback: str) -> str:
    if RequestType:
        return getattr(RequestType, name, fallback)
    return fallback


def _unified_request_dashboard_link(obj: UnifiedRequest) -> str:
    source_app = (obj.source_app or "").strip().lower()
    source_model = (obj.source_model or "").strip().lower()
    source_id = (obj.source_object_id or "").strip()
    if not source_id:
        return ""
    try:
        sid = int(source_id)
    except Exception:
        sid = None

    if source_app == "support" and source_model == "supportticket" and sid is not None:
        return reverse("dashboard:support_ticket_detail", args=[sid])
    if source_app == "verification" and source_model == "verificationrequest" and sid is not None:
        return reverse("dashboard:verification_request_detail", args=[sid])
    if source_app == "promo" and source_model == "promorequest" and sid is not None:
        return reverse("dashboard:promo_request_detail", args=[sid])
    if source_app == "subscriptions":
        q = getattr(getattr(obj, "requester", None), "phone", "") or ""
        return f"{reverse('dashboard:subscriptions_list')}?q={q}" if q else reverse("dashboard:subscriptions_list")
    if source_app == "extras":
        q = getattr(getattr(obj, "requester", None), "phone", "") or ""
        return f"{reverse('dashboard:extras_list')}?q={q}" if q else reverse("dashboard:extras_list")
    return ""


def _unified_request_source_dashboard_code(obj: UnifiedRequest) -> str:
    return {
        "support": "support",
        "verification": "verify",
        "promo": "promo",
        "subscriptions": "subs",
        "extras": "extras",
    }.get((obj.source_app or "").strip().lower(), "")


def _unified_request_quick_links(user, obj: UnifiedRequest, metadata_payload: dict) -> list[dict]:
    links: list[dict] = []
    source_url = _unified_request_dashboard_link(obj)
    source_dashboard_code = _unified_request_source_dashboard_code(obj)
    if source_url and source_dashboard_code:
        ap = getattr(user, "access_profile", None)
        allowed = bool(
            getattr(user, "is_superuser", False)
            or (
                ap
                and not ap.is_revoked()
                and not ap.is_expired()
                and (
                    ap.level in (AccessLevel.ADMIN, AccessLevel.POWER)
                    or ap.allowed_dashboards.filter(code=source_dashboard_code, is_active=True).exists()
                )
            )
        )
        if allowed:
            links.append({"label": "المصدر الأصلي", "url": source_url})
    elif source_url:
        links.append({"label": "المصدر الأصلي", "url": source_url})

    invoice_id = metadata_payload.get("invoice_id") if isinstance(metadata_payload, dict) else None
    if invoice_id not in (None, "") and _dashboard_allowed(user, "billing", write=False):
        try:
            inv = Invoice.objects.filter(id=int(invoice_id)).only("id", "code").first()
            if inv:
                q = (inv.code or str(inv.id)).strip()
                url = reverse("dashboard:billing_invoices_list")
                if q:
                    url = f"{url}?q={q}"
                links.append({"label": "الفاتورة", "url": url, "value": inv.code or str(inv.id)})
        except Exception:
            pass

    requester = getattr(obj, "requester", None)
    if requester and getattr(requester, "phone", None):
        phone = requester.phone
        if _dashboard_allowed(user, "content", write=False):
            links.append({
                "label": "طلبات العميل",
                "url": f"{reverse('dashboard:requests_list')}?q={phone}",
                "value": phone,
            })
            provider_profile = ProviderProfile.objects.filter(user_id=requester.id).only("id").first()
            if provider_profile:
                links.append({
                    "label": "ملف مقدم الخدمة",
                    "url": reverse("dashboard:provider_detail", args=[provider_profile.id]),
                })
        if _dashboard_allowed(user, "billing", write=False):
            links.append({
                "label": "فوترة العميل",
                "url": f"{reverse('dashboard:billing_invoices_list')}?q={phone}",
                "value": phone,
            })
        if obj.request_type == UnifiedRequestType.SUBSCRIPTION and _dashboard_allowed(user, "subs", write=False):
            links.append({
                "label": "اشتراكات العميل",
                "url": f"{reverse('dashboard:subscriptions_list')}?q={phone}",
            })
        if obj.request_type == UnifiedRequestType.EXTRAS and _dashboard_allowed(user, "extras", write=False):
            links.append({
                "label": "خدمات إضافية للعميل",
                "url": f"{reverse('dashboard:extras_list')}?q={phone}",
            })

    # Keep deterministic output and avoid duplicate URLs.
    seen = set()
    uniq = []
    for link in links:
        key = (link.get("label"), link.get("url"))
        if not link.get("url") or key in seen:
            continue
        seen.add(key)
        uniq.append(link)
    return uniq


@staff_member_required
@dashboard_access_required("analytics")
def unified_request_detail(request: HttpRequest, unified_request_id: int) -> HttpResponse:
    obj = get_object_or_404(
        UnifiedRequest.objects.select_related("requester", "assigned_user")
        .prefetch_related(
            "status_logs__changed_by",
            "assignment_logs__from_user",
            "assignment_logs__to_user",
            "assignment_logs__changed_by",
        ),
        id=unified_request_id,
    )
    metadata_record = getattr(obj, "metadata_record", None)
    metadata_payload = getattr(metadata_record, "payload", {}) or {}
    source_url = _unified_request_dashboard_link(obj)
    source_dashboard_code = _unified_request_source_dashboard_code(obj)
    if source_url and source_dashboard_code:
        ap = getattr(request.user, "access_profile", None)
        allowed = bool(
            getattr(request.user, "is_superuser", False)
            or (
                ap
                and not ap.is_revoked()
                and not ap.is_expired()
                and (
                    ap.level in (AccessLevel.ADMIN, AccessLevel.POWER)
                    or ap.allowed_dashboards.filter(code=source_dashboard_code, is_active=True).exists()
                )
            )
        )
        if not allowed:
            source_url = ""
    quick_links = _unified_request_quick_links(request.user, obj, metadata_payload)
    return render(
        request,
        "dashboard/unified_request_detail.html",
        {
            "ur": obj,
            "metadata_payload": metadata_payload,
            "metadata_record": metadata_record,
            "source_url": source_url,
            "quick_links": quick_links,
            "status_logs": obj.status_logs.all(),
            "assignment_logs": obj.assignment_logs.all(),
        },
    )


@staff_member_required
@dashboard_access_required("analytics")
def unified_requests_list(request: HttpRequest) -> HttpResponse:
    qs = UnifiedRequest.objects.select_related("requester", "assigned_user").all().order_by("-id")
    q = (request.GET.get("q") or "").strip()
    type_val = (request.GET.get("type") or "").strip()
    status_val = (request.GET.get("status") or "").strip()
    team_val = (request.GET.get("team") or "").strip()
    assignee_val = (request.GET.get("assignee") or "").strip()
    has_invoice_val = (request.GET.get("has_invoice") or "").strip()
    has_assignee_val = (request.GET.get("has_assignee") or "").strip()
    open_only_val = (request.GET.get("open_only") or "").strip()
    preset_val = (request.GET.get("preset") or "").strip().lower()
    date_from = _parse_date_yyyy_mm_dd(request.GET.get("from"))
    date_to = _parse_date_yyyy_mm_dd(request.GET.get("to"))

    if q:
        qs = qs.filter(
            Q(code__icontains=q)
            | Q(summary__icontains=q)
            | Q(requester__phone__icontains=q)
            | Q(source_object_id__icontains=q)
        )
    if type_val:
        qs = qs.filter(request_type=type_val)
    if status_val:
        qs = qs.filter(status=status_val)
    if team_val:
        qs = qs.filter(assigned_team_code=team_val)
    if assignee_val == "__unassigned__":
        qs = qs.filter(assigned_user__isnull=True)
    elif assignee_val:
        try:
            qs = qs.filter(assigned_user_id=int(assignee_val))
        except Exception:
            pass
    if preset_val == "pending_payment":
        qs = qs.filter(status=UnifiedRequestStatus.PENDING_PAYMENT)
    elif preset_val == "unassigned":
        qs = qs.filter(assigned_user__isnull=True)
    elif preset_val == "open_unassigned":
        qs = qs.filter(
            assigned_user__isnull=True,
            status__in=[
                UnifiedRequestStatus.NEW,
                UnifiedRequestStatus.IN_PROGRESS,
                UnifiedRequestStatus.RETURNED,
            ],
        )
    has_invoice_bool = _bool_param(has_invoice_val)
    if has_invoice_bool is True:
        qs = qs.filter(metadata_record__payload__invoice_id__isnull=False).exclude(metadata_record__payload__invoice_id="")
    elif has_invoice_bool is False:
        qs = qs.filter(
            Q(metadata_record__isnull=True)
            | Q(metadata_record__payload__invoice_id__isnull=True)
            | Q(metadata_record__payload__invoice_id="")
        )
    has_assignee_bool = _bool_param(has_assignee_val)
    if has_assignee_bool is True:
        qs = qs.filter(assigned_user__isnull=False)
    elif has_assignee_bool is False:
        qs = qs.filter(assigned_user__isnull=True)
    if _bool_param(open_only_val) is True:
        qs = qs.filter(
            status__in=[
                UnifiedRequestStatus.NEW,
                UnifiedRequestStatus.IN_PROGRESS,
                UnifiedRequestStatus.RETURNED,
            ]
        )
    if date_from:
        qs = qs.filter(created_at__gte=date_from)
    if date_to:
        qs = qs.filter(created_at__lt=(date_to + timedelta(days=1)))

    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == "user":
        qs = qs.filter(Q(assigned_user=request.user) | Q(assigned_user__isnull=True))

    filtered_summary = {
        "total": qs.count(),
        "open": qs.filter(
            status__in=[
                UnifiedRequestStatus.NEW,
                UnifiedRequestStatus.IN_PROGRESS,
                UnifiedRequestStatus.RETURNED,
            ]
        ).count(),
        "pending_payment": qs.filter(status=UnifiedRequestStatus.PENDING_PAYMENT).count(),
        "active": qs.filter(status=UnifiedRequestStatus.ACTIVE).count(),
        "unassigned": qs.filter(assigned_user__isnull=True).count(),
    }
    filtered_type_counts = {
        "helpdesk": qs.filter(request_type=UnifiedRequestType.HELPDESK).count(),
        "verification": qs.filter(request_type=UnifiedRequestType.VERIFICATION).count(),
        "promo": qs.filter(request_type=UnifiedRequestType.PROMO).count(),
        "subscription": qs.filter(request_type=UnifiedRequestType.SUBSCRIPTION).count(),
        "extras": qs.filter(request_type=UnifiedRequestType.EXTRAS).count(),
    }

    if _want_xlsx(request) or _want_pdf(request) or _want_csv(request):
        headers_ar = [
            "الكود",
            "النوع",
            "الحالة",
            "الأولوية",
            "الطالب",
            "الفريق",
            "المكلّف",
            "المرجع",
            "الملخص",
            "إجراءات",
        ]
        export_rows = []
        for r in qs[:5000]:
            unified_detail_path = reverse("dashboard:unified_request_detail", args=[r.id])
            source_path = _unified_request_dashboard_link(r)
            reference = f"{r.source_app}.{r.source_model}#{r.source_object_id}" if r.source_app else "—"
            actions = f"تفاصيل موحدة: {unified_detail_path}"
            if source_path:
                actions = f"{actions} | فتح المصدر: {source_path}"
            export_rows.append(
                [
                    r.code or r.id,
                    r.get_request_type_display(),
                    r.get_status_display(),
                    r.get_priority_display(),
                    getattr(getattr(r, "requester", None), "phone", "—") or "—",
                    r.assigned_team_name or r.assigned_team_code or "—",
                    getattr(getattr(r, "assigned_user", None), "phone", "—") or "—",
                    reference,
                    r.summary or "—",
                    actions,
                ]
            )

        if _want_csv(request):
            return _csv_response("unified_requests.csv", headers_ar, export_rows)

        from .exports import pdf_response, xlsx_response

        if _want_xlsx(request):
            return xlsx_response("unified_requests.xlsx", "الطلبات الموحدة", headers_ar, export_rows)
        return pdf_response("unified_requests.pdf", "الطلبات الموحدة", headers_ar, export_rows, landscape=True)

    staff_users = User.objects.filter(is_staff=True).order_by("-id")[:150]
    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    for row in page_obj.object_list:
        row.dashboard_detail_url = _unified_request_dashboard_link(row)
        row.unified_detail_url = reverse("dashboard:unified_request_detail", args=[row.id])
    return render(
        request,
        "dashboard/unified_requests_list.html",
        {
            "page_obj": page_obj,
            "q": q,
            "type_val": type_val,
            "status_val": status_val,
            "team_val": team_val,
              "assignee_val": assignee_val,
              "has_invoice_val": has_invoice_val,
              "has_assignee_val": has_assignee_val,
              "open_only_val": open_only_val,
              "preset_val": preset_val,
              "date_from_val": (request.GET.get("from") or "").strip(),
            "date_to_val": (request.GET.get("to") or "").strip(),
              "type_choices": UnifiedRequestType.choices,
              "status_choices": UnifiedRequestStatus.choices,
              "staff_users": staff_users,
              "filtered_summary": filtered_summary,
              "filtered_type_counts": filtered_type_counts,
          },
      )


def _compute_actions(user, obj) -> dict:
    user_id = getattr(user, "id", None)
    status = (obj.status or "").lower()

    has_profile = False
    if status == "sent" and user_id:
        is_staff = bool(getattr(user, "is_staff", False))
        is_client = obj.client_id == user_id
        if not is_staff and not is_client:
            has_profile = ProviderProfile.objects.filter(user_id=user_id).exists()

    acts = allowed_actions(user, obj, has_provider_profile=has_profile)

    return {
        "can_accept": "accept" in acts,
        "can_start": "start" in acts,
        "can_complete": "complete" in acts,
        "can_cancel": "cancel" in acts,
        "can_send": "send" in acts,
    }


@staff_member_required
@dashboard_access_required("analytics")
def dashboard_home(request):
    qs = ServiceRequest.objects.all()

    # KPIs عامة للطلبات
    total = qs.count()
    by_status = qs.values("status").annotate(c=Count("id")).order_by("-c")
    by_type = qs.values("request_type").annotate(c=Count("id")).order_by("-c")
    open_statuses = [
        _status_value("NEW", "new"),
        _status_value("SENT", "sent"),
        _status_value("ACCEPTED", "accepted"),
        _status_value("IN_PROGRESS", "in_progress"),
    ]
    open_requests = qs.filter(status__in=open_statuses).count()
    completed_requests = qs.filter(status=_status_value("COMPLETED", "completed")).count()
    cancelled_requests = qs.filter(status=_status_value("CANCELLED", "cancelled")).count()

    # آخر 10 طلبات
    latest = (
        qs.select_related("client", "provider")
        .order_by("-id")[:12]
    )

    # KPIs المزوّدين
    providers_qs = ProviderProfile.objects.all()
    total_providers = providers_qs.count()
    verified_providers = providers_qs.filter(
        Q(is_verified_blue=True) | Q(is_verified_green=True)
    ).count()
    urgent_providers = providers_qs.filter(accepts_urgent=True).count()

    # KPIs الفوترة (اختياري حسب التطبيقات المثبتة)
    pending_invoices = 0
    paid_invoices = 0
    failed_invoices = 0
    try:
        from apps.billing.models import Invoice, InvoiceStatus

        pending_invoices = Invoice.objects.filter(status=InvoiceStatus.PENDING).count()
        paid_invoices = Invoice.objects.filter(status=InvoiceStatus.PAID).count()
        failed_invoices = Invoice.objects.filter(status=InvoiceStatus.FAILED).count()
    except Exception:
        pass

    # KPIs التذاكر
    support_new = 0
    support_open = 0
    try:
        from apps.support.models import SupportTicket, SupportTicketStatus

        support_new = SupportTicket.objects.filter(status=SupportTicketStatus.NEW).count()
        support_open = SupportTicket.objects.exclude(status=SupportTicketStatus.CLOSED).count()
    except Exception:
        pass

    # KPIs التفعيل/الاشتراكات
    active_subscriptions = 0
    pending_verifications = 0
    active_promos = 0
    active_extras = 0
    try:
        from apps.subscriptions.models import Subscription, SubscriptionStatus

        active_subscriptions = Subscription.objects.filter(
            status=SubscriptionStatus.ACTIVE
        ).count()
    except Exception:
        pass
    try:
        from apps.verification.models import VerificationRequest, VerificationStatus

        pending_verifications = VerificationRequest.objects.filter(
            status__in=[VerificationStatus.NEW, VerificationStatus.IN_REVIEW, VerificationStatus.PENDING_PAYMENT]
        ).count()
    except Exception:
        pass
    try:
        from apps.promo.models import PromoRequest, PromoRequestStatus

        active_promos = PromoRequest.objects.filter(
            status=PromoRequestStatus.ACTIVE
        ).count()
    except Exception:
        pass
    try:
        from apps.extras.models import ExtraPurchase, ExtraPurchaseStatus

        active_extras = ExtraPurchase.objects.filter(
            status=ExtraPurchaseStatus.ACTIVE
        ).count()
    except Exception:
        pass

    # KPIs الطلبات الموحدة (الطبقة التشغيلية الموحدة)
    unified_qs = UnifiedRequest.objects.select_related("requester", "assigned_user").all()
    unified_total = unified_qs.count()
    unified_open = unified_qs.exclude(
        status__in=[
            UnifiedRequestStatus.CLOSED,
            UnifiedRequestStatus.COMPLETED,
            UnifiedRequestStatus.REJECTED,
            UnifiedRequestStatus.EXPIRED,
            UnifiedRequestStatus.CANCELLED,
        ]
    ).count()
    unified_pending_payment = unified_qs.filter(status=UnifiedRequestStatus.PENDING_PAYMENT).count()
    unified_active = unified_qs.filter(status=UnifiedRequestStatus.ACTIVE).count()
    unified_recent = list(unified_qs.order_by("-id")[:8])
    for ur in unified_recent:
        ur.dashboard_detail_url = _unified_request_dashboard_link(ur)

    status_labels = dict(getattr(RequestStatus, "choices", []) or [])
    type_labels = dict(getattr(RequestType, "choices", []) or [])

    for r in latest:
        r.status_label = status_labels.get(getattr(r, "status", ""), getattr(r, "status", "") or "—")
        r.type_label = type_labels.get(getattr(r, "request_type", ""), getattr(r, "request_type", "") or "—")

    # Trend charts (last 14 days)
    days = 14
    start_date = timezone.now().date() - timedelta(days=days - 1)
    labels = [(start_date + timedelta(days=i)).isoformat() for i in range(days)]

    req_by_day = {
        str(row["day"]): row["c"]
        for row in (
            ServiceRequest.objects.filter(created_at__date__gte=start_date)
            .annotate(day=TruncDate("created_at"))
            .values("day")
            .annotate(c=Count("id"))
            .order_by("day")
        )
    }
    inv_by_day = {
        str(row["day"]): row["c"]
        for row in (
            Invoice.objects.filter(created_at__date__gte=start_date)
            .annotate(day=TruncDate("created_at"))
            .values("day")
            .annotate(c=Count("id"))
            .order_by("day")
        )
    }
    sup_by_day = {
        str(row["day"]): row["c"]
        for row in (
            SupportTicket.objects.filter(created_at__date__gte=start_date)
            .annotate(day=TruncDate("created_at"))
            .values("day")
            .annotate(c=Count("id"))
            .order_by("day")
        )
    }
    unified_by_day = {
        str(row["day"]): row["c"]
        for row in (
            UnifiedRequest.objects.filter(created_at__date__gte=start_date)
            .annotate(day=TruncDate("created_at"))
            .values("day")
            .annotate(c=Count("id"))
            .order_by("day")
        )
    }

    request_series = [req_by_day.get(d, 0) for d in labels]
    invoice_series = [inv_by_day.get(d, 0) for d in labels]
    support_series = [sup_by_day.get(d, 0) for d in labels]
    unified_request_series = [unified_by_day.get(d, 0) for d in labels]

    ctx = {
        "total_requests": total,
        "open_requests": open_requests,
        "completed_requests": completed_requests,
        "cancelled_requests": cancelled_requests,
        "by_status": list(by_status),
        "by_type": list(by_type),
        "latest_requests": latest,
        "total_providers": total_providers,
        "verified_providers": verified_providers,
        "urgent_providers": urgent_providers,
        "pending_invoices": pending_invoices,
        "paid_invoices": paid_invoices,
        "failed_invoices": failed_invoices,
        "support_new": support_new,
        "support_open": support_open,
        "active_subscriptions": active_subscriptions,
        "pending_verifications": pending_verifications,
        "active_promos": active_promos,
        "active_extras": active_extras,
        "unified_total_requests": unified_total,
        "unified_open_requests": unified_open,
        "unified_pending_payment_requests": unified_pending_payment,
        "unified_active_requests": unified_active,
        "unified_recent_requests": unified_recent,
        "dashboard_now": timezone.now(),
        "chart_labels_json": json.dumps(labels, ensure_ascii=False),
        "request_series_json": json.dumps(request_series),
        "invoice_series_json": json.dumps(invoice_series),
        "support_series_json": json.dumps(support_series),
        "unified_request_series_json": json.dumps(unified_request_series),
        "can_content": _dashboard_allowed(request.user, "content", write=False),
        "can_billing": _dashboard_allowed(request.user, "billing", write=False),
        "can_support": _dashboard_allowed(request.user, "support", write=False),
        "can_verify": _dashboard_allowed(request.user, "verify", write=False),
        "can_promo": _dashboard_allowed(request.user, "promo", write=False),
        "can_subs": _dashboard_allowed(request.user, "subs", write=False),
        "can_access_mgmt": _dashboard_allowed(request.user, "access", write=False),
    }
    return render(request, "dashboard/home.html", ctx)


@staff_member_required
@dashboard_access_required("content")
def requests_list(request):
    qs = (
        ServiceRequest.objects
        .select_related("client", "provider")
        .all()
        .order_by("-id")
    )

    # -------- Filters --------
    q = (request.GET.get("q") or "").strip()
    status_val = (request.GET.get("status") or "").strip()
    type_val = (request.GET.get("type") or "").strip()
    city = (request.GET.get("city") or "").strip()
    date_from = _parse_date_yyyy_mm_dd(request.GET.get("from"))
    date_to = _parse_date_yyyy_mm_dd(request.GET.get("to"))

    if q:
        # بحث آمن على العنوان/الوصف/جوال العميل (إن وجد)
        qs = qs.filter(
            Q(title__icontains=q) |
            Q(description__icontains=q) |
            Q(client__phone__icontains=q)
        )

    if status_val:
        qs = qs.filter(status=status_val)

    if type_val:
        qs = qs.filter(request_type=type_val)

    if city:
        qs = qs.filter(city__icontains=city)

    if date_from:
        qs = qs.filter(created_at__gte=date_from)

    if date_to:
        # Inclusive end-date: include full selected day.
        qs = qs.filter(created_at__lt=(date_to + timedelta(days=1)))

    if _want_xlsx(request) or _want_pdf(request) or _want_csv(request):
        headers_ar = ["#", "العنوان", "النوع", "الحالة", "المدينة", "العميل", "المزوّد", "إجراءات"]

        def _row(r: ServiceRequest):
            provider_name = getattr(getattr(r, "provider", None), "display_name", "")
            detail_path = f"/dashboard/requests/{r.id}/"
            return [
                r.id,
                (r.title or "—"),
                getattr(r, "request_type", "") or "—",
                getattr(r, "status", "") or "—",
                (r.city or "—"),
                getattr(getattr(r, "client", None), "phone", "—") or "—",
                (provider_name or "—"),
                detail_path,
            ]

        export_rows = [_row(r) for r in qs[:2000]]

        if _want_csv(request):
            return _csv_response("requests.csv", headers_ar, export_rows)

        from .exports import pdf_response, xlsx_response

        if _want_xlsx(request):
            return xlsx_response("requests.xlsx", "الطلبات", headers_ar, export_rows)

        return pdf_response("requests.pdf", "الطلبات", headers_ar, export_rows, landscape=True)

    # -------- Pagination --------
    page_size = 20
    paginator = Paginator(qs, page_size)
    page_number = request.GET.get("page") or "1"
    page_obj = paginator.get_page(page_number)

    # خيارات فلاتر (لو عندك Enums استخدمها، وإلا اعرض الموجود)
    if RequestStatus:
        status_choices = getattr(RequestStatus, "choices", None) or []
    else:
        status_choices = []

    if RequestType:
        type_choices = getattr(RequestType, "choices", None) or []
    else:
        type_choices = []

    ctx = {
        "page_obj": page_obj,
        "q": q,
        "status_val": status_val,
        "type_val": type_val,
        "city": city,
        "from": request.GET.get("from") or "",
        "to": request.GET.get("to") or "",
        "status_choices": status_choices,
        "type_choices": type_choices,
    }
    return render(request, "dashboard/requests_list.html", ctx)


@staff_member_required
@dashboard_access_required("content")
def providers_list(request: HttpRequest) -> HttpResponse:
    qs = (
        ProviderProfile.objects
        .select_related("user")
        .all()
        .order_by("-id")
    )

    q = (request.GET.get("q") or "").strip()
    city = (request.GET.get("city") or "").strip()
    verified = _bool_param(request.GET.get("verified"))
    accepts_urgent = _bool_param(request.GET.get("urgent"))

    if q:
        qs = qs.filter(
            Q(display_name__icontains=q)
            | Q(user__phone__icontains=q)
            | Q(bio__icontains=q)
        )

    if city:
        qs = qs.filter(city__icontains=city)

    if verified is not None:
        if verified:
            qs = qs.filter(Q(is_verified_blue=True) | Q(is_verified_green=True))
        else:
            qs = qs.filter(is_verified_blue=False, is_verified_green=False)

    if accepts_urgent is not None:
        qs = qs.filter(accepts_urgent=accepts_urgent)

    if _want_csv(request):
        rows = [
            [
                p.id,
                p.display_name or "",
                getattr(getattr(p, "user", None), "phone", ""),
                p.city or "",
                bool(p.is_verified_blue or p.is_verified_green),
                bool(p.accepts_urgent),
                p.rating_avg,
                p.rating_count,
            ]
            for p in qs[:2000]
        ]
        return _csv_response(
            "providers.csv",
            ["id", "display_name", "phone", "city", "verified", "accepts_urgent", "rating_avg", "rating_count"],
            rows,
        )

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")

    ctx = {
        "page_obj": page_obj,
        "q": q,
        "city": city,
        "verified": request.GET.get("verified") or "",
        "urgent": request.GET.get("urgent") or "",
    }
    return render(request, "dashboard/providers_list.html", ctx)


@staff_member_required
@dashboard_access_required("content")
def provider_detail(request: HttpRequest, provider_id: int) -> HttpResponse:
    provider = get_object_or_404(
        ProviderProfile.objects.select_related("user"),
        id=provider_id,
    )

    services = (
        ProviderService.objects
        .select_related("subcategory", "subcategory__category")
        .filter(provider_id=provider_id)
        .order_by("-updated_at")
    )

    ctx = {
        "provider": provider,
        "services": list(services),
    }
    return render(request, "dashboard/provider_detail.html", ctx)


@staff_member_required
@dashboard_access_required("content", write=True)
@require_POST
def provider_service_toggle_active(request: HttpRequest, provider_id: int, service_id: int) -> HttpResponse:
    service = get_object_or_404(
        ProviderService,
        id=service_id,
        provider_id=provider_id,
    )
    service.is_active = not bool(service.is_active)
    service.save(update_fields=["is_active", "updated_at"])
    messages.success(request, "تم تحديث حالة الخدمة بنجاح")
    return redirect("dashboard:provider_detail", provider_id=provider_id)


@staff_member_required
@dashboard_access_required("content")
def services_list(request: HttpRequest) -> HttpResponse:
    qs = (
        ProviderService.objects
        .select_related("provider", "provider__user", "subcategory", "subcategory__category")
        .all()
        .order_by("-updated_at")
    )

    q = (request.GET.get("q") or "").strip()
    active = _bool_param(request.GET.get("active"))
    city = (request.GET.get("city") or "").strip()

    if q:
        qs = qs.filter(
            Q(title__icontains=q)
            | Q(description__icontains=q)
            | Q(provider__display_name__icontains=q)
            | Q(provider__user__phone__icontains=q)
        )

    if active is not None:
        qs = qs.filter(is_active=active)

    if city:
        qs = qs.filter(provider__city__icontains=city)

    if _want_csv(request):
        rows = [
            [
                s.id,
                s.title or "",
                getattr(getattr(s, "provider", None), "display_name", ""),
                getattr(getattr(getattr(s, "provider", None), "user", None), "phone", ""),
                getattr(getattr(s, "subcategory", None), "name", ""),
                bool(s.is_active),
                s.updated_at.isoformat() if s.updated_at else "",
            ]
            for s in qs[:2000]
        ]
        return _csv_response(
            "provider_services.csv",
            ["id", "title", "provider", "provider_phone", "subcategory", "is_active", "updated_at"],
            rows,
        )

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")

    ctx = {
        "page_obj": page_obj,
        "q": q,
        "active": request.GET.get("active") or "",
        "city": city,
    }
    return render(request, "dashboard/services_list.html", ctx)


@staff_member_required
@dashboard_access_required("content")
def request_detail(request, request_id: int):
    qs = ServiceRequest.objects
    try:
        qs = qs.select_related("client", "provider", "subcategory")
    except Exception:
        qs = qs.select_related("client", "provider")

    obj = (
        qs.filter(id=request_id)
        .first()
    )
    if not obj:
        obj = get_object_or_404(ServiceRequest, id=request_id)

    # ---- محاولات تحميل بيانات مرتبطة (حسب توفر موديلاتك) ----
    offers = []
    thread = None
    thread_messages = None
    notifications_page = None
    review = None

    # Offers (إن كان تطبيق marketplace يحتوي Offer)
    try:
        from apps.marketplace.models import Offer

        offers = (
            Offer.objects
            .select_related("provider")
            .filter(request=obj)
            .order_by("-id")
        )
    except Exception:
        offers = []

    # Messaging Thread + Messages
    try:
        from apps.messaging.models import Thread, Message

        thread = Thread.objects.filter(request=obj).first()
        if thread:
            # نعرض آخر 30 رسالة فقط (سهل وسريع للويب)
            thread_messages = (
                Message.objects
                .select_related("sender")
                .filter(thread=thread)
                .order_by("-id")[:30]
            )
    except Exception:
        thread = None
        thread_messages = None

    # Notifications مرتبطة بالطلب (لو عندك ربط content_object أو request FK)
    try:
        from apps.notifications.models import Notification

        # إن كان عندك request FK:
        has_request_fk = False
        try:
            has_request_fk = any(f.name == "request" for f in Notification._meta.fields)
        except Exception:
            has_request_fk = hasattr(Notification, "request")

        if has_request_fk:
            notifications_page = (
                Notification.objects
                .filter(request=obj)
                .order_by("-id")[:30]
            )
        else:
            # fallback: نحاول نبحث نصيًا عن رقم الطلب في الرسالة (اختياري)
            notifications_page = (
                Notification.objects
                .filter(Q(title__icontains=str(obj.id)) | Q(body__icontains=str(obj.id)))
                .order_by("-id")[:30]
            )
    except Exception:
        notifications_page = None

    # Review (إن كان عندك Review OneToOne مع الطلب)
    try:
        from apps.reviews.models import Review

        review = Review.objects.filter(request=obj).first()
    except Exception:
        review = None

    tab = (request.GET.get("tab") or "details").strip()
    allowed_tabs = {"details", "offers", "chat", "notifications", "review"}
    if tab not in allowed_tabs:
        tab = "details"

    ctx = {
        "obj": obj,
        "tab": tab,
        "offers": offers,
        "thread": thread,
        "thread_messages": thread_messages,
        "notifications": notifications_page,
        "review": review,
    }
    providers = None
    if request.user.is_staff:
        providers = ProviderProfile.objects.select_related("user").order_by("id")

    ctx.update({
        "providers": providers,
    })
    ctx["actions"] = _compute_actions(request.user, obj)
    return render(request, "dashboard/request_detail.html", ctx)


@login_required
@dashboard_access_required("content", write=True)
@require_POST
def request_accept(request: HttpRequest, request_id: int) -> HttpResponse:
    sr = get_object_or_404(ServiceRequest, id=request_id)
    try:
        user = request.user
        is_staff = bool(getattr(user, "is_staff", False))

        provider_profile = None

        if is_staff:
            # staff must choose provider from form
            form = AcceptAssignProviderForm(request.POST)
            if not form.is_valid():
                messages.warning(request, "اختر مزودًا لقبول الطلب")
                return redirect("dashboard:request_detail", request_id=sr.id)

            provider_profile = form.cleaned_data["provider"]
        else:
            # provider accepts using his own profile
            provider_profile = ProviderProfile.objects.filter(user=user).first()

        result = execute_action(
            user=user,
            request_id=sr.id,
            action="accept",
            provider_profile=provider_profile,
        )
        messages.success(request, result.message)
    except PermissionDenied:
        messages.error(request, "غير مصرح بتنفيذ هذا الإجراء")
    except ValidationError as e:
        msg = getattr(e, "message", None)
        if not msg and getattr(e, "messages", None):
            msg = e.messages[0]
        messages.warning(request, msg or "لا يمكن تنفيذ الإجراء")
    except Exception:
        logger.exception("dashboard request_accept error")
        messages.error(request, "حدث خطأ غير متوقع")
    return redirect("dashboard:request_detail", request_id=sr.id)


@login_required
@dashboard_access_required("content", write=True)
@require_POST
def request_start(request: HttpRequest, request_id: int) -> HttpResponse:
    sr = get_object_or_404(ServiceRequest, id=request_id)
    try:
        provider_profile = ProviderProfile.objects.filter(user=request.user).first()
        result = execute_action(
            user=request.user,
            request_id=sr.id,
            action="start",
            provider_profile=provider_profile,
        )
        messages.success(request, result.message)
    except PermissionDenied:
        messages.error(request, "غير مصرح بتنفيذ هذا الإجراء")
    except ValidationError as e:
        msg = getattr(e, "message", None)
        if not msg and getattr(e, "messages", None):
            msg = e.messages[0]
        messages.warning(request, msg or "لا يمكن تنفيذ الإجراء")
    except Exception:
        logger.exception("dashboard request_start error")
        messages.error(request, "حدث خطأ غير متوقع")
    return redirect("dashboard:request_detail", request_id=sr.id)


@login_required
@dashboard_access_required("content", write=True)
@require_POST
def request_complete(request: HttpRequest, request_id: int) -> HttpResponse:
    sr = get_object_or_404(ServiceRequest, id=request_id)
    try:
        provider_profile = ProviderProfile.objects.filter(user=request.user).first()
        result = execute_action(
            user=request.user,
            request_id=sr.id,
            action="complete",
            provider_profile=provider_profile,
        )
        messages.success(request, result.message)
    except PermissionDenied:
        messages.error(request, "غير مصرح بتنفيذ هذا الإجراء")
    except ValidationError as e:
        msg = getattr(e, "message", None)
        if not msg and getattr(e, "messages", None):
            msg = e.messages[0]
        messages.warning(request, msg or "لا يمكن تنفيذ الإجراء")
    except Exception:
        logger.exception("dashboard request_complete error")
        messages.error(request, "حدث خطأ غير متوقع")
    return redirect("dashboard:request_detail", request_id=sr.id)


@login_required
@dashboard_access_required("content", write=True)
@require_POST
def request_cancel(request: HttpRequest, request_id: int) -> HttpResponse:
    sr = get_object_or_404(ServiceRequest, id=request_id)
    try:
        provider_profile = ProviderProfile.objects.filter(user=request.user).first()
        result = execute_action(
            user=request.user,
            request_id=sr.id,
            action="cancel",
            provider_profile=provider_profile,
        )
        messages.success(request, result.message)
    except PermissionDenied:
        messages.error(request, "غير مصرح بتنفيذ هذا الإجراء")
    except ValidationError as e:
        msg = getattr(e, "message", None)
        if not msg and getattr(e, "messages", None):
            msg = e.messages[0]
        messages.warning(request, msg or "لا يمكن تنفيذ الإجراء")
    except Exception:
        logger.exception("dashboard request_cancel error")
        messages.error(request, "حدث خطأ غير متوقع")
    return redirect("dashboard:request_detail", request_id=sr.id)


@login_required
@dashboard_access_required("content", write=True)
@require_POST
def request_send(request: HttpRequest, request_id: int) -> HttpResponse:
    sr = get_object_or_404(ServiceRequest, id=request_id)
    try:
        provider_profile = ProviderProfile.objects.filter(user=request.user).first()
        result = execute_action(
            user=request.user,
            request_id=sr.id,
            action="send",
            provider_profile=provider_profile,
        )
        messages.success(request, result.message)
    except PermissionDenied:
        messages.error(request, "غير مصرح بتنفيذ هذا الإجراء")
    except ValidationError as e:
        msg = getattr(e, "message", None)
        if not msg and getattr(e, "messages", None):
            msg = e.messages[0]
        messages.warning(request, msg or "لا يمكن تنفيذ الإجراء")
    except Exception:
        logger.exception("dashboard request_send error")
        messages.error(request, "حدث خطأ غير متوقع")
    return redirect("dashboard:request_detail", request_id=sr.id)


# =============================================================================
# Categories & Subcategories Management
# =============================================================================

@staff_member_required
@dashboard_access_required("content")
def categories_list(request: HttpRequest) -> HttpResponse:
    """عرض قائمة التصنيفات الرئيسية مع التصنيفات الفرعية"""
    q = request.GET.get("q", "").strip()
    active = request.GET.get("active", "").strip()

    categories = Category.objects.all()

    # البحث
    if q:
        categories = categories.filter(name__icontains=q)

    # فلتر الحالة
    if active:
        is_active = _bool_param(active)
        if is_active is not None:
            categories = categories.filter(is_active=is_active)

    # عدد التصنيفات الفرعية
    categories = categories.annotate(subcategories_count=Count("subcategories"))

    # الترتيب
    categories = categories.order_by("-is_active", "name")

    if _want_csv(request):
        rows = [
            [c.id, c.name, bool(c.is_active), c.subcategories_count]
            for c in categories[:2000]
        ]
        return _csv_response(
            "categories.csv",
            ["id", "name", "is_active", "subcategories_count"],
            rows,
        )

    # Pagination
    paginator = Paginator(categories, 25)
    page_number = request.GET.get("page", 1)
    page_obj = paginator.get_page(page_number)

    return render(
        request,
        "dashboard/categories_list.html",
        {
            "page_obj": page_obj,
            "q": q,
            "active": active,
        },
    )


@staff_member_required
@dashboard_access_required("content")
def category_detail(request: HttpRequest, category_id: int) -> HttpResponse:
    """عرض تفاصيل تصنيف رئيسي مع جميع التصنيفات الفرعية"""
    category = get_object_or_404(Category, id=category_id)
    subcategories = category.subcategories.all().order_by("-is_active", "name")

    return render(
        request,
        "dashboard/category_detail.html",
        {
            "category": category,
            "subcategories": subcategories,
        },
    )


@staff_member_required
@dashboard_access_required("content", write=True)
@require_POST
def category_toggle_active(request: HttpRequest, category_id: int) -> HttpResponse:
    """تفعيل/إيقاف تصنيف رئيسي"""
    category = get_object_or_404(Category, id=category_id)
    category.is_active = not category.is_active
    category.save()
    
    status = "مفعّل" if category.is_active else "موقوف"
    messages.success(request, f"تم تحديث حالة التصنيف إلى: {status}")
    
    return redirect("dashboard:category_detail", category_id=category.id)


@staff_member_required
@dashboard_access_required("content", write=True)
@require_POST
def subcategory_toggle_active(
    request: HttpRequest, category_id: int, subcategory_id: int
) -> HttpResponse:
    """تفعيل/إيقاف تصنيف فرعي"""
    category = get_object_or_404(Category, id=category_id)
    subcategory = get_object_or_404(SubCategory, id=subcategory_id, category=category)
    
    subcategory.is_active = not subcategory.is_active
    subcategory.save()
    
    status = "مفعّل" if subcategory.is_active else "موقوف"
    messages.success(request, f"تم تحديث حالة التصنيف الفرعي إلى: {status}")
    
    return redirect("dashboard:category_detail", category_id=category.id)


@staff_member_required
@dashboard_access_required("content", write=True)
def category_create(request: HttpRequest) -> HttpResponse:
    """إضافة تصنيف رئيسي جديد"""
    if request.method == "POST":
        form = CategoryForm(request.POST)
        if form.is_valid():
            category = form.save()
            messages.success(request, f"تم إضافة التصنيف '{category.name}' بنجاح")
            return redirect("dashboard:category_detail", category_id=category.id)
    else:
        form = CategoryForm()
    
    return render(
        request,
        "dashboard/category_form.html",
        {
            "form": form,
            "title": "إضافة تصنيف رئيسي",
            "is_edit": False,
        },
    )


@staff_member_required
@dashboard_access_required("content", write=True)
def category_edit(request: HttpRequest, category_id: int) -> HttpResponse:
    """تعديل تصنيف رئيسي"""
    category = get_object_or_404(Category, id=category_id)
    
    if request.method == "POST":
        form = CategoryForm(request.POST, instance=category)
        if form.is_valid():
            category = form.save()
            messages.success(request, f"تم تحديث التصنيف '{category.name}' بنجاح")
            return redirect("dashboard:category_detail", category_id=category.id)
    else:
        form = CategoryForm(instance=category)
    
    return render(
        request,
        "dashboard/category_form.html",
        {
            "form": form,
            "category": category,
            "title": "تعديل التصنيف",
            "is_edit": True,
        },
    )


@staff_member_required
@dashboard_access_required("content", write=True)
def subcategory_create(request: HttpRequest) -> HttpResponse:
    """إضافة تصنيف فرعي جديد"""
    category_id = request.GET.get("category")
    
    if request.method == "POST":
        form = SubCategoryForm(request.POST)
        if form.is_valid():
            subcategory = form.save()
            messages.success(request, f"تم إضافة التصنيف الفرعي '{subcategory.name}' بنجاح")
            return redirect("dashboard:category_detail", category_id=subcategory.category.id)
    else:
        initial = {}
        if category_id:
            try:
                initial['category'] = int(category_id)
            except ValueError:
                pass
        form = SubCategoryForm(initial=initial)
    
    return render(
        request,
        "dashboard/subcategory_form.html",
        {
            "form": form,
            "title": "إضافة تصنيف فرعي",
            "is_edit": False,
        },
    )


@staff_member_required
@dashboard_access_required("content", write=True)
def subcategory_edit(request: HttpRequest, subcategory_id: int) -> HttpResponse:
    """تعديل تصنيف فرعي"""
    subcategory = get_object_or_404(SubCategory, id=subcategory_id)
    
    if request.method == "POST":
        form = SubCategoryForm(request.POST, instance=subcategory)
        if form.is_valid():
            subcategory = form.save()
            messages.success(request, f"تم تحديث التصنيف الفرعي '{subcategory.name}' بنجاح")
            return redirect("dashboard:category_detail", category_id=subcategory.category.id)
    else:
        form = SubCategoryForm(instance=subcategory)
    
    return render(
        request,
        "dashboard/subcategory_form.html",
        {
            "form": form,
            "subcategory": subcategory,
            "title": "تعديل التصنيف الفرعي",
            "is_edit": True,
        },
    )


# =============================================================================
# Operations / Full Platform Management
# =============================================================================

@staff_member_required
@dashboard_access_required("billing")
def billing_invoices_list(request: HttpRequest) -> HttpResponse:
    qs = Invoice.objects.select_related("user").all().order_by("-id")
    q = (request.GET.get("q") or "").strip()
    status_val = (request.GET.get("status") or "").strip()
    ref_type = (request.GET.get("ref_type") or "").strip()
    if q:
        qs = qs.filter(Q(code__icontains=q) | Q(user__phone__icontains=q) | Q(title__icontains=q))
    if status_val:
        qs = qs.filter(status=status_val)
    if ref_type:
        qs = qs.filter(reference_type__icontains=ref_type)

    if _want_xlsx(request) or _want_pdf(request) or _want_csv(request):
        headers_ar = ["الكود", "العميل", "العنوان", "الإجمالي", "الحالة", "المرجع", "محاولات", "إجراءات", "تاريخ"]

        export_rows = []
        for inv in qs[:2000]:
            code = inv.code or inv.id
            phone = getattr(getattr(inv, "user", None), "phone", "—") or "—"
            total_str = f"{inv.total} {inv.currency}".strip()
            status_label = getattr(inv, "get_status_display", lambda: inv.status)()
            ref_str = f"{inv.reference_type or '—'} / {inv.reference_id or '—'}"
            attempts = 0
            try:
                attempts = inv.attempts.count()
            except Exception:
                attempts = 0
            detail_action = "—"
            created = inv.created_at
            created_str = created.strftime("%Y-%m-%d %H:%M") if created else "—"
            export_rows.append(
                [
                    code,
                    phone,
                    inv.title or "—",
                    total_str or "—",
                    status_label or "—",
                    ref_str,
                    attempts,
                    detail_action,
                    created_str,
                ]
            )

        if _want_csv(request):
            return _csv_response("billing_invoices.csv", headers_ar, export_rows)

        from .exports import pdf_response, xlsx_response

        if _want_xlsx(request):
            return xlsx_response("billing_invoices.xlsx", "الفوترة", headers_ar, export_rows)
        return pdf_response("billing_invoices.pdf", "إدارة الفوترة", headers_ar, export_rows, landscape=True)

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    return render(
        request,
        "dashboard/billing_invoices_list.html",
        {
            "page_obj": page_obj,
            "q": q,
            "status_val": status_val,
            "ref_type": ref_type,
            "status_choices": InvoiceStatus.choices,
            "can_write": _dashboard_allowed(request.user, "billing", write=True),
        },
    )


@staff_member_required
@dashboard_access_required("billing", write=True)
@require_POST
def billing_invoice_set_status_action(request: HttpRequest, invoice_id: int) -> HttpResponse:
    invoice = get_object_or_404(Invoice, id=invoice_id)
    action = (request.POST.get("action") or "").strip().lower()

    if action == "mark_paid":
        invoice.mark_paid()
        invoice.cancelled_at = None
        invoice.save(update_fields=["status", "paid_at", "cancelled_at", "updated_at"])
        messages.success(request, f"تم تعليم الفاتورة {invoice.code or invoice.id} كمدفوعة")
    elif action == "mark_unpaid":
        invoice.status = InvoiceStatus.PENDING
        invoice.paid_at = None
        invoice.cancelled_at = None
        invoice.save(update_fields=["status", "paid_at", "cancelled_at", "updated_at"])
        messages.success(request, f"تم تعليم الفاتورة {invoice.code or invoice.id} كغير مدفوعة")
    else:
        messages.warning(request, "إجراء غير صالح")

    next_url = (request.POST.get("next") or "").strip()
    if next_url:
        return redirect(next_url)
    return redirect("dashboard:billing_invoices_list")


@staff_member_required
@dashboard_access_required("support")
def support_tickets_list(request: HttpRequest) -> HttpResponse:
    qs = (
        SupportTicket.objects.select_related("requester", "assigned_team", "assigned_to")
        .all()
        .order_by("-id")
    )
    q = (request.GET.get("q") or "").strip()
    status_val = (request.GET.get("status") or "").strip()
    type_val = (request.GET.get("type") or "").strip()
    priority_val = (request.GET.get("priority") or "").strip()
    if q:
        qs = qs.filter(Q(code__icontains=q) | Q(requester__phone__icontains=q) | Q(description__icontains=q))
    if status_val:
        qs = qs.filter(status=status_val)
    if type_val:
        qs = qs.filter(ticket_type=type_val)
    if priority_val:
        qs = qs.filter(priority=priority_val)

    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == "user":
        qs = qs.filter(Q(assigned_to=request.user) | Q(assigned_to__isnull=True))

    if _want_xlsx(request) or _want_pdf(request) or _want_csv(request):
        headers_ar = ["الكود", "العميل", "النوع", "الأولوية", "الحالة", "الفريق", "المكلّف", "إجراءات"]
        export_rows = []
        for t in qs[:2000]:
            code = t.code or t.id
            phone = getattr(getattr(t, "requester", None), "phone", "—") or "—"
            type_label = getattr(t, "get_ticket_type_display", lambda: t.ticket_type)() or "—"
            priority_label = getattr(t, "get_priority_display", lambda: t.priority)() or "—"
            status_label = getattr(t, "get_status_display", lambda: t.status)() or "—"
            team = getattr(getattr(t, "assigned_team", None), "name_ar", "—") or "—"
            assignee = getattr(getattr(t, "assigned_to", None), "phone", "—") or "—"
            detail_path = f"/dashboard/support/{t.id}/"
            export_rows.append([code, phone, type_label, priority_label, status_label, team, assignee, detail_path])

        if _want_csv(request):
            return _csv_response("support_tickets.csv", headers_ar, export_rows)

        from .exports import pdf_response, xlsx_response

        if _want_xlsx(request):
            return xlsx_response("support_tickets.xlsx", "الدعم", headers_ar, export_rows)
        return pdf_response("support_tickets.pdf", "إدارة الدعم", headers_ar, export_rows, landscape=True)

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    return render(
        request,
        "dashboard/support_tickets_list.html",
        {
            "page_obj": page_obj,
            "q": q,
            "status_val": status_val,
            "type_val": type_val,
            "priority_val": priority_val,
            "status_choices": SupportTicketStatus.choices,
            "type_choices": SupportTicket._meta.get_field("ticket_type").choices,
            "priority_choices": SupportTicket._meta.get_field("priority").choices,
        },
    )


@staff_member_required
@dashboard_access_required("support")
def support_ticket_detail(request: HttpRequest, ticket_id: int) -> HttpResponse:
    ticket = get_object_or_404(
        SupportTicket.objects.select_related("requester", "assigned_team", "assigned_to", "last_action_by"),
        id=ticket_id,
    )

    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == "user" and ticket.assigned_to_id is not None and ticket.assigned_to_id != request.user.id:
        return HttpResponse("غير مصرح", status=403)
    comments = ticket.comments.select_related("created_by").order_by("-id")
    logs = ticket.status_logs.select_related("changed_by").order_by("-id")
    teams = SupportTeam.objects.filter(is_active=True).order_by("sort_order", "id")
    staff_users = User.objects.filter(is_staff=True).order_by("-id")[:150]

    can_write = _dashboard_allowed(request.user, "support", write=True)

    reported_user_profile_url = ""
    reported_user = getattr(ticket, "reported_user", None)
    if reported_user:
        provider_profile = ProviderProfile.objects.filter(user_id=reported_user.id).only("id").first()
        if provider_profile:
            reported_user_profile_url = reverse("dashboard:provider_detail", args=[provider_profile.id])

    reported_target_label = ""
    reported_target_url = ""
    reported_kind = (getattr(ticket, "reported_kind", "") or "").strip().lower()
    reported_object_id = (getattr(ticket, "reported_object_id", "") or "").strip()
    try:
        reported_pk = int(reported_object_id) if reported_object_id else None
    except Exception:
        reported_pk = None

    if reported_kind and reported_pk is not None:
        if reported_kind == "review":
            r = Review.objects.filter(id=reported_pk).select_related("request").only("id", "request_id").first()
            reported_target_label = f"تقييم #{reported_pk}"
            if r and r.request_id:
                reported_target_url = reverse("dashboard:request_detail", args=[r.request_id])
        elif reported_kind == "message":
            reported_target_label = f"تعليق/رسالة #{reported_pk}"
        elif reported_kind == "portfolio_item":
            item = ProviderPortfolioItem.objects.filter(id=reported_pk).only("id", "provider_id").first()
            reported_target_label = f"محتوى (Portfolio) #{reported_pk}"
            if item and item.provider_id:
                reported_target_url = reverse("dashboard:provider_detail", args=[item.provider_id])
        elif reported_kind == "service":
            svc = ProviderService.objects.filter(id=reported_pk).only("id", "provider_id").first()
            reported_target_label = f"محتوى (خدمة) #{reported_pk}"
            if svc and svc.provider_id:
                reported_target_url = reverse("dashboard:provider_detail", args=[svc.provider_id])
        else:
            reported_target_label = f"{reported_kind} #{reported_pk}"

    return render(
        request,
        "dashboard/support_ticket_detail.html",
        {
            "ticket": ticket,
            "comments": comments,
            "logs": logs,
            "teams": teams,
            "staff_users": staff_users,
            "status_choices": SupportTicketStatus.choices,
            "can_write": can_write,
            "reported_user_profile_url": reported_user_profile_url,
            "reported_target_label": reported_target_label,
            "reported_target_url": reported_target_url,
        },
    )


@staff_member_required
@dashboard_access_required("promo")
def promo_inquiries_list(request: HttpRequest) -> HttpResponse:
    """Promo inquiries are SupportTickets of type ADS.

    This is intentionally separate from promo requests (PromoRequest).
    """

    qs = (
        SupportTicket.objects.select_related("requester", "assigned_team", "assigned_to")
        .filter(ticket_type=SupportTicketType.ADS)
        .order_by("-id")
    )
    q = (request.GET.get("q") or "").strip()
    status_val = (request.GET.get("status") or "").strip()
    priority_val = (request.GET.get("priority") or "").strip()
    if q:
        qs = qs.filter(Q(code__icontains=q) | Q(requester__phone__icontains=q) | Q(description__icontains=q))
    if status_val:
        qs = qs.filter(status=status_val)
    if priority_val:
        qs = qs.filter(priority=priority_val)

    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == "user":
        qs = qs.filter(Q(assigned_to=request.user) | Q(assigned_to__isnull=True))

    if _want_xlsx(request) or _want_pdf(request) or _want_csv(request):
        headers_ar = ["الكود", "العميل", "الأولوية", "الحالة", "الفريق", "المكلّف", "إجراءات"]
        export_rows = []
        for t in qs[:2000]:
            code = t.code or t.id
            phone = getattr(getattr(t, "requester", None), "phone", "—") or "—"
            priority_label = getattr(t, "get_priority_display", lambda: t.priority)() or "—"
            status_label = getattr(t, "get_status_display", lambda: t.status)() or "—"
            team = getattr(getattr(t, "assigned_team", None), "name_ar", "—") or "—"
            assignee = getattr(getattr(t, "assigned_to", None), "phone", "—") or "—"
            detail_path = f"/dashboard/support/{t.id}/"
            export_rows.append([code, phone, priority_label, status_label, team, assignee, detail_path])

        if _want_csv(request):
            return _csv_response("promo_inquiries.csv", headers_ar, export_rows)

        from .exports import pdf_response, xlsx_response

        if _want_xlsx(request):
            return xlsx_response("promo_inquiries.xlsx", "استفسارات الترويج", headers_ar, export_rows)
        return pdf_response("promo_inquiries.pdf", "استفسارات الترويج", headers_ar, export_rows, landscape=True)

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    return render(
        request,
        "dashboard/promo_inquiries_list.html",
        {
            "page_obj": page_obj,
            "q": q,
            "status_val": status_val,
            "priority_val": priority_val,
            "status_choices": SupportTicketStatus.choices,
            "priority_choices": SupportTicket._meta.get_field("priority").choices,
        },
    )


@staff_member_required
@dashboard_access_required("promo")
def promo_pricing(request: HttpRequest) -> HttpResponse:
    rows = {p.ad_type: p for p in PromoAdPrice.objects.all()}
    data = []
    for ad_type, label in PromoAdType.choices:
        obj = rows.get(ad_type)
        data.append(
            {
                "ad_type": ad_type,
                "label": label,
                "price_per_day": getattr(obj, "price_per_day", None),
                "is_active": bool(getattr(obj, "is_active", True)) if obj else True,
            }
        )
    return render(request, "dashboard/promo_pricing.html", {"rows": data})


@staff_member_required
@dashboard_access_required("promo", write=True)
@require_POST
def promo_pricing_update_action(request: HttpRequest) -> HttpResponse:
    ad_type = (request.POST.get("ad_type") or "").strip()
    raw_price = (request.POST.get("price_per_day") or "").strip()
    is_active = (request.POST.get("is_active") or "").strip().lower() in {"1", "true", "on", "yes"}

    if ad_type not in PromoAdType.values:
        messages.error(request, "نوع الإعلان غير صحيح")
        return redirect("dashboard:promo_pricing")

    try:
        from decimal import Decimal

        price = Decimal(raw_price)
        if price < 0:
            raise ValueError
    except Exception:
        messages.error(request, "السعر غير صحيح")
        return redirect("dashboard:promo_pricing")

    PromoAdPrice.objects.update_or_create(ad_type=ad_type, defaults={"price_per_day": price, "is_active": is_active})
    messages.success(request, "تم حفظ التسعير")
    return redirect("dashboard:promo_pricing")


@staff_member_required
@dashboard_access_required("support", write=True)
@require_POST
def support_ticket_delete_reported_object_action(request: HttpRequest, ticket_id: int) -> HttpResponse:
    ticket = get_object_or_404(SupportTicket.objects.select_related("reported_user"), id=ticket_id)

    reported_kind = (getattr(ticket, "reported_kind", "") or "").strip().lower()
    reported_object_id = (getattr(ticket, "reported_object_id", "") or "").strip()
    try:
        reported_pk = int(reported_object_id) if reported_object_id else None
    except Exception:
        reported_pk = None

    if ticket.ticket_type != "complaint":
        messages.error(request, "هذه التذكرة ليست شكوى/بلاغ")
        return redirect("dashboard:support_ticket_detail", ticket_id=ticket.id)

    if not reported_kind or reported_pk is None:
        messages.error(request, "لا توجد بيانات للعنصر محل الشكوى")
        return redirect("dashboard:support_ticket_detail", ticket_id=ticket.id)

    deleted = False
    try:
        if reported_kind == "review":
            obj = Review.objects.filter(id=reported_pk).first()
            if obj:
                obj.delete()
                deleted = True
        elif reported_kind == "message":
            obj = Message.objects.filter(id=reported_pk).first()
            if obj:
                obj.delete()
                deleted = True
        elif reported_kind == "portfolio_item":
            obj = ProviderPortfolioItem.objects.filter(id=reported_pk).first()
            if obj:
                obj.delete()
                deleted = True
        elif reported_kind == "service":
            obj = ProviderService.objects.filter(id=reported_pk).first()
            if obj:
                obj.delete()
                deleted = True
        else:
            messages.error(request, "نوع العنصر محل الشكوى غير مدعوم")
            return redirect("dashboard:support_ticket_detail", ticket_id=ticket.id)
    except Exception:
        logger.exception("support_ticket_delete_reported_object_action error")
        messages.error(request, "تعذر حذف المحتوى محل الشكوى")
        return redirect("dashboard:support_ticket_detail", ticket_id=ticket.id)

    if not deleted:
        messages.warning(request, "العنصر غير موجود أو تم حذفه مسبقًا")
        return redirect("dashboard:support_ticket_detail", ticket_id=ticket.id)

    # Keep an internal trail on the ticket.
    try:
        from apps.support.models import SupportComment

        SupportComment.objects.create(
            ticket=ticket,
            text=f"تم حذف المحتوى محل الشكوى: {reported_kind}#{reported_pk}",
            is_internal=True,
            created_by=request.user,
        )
    except Exception:
        logger.exception("support_ticket_delete_reported_object_action comment error")

    # Clear reported target to prevent accidental re-delete attempts.
    ticket.reported_kind = ""
    ticket.reported_object_id = ""
    ticket.save(update_fields=["reported_kind", "reported_object_id", "updated_at"])

    messages.success(request, "تم حذف المحتوى محل الشكوى نهائيًا")
    return redirect("dashboard:support_ticket_detail", ticket_id=ticket.id)


@staff_member_required
@dashboard_access_required("support", write=True)
@require_POST
def support_ticket_assign_action(request: HttpRequest, ticket_id: int) -> HttpResponse:
    ticket = get_object_or_404(SupportTicket, id=ticket_id)

    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == "user" and ticket.assigned_to_id is not None and ticket.assigned_to_id != request.user.id:
        return HttpResponse("غير مصرح", status=403)
    team_id = request.POST.get("assigned_team") or None
    assigned_to = request.POST.get("assigned_to") or None
    note = (request.POST.get("note") or "").strip()
    try:
        team_id = int(team_id) if team_id else None
    except Exception:
        team_id = None
    try:
        assigned_to = int(assigned_to) if assigned_to else None
    except Exception:
        assigned_to = None

    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == "user":
        if assigned_to is not None and assigned_to != request.user.id:
            return HttpResponse("غير مصرح", status=403)
    try:
        assign_ticket(
            ticket=ticket,
            team_id=team_id,
            user_id=assigned_to,
            by_user=request.user,
            note=note,
        )
        messages.success(request, "تم تحديث التعيين بنجاح")
    except Exception:
        logger.exception("support_ticket_assign_action error")
        messages.error(request, "تعذر تحديث التعيين")
    return redirect("dashboard:support_ticket_detail", ticket_id=ticket.id)


@staff_member_required
@dashboard_access_required("support", write=True)
@require_POST
def support_ticket_status_action(request: HttpRequest, ticket_id: int) -> HttpResponse:
    ticket = get_object_or_404(SupportTicket, id=ticket_id)

    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == "user" and ticket.assigned_to_id is not None and ticket.assigned_to_id != request.user.id:
        return HttpResponse("غير مصرح", status=403)
    status_new = (request.POST.get("status") or "").strip()
    note = (request.POST.get("note") or "").strip()
    if not status_new:
        messages.warning(request, "اختر حالة التذكرة")
        return redirect("dashboard:support_ticket_detail", ticket_id=ticket.id)
    try:
        change_ticket_status(ticket=ticket, new_status=status_new, by_user=request.user, note=note)
        messages.success(request, "تم تحديث حالة التذكرة")
    except Exception:
        logger.exception("support_ticket_status_action error")
        messages.error(request, "تعذر تحديث الحالة")
    return redirect("dashboard:support_ticket_detail", ticket_id=ticket.id)


@staff_member_required
@dashboard_access_required("verify")
def verification_requests_list(request: HttpRequest) -> HttpResponse:
    qs = VerificationRequest.objects.select_related("requester", "invoice", "assigned_to").all().order_by("-id")
    q = (request.GET.get("q") or "").strip()
    status_val = (request.GET.get("status") or "").strip()
    if q:
        qs = qs.filter(Q(code__icontains=q) | Q(requester__phone__icontains=q))
    if status_val:
        qs = qs.filter(status=status_val)

    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == "user":
        qs = qs.filter(Q(assigned_to=request.user) | Q(assigned_to__isnull=True))

    if _want_xlsx(request) or _want_pdf(request) or _want_csv(request):
        headers_ar = ["الكود", "المستخدم", "نوع الشارة", "الحالة", "فاتورة", "إجراءات"]
        export_rows = []
        for vr in qs[:2000]:
            code = vr.code or vr.id
            phone = getattr(getattr(vr, "requester", None), "phone", "—") or "—"
            badge = getattr(vr, "get_badge_type_display", lambda: getattr(vr, "badge_type", ""))() or "—"
            status_label = getattr(vr, "get_status_display", lambda: vr.status)() or "—"
            invoice_code = getattr(getattr(vr, "invoice", None), "code", "—") or "—"
            detail_path = f"/dashboard/verification/{vr.id}/"
            export_rows.append([code, phone, badge, status_label, invoice_code, detail_path])

        if _want_csv(request):
            return _csv_response("verification_requests.csv", headers_ar, export_rows)

        from .exports import pdf_response, xlsx_response

        if _want_xlsx(request):
            return xlsx_response("verification_requests.xlsx", "التوثيق", headers_ar, export_rows)
        return pdf_response("verification_requests.pdf", "إدارة التوثيق", headers_ar, export_rows, landscape=False)

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    return render(
        request,
        "dashboard/verification_requests_list.html",
        {
            "page_obj": page_obj,
            "q": q,
            "status_val": status_val,
            "status_choices": VerificationStatus.choices,
        },
    )


@staff_member_required
@dashboard_access_required("verify")
def verification_request_detail(request: HttpRequest, verification_id: int) -> HttpResponse:
    vr = get_object_or_404(
        VerificationRequest.objects.select_related("requester", "invoice", "assigned_to"),
        id=verification_id,
    )

    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == "user" and vr.assigned_to_id is not None and vr.assigned_to_id != request.user.id:
        return HttpResponse("غير مصرح", status=403)
    docs = VerificationDocument.objects.filter(request=vr).select_related("decided_by").order_by("-id")
    return render(
        request,
        "dashboard/verification_request_detail.html",
        {"vr": vr, "docs": docs},
    )


@staff_member_required
@dashboard_access_required("verify", write=True)
@require_POST
def verification_finalize_action(request: HttpRequest, verification_id: int) -> HttpResponse:
    vr = get_object_or_404(VerificationRequest, id=verification_id)

    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == "user" and vr.assigned_to_id is not None and vr.assigned_to_id != request.user.id:
        return HttpResponse("غير مصرح", status=403)
    try:
        vr = finalize_request_and_create_invoice(vr=vr, by_user=request.user)
        messages.success(request, f"تمت معالجة الطلب: {vr.get_status_display()}")
    except Exception as e:
        messages.error(request, str(e) or "تعذر إنهاء طلب التوثيق")
    return redirect("dashboard:verification_request_detail", verification_id=verification_id)


@staff_member_required
@dashboard_access_required("verify", write=True)
@require_POST
def verification_activate_action(request: HttpRequest, verification_id: int) -> HttpResponse:
    vr = get_object_or_404(VerificationRequest, id=verification_id)

    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == "user" and vr.assigned_to_id is not None and vr.assigned_to_id != request.user.id:
        return HttpResponse("غير مصرح", status=403)
    try:
        activate_verification_after_payment(vr=vr)
        messages.success(request, "تم تفعيل التوثيق بنجاح")
    except Exception as e:
        messages.error(request, str(e) or "تعذر تفعيل طلب التوثيق")
    return redirect("dashboard:verification_request_detail", verification_id=verification_id)


@staff_member_required
@dashboard_access_required("promo")
def promo_requests_list(request: HttpRequest) -> HttpResponse:
    qs = PromoRequest.objects.select_related("requester", "invoice", "assigned_to").all().order_by("-id")
    q = (request.GET.get("q") or "").strip()
    status_val = (request.GET.get("status") or "").strip()
    ad_type = (request.GET.get("ad_type") or "").strip()
    if q:
        qs = qs.filter(Q(code__icontains=q) | Q(title__icontains=q) | Q(requester__phone__icontains=q))
    if status_val:
        qs = qs.filter(status=status_val)
    if ad_type:
        qs = qs.filter(ad_type=ad_type)

    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == "user":
        qs = qs.filter(Q(assigned_to=request.user) | Q(assigned_to__isnull=True))

    if _want_xlsx(request) or _want_pdf(request) or _want_csv(request):
        headers_ar = ["الكود", "العميل", "العنوان", "النوع", "الحالة", "الفاتورة", "إجراءات"]
        export_rows = []
        for pr in qs[:2000]:
            code = pr.code or pr.id
            phone = getattr(getattr(pr, "requester", None), "phone", "—") or "—"
            ad_label = getattr(pr, "get_ad_type_display", lambda: pr.ad_type)() or "—"
            status_label = getattr(pr, "get_status_display", lambda: pr.status)() or "—"
            invoice_code = getattr(getattr(pr, "invoice", None), "code", "—") or "—"
            detail_path = f"/dashboard/promo/{pr.id}/"
            export_rows.append([code, phone, pr.title or "—", ad_label, status_label, invoice_code, detail_path])

        if _want_csv(request):
            return _csv_response("promo_requests.csv", headers_ar, export_rows)

        from .exports import pdf_response, xlsx_response

        if _want_xlsx(request):
            return xlsx_response("promo_requests.xlsx", "الترويج", headers_ar, export_rows)
        return pdf_response("promo_requests.pdf", "إدارة الترويج", headers_ar, export_rows, landscape=True)

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    return render(
        request,
        "dashboard/promo_requests_list.html",
        {
            "page_obj": page_obj,
            "q": q,
            "status_val": status_val,
            "ad_type": ad_type,
            "status_choices": PromoRequestStatus.choices,
            "ad_type_choices": PromoRequest._meta.get_field("ad_type").choices,
        },
    )


@staff_member_required
@dashboard_access_required("promo")
def promo_request_detail(request: HttpRequest, promo_id: int) -> HttpResponse:
    pr = get_object_or_404(
        PromoRequest.objects.select_related(
            "requester",
            "invoice",
            "assigned_to",
            "target_provider",
            "target_portfolio_item",
        ),
        id=promo_id,
    )

    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == "user" and pr.assigned_to_id is not None and pr.assigned_to_id != request.user.id:
        return HttpResponse("غير مصرح", status=403)
    assets = pr.assets.all().order_by("-id")
    return render(
        request,
        "dashboard/promo_request_detail.html",
        {"pr": pr, "assets": assets},
    )


@staff_member_required
@dashboard_access_required("promo", write=True)
@require_POST
def promo_quote_action(request: HttpRequest, promo_id: int) -> HttpResponse:
    pr = get_object_or_404(PromoRequest, id=promo_id)

    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == "user" and pr.assigned_to_id is not None and pr.assigned_to_id != request.user.id:
        return HttpResponse("غير مصرح", status=403)
    note = (request.POST.get("quote_note") or "").strip()
    try:
        quote_and_create_invoice(pr=pr, by_user=request.user, quote_note=note)
        messages.success(request, "تم التسعير وإنشاء الفاتورة")
    except Exception as e:
        messages.error(request, str(e) or "تعذر تسعير الطلب")
    return redirect("dashboard:promo_request_detail", promo_id=promo_id)


@staff_member_required
@dashboard_access_required("promo", write=True)
@require_POST
def promo_reject_action(request: HttpRequest, promo_id: int) -> HttpResponse:
    pr = get_object_or_404(PromoRequest, id=promo_id)

    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == "user" and pr.assigned_to_id is not None and pr.assigned_to_id != request.user.id:
        return HttpResponse("غير مصرح", status=403)
    reason = (request.POST.get("reject_reason") or "").strip()
    if not reason:
        messages.warning(request, "سبب الرفض مطلوب")
        return redirect("dashboard:promo_request_detail", promo_id=promo_id)
    try:
        reject_request(pr=pr, reason=reason, by_user=request.user)
        messages.success(request, "تم رفض الطلب")
    except Exception as e:
        messages.error(request, str(e) or "تعذر رفض الطلب")
    return redirect("dashboard:promo_request_detail", promo_id=promo_id)


@staff_member_required
@dashboard_access_required("promo", write=True)
@require_POST
def promo_activate_action(request: HttpRequest, promo_id: int) -> HttpResponse:
    pr = get_object_or_404(PromoRequest, id=promo_id)

    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == "user" and pr.assigned_to_id is not None and pr.assigned_to_id != request.user.id:
        return HttpResponse("غير مصرح", status=403)
    try:
        activate_promo_after_payment(pr=pr)
        messages.success(request, "تم تفعيل الحملة")
    except Exception as e:
        messages.error(request, str(e) or "تعذر تفعيل الحملة")
    return redirect("dashboard:promo_request_detail", promo_id=promo_id)


@staff_member_required
@dashboard_access_required("subs")
def subscriptions_list(request: HttpRequest) -> HttpResponse:
    qs = Subscription.objects.select_related("user", "plan", "invoice").all().order_by("-id")
    q = (request.GET.get("q") or "").strip()
    status_val = (request.GET.get("status") or "").strip()
    if q:
        qs = qs.filter(Q(user__phone__icontains=q) | Q(plan__title__icontains=q) | Q(plan__code__icontains=q))
    if status_val:
        qs = qs.filter(status=status_val)

    if _want_xlsx(request) or _want_pdf(request) or _want_csv(request):
        headers_ar = ["#", "المستخدم", "الخطة", "الحالة", "البداية/النهاية", "الفاتورة", "تشغيل"]
        export_rows = []
        for s in qs[:2000]:
            phone = getattr(getattr(s, "user", None), "phone", "—") or "—"
            plan_title = getattr(getattr(s, "plan", None), "title", "—") or "—"
            plan_code = getattr(getattr(s, "plan", None), "code", "—") or "—"
            plan_str = f"{plan_title} ({plan_code})"
            status_label = getattr(s, "get_status_display", lambda: s.status)() or "—"
            start_str = s.start_at.strftime("%Y-%m-%d %H:%M") if s.start_at else "—"
            end_str = s.end_at.strftime("%Y-%m-%d %H:%M") if s.end_at else "—"
            invoice_code = getattr(getattr(s, "invoice", None), "code", "—") or "—"
            ops = "Refresh / Activate"
            export_rows.append([s.id, phone, plan_str, status_label, f"{start_str} / {end_str}", invoice_code, ops])

        if _want_csv(request):
            return _csv_response("subscriptions.csv", headers_ar, export_rows)

        from .exports import pdf_response, xlsx_response

        if _want_xlsx(request):
            return xlsx_response("subscriptions.xlsx", "الاشتراكات", headers_ar, export_rows)
        return pdf_response("subscriptions.pdf", "إدارة الاشتراكات", headers_ar, export_rows, landscape=True)

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    return render(
        request,
        "dashboard/subscriptions_list.html",
        {
            "page_obj": page_obj,
            "q": q,
            "status_val": status_val,
            "status_choices": SubscriptionStatus.choices,
        },
    )


@staff_member_required
@dashboard_access_required("subs", write=True)
@require_POST
def subscription_refresh_action(request: HttpRequest, subscription_id: int) -> HttpResponse:
    sub = get_object_or_404(Subscription, id=subscription_id)
    try:
        refresh_subscription_status(sub=sub)
        messages.success(request, "تم تحديث حالة الاشتراك")
    except Exception as e:
        messages.error(request, str(e) or "تعذر تحديث الاشتراك")
    return redirect("dashboard:subscriptions_list")


@staff_member_required
@dashboard_access_required("subs", write=True)
@require_POST
def subscription_activate_action(request: HttpRequest, subscription_id: int) -> HttpResponse:
    sub = get_object_or_404(Subscription, id=subscription_id)
    try:
        activate_subscription_after_payment(sub=sub)
        messages.success(request, "تم تفعيل الاشتراك")
    except Exception as e:
        messages.error(request, str(e) or "تعذر تفعيل الاشتراك")
    return redirect("dashboard:subscriptions_list")


@staff_member_required
@dashboard_access_required("extras")
def extras_list(request: HttpRequest) -> HttpResponse:
    qs = ExtraPurchase.objects.select_related("user", "invoice").all().order_by("-id")
    q = (request.GET.get("q") or "").strip()
    status_val = (request.GET.get("status") or "").strip()
    if q:
        qs = qs.filter(Q(user__phone__icontains=q) | Q(sku__icontains=q) | Q(title__icontains=q))
    if status_val:
        qs = qs.filter(status=status_val)

    if _want_xlsx(request) or _want_pdf(request) or _want_csv(request):
        headers_ar = ["#", "المستخدم", "SKU", "النوع", "الحالة", "الفاتورة", "إجراءات"]
        export_rows = []
        for e in qs[:2000]:
            phone = getattr(getattr(e, "user", None), "phone", "—") or "—"
            type_label = getattr(e, "get_extra_type_display", lambda: e.extra_type)() or "—"
            status_label = getattr(e, "get_status_display", lambda: e.status)() or "—"
            invoice_code = getattr(getattr(e, "invoice", None), "code", "—") or "—"
            action_path = f"/dashboard/extras/{e.id}/actions/activate/"
            export_rows.append([e.id, phone, e.sku or "—", type_label, status_label, invoice_code, action_path])

        if _want_csv(request):
            return _csv_response("extras.csv", headers_ar, export_rows)

        from .exports import pdf_response, xlsx_response

        if _want_xlsx(request):
            return xlsx_response("extras.xlsx", "الإضافات", headers_ar, export_rows)
        return pdf_response("extras.pdf", "إدارة الإضافات", headers_ar, export_rows, landscape=True)

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    return render(
        request,
        "dashboard/extras_list.html",
        {
            "page_obj": page_obj,
            "q": q,
            "status_val": status_val,
            "status_choices": ExtraPurchaseStatus.choices,
        },
    )


@staff_member_required
@dashboard_access_required("extras", write=True)
@require_POST
def extra_activate_action(request: HttpRequest, extra_id: int) -> HttpResponse:
    purchase = get_object_or_404(ExtraPurchase, id=extra_id)
    try:
        activate_extra_after_payment(purchase=purchase)
        messages.success(request, "تم تفعيل الإضافة")
    except Exception as e:
        messages.error(request, str(e) or "تعذر تفعيل الإضافة")
    return redirect("dashboard:extras_list")


@staff_member_required
@dashboard_access_required("analytics")
def features_overview(request: HttpRequest) -> HttpResponse:
    users_qs = User.objects.all().order_by("-id")
    q = (request.GET.get("q") or "").strip()
    if q:
        users_qs = users_qs.filter(Q(phone__icontains=q) | Q(username__icontains=q) | Q(email__icontains=q))
    paginator = Paginator(users_qs, 20)
    page_obj = paginator.get_page(request.GET.get("page") or "1")

    rows = []
    for user in page_obj.object_list:
        rows.append(
            {
                "user": user,
                "verify_blue": has_feature(user, "verify_blue"),
                "verify_green": has_feature(user, "verify_green"),
                "promo_ads": has_feature(user, "promo_ads"),
                "priority_support": has_feature(user, "priority_support"),
                "extra_uploads": has_feature(user, "extra_uploads"),
                "max_upload_mb": user_max_upload_mb(user),
            }
        )

    if _want_csv(request):
        csv_rows = [
            [
                row["user"].id,
                row["user"].phone or "",
                row["verify_blue"],
                row["verify_green"],
                row["promo_ads"],
                row["priority_support"],
                row["extra_uploads"],
                row["max_upload_mb"],
            ]
            for row in rows
        ]
        return _csv_response(
            "features_overview.csv",
            ["user_id", "phone", "verify_blue", "verify_green", "promo_ads", "priority_support", "extra_uploads", "max_upload_mb"],
            csv_rows,
        )

    return render(
        request,
        "dashboard/features_overview.html",
        {
            "page_obj": page_obj,
            "rows": rows,
            "q": q,
        },
    )


@staff_member_required
@dashboard_access_required("access")
def access_profiles_list(request: HttpRequest) -> HttpResponse:
    qs = (
        UserAccessProfile.objects.select_related("user")
        .prefetch_related("allowed_dashboards")
        .all()
        .order_by("-updated_at")
    )
    q = (request.GET.get("q") or "").strip()
    level = (request.GET.get("level") or "").strip()
    if q:
        qs = qs.filter(Q(user__phone__icontains=q) | Q(user__username__icontains=q) | Q(user__email__icontains=q))
    if level:
        qs = qs.filter(level=level)

    if _want_csv(request):
        rows = []
        for ap in qs[:2000]:
            dashboards = ",".join(ap.allowed_dashboards.values_list("code", flat=True))
            rows.append(
                [
                    ap.user_id,
                    ap.user.phone or "",
                    ap.level,
                    bool(ap.revoked_at),
                    ap.expires_at.isoformat() if ap.expires_at else "",
                    dashboards,
                    ap.updated_at.isoformat() if ap.updated_at else "",
                ]
            )
        return _csv_response(
            "access_profiles.csv",
            ["user_id", "phone", "level", "is_revoked", "expires_at", "dashboards", "updated_at"],
            rows,
        )

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    return render(
        request,
        "dashboard/access_profiles_list.html",
        {
            "page_obj": page_obj,
            "q": q,
            "level": level,
            "level_choices": UserAccessProfile._meta.get_field("level").choices,
            "all_dashboards": Dashboard.objects.filter(is_active=True).order_by("sort_order", "id"),
            "can_write": _dashboard_allowed(request.user, "access", write=True),
        },
    )


@staff_member_required
@dashboard_access_required("access", write=True)
@require_POST
def access_profile_create_action(request: HttpRequest) -> HttpResponse:
    phone = (request.POST.get("target_phone") or "").strip()
    if not phone:
        messages.error(request, "رقم الجوال مطلوب")
        return redirect("dashboard:access_profiles_list")

    target_user = User.objects.filter(phone=phone).first()
    if not target_user:
        messages.error(request, "لا يوجد مستخدم بهذا الجوال")
        return redirect("dashboard:access_profiles_list")

    if not (target_user.is_staff or target_user.is_superuser):
        messages.error(request, "لا يمكن منح صلاحيات تشغيل لمستخدم غير موظف")
        return redirect("dashboard:access_profiles_list")

    level = (request.POST.get("level") or "").strip().lower()
    if level not in {choice[0] for choice in AccessLevel.choices}:
        messages.error(request, "مستوى الصلاحية غير صالح")
        return redirect("dashboard:access_profiles_list")

    expires_at_raw = (request.POST.get("expires_at") or "").strip()
    expires_at = _parse_datetime_local(expires_at_raw) if expires_at_raw else None
    if expires_at_raw and expires_at is None:
        messages.error(request, "صيغة تاريخ الانتهاء غير صحيحة")
        return redirect("dashboard:access_profiles_list")

    dashboard_ids = request.POST.getlist("dashboard_ids")
    selected_dashboards = Dashboard.objects.filter(id__in=dashboard_ids, is_active=True)

    ap, created = UserAccessProfile.objects.get_or_create(
        user=target_user,
        defaults={"level": level, "expires_at": expires_at},
    )
    if not created:
        if _is_active_admin_profile(ap):
            will_still_be_active_admin = (
                level == AccessLevel.ADMIN
                and (expires_at is None or expires_at > timezone.now())
            )
            if not will_still_be_active_admin and _active_admin_profiles_count() <= 1:
                messages.error(request, "لا يمكن خفض/تعطيل آخر Admin فعّال في المنصة")
                return redirect("dashboard:access_profiles_list")

        ap.level = level
        ap.expires_at = expires_at
        ap.save(update_fields=["level", "expires_at", "updated_at"])

    ap.allowed_dashboards.set(selected_dashboards)

    log_action(
        actor=request.user,
        action=AuditAction.ACCESS_PROFILE_CREATED if created else AuditAction.ACCESS_PROFILE_UPDATED,
        reference_type="backoffice.user_access_profile",
        reference_id=str(ap.id),
        request=request,
        extra={
            "target_user_id": target_user.id,
            "created": bool(created),
            "after": {
                "level": ap.level,
                "expires_at": ap.expires_at.isoformat() if ap.expires_at else None,
                "dashboards": list(ap.allowed_dashboards.values_list("code", flat=True)),
            },
        },
    )

    if created:
        messages.success(request, "تم إنشاء ملف صلاحيات التشغيل بنجاح")
    else:
        messages.success(request, "المستخدم لديه ملف سابق وتم تحديثه")
    return redirect("dashboard:access_profiles_list")


@staff_member_required
@dashboard_access_required("access", write=True)
@require_POST
def access_profile_update_action(request: HttpRequest, profile_id: int) -> HttpResponse:
    ap = get_object_or_404(UserAccessProfile.objects.prefetch_related("allowed_dashboards"), id=profile_id)
    old_level = ap.level
    old_expires_at = ap.expires_at.isoformat() if ap.expires_at else None
    old_dashboards = list(ap.allowed_dashboards.values_list("code", flat=True))

    level = (request.POST.get("level") or "").strip().lower()
    if level not in {choice[0] for choice in AccessLevel.choices}:
        messages.error(request, "مستوى الصلاحية غير صالح")
        return redirect("dashboard:access_profiles_list")

    expires_at_raw = (request.POST.get("expires_at") or "").strip()
    expires_at = _parse_datetime_local(expires_at_raw) if expires_at_raw else None
    if expires_at_raw and expires_at is None:
        messages.error(request, "صيغة تاريخ الانتهاء غير صحيحة")
        return redirect("dashboard:access_profiles_list")

    if _is_active_admin_profile(ap):
        will_still_be_active_admin = (
            level == AccessLevel.ADMIN
            and (expires_at is None or expires_at > timezone.now())
        )
        if not will_still_be_active_admin and _active_admin_profiles_count() <= 1:
            messages.error(request, "لا يمكن خفض/تعطيل آخر Admin فعّال في المنصة")
            return redirect("dashboard:access_profiles_list")

    dashboard_ids = request.POST.getlist("dashboard_ids")
    selected_dashboards = Dashboard.objects.filter(id__in=dashboard_ids, is_active=True)

    ap.level = level
    ap.expires_at = expires_at
    ap.save(update_fields=["level", "expires_at", "updated_at"])
    ap.allowed_dashboards.set(selected_dashboards)

    new_dashboards = list(ap.allowed_dashboards.values_list("code", flat=True))
    log_action(
        actor=request.user,
        action=AuditAction.ACCESS_PROFILE_UPDATED,
        reference_type="backoffice.user_access_profile",
        reference_id=str(ap.id),
        request=request,
        extra={
            "target_user_id": ap.user_id,
            "before": {
                "level": old_level,
                "expires_at": old_expires_at,
                "dashboards": old_dashboards,
            },
            "after": {
                "level": ap.level,
                "expires_at": ap.expires_at.isoformat() if ap.expires_at else None,
                "dashboards": new_dashboards,
            },
        },
    )

    messages.success(request, "تم تحديث ملف الصلاحيات بنجاح")
    return redirect("dashboard:access_profiles_list")


@staff_member_required
@dashboard_access_required("access", write=True)
@require_POST
def access_profile_toggle_revoke_action(request: HttpRequest, profile_id: int) -> HttpResponse:
    ap = get_object_or_404(UserAccessProfile, id=profile_id)

    if ap.user_id == getattr(request.user, "id", None):
        messages.warning(request, "لا يمكن سحب صلاحيات حسابك الحالي")
        return redirect("dashboard:access_profiles_list")

    if ap.revoked_at:
        ap.revoked_at = None
        ap.save(update_fields=["revoked_at", "updated_at"])
        log_action(
            actor=request.user,
            action=AuditAction.ACCESS_PROFILE_UNREVOKED,
            reference_type="backoffice.user_access_profile",
            reference_id=str(ap.id),
            request=request,
            extra={
                "target_user_id": ap.user_id,
                "revoked": False,
            },
        )
        messages.success(request, "تم إلغاء سحب الصلاحية")
    else:
        if _is_active_admin_profile(ap) and _active_admin_profiles_count() <= 1:
            messages.error(request, "لا يمكن سحب آخر Admin فعّال في المنصة")
            return redirect("dashboard:access_profiles_list")

        ap.revoked_at = timezone.now()
        ap.save(update_fields=["revoked_at", "updated_at"])
        log_action(
            actor=request.user,
            action=AuditAction.ACCESS_PROFILE_REVOKED,
            reference_type="backoffice.user_access_profile",
            reference_id=str(ap.id),
            request=request,
            extra={
                "target_user_id": ap.user_id,
                "revoked": True,
                "revoked_at": ap.revoked_at.isoformat() if ap.revoked_at else None,
            },
        )
        messages.success(request, "تم سحب الصلاحية")

    return redirect("dashboard:access_profiles_list")
