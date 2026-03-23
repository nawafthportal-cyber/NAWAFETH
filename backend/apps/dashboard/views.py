from __future__ import annotations

from datetime import datetime, timedelta
import csv
import io
import json
import logging
from decimal import Decimal
from functools import wraps
from django.contrib import messages

# Dashboard auth (OTP + staff) — keep legacy decorator names used in this file.
from .auth import dashboard_staff_required as staff_member_required
from django.core.exceptions import PermissionDenied, ValidationError
from django.core.paginator import Paginator
from django.db import transaction
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
from apps.providers.models import ProviderPortfolioItem, ProviderSpotlightItem
from apps.accounts.models import User
from apps.core.models import PlatformConfig
from apps.messaging.models import Message
from apps.reviews.models import Review
from apps.support.models import SupportTicket, SupportTicketStatus, SupportTeam, SupportTicketType
from apps.support.services import change_ticket_status, assign_ticket
from apps.billing.models import Invoice, InvoiceStatus, PaymentAttempt, TRUSTED_PAYMENT_REFERENCE_TYPES, money_round
from apps.billing.services import handle_webhook, init_payment, sign_webhook_payload
from apps.verification.models import (
    VerificationRequest,
    VerificationStatus,
    VerificationDocument,
    VerificationRequirement,
    VerifiedBadge,
)
from apps.verification.services import (
    finalize_request_and_create_invoice,
    decide_requirement,
    activate_after_payment as activate_verification_after_payment,
    verification_price_amount,
    verification_pricing_for_plan,
    sync_provider_badges,
)
from apps.subscriptions.models import Subscription, SubscriptionStatus, SubscriptionPlan, FeatureKey
from apps.subscriptions.services import (
    refresh_subscription_status,
    activate_subscription_after_payment,
    get_effective_active_subscriptions_map,
    start_subscription_checkout,
    start_subscription_renewal_checkout,
)
from apps.promo.models import (
    HomeBanner,
    HomeBannerMediaType,
    PromoAdType,
    PromoAsset,
    PromoAssetType,
    PromoFrequency,
    PromoInquiryProfile,
    PromoOpsStatus,
    PromoPosition,
    PromoPricingRule,
    PromoRequest,
    PromoRequestItem,
    PromoRequestStatus,
    PromoSearchScope,
    PromoServiceType,
)
from apps.promo.serializers import PromoRequestCreateSerializer
from apps.promo.services import (
    activate_after_payment as activate_promo_after_payment,
    ensure_default_pricing_rules,
    quote_and_create_invoice,
    reject_request,
    set_promo_ops_status,
    _sync_promo_to_unified,
)
from apps.extras.models import ExtraPurchase, ExtraPurchaseStatus
from apps.extras.services import activate_extra_after_payment
from apps.features.checks import has_feature
from apps.features.upload_limits import user_max_upload_mb
from apps.backoffice.models import AccessLevel, Dashboard, UserAccessProfile
from apps.backoffice.policies import (
    AnalyticsExportPolicy,
    ContentHideDeletePolicy,
    ExtrasManagePolicy,
    PromoQuoteActivatePolicy,
    SubscriptionManagePolicy,
    SupportAssignPolicy,
    SupportResolvePolicy,
    VerificationFinalizePolicy,
)
from apps.audit.models import AuditAction
from apps.audit.services import log_action
from apps.moderation.integrations import record_support_target_delete_case
from apps.unified_requests.models import (
    UnifiedRequest,
    UnifiedRequestAssignmentLog,
    UnifiedRequestMetadata,
    UnifiedRequestStatus,
    UnifiedRequestStatusLog,
    UnifiedRequestType,
)
from apps.unified_requests.workflows import (
    THREE_STAGE_ALLOWED_STATUSES,
    allowed_statuses_for_request_type,
    canonical_status_for_workflow,
    is_valid_transition,
)
from .forms import AcceptAssignProviderForm, CategoryForm, SubCategoryForm
from .access import (
    active_dashboard_choices,
    backoffice_assignment_users,
    can_access_dashboard,
    can_access_object,
    dashboard_allowed,
    dashboard_assignee_user,
    dashboard_assignment_users,
    first_allowed_dashboard_route,
    has_action_permission,
    sync_dashboard_user_access,
)
from .security import (
    apply_user_level_filter,
    is_safe_redirect_url,
    safe_redirect_url,
    validate_uploaded_file,
    FileValidationError,
    ALLOWED_MEDIA_EXTENSIONS,
    ALLOWED_MEDIA_MIME_TYPES,
)

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
    def _csv_safe_cell(value):
        if value is None:
            return ""
        text = str(value)
        if text and text[0] in {"=", "+", "-", "@"}:
            return f"'{text}"
        return text

    stream = io.StringIO()
    writer = csv.writer(stream)
    writer.writerow(headers)
    for r in rows:
        writer.writerow([_csv_safe_cell(v) for v in r])
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


def _tabular_export_limit() -> int:
    return max(1, int(PlatformConfig.load().export_xlsx_max_rows or 2000))


def _pdf_export_limit() -> int:
    return max(1, int(PlatformConfig.load().export_pdf_max_rows or 200))


def _current_export_limit(request: HttpRequest) -> int:
    if _want_pdf(request):
        return _pdf_export_limit()
    return _tabular_export_limit()


def _limited_export_queryset(request: HttpRequest, qs):
    return qs[:_current_export_limit(request)]


def _dashboard_tile_meta(code: str) -> dict[str, str]:
    mapping = {
        "analytics": {"icon": "🏠", "from": "from-purple-500", "to": "to-indigo-600"},
        "content": {"icon": "📋", "from": "from-blue-500", "to": "to-cyan-600"},
        "billing": {"icon": "💳", "from": "from-sky-500", "to": "to-blue-600"},
        "support": {"icon": "🎫", "from": "from-cyan-500", "to": "to-teal-600"},
        "verify": {"icon": "✅", "from": "from-indigo-500", "to": "to-violet-600"},
        "promo": {"icon": "📢", "from": "from-fuchsia-500", "to": "to-pink-600"},
        "subs": {"icon": "📦", "from": "from-violet-500", "to": "to-indigo-600"},
        "extras": {"icon": "➕", "from": "from-orange-500", "to": "to-amber-600"},
        "features": {"icon": "🧩", "from": "from-teal-500", "to": "to-emerald-600"},
        "admin_control": {"icon": "🔐", "from": "from-slate-600", "to": "to-gray-800"},
        "access": {"icon": "🔐", "from": "from-slate-600", "to": "to-gray-800"},
        "client_extras": {"icon": "🛒", "from": "from-emerald-500", "to": "to-green-600"},
        "moderation": {"icon": "🛡️", "from": "from-red-500", "to": "to-rose-600"},
        "excellence": {"icon": "🏆", "from": "from-yellow-500", "to": "to-amber-600"},
    }
    return mapping.get(code, {"icon": "🗂️", "from": "from-gray-500", "to": "to-slate-600"})




def _dashboard_allowed(user, dashboard_code: str, write: bool = False) -> bool:
    return can_access_dashboard(user, dashboard_code, write=write)


def _is_promo_operator_user(user) -> bool:
    return bool(user and dashboard_allowed(user, "promo", write=True))


PROMO_MODULE_MENU: tuple[tuple[str, str], ...] = (
    (PromoServiceType.HOME_BANNER, "بنر الصفحة الرئيسية"),
    (PromoServiceType.FEATURED_SPECIALISTS, "شريط أبرز المختصين"),
    (PromoServiceType.PORTFOLIO_SHOWCASE, "شريط البنرات والمشاريع"),
    (PromoServiceType.SNAPSHOTS, "شريط اللمحات"),
    (PromoServiceType.SEARCH_RESULTS, "الظهور في قوائم البحث"),
    (PromoServiceType.PROMO_MESSAGES, "الرسائل الدعائية"),
    (PromoServiceType.SPONSORSHIP, "الرعاية"),
)


def _promo_staff_users():
    return dashboard_assignment_users("promo", write=True, limit=150)


def _promo_requests_queryset():
    return (
        PromoRequest.objects.select_related("requester", "invoice", "assigned_to")
        .prefetch_related("items", "items__assets", "assets")
        .order_by("-id")
    )


def _promo_inquiries_queryset():
    return (
        SupportTicket.objects.select_related("requester", "assigned_team", "assigned_to")
        .filter(ticket_type=SupportTicketType.ADS)
        .order_by("-id")
    )


def _promo_service_counts():
    counts = {
        row["service_type"]: row["c"]
        for row in PromoRequestItem.objects.values("service_type").annotate(c=Count("id"))
    }
    return [{"key": key, "label": label, "count": counts.get(key, 0)} for key, label in PROMO_MODULE_MENU]


def _promo_unified_request(pr: PromoRequest):
    return UnifiedRequest.objects.select_related("assigned_user").filter(
        source_app="promo",
        source_model="PromoRequest",
        source_object_id=str(pr.id),
    ).first()


def _promo_attach_note_to_latest_log(*, ur: UnifiedRequest | None, model_cls, to_value: str, note: str, changed_by):
    if not ur or not note:
        return
    log = (
        model_cls.objects.filter(
            request=ur,
            to_status=to_value,
            changed_by=changed_by,
        )
        .order_by("-id")
        .first()
    )
    if log and not log.note:
        log.note = note[:200]
        log.save(update_fields=["note"])


def _promo_dashboard_menu_context(*, active: str):
    return {
        "promo_menu": [{"key": key, "label": label} for key, label in PROMO_MODULE_MENU],
        "promo_active": active,
        "promo_service_counts": _promo_service_counts(),
    }


_PROMO_DASHBOARD_UNSUPPORTED_AD_TYPES = {
    PromoAdType.BANNER_CATEGORY,
    PromoAdType.POPUP_CATEGORY,
    PromoAdType.PUSH_NOTIFICATION,
}
_PROMO_DASHBOARD_MEDIA_AD_TYPES = {
    PromoAdType.BANNER_HOME,
    PromoAdType.BANNER_SEARCH,
    PromoAdType.POPUP_HOME,
}
_PROMO_DASHBOARD_MEDIA_SERVICE_TYPES = {
    PromoServiceType.HOME_BANNER,
    PromoServiceType.SPONSORSHIP,
}
_PROMO_DASHBOARD_SEARCH_POSITION_CHOICES = (
    (PromoPosition.FIRST, "الأول"),
    (PromoPosition.SECOND, "الثاني"),
    (PromoPosition.TOP5, "ضمن أول 5"),
    (PromoPosition.TOP10, "ضمن أول 10"),
)


def _promo_dashboard_ad_type_choices():
    return [(value, label) for value, label in PromoAdType.choices if value not in _PROMO_DASHBOARD_UNSUPPORTED_AD_TYPES]


def _promo_dashboard_error_messages(detail) -> list[str]:
    if detail in (None, "", []):
        return []
    if isinstance(detail, list):
        messages_list: list[str] = []
        for item in detail:
            messages_list.extend(_promo_dashboard_error_messages(item))
        return messages_list
    if isinstance(detail, dict):
        messages_list = []
        for key, value in detail.items():
            key_label = "" if key in {"non_field_errors", "detail"} else f"{key}: "
            for item in _promo_dashboard_error_messages(value):
                messages_list.append(f"{key_label}{item}" if key_label else item)
        return messages_list
    return [str(detail)]


def _promo_dashboard_first_error(detail, fallback: str) -> str:
    messages_list = _promo_dashboard_error_messages(detail)
    return messages_list[0] if messages_list else fallback


def _promo_asset_type_from_upload(file_obj) -> str:
    ext = (file_obj.name.rsplit(".", 1)[-1] if "." in file_obj.name else "").lower()
    if ext in {"mp4", "mov", "avi", "webm", "mkv", "m4v"}:
        return PromoAssetType.VIDEO
    if ext in {"pdf"}:
        return PromoAssetType.PDF
    if ext in {"jpg", "jpeg", "png", "gif", "webp", "svg"}:
        return PromoAssetType.IMAGE
    return PromoAssetType.OTHER


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


def require_dashboard_access(dashboard_key: str, write: bool = False):
    def decorator(func):
        @wraps(func)
        def wrapped(request: HttpRequest, *args, **kwargs):
            if not _dashboard_allowed(request.user, dashboard_key, write=write):
                messages.error(request, "لا تملك صلاحية الوصول لهذه اللوحة.")
                fallback = first_allowed_dashboard_route(request.user)
                current = getattr(request, "path", "")
                if fallback and fallback != current:
                    return redirect(fallback)
                return HttpResponse("غير مصرح", status=403)
            if write:
                logger.info(
                    "dashboard_write_access_granted user_id=%s dashboard=%s method=%s path=%s",
                    getattr(getattr(request, "user", None), "id", None),
                    dashboard_key,
                    getattr(request, "method", ""),
                    getattr(request, "path", ""),
                )
            return func(request, *args, **kwargs)
        return wrapped
    return decorator


dashboard_access_required = require_dashboard_access


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
    if source_app == "reviews" and source_model == "review" and sid is not None:
        return reverse("dashboard:reviews_dashboard_detail", args=[sid])
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
        "reviews": "content",
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
        "reviews": qs.filter(request_type=UnifiedRequestType.REVIEWS).count(),
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
        for r in _limited_export_queryset(request, qs):
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

    staff_users = backoffice_assignment_users(write=False, limit=150)
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
    if status in ("sent", "new") and user_id:
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

    today = timezone.localdate()
    default_start_date = today - timedelta(days=29)
    date_from_raw = (request.GET.get("date_from") or "").strip()
    date_to_raw = (request.GET.get("date_to") or "").strip()
    date_from_dt = _parse_date_yyyy_mm_dd(date_from_raw) if date_from_raw else None
    date_to_dt = _parse_date_yyyy_mm_dd(date_to_raw) if date_to_raw else None

    if date_from_raw and date_from_dt is None:
        messages.warning(request, "تم تجاهل تاريخ البداية لعدم صحة الصيغة")
    if date_to_raw and date_to_dt is None:
        messages.warning(request, "تم تجاهل تاريخ النهاية لعدم صحة الصيغة")

    if date_from_dt is None:
        date_from_dt = timezone.make_aware(
            datetime.combine(default_start_date, datetime.min.time()),
            timezone.get_current_timezone(),
        )
        date_from_raw = default_start_date.isoformat()
    if date_to_dt is None:
        date_to_dt = timezone.make_aware(
            datetime.combine(today, datetime.min.time()),
            timezone.get_current_timezone(),
        )
        date_to_raw = today.isoformat()

    if date_from_dt > date_to_dt:
        date_from_dt, date_to_dt = date_to_dt, date_from_dt
        date_from_raw = date_from_dt.date().isoformat()
        date_to_raw = date_to_dt.date().isoformat()

    date_to_exclusive = date_to_dt + timedelta(days=1)
    scoped_requests_qs = qs.filter(created_at__gte=date_from_dt, created_at__lt=date_to_exclusive)

    # KPIs عامة للطلبات
    total = scoped_requests_qs.count()
    by_status = scoped_requests_qs.values("status").annotate(c=Count("id")).order_by("-c")
    by_type = scoped_requests_qs.values("request_type").annotate(c=Count("id")).order_by("-c")
    open_statuses = [
        _status_value("NEW", "new"),
        _status_value("SENT", "sent"),
        _status_value("ACCEPTED", "accepted"),
        _status_value("IN_PROGRESS", "in_progress"),
    ]
    open_requests = scoped_requests_qs.filter(status__in=open_statuses).count()
    completed_requests = scoped_requests_qs.filter(status=_status_value("COMPLETED", "completed")).count()
    cancelled_requests = scoped_requests_qs.filter(status=_status_value("CANCELLED", "cancelled")).count()

    # آخر 10 طلبات
    latest = (
        scoped_requests_qs.select_related("client", "provider")
        .order_by("-id")[:12]
    )

    # KPIs المزوّدين (single aggregate instead of 3 separate COUNT queries)
    provider_kpis = ProviderProfile.objects.aggregate(
        total=Count("id"),
        verified=Count("id", filter=Q(is_verified_blue=True) | Q(is_verified_green=True)),
        urgent=Count("id", filter=Q(accepts_urgent=True)),
    )
    total_providers = provider_kpis["total"]
    verified_providers = provider_kpis["verified"]
    urgent_providers = provider_kpis["urgent"]

    # KPIs الفوترة (single aggregate)
    pending_invoices = 0
    paid_invoices = 0
    failed_invoices = 0
    try:
        from apps.billing.models import Invoice, InvoiceStatus

        invoice_kpis = Invoice.objects.aggregate(
            pending=Count("id", filter=Q(status=InvoiceStatus.PENDING)),
            paid=Count("id", filter=Q(status=InvoiceStatus.PAID)),
            failed=Count("id", filter=Q(status=InvoiceStatus.FAILED)),
        )
        pending_invoices = invoice_kpis["pending"]
        paid_invoices = invoice_kpis["paid"]
        failed_invoices = invoice_kpis["failed"]
    except Exception:
        pass

    # KPIs التذاكر (single aggregate)
    support_new = 0
    support_open = 0
    try:
        from apps.support.models import SupportTicket, SupportTicketStatus

        support_kpis = SupportTicket.objects.aggregate(
            new=Count("id", filter=Q(status=SupportTicketStatus.NEW)),
            open=Count("id", filter=~Q(status=SupportTicketStatus.CLOSED)),
        )
        support_new = support_kpis["new"]
        support_open = support_kpis["open"]
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

    # KPIs الطلبات الموحدة (single aggregate instead of 4 separate COUNT queries)
    unified_scoped_qs = UnifiedRequest.objects.filter(created_at__gte=date_from_dt, created_at__lt=date_to_exclusive)
    unified_closed_statuses = [
        UnifiedRequestStatus.CLOSED,
        UnifiedRequestStatus.COMPLETED,
        UnifiedRequestStatus.REJECTED,
        UnifiedRequestStatus.EXPIRED,
        UnifiedRequestStatus.CANCELLED,
    ]
    unified_kpis = unified_scoped_qs.aggregate(
        total=Count("id"),
        open=Count("id", filter=~Q(status__in=unified_closed_statuses)),
        pending_payment=Count("id", filter=Q(status=UnifiedRequestStatus.PENDING_PAYMENT)),
        active=Count("id", filter=Q(status=UnifiedRequestStatus.ACTIVE)),
    )
    unified_total = unified_kpis["total"]
    unified_open = unified_kpis["open"]
    unified_pending_payment = unified_kpis["pending_payment"]
    unified_active = unified_kpis["active"]
    unified_recent = list(
        unified_scoped_qs.select_related("requester", "assigned_user").order_by("-id")[:8]
    )
    for ur in unified_recent:
        ur.dashboard_detail_url = _unified_request_dashboard_link(ur)

    status_labels = dict(getattr(RequestStatus, "choices", []) or [])
    type_labels = dict(getattr(RequestType, "choices", []) or [])

    for r in latest:
        r.status_label = status_labels.get(getattr(r, "status", ""), getattr(r, "status", "") or "—")
        r.type_label = type_labels.get(getattr(r, "request_type", ""), getattr(r, "request_type", "") or "—")

    # Trend charts (last 14 days)
    days = max((date_to_dt.date() - date_from_dt.date()).days + 1, 1)
    start_date = date_from_dt.date()
    labels = [(start_date + timedelta(days=i)).isoformat() for i in range(days)]

    req_by_day = {
        str(row["day"]): row["c"]
        for row in (
            ServiceRequest.objects.filter(created_at__gte=date_from_dt, created_at__lt=date_to_exclusive)
            .annotate(day=TruncDate("created_at"))
            .values("day")
            .annotate(c=Count("id"))
            .order_by("day")
        )
    }
    inv_by_day = {
        str(row["day"]): row["c"]
        for row in (
            Invoice.objects.filter(created_at__gte=date_from_dt, created_at__lt=date_to_exclusive)
            .annotate(day=TruncDate("created_at"))
            .values("day")
            .annotate(c=Count("id"))
            .order_by("day")
        )
    }
    sup_by_day = {
        str(row["day"]): row["c"]
        for row in (
            SupportTicket.objects.filter(created_at__gte=date_from_dt, created_at__lt=date_to_exclusive)
            .annotate(day=TruncDate("created_at"))
            .values("day")
            .annotate(c=Count("id"))
            .order_by("day")
        )
    }
    unified_by_day = {
        str(row["day"]): row["c"]
        for row in (
            UnifiedRequest.objects.filter(created_at__gte=date_from_dt, created_at__lt=date_to_exclusive)
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

    primary_ops_url = reverse("dashboard:home")
    if _dashboard_allowed(request.user, "content", write=False):
        primary_ops_url = reverse("dashboard:requests_list")
    elif _dashboard_allowed(request.user, "support", write=False):
        primary_ops_url = reverse("dashboard:support_tickets_list")
    elif _dashboard_allowed(request.user, "billing", write=False):
        primary_ops_url = reverse("dashboard:billing_invoices_list")

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
        "date_from_val": date_from_raw,
        "date_to_val": date_to_raw,
        "analytics_scope_days": days,
        "primary_ops_url": primary_ops_url,
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

        export_rows = [_row(r) for r in _limited_export_queryset(request, qs)]

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
            for p in _limited_export_queryset(request, qs)
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

    portfolio_items = (
        ProviderPortfolioItem.objects
        .filter(provider_id=provider_id)
        .order_by("-created_at")
    )

    spotlight_items = (
        ProviderSpotlightItem.objects
        .filter(provider_id=provider_id)
        .order_by("-created_at")
    )

    ctx = {
        "provider": provider,
        "services": list(services),
        "portfolio_items": list(portfolio_items),
        "spotlight_items": list(spotlight_items),
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
    policy = ContentHideDeletePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="providers.provider_service",
        reference_id=str(service.id),
        extra={"surface": "dashboard.provider_service_toggle_active"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتعديل حالة هذه الخدمة")
        return redirect("dashboard:provider_detail", provider_id=provider_id)
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
            for s in _limited_export_queryset(request, qs)
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


@staff_member_required
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


@staff_member_required
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


@staff_member_required
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


@staff_member_required
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


@staff_member_required
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
            for c in _limited_export_queryset(request, categories)
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
    policy = ContentHideDeletePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="marketplace.category",
        reference_id=str(category.id),
        extra={"surface": "dashboard.category_toggle_active"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتعديل حالة هذا التصنيف")
        return redirect("dashboard:category_detail", category_id=category.id)
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
    policy = ContentHideDeletePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="marketplace.subcategory",
        reference_id=str(subcategory.id),
        extra={"surface": "dashboard.subcategory_toggle_active"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتعديل حالة هذا التصنيف الفرعي")
        return redirect("dashboard:category_detail", category_id=category.id)
    
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
        for inv in _limited_export_queryset(request, qs):
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

    if action in {"mark_paid", "mark_unpaid"} and invoice.reference_type in TRUSTED_PAYMENT_REFERENCE_TYPES:
        log_action(
            actor=request.user,
            action=AuditAction.INVOICE_STATUS_CHANGE_BLOCKED,
            reference_type="invoice",
            reference_id=invoice.code or str(invoice.id),
            request=request,
            extra={
                "blocked_action": action,
                "invoice_id": invoice.id,
                "reference_type": invoice.reference_type,
                "reference_id": invoice.reference_id,
                "channel": "dashboard",
            },
        )
        messages.error(
            request,
            "لا يمكن تعليم فواتير الاشتراك/التوثيق كمدفوعة أو غير مدفوعة يدويًا. استخدم مسار الدفع الموثوق فقط.",
        )
    elif action == "mark_paid":
        invoice.mark_paid()
        invoice.clear_payment_confirmation()
        invoice.cancelled_at = None
        invoice.save(
            update_fields=[
                "status",
                "paid_at",
                "cancelled_at",
                "payment_confirmed",
                "payment_confirmed_at",
                "payment_provider",
                "payment_reference",
                "payment_event_id",
                "payment_amount",
                "payment_currency",
                "updated_at",
            ]
        )
        messages.success(request, f"تم تعليم الفاتورة {invoice.code or invoice.id} كمدفوعة")
    elif action == "mark_unpaid":
        invoice.status = InvoiceStatus.PENDING
        invoice.paid_at = None
        invoice.cancelled_at = None
        invoice.clear_payment_confirmation()
        invoice.save(
            update_fields=[
                "status",
                "paid_at",
                "cancelled_at",
                "payment_confirmed",
                "payment_confirmed_at",
                "payment_provider",
                "payment_reference",
                "payment_event_id",
                "payment_amount",
                "payment_currency",
                "updated_at",
            ]
        )
        messages.success(request, f"تم تعليم الفاتورة {invoice.code or invoice.id} كغير مدفوعة")
    else:
        messages.warning(request, "إجراء غير صالح")

    return redirect(safe_redirect_url(request, reverse("dashboard:billing_invoices_list")))


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

    qs = apply_user_level_filter(qs, request.user, assigned_field="assigned_to")

    if _want_xlsx(request) or _want_pdf(request) or _want_csv(request):
        headers_ar = ["الكود", "العميل", "النوع", "الأولوية", "الحالة", "الفريق", "المكلّف", "إجراءات"]
        export_rows = []
        for t in _limited_export_queryset(request, qs):
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

    if not can_access_object(request.user, ticket, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)
    comments = ticket.comments.select_related("created_by").order_by("-id")
    logs = ticket.status_logs.select_related("changed_by").order_by("-id")
    teams = SupportTeam.objects.filter(is_active=True).order_by("sort_order", "id")
    staff_users = dashboard_assignment_users("support", write=True, limit=150)

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
            "back_url": reverse("dashboard:support_tickets_list"),
            "assign_action_url": reverse("dashboard:support_ticket_assign_action", args=[ticket.id]),
            "status_action_url": reverse("dashboard:support_ticket_status_action", args=[ticket.id]),
        },
    )


@staff_member_required
@dashboard_access_required("promo")
def promo_inquiries_list(request: HttpRequest) -> HttpResponse:
    qs = _promo_inquiries_queryset()
    q = (request.GET.get("q") or "").strip()
    status_val = (request.GET.get("status") or "").strip()
    priority_val = (request.GET.get("priority") or "").strip()
    if q:
        qs = qs.filter(Q(code__icontains=q) | Q(requester__phone__icontains=q) | Q(description__icontains=q))
    if status_val:
        qs = qs.filter(status=status_val)
    if priority_val:
        qs = qs.filter(priority=priority_val)

    qs = apply_user_level_filter(qs, request.user, assigned_field="assigned_to")

    if _want_xlsx(request) or _want_pdf(request) or _want_csv(request):
        headers_ar = ["الكود", "العميل", "الأولوية", "الحالة", "الفريق", "المكلّف", "إجراءات"]
        export_rows = []
        for t in _limited_export_queryset(request, qs):
            code = t.code or t.id
            phone = getattr(getattr(t, "requester", None), "phone", "—") or "—"
            priority_label = getattr(t, "get_priority_display", lambda: t.priority)() or "—"
            status_label = getattr(t, "get_status_display", lambda: t.status)() or "—"
            team = getattr(getattr(t, "assigned_team", None), "name_ar", "—") or "—"
            assignee = getattr(getattr(t, "assigned_to", None), "phone", "—") or "—"
            detail_path = f"/dashboard/promo/inquiries/{t.id}/"
            export_rows.append([code, phone, priority_label, status_label, team, assignee, detail_path])

        if _want_csv(request):
            return _csv_response("promo_inquiries.csv", headers_ar, export_rows)

        from .exports import pdf_response, xlsx_response

        if _want_xlsx(request):
            return xlsx_response("promo_inquiries.xlsx", "استفسارات الترويج", headers_ar, export_rows)
        return pdf_response("promo_inquiries.pdf", "استفسارات الترويج", headers_ar, export_rows, landscape=True)

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    ctx = {
        "page_obj": page_obj,
        "q": q,
        "status_val": status_val,
        "priority_val": priority_val,
        "status_choices": SupportTicketStatus.choices,
        "priority_choices": SupportTicket._meta.get_field("priority").choices,
        "can_write": _dashboard_allowed(request.user, "promo", write=True),
    }
    ctx.update(_promo_dashboard_menu_context(active="inquiries"))
    return render(request, "dashboard/promo_inquiries_list.html", ctx)


@staff_member_required
@dashboard_access_required("promo")
def promo_inquiry_detail(request: HttpRequest, ticket_id: int) -> HttpResponse:
    ticket = get_object_or_404(
        SupportTicket.objects.select_related("requester", "assigned_team", "assigned_to", "last_action_by"),
        id=ticket_id,
        ticket_type=SupportTicketType.ADS,
    )

    if not can_access_object(request.user, ticket, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)

    comments = ticket.comments.select_related("created_by").order_by("-id")
    logs = ticket.status_logs.select_related("changed_by").order_by("-id")
    teams = SupportTeam.objects.filter(is_active=True).order_by("sort_order", "id")
    staff_users = _promo_staff_users()
    can_write = _dashboard_allowed(request.user, "promo", write=True)
    profile, _ = PromoInquiryProfile.objects.get_or_create(ticket=ticket)
    linked_requests = _promo_requests_queryset().filter(requester=ticket.requester)[:20]

    ctx = {
        "ticket": ticket,
        "profile": profile,
        "comments": comments,
        "logs": logs,
        "teams": teams,
        "staff_users": staff_users,
        "linked_requests": linked_requests,
        "status_choices": SupportTicketStatus.choices,
        "can_write": can_write,
        "back_url": reverse("dashboard:promo_inquiries_list"),
        "assign_action_url": reverse("dashboard:promo_assign_action", args=[ticket.id]),
        "status_action_url": reverse("dashboard:promo_inquiry_status_action", args=[ticket.id]),
        "profile_action_url": reverse("dashboard:promo_inquiry_profile_action", args=[ticket.id]),
    }
    ctx.update(_promo_dashboard_menu_context(active="inquiries"))
    return render(request, "dashboard/promo_inquiry_detail.html", ctx)


@staff_member_required
@dashboard_access_required("promo", write=True)
@require_POST
def promo_assign_action(request: HttpRequest, ticket_id: int) -> HttpResponse:
    ticket = get_object_or_404(SupportTicket, id=ticket_id, ticket_type=SupportTicketType.ADS)

    ap = getattr(request.user, "access_profile", None)
    if not can_access_object(request.user, ticket, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)

    team_id = request.POST.get("assigned_team") or None
    assigned_to = request.POST.get("assigned_to") or None
    if request.POST.get("assign_to_me") == "1" and not assigned_to:
        assigned_to = str(request.user.id)

    note = (request.POST.get("note") or "").strip()

    try:
        team_id = int(team_id) if team_id else None
    except Exception:
        team_id = None

    try:
        assigned_to = int(assigned_to) if assigned_to else None
    except Exception:
        assigned_to = None

    if ap and ap.level == "user":
        if assigned_to is not None and assigned_to != request.user.id:
            return HttpResponse("غير مصرح", status=403)

    if assigned_to is not None:
        assignee = dashboard_assignee_user(assigned_to, "promo", write=True)
        if not assignee:
            messages.error(request, "المستخدم المحدد غير صالح")
            return redirect("dashboard:promo_inquiry_detail", ticket_id=ticket.id)
        if not _is_promo_operator_user(assignee):
            messages.error(request, "لا يمكن التعيين إلا لمستخدم يملك صلاحية promo_operator")
            return redirect("dashboard:promo_inquiry_detail", ticket_id=ticket.id)

    try:
        assign_ticket(ticket=ticket, team_id=team_id, user_id=assigned_to, by_user=request.user, note=note)
        messages.success(request, "تم تحديث التعيين بنجاح")
    except Exception:
        logger.exception("promo_assign_action error")
        messages.error(request, "تعذر تحديث التعيين")

    return redirect(safe_redirect_url(request, reverse("dashboard:promo_inquiry_detail", args=[ticket.id])))


@staff_member_required
@dashboard_access_required("promo", write=True)
@require_POST
def promo_inquiry_profile_action(request: HttpRequest, ticket_id: int) -> HttpResponse:
    ticket = get_object_or_404(SupportTicket, id=ticket_id, ticket_type=SupportTicketType.ADS)
    profile, _ = PromoInquiryProfile.objects.get_or_create(ticket=ticket)
    linked_request_id = (request.POST.get("linked_request") or "").strip()
    profile.linked_request = PromoRequest.objects.filter(id=linked_request_id).first() if linked_request_id else None
    profile.detailed_request_url = (request.POST.get("detailed_request_url") or "").strip()
    profile.documentation_note = (request.POST.get("documentation_note") or "").strip()[:300]
    profile.operator_comment = (request.POST.get("operator_comment") or "").strip()[:300]
    profile.save(update_fields=["linked_request", "detailed_request_url", "documentation_note", "operator_comment", "updated_at"])
    messages.success(request, "تم حفظ بيانات الاستفسار الترويجي")
    return redirect("dashboard:promo_inquiry_detail", ticket_id=ticket.id)


@staff_member_required
@dashboard_access_required("promo", write=True)
@require_POST
def promo_inquiry_status_action(request: HttpRequest, ticket_id: int) -> HttpResponse:
    ticket = get_object_or_404(SupportTicket, id=ticket_id, ticket_type=SupportTicketType.ADS)

    if not can_access_object(request.user, ticket, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)

    status_new = (request.POST.get("status") or "").strip()
    note = (request.POST.get("note") or "").strip()
    if not status_new:
        messages.warning(request, "اختر حالة التذكرة")
        return redirect("dashboard:promo_inquiry_detail", ticket_id=ticket.id)

    try:
        change_ticket_status(ticket=ticket, new_status=status_new, by_user=request.user, note=note)
        messages.success(request, "تم تحديث حالة الاستفسار")
    except Exception:
        logger.exception("promo_inquiry_status_action error")
        messages.error(request, "تعذر تحديث الحالة")

    return redirect("dashboard:promo_inquiry_detail", ticket_id=ticket.id)


@staff_member_required
@dashboard_access_required("promo")
def promo_pricing(request: HttpRequest) -> HttpResponse:
    ensure_default_pricing_rules()
    rows = list(PromoPricingRule.objects.all().order_by("sort_order", "id"))
    groups = []
    for key, label in PROMO_MODULE_MENU:
        groups.append({"key": key, "label": label, "rows": [row for row in rows if row.service_type == key]})
    ctx = {"groups": groups}
    ctx.update(_promo_dashboard_menu_context(active="pricing"))
    return render(request, "dashboard/promo_pricing.html", ctx)


@staff_member_required
@dashboard_access_required("promo", write=True)
@require_POST
def promo_pricing_update_action(request: HttpRequest) -> HttpResponse:
    if not has_action_permission(request.user, "promo.quote_activate"):
        messages.error(request, "ليس لديك صلاحية تعديل تسعير الحملات.")
        return redirect("dashboard:promo_pricing")

    code = (request.POST.get("code") or "").strip()
    raw_price = (request.POST.get("amount") or "").strip()
    is_active = (request.POST.get("is_active") or "").strip().lower() in {"1", "true", "on", "yes"}

    rule = PromoPricingRule.objects.filter(code=code).first()
    if not rule:
        messages.error(request, "قاعدة التسعير غير صحيحة")
        return redirect("dashboard:promo_pricing")

    try:
        price = Decimal(raw_price)
        if price < 0:
            raise ValueError
    except Exception:
        messages.error(request, "السعر غير صحيح")
        return redirect("dashboard:promo_pricing")

    rule.amount = price
    rule.is_active = is_active
    rule.save(update_fields=["amount", "is_active", "updated_at"])
    messages.success(request, "تم حفظ التسعير")
    return redirect("dashboard:promo_pricing")


@staff_member_required
@dashboard_access_required("support", write=True)
@require_POST
def support_ticket_delete_reported_object_action(request: HttpRequest, ticket_id: int) -> HttpResponse:
    ticket = get_object_or_404(SupportTicket.objects.select_related("reported_user"), id=ticket_id)
    policy = ContentHideDeletePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="support.ticket",
        reference_id=str(ticket.id),
        extra={"surface": "dashboard.support_ticket_delete_reported_object_action"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بحذف المحتوى محل الشكوى")
        return redirect("dashboard:support_ticket_detail", ticket_id=ticket.id)

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

    try:
        record_support_target_delete_case(
            ticket=ticket,
            by_user=request.user,
            request=request,
            note=f"delete_reported:{reported_kind}",
        )
    except Exception:
        logger.exception("support_ticket_delete_reported_object_action moderation sync error")

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
    policy = SupportAssignPolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="support.ticket",
        reference_id=str(ticket.id),
        extra={"surface": "dashboard.support_ticket_assign_action"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتعيين هذه التذكرة")
        return redirect("dashboard:support_ticket_detail", ticket_id=ticket.id)

    if not can_access_object(request.user, ticket, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
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
    if assigned_to is not None and dashboard_assignee_user(assigned_to, "support", write=True) is None:
        messages.error(request, "المكلّف المحدد غير صالح لهذه اللوحة")
        return redirect("dashboard:support_ticket_detail", ticket_id=ticket.id)
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
    policy = SupportResolvePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="support.ticket",
        reference_id=str(ticket.id),
        extra={"surface": "dashboard.support_ticket_status_action"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتحديث حالة هذه التذكرة")
        return redirect("dashboard:support_ticket_detail", ticket_id=ticket.id)

    if not can_access_object(request.user, ticket, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
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
@dashboard_access_required("support", write=True)
@require_POST
def support_ticket_quick_update_action(request: HttpRequest, ticket_id: int) -> HttpResponse:
    ticket = get_object_or_404(SupportTicket, id=ticket_id)

    ap = getattr(request.user, "access_profile", None)
    if not can_access_object(request.user, ticket, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)

    team_id = request.POST.get("assigned_team") or None
    assigned_to = request.POST.get("assigned_to") or None
    status_new = (request.POST.get("status") or "").strip()
    description = (request.POST.get("description") or "").strip()
    comment_text = (request.POST.get("comment") or request.POST.get("text") or "").strip()
    note = (request.POST.get("note") or "").strip()
    attachment = request.FILES.get("attachment") or request.FILES.get("file")

    try:
        team_id = int(team_id) if team_id else None
    except Exception:
        team_id = None
    try:
        assigned_to = int(assigned_to) if assigned_to else None
    except Exception:
        assigned_to = None

    if team_id is not None or assigned_to is not None:
        assign_policy = SupportAssignPolicy.evaluate_and_log(
            request.user,
            request=request,
            reference_type="support.ticket",
            reference_id=str(ticket.id),
            extra={"surface": "dashboard.support_ticket_quick_update_action", "action_name": "assign"},
        )
        if not assign_policy.allowed:
            messages.error(request, "غير مصرح بتحديث إسناد التذكرة")
            return redirect("dashboard:support_ticket_detail", ticket_id=ticket.id)

    if any([status_new, description, comment_text, attachment]):
        resolve_policy = SupportResolvePolicy.evaluate_and_log(
            request.user,
            request=request,
            reference_type="support.ticket",
            reference_id=str(ticket.id),
            extra={"surface": "dashboard.support_ticket_quick_update_action", "action_name": "quick_update"},
        )
        if not resolve_policy.allowed:
            messages.error(request, "غير مصرح بتحديث هذه التذكرة")
            return redirect("dashboard:support_ticket_detail", ticket_id=ticket.id)

    if ap and ap.level == "user" and assigned_to is not None and assigned_to != request.user.id:
        return HttpResponse("غير مصرح", status=403)
    if assigned_to is not None and dashboard_assignee_user(assigned_to, "support", write=True) is None:
        messages.error(request, "المكلّف المحدد غير صالح لهذه اللوحة")
        return redirect("dashboard:support_ticket_detail", ticket_id=ticket.id)

    updated = False
    try:
        with transaction.atomic():
            if description and description != (ticket.description or "").strip():
                ticket.description = description
                ticket.last_action_by = request.user
                ticket.save(update_fields=["description", "last_action_by", "updated_at"])
                updated = True

            if team_id is not None or assigned_to is not None:
                assign_ticket(
                    ticket=ticket,
                    team_id=team_id,
                    user_id=assigned_to,
                    by_user=request.user,
                    note=note or comment_text,
                )
                updated = True

            if status_new:
                change_ticket_status(
                    ticket=ticket,
                    new_status=status_new,
                    by_user=request.user,
                    note=note or comment_text,
                )
                updated = True

            if comment_text:
                from apps.support.models import SupportComment

                SupportComment.objects.create(
                    ticket=ticket,
                    created_by=request.user,
                    text=comment_text[:300],
                    is_internal=(request.POST.get("is_internal") == "1"),
                )
                updated = True

            if attachment:
                from apps.support.models import SupportAttachment

                SupportAttachment.objects.create(
                    ticket=ticket,
                    uploaded_by=request.user,
                    file=attachment,
                )
                updated = True

        messages.success(request, "تم تحديث التذكرة بنجاح" if updated else "لم يتم إجراء أي تعديل")
    except ValidationError as exc:
        messages.error(request, exc.messages[0] if getattr(exc, "messages", None) else "تعذر تحديث التذكرة")
    except Exception:
        logger.exception("support_ticket_quick_update_action error")
        messages.error(request, "تعذر تحديث التذكرة")
    return redirect("dashboard:support_ticket_detail", ticket_id=ticket.id)


@staff_member_required
@dashboard_access_required("verify")
def verification_requests_list(request: HttpRequest) -> HttpResponse:
    qs = (
        VerificationRequest.objects.select_related("requester", "invoice", "assigned_to")
        .prefetch_related("requirements")
        .all()
        .order_by("-id")
    )
    q = (request.GET.get("q") or "").strip()
    status_val = (request.GET.get("status") or "").strip()
    if q:
        qs = qs.filter(Q(code__icontains=q) | Q(requester__phone__icontains=q))
    if status_val:
        qs = qs.filter(status=status_val)

    qs = apply_user_level_filter(qs, request.user, assigned_field="assigned_to")

    if _want_xlsx(request) or _want_pdf(request) or _want_csv(request):
        headers_ar = ["الكود", "المستخدم", "نوع/بنود التوثيق", "الأولوية", "الحالة", "فاتورة", "إجراءات"]
        export_rows = []
        for vr in _limited_export_queryset(request, qs):
            code = vr.code or vr.id
            phone = getattr(getattr(vr, "requester", None), "phone", "—") or "—"
            if vr.badge_type:
                badge = getattr(vr, "get_badge_type_display", lambda: getattr(vr, "badge_type", ""))() or "—"
            else:
                codes = [r.code for r in getattr(vr, "requirements", []).all()]
                badge = " / ".join([c for c in codes if c]) or "—"
            priority = getattr(vr, "priority", "—")
            status_label = getattr(vr, "get_status_display", lambda: vr.status)() or "—"
            invoice_code = getattr(getattr(vr, "invoice", None), "code", "—") or "—"
            detail_path = f"/dashboard/verification/{vr.id}/"
            export_rows.append([code, phone, badge, priority, status_label, invoice_code, detail_path])

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

    if not can_access_object(request.user, vr, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)
    docs = VerificationDocument.objects.filter(request=vr).select_related("decided_by").order_by("-id")
    reqs = (
        vr.requirements.select_related("decided_by")
        .prefetch_related("attachments")
        .order_by("sort_order", "id")
    )
    inv_lines = []
    if getattr(vr, "invoice", None) and hasattr(vr.invoice, "lines"):
        inv_lines = list(vr.invoice.lines.all().order_by("sort_order", "id"))
    return render(
        request,
        "dashboard/verification_request_detail.html",
        {"vr": vr, "docs": docs, "reqs": reqs, "inv_lines": inv_lines},
    )


@staff_member_required
@dashboard_access_required("verify")
def verified_badges_list(request: HttpRequest) -> HttpResponse:
    qs = (
        VerifiedBadge.objects.select_related("user", "request")
        .all()
        .order_by("-is_active", "-id")
    )
    q = (request.GET.get("q") or "").strip()
    active_val = (request.GET.get("active") or "").strip()
    if q:
        qs = qs.filter(
            Q(user__phone__icontains=q)
            | Q(verification_code__icontains=q)
            | Q(request__code__icontains=q)
        )
    if active_val in ("1", "true", "yes"):
        qs = qs.filter(is_active=True)
    if active_val in ("0", "false", "no"):
        qs = qs.filter(is_active=False)

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    return render(
        request,
        "dashboard/verified_badges_list.html",
        {
            "page_obj": page_obj,
            "q": q,
            "active_val": active_val,
        },
    )


@staff_member_required
@dashboard_access_required("verify", write=True)
@require_POST
def verified_badge_deactivate_action(request: HttpRequest, badge_id: int) -> HttpResponse:
    badge = get_object_or_404(VerifiedBadge, id=badge_id)
    try:
        badge.is_active = False
        badge.expires_at = timezone.now()
        badge.save(update_fields=["is_active", "expires_at"])
        sync_provider_badges(badge.user)
        messages.success(request, "تم إلغاء التفعيل")
    except Exception:
        logger.exception("verified_badge_deactivate_action error")
        messages.error(request, "تعذر إلغاء التفعيل")
    return redirect("dashboard:verified_badges_list")


@staff_member_required
@dashboard_access_required("verify", write=True)
@require_POST
def verified_badge_renew_action(request: HttpRequest, badge_id: int) -> HttpResponse:
    badge = get_object_or_404(VerifiedBadge.objects.select_related("user"), id=badge_id)
    user = badge.user

    # Create a renewal verification request with a single approved requirement.
    try:
        vr = VerificationRequest.objects.create(
            requester=user,
            badge_type=badge.badge_type,
            status=VerificationStatus.IN_REVIEW,
            priority=2,
        )
        VerificationRequirement.objects.create(
            request=vr,
            badge_type=badge.badge_type,
            code=badge.verification_code or ("B1" if badge.badge_type == "blue" else "G1"),
            title=badge.verification_title or "",
            is_approved=True,
            decision_note="تجديد",
            decided_by=request.user,
            decided_at=timezone.now(),
            sort_order=0,
        )
        vr = finalize_request_and_create_invoice(vr=vr, by_user=request.user)
        messages.success(request, f"تم إنشاء فاتورة تجديد: {vr.invoice.code if vr.invoice else vr.code}")
    except Exception:
        logger.exception("verified_badge_renew_action error")
        messages.error(request, "تعذر إنشاء طلب تجديد")
    return redirect("dashboard:verified_badges_list")


@staff_member_required
@dashboard_access_required("verify", write=True)
@require_POST
def verification_requirement_decision_action(request: HttpRequest, req_id: int) -> HttpResponse:
    req = get_object_or_404(VerificationRequirement.objects.select_related("request"), id=req_id)
    vr = req.request

    if not can_access_object(request.user, vr, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)

    raw = (request.POST.get("is_approved") or "").strip().lower()
    if raw not in ("true", "false", "1", "0", "yes", "no"):
        messages.warning(request, "اختر قرار البند")
        return redirect("dashboard:verification_request_detail", verification_id=vr.id)
    is_approved = raw in ("true", "1", "yes")
    note = (request.POST.get("decision_note") or "").strip()
    try:
        decide_requirement(req=req, is_approved=is_approved, note=note, by_user=request.user)
        messages.success(request, "تم حفظ قرار البند")
    except Exception:
        logger.exception("verification_requirement_decision_action error")
        messages.error(request, "تعذر حفظ قرار البند")
    return redirect("dashboard:verification_request_detail", verification_id=vr.id)


@staff_member_required
@dashboard_access_required("verify", write=True)
@require_POST
def verification_finalize_action(request: HttpRequest, verification_id: int) -> HttpResponse:
    vr = get_object_or_404(VerificationRequest, id=verification_id)
    policy = VerificationFinalizePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="verification.request",
        reference_id=str(vr.id),
        extra={"surface": "dashboard.verification_finalize_action"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بإنهاء هذا الطلب")
        return redirect("dashboard:verification_request_detail", verification_id=verification_id)

    if not can_access_object(request.user, vr, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
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
    policy = VerificationFinalizePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="verification.request",
        reference_id=str(vr.id),
        extra={"surface": "dashboard.verification_activate_action", "action_name": "activate"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتفعيل طلب التوثيق")
        return redirect("dashboard:verification_request_detail", verification_id=verification_id)

    if not can_access_object(request.user, vr, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)
    try:
        activate_verification_after_payment(vr=vr)
        messages.success(request, "تم تفعيل التوثيق بنجاح")
    except Exception as e:
        messages.error(request, str(e) or "تعذر تفعيل طلب التوثيق")
    return redirect("dashboard:verification_request_detail", verification_id=verification_id)


@staff_member_required
@dashboard_access_required("verify")
def verification_ops(request: HttpRequest) -> HttpResponse:
    """Unified verification operations page.

    Shows:
    - Verification inquiries (SupportTicketType.VERIFY) codes HDxxxx
    - Verification requests (VerificationRequest) codes ADxxxx
    """

    q = (request.GET.get("q") or "").strip()
    inq_status = (request.GET.get("inq_status") or "").strip()
    req_status = (request.GET.get("req_status") or "").strip()

    inq_qs = (
        SupportTicket.objects.select_related("requester", "assigned_team", "assigned_to")
        .filter(ticket_type=SupportTicketType.VERIFY)
        .order_by("-id")
    )
    if q:
        inq_qs = inq_qs.filter(Q(code__icontains=q) | Q(requester__phone__icontains=q) | Q(description__icontains=q))
    if inq_status:
        inq_qs = inq_qs.filter(status=inq_status)

    req_qs = (
        VerificationRequest.objects.select_related("requester", "invoice", "assigned_to")
        .prefetch_related("requirements")
        .all()
        .order_by("-id")
    )
    if q:
        req_qs = req_qs.filter(Q(code__icontains=q) | Q(requester__phone__icontains=q))
    if req_status:
        req_qs = req_qs.filter(status=req_status)

    inq_qs = apply_user_level_filter(inq_qs, request.user, assigned_field="assigned_to")
    req_qs = apply_user_level_filter(req_qs, request.user, assigned_field="assigned_to")

    inq_paginator = Paginator(inq_qs, 15)
    inq_page_obj = inq_paginator.get_page(request.GET.get("inq_page") or "1")

    req_paginator = Paginator(req_qs, 15)
    req_page_obj = req_paginator.get_page(request.GET.get("req_page") or "1")

    _v_agg = VerificationRequest.objects.aggregate(
        total=Count("id"),
        new=Count("id", filter=Q(status=VerificationStatus.NEW)),
        in_review=Count("id", filter=Q(status=VerificationStatus.IN_REVIEW)),
        approved=Count("id", filter=Q(status=VerificationStatus.APPROVED)),
        active=Count("id", filter=Q(status=VerificationStatus.ACTIVE)),
    )
    _inq_new = SupportTicket.objects.filter(ticket_type=SupportTicketType.VERIFY, status=SupportTicketStatus.NEW).count()
    stats = {
        "total_requests": _v_agg["total"],
        "new_requests": _v_agg["new"],
        "in_review": _v_agg["in_review"],
        "approved": _v_agg["approved"],
        "active": _v_agg["active"],
        "new_inquiries": _inq_new,
    }

    return render(
        request,
        "dashboard/verification_ops.html",
        {
            "q": q,
            "inq_status": inq_status,
            "req_status": req_status,
            "inq_page_obj": inq_page_obj,
            "req_page_obj": req_page_obj,
            "inq_status_choices": SupportTicketStatus.choices,
            "req_status_choices": VerificationStatus.choices,
            "stats": stats,
        },
    )


@staff_member_required
@dashboard_access_required("verify")
def verification_inquiry_detail(request: HttpRequest, ticket_id: int) -> HttpResponse:
    ticket = get_object_or_404(
        SupportTicket.objects.select_related("requester", "assigned_team", "assigned_to", "last_action_by"),
        id=ticket_id,
        ticket_type=SupportTicketType.VERIFY,
    )

    if not can_access_object(request.user, ticket, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)

    comments = ticket.comments.select_related("created_by").order_by("-id")
    logs = ticket.status_logs.select_related("changed_by").order_by("-id")
    teams = SupportTeam.objects.filter(is_active=True).order_by("sort_order", "id")
    staff_users = dashboard_assignment_users("verify", write=True, limit=150)
    can_write = _dashboard_allowed(request.user, "verify", write=True)

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
            "reported_user_profile_url": "",
            "reported_target_label": "",
            "reported_target_url": "",
            "can_write": can_write,
            "back_url": reverse("dashboard:verification_ops"),
            "assign_action_url": reverse("dashboard:verification_inquiry_assign_action", args=[ticket.id]),
            "status_action_url": reverse("dashboard:verification_inquiry_status_action", args=[ticket.id]),
        },
    )


@staff_member_required
@dashboard_access_required("verify", write=True)
@require_POST
def verification_inquiry_assign_action(request: HttpRequest, ticket_id: int) -> HttpResponse:
    ticket = get_object_or_404(SupportTicket, id=ticket_id, ticket_type=SupportTicketType.VERIFY)

    ap = getattr(request.user, "access_profile", None)
    if not can_access_object(request.user, ticket, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
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

    if ap and ap.level == "user":
        if assigned_to is not None and assigned_to != request.user.id:
            return HttpResponse("غير مصرح", status=403)
    if assigned_to is not None and dashboard_assignee_user(assigned_to, "verify", write=True) is None:
        messages.error(request, "المكلّف المحدد غير صالح لهذه اللوحة")
        return redirect("dashboard:verification_inquiry_detail", ticket_id=ticket.id)

    try:
        assign_ticket(ticket=ticket, team_id=team_id, user_id=assigned_to, by_user=request.user, note=note)
        messages.success(request, "تم تحديث التعيين بنجاح")
    except Exception:
        logger.exception("verification_inquiry_assign_action error")
        messages.error(request, "تعذر تحديث التعيين")

    return redirect("dashboard:verification_inquiry_detail", ticket_id=ticket.id)


@staff_member_required
@dashboard_access_required("verify", write=True)
@require_POST
def verification_inquiry_status_action(request: HttpRequest, ticket_id: int) -> HttpResponse:
    ticket = get_object_or_404(SupportTicket, id=ticket_id, ticket_type=SupportTicketType.VERIFY)

    if not can_access_object(request.user, ticket, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)

    status_new = (request.POST.get("status") or "").strip()
    note = (request.POST.get("note") or "").strip()
    if not status_new:
        messages.warning(request, "اختر حالة التذكرة")
        return redirect("dashboard:verification_inquiry_detail", ticket_id=ticket.id)

    try:
        change_ticket_status(ticket=ticket, new_status=status_new, by_user=request.user, note=note)
        messages.success(request, "تم تحديث حالة الاستفسار")
    except Exception:
        logger.exception("verification_inquiry_status_action error")
        messages.error(request, "تعذر تحديث الحالة")

    return redirect("dashboard:verification_inquiry_detail", ticket_id=ticket.id)


@staff_member_required
@dashboard_access_required("promo")
def promo_requests_list(request: HttpRequest) -> HttpResponse:
    qs = _promo_requests_queryset()
    inquiries_qs = _promo_inquiries_queryset()
    q = (request.GET.get("q") or "").strip()
    status_val = (request.GET.get("status") or "").strip()
    ops_status_val = (request.GET.get("ops_status") or "").strip()
    if q:
        qs = qs.filter(Q(code__icontains=q) | Q(title__icontains=q) | Q(requester__phone__icontains=q))
        inquiries_qs = inquiries_qs.filter(
            Q(code__icontains=q) | Q(description__icontains=q) | Q(requester__phone__icontains=q)
        )
    if status_val:
        qs = qs.filter(status=status_val)
    if ops_status_val:
        qs = qs.filter(ops_status=ops_status_val)

    qs = apply_user_level_filter(qs, request.user, assigned_field="assigned_to")
    inquiries_qs = apply_user_level_filter(inquiries_qs, request.user, assigned_field="assigned_to")

    paginator = Paginator(qs, 25)
    requests_page = paginator.get_page(request.GET.get("page") or "1")
    inquiries_rows = list(inquiries_qs[:8])
    recent_requests = list(qs[:8])
    # Single aggregate for all promo stats
    _promo_agg = qs.aggregate(
        total=Count("id"),
        active=Count("id", filter=Q(status=PromoRequestStatus.ACTIVE)),
        completed=Count("id", filter=Q(ops_status=PromoOpsStatus.COMPLETED)),
    )
    stats = {
        "total_requests": _promo_agg["total"],
        "active_requests": _promo_agg["active"],
        "completed_requests": _promo_agg["completed"],
        "new_inquiries": inquiries_qs.filter(status=SupportTicketStatus.NEW).count(),
    }
    ctx = {
        "requests_page": requests_page,
        "inquiries_rows": inquiries_rows,
        "recent_requests": recent_requests,
        "q": q,
        "status_val": status_val,
        "ops_status_val": ops_status_val,
        "status_choices": PromoRequestStatus.choices,
        "ops_status_choices": PromoOpsStatus.choices,
        "stats": stats,
        "can_write": _dashboard_allowed(request.user, "promo", write=True),
    }
    ctx.update(_promo_dashboard_menu_context(active="dashboard"))
    return render(request, "dashboard/promo_requests_list.html", ctx)


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

    if not can_access_object(request.user, pr, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)
    items = pr.items.select_related("target_provider", "target_portfolio_item").prefetch_related("assets").all().order_by("sort_order", "id")
    assets = pr.assets.select_related("item").all().order_by("-id")
    ur = _promo_unified_request(pr)
    status_logs = ur.status_logs.select_related("changed_by").all() if ur else []
    assignment_logs = ur.assignment_logs.select_related("from_user", "to_user", "changed_by").all() if ur else []
    staff_users = _promo_staff_users()
    invoice_lines = pr.invoice.lines.all() if pr.invoice_id and hasattr(pr.invoice, "lines") else []
    active_key = items[0].service_type if len(items) == 1 else "dashboard"
    ctx = {
        "pr": pr,
        "items": items,
        "assets": assets,
        "ur": ur,
        "status_logs": status_logs,
        "assignment_logs": assignment_logs,
        "staff_users": staff_users,
        "invoice_lines": invoice_lines,
        "can_write": _dashboard_allowed(request.user, "promo", write=True),
        "back_url": reverse("dashboard:promo_requests_list"),
    }
    ctx.update(_promo_dashboard_menu_context(active=active_key))
    return render(request, "dashboard/promo_request_detail.html", ctx)


@staff_member_required
@dashboard_access_required("promo", write=True)
@require_POST
def promo_request_assign_action(request: HttpRequest, promo_id: int) -> HttpResponse:
    if not has_action_permission(request.user, "promo.quote_activate"):
        messages.error(request, "ليس لديك صلاحية تعديل هذا الطلب.")
        return redirect("dashboard:promo_request_detail", promo_id=promo_id)

    pr = get_object_or_404(PromoRequest, id=promo_id)
    ap = getattr(request.user, "access_profile", None)
    if not can_access_object(request.user, pr, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)

    assigned_to = request.POST.get("assigned_to") or None
    note = (request.POST.get("note") or "").strip()
    try:
        assigned_to = int(assigned_to) if assigned_to else None
    except Exception:
        assigned_to = None

    if ap and ap.level == "user" and assigned_to not in (None, request.user.id):
        return HttpResponse("غير مصرح", status=403)
    assignee = None
    if assigned_to is not None:
        assignee = dashboard_assignee_user(assigned_to, "promo", write=True)
        if not assignee or not _is_promo_operator_user(assignee):
            messages.error(request, "المكلّف غير صحيح")
            return redirect("dashboard:promo_request_detail", promo_id=pr.id)

    pr.assigned_to = assignee
    pr.assigned_at = timezone.now() if assignee else None
    pr.save(update_fields=["assigned_to", "assigned_at", "updated_at"])
    _sync_promo_to_unified(pr=pr, changed_by=request.user)
    if note:
        ur = _promo_unified_request(pr)
        log = UnifiedRequestAssignmentLog.objects.filter(request=ur, changed_by=request.user).order_by("-id").first() if ur else None
        if log and not log.note:
            log.note = note[:200]
            log.save(update_fields=["note"])
    messages.success(request, "تم تحديث الإسناد")
    return redirect("dashboard:promo_request_detail", promo_id=pr.id)


@staff_member_required
@dashboard_access_required("promo", write=True)
@require_POST
def promo_request_ops_status_action(request: HttpRequest, promo_id: int) -> HttpResponse:
    pr = get_object_or_404(PromoRequest, id=promo_id)
    policy = PromoQuoteActivatePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="promo.request",
        reference_id=str(pr.id),
        extra={"surface": "dashboard.promo_request_ops_status_action", "action_name": "ops_status"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتحديث تشغيل هذه الحملة")
        return redirect("dashboard:promo_request_detail", promo_id=promo_id)
    if not can_access_object(request.user, pr, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)
    status_new = (request.POST.get("status") or "").strip()
    note = (request.POST.get("note") or "").strip()
    if status_new not in PromoOpsStatus.values:
        messages.warning(request, "حالة التنفيذ غير صحيحة")
        return redirect("dashboard:promo_request_detail", promo_id=pr.id)
    try:
        old_status = pr.ops_status
        set_promo_ops_status(pr=pr, new_status=status_new, by_user=request.user, note=note)
        if old_status != status_new and note:
            ur = _promo_unified_request(pr)
            _promo_attach_note_to_latest_log(
                ur=ur,
                model_cls=UnifiedRequestStatusLog,
                to_value=status_new,
                note=note,
                changed_by=request.user,
            )
        messages.success(request, "تم تحديث حالة التنفيذ")
    except Exception as e:
        messages.error(request, str(e) or "تعذر تحديث حالة التنفيذ")
    return redirect("dashboard:promo_request_detail", promo_id=pr.id)


@staff_member_required
@dashboard_access_required("promo")
def promo_service_board(request: HttpRequest, service_key: str) -> HttpResponse:
    service_map = dict(PROMO_MODULE_MENU)
    if service_key not in service_map:
        return HttpResponse("غير موجود", status=404)
    qs = (
        PromoRequestItem.objects.select_related(
            "request",
            "request__requester",
            "request__invoice",
            "request__assigned_to",
            "target_provider",
            "target_portfolio_item",
        )
        .prefetch_related("assets")
        .filter(service_type=service_key)
        .order_by("-id")
    )
    q = (request.GET.get("q") or "").strip()
    status_val = (request.GET.get("status") or "").strip()
    ops_status_val = (request.GET.get("ops_status") or "").strip()
    if q:
        qs = qs.filter(
            Q(title__icontains=q)
            | Q(request__code__icontains=q)
            | Q(request__requester__phone__icontains=q)
        )
    if status_val:
        qs = qs.filter(request__status=status_val)
    if ops_status_val:
        qs = qs.filter(request__ops_status=ops_status_val)
    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == "user":
        qs = qs.filter(Q(request__assigned_to=request.user) | Q(request__assigned_to__isnull=True))

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    ctx = {
        "page_obj": page_obj,
        "service_key": service_key,
        "service_label": service_map[service_key],
        "q": q,
        "status_val": status_val,
        "ops_status_val": ops_status_val,
        "status_choices": PromoRequestStatus.choices,
        "ops_status_choices": PromoOpsStatus.choices,
    }
    ctx.update(_promo_dashboard_menu_context(active=service_key))
    return render(request, "dashboard/promo_service_board.html", ctx)


@staff_member_required
@dashboard_access_required("promo", write=True)
@require_POST
def promo_quote_action(request: HttpRequest, promo_id: int) -> HttpResponse:
    pr = get_object_or_404(PromoRequest, id=promo_id)
    policy = PromoQuoteActivatePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="promo.request",
        reference_id=str(pr.id),
        extra={"surface": "dashboard.promo_quote_action", "action_name": "quote"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتسعير هذه الحملة")
        return redirect("dashboard:promo_request_detail", promo_id=promo_id)

    if not can_access_object(request.user, pr, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
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
    policy = PromoQuoteActivatePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="promo.request",
        reference_id=str(pr.id),
        extra={"surface": "dashboard.promo_reject_action", "action_name": "reject"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح برفض هذه الحملة")
        return redirect("dashboard:promo_request_detail", promo_id=promo_id)

    if not can_access_object(request.user, pr, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
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
    policy = PromoQuoteActivatePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="promo.request",
        reference_id=str(pr.id),
        extra={"surface": "dashboard.promo_activate_action", "action_name": "activate"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتفعيل هذه الحملة")
        return redirect("dashboard:promo_request_detail", promo_id=promo_id)

    if not can_access_object(request.user, pr, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)
    try:
        activate_promo_after_payment(pr=pr)
        messages.success(request, "تم تفعيل الحملة")
    except Exception as e:
        messages.error(request, str(e) or "تعذر تفعيل الحملة")
    return redirect("dashboard:promo_request_detail", promo_id=promo_id)


# ---------- Home Banner (Carousel) Management ----------


def _parse_home_banner_scale(raw_value: str | None, *, default: int, minimum: int, maximum: int) -> int:
    try:
        value = int(str(raw_value or "").strip())
    except (TypeError, ValueError):
        return default
    return max(minimum, min(value, maximum))


def _home_banner_scale_payload(post_data, *, prefix: str = "") -> dict[str, int]:
    return {
        "mobile_scale": _parse_home_banner_scale(
            post_data.get(f"{prefix}mobile_scale"),
            default=100,
            minimum=40,
            maximum=140,
        ),
        "tablet_scale": _parse_home_banner_scale(
            post_data.get(f"{prefix}tablet_scale"),
            default=100,
            minimum=40,
            maximum=150,
        ),
        "desktop_scale": _parse_home_banner_scale(
            post_data.get(f"{prefix}desktop_scale"),
            default=100,
            minimum=40,
            maximum=160,
        ),
    }


@staff_member_required
@dashboard_access_required("promo")
def promo_home_banners_list(request: HttpRequest) -> HttpResponse:
    qs = HomeBanner.objects.select_related("provider", "created_by").all().order_by("display_order", "-created_at")
    ctx = {
        "banners": qs,
        "media_type_choices": HomeBannerMediaType.choices,
        "mobile_scale_min": 40,
        "mobile_scale_max": 140,
        "tablet_scale_min": 40,
        "tablet_scale_max": 150,
        "desktop_scale_min": 40,
        "desktop_scale_max": 160,
        "default_banner_scale": 100,
    }
    ctx.update(_promo_dashboard_menu_context(active=PromoServiceType.HOME_BANNER))
    return render(request, "dashboard/promo_home_banners.html", ctx)


@staff_member_required
@dashboard_access_required("promo", write=True)
@require_POST
def promo_home_banner_create(request: HttpRequest) -> HttpResponse:
    title = (request.POST.get("title") or "").strip()
    media_type = (request.POST.get("media_type") or "image").strip()
    link_url = (request.POST.get("link_url") or "").strip()
    display_order = request.POST.get("display_order") or "0"
    mobile_scale = request.POST.get("mobile_scale")
    tablet_scale = request.POST.get("tablet_scale")
    desktop_scale = request.POST.get("desktop_scale")
    provider_id = request.POST.get("provider") or ""
    start_at = (request.POST.get("start_at") or "").strip()
    end_at = (request.POST.get("end_at") or "").strip()
    media_file = request.FILES.get("media_file")

    if not title or not media_file:
        messages.error(request, "العنوان وملف الوسائط مطلوبان")
        return redirect("dashboard:promo_home_banners")

    try:
        order = int(display_order)
    except (ValueError, TypeError):
        order = 0

    provider = None
    if provider_id:
        provider = ProviderProfile.objects.filter(id=provider_id).first()

    banner = HomeBanner(
        title=title,
        media_type=media_type,
        media_file=media_file,
        link_url=link_url,
        display_order=order,
        **_home_banner_scale_payload(
            {
                "mobile_scale": mobile_scale,
                "tablet_scale": tablet_scale,
                "desktop_scale": desktop_scale,
            }
        ),
        provider=provider,
        created_by=request.user,
        is_active=True,
    )

    if start_at:
        try:
            banner.start_at = make_aware(datetime.strptime(start_at, "%Y-%m-%dT%H:%M"))
        except (ValueError, TypeError):
            pass

    if end_at:
        try:
            banner.end_at = make_aware(datetime.strptime(end_at, "%Y-%m-%dT%H:%M"))
        except (ValueError, TypeError):
            pass

    try:
        banner.full_clean()
        banner.save()
    except ValidationError as exc:
        messages.error(
            request,
            _promo_dashboard_first_error(
                getattr(exc, "message_dict", None) or getattr(exc, "messages", None),
                "تعذر حفظ البانر",
            ),
        )
        return redirect("dashboard:promo_home_banners")
    messages.success(request, f"تم إنشاء البانر: {title}")
    return redirect("dashboard:promo_home_banners")


@staff_member_required
@dashboard_access_required("promo", write=True)
@require_POST
def promo_home_banner_update(request: HttpRequest, banner_id: int) -> HttpResponse:
    banner = get_object_or_404(HomeBanner, id=banner_id)

    title = (request.POST.get("title") or "").strip()
    if title:
        banner.title = title

    media_type = (request.POST.get("media_type") or "").strip()
    if media_type:
        banner.media_type = media_type

    link_url = request.POST.get("link_url")
    if link_url is not None:
        banner.link_url = link_url.strip()

    display_order = request.POST.get("display_order")
    if display_order is not None:
        try:
            banner.display_order = int(display_order)
        except (ValueError, TypeError):
            pass

    if "mobile_scale" in request.POST:
        banner.mobile_scale = _parse_home_banner_scale(
            request.POST.get("mobile_scale"),
            default=banner.mobile_scale or 100,
            minimum=40,
            maximum=140,
        )

    if "desktop_scale" in request.POST:
        banner.desktop_scale = _parse_home_banner_scale(
            request.POST.get("desktop_scale"),
            default=banner.desktop_scale or 100,
            minimum=40,
            maximum=160,
        )

    if "tablet_scale" in request.POST:
        banner.tablet_scale = _parse_home_banner_scale(
            request.POST.get("tablet_scale"),
            default=banner.tablet_scale or 100,
            minimum=40,
            maximum=150,
        )

    provider_id = request.POST.get("provider") or ""
    if provider_id:
        banner.provider = ProviderProfile.objects.filter(id=provider_id).first()
    elif "provider" in request.POST:
        banner.provider = None

    start_at = (request.POST.get("start_at") or "").strip()
    if start_at:
        try:
            banner.start_at = make_aware(datetime.strptime(start_at, "%Y-%m-%dT%H:%M"))
        except (ValueError, TypeError):
            pass
    elif "start_at" in request.POST:
        banner.start_at = None

    end_at = (request.POST.get("end_at") or "").strip()
    if end_at:
        try:
            banner.end_at = make_aware(datetime.strptime(end_at, "%Y-%m-%dT%H:%M"))
        except (ValueError, TypeError):
            pass
    elif "end_at" in request.POST:
        banner.end_at = None

    media_file = request.FILES.get("media_file")
    if media_file:
        banner.media_file = media_file

    is_active = request.POST.get("is_active")
    banner.is_active = is_active == "on" or is_active == "1"

    try:
        banner.full_clean()
        banner.save()
    except ValidationError as exc:
        messages.error(
            request,
            _promo_dashboard_first_error(
                getattr(exc, "message_dict", None) or getattr(exc, "messages", None),
                "تعذر تحديث البانر",
            ),
        )
        return redirect("dashboard:promo_home_banners")
    messages.success(request, f"تم تحديث البانر: {banner.title}")
    return redirect("dashboard:promo_home_banners")


@staff_member_required
@dashboard_access_required("promo", write=True)
@require_POST
def promo_home_banner_toggle(request: HttpRequest, banner_id: int) -> HttpResponse:
    banner = get_object_or_404(HomeBanner, id=banner_id)
    banner.is_active = not banner.is_active
    banner.save(update_fields=["is_active", "updated_at"])
    status_text = "مفعل" if banner.is_active else "معطل"
    messages.success(request, f"تم تبديل حالة البانر: {status_text}")
    return redirect("dashboard:promo_home_banners")


@staff_member_required
@dashboard_access_required("promo", write=True)
@require_POST
def promo_home_banner_delete(request: HttpRequest, banner_id: int) -> HttpResponse:
    banner = get_object_or_404(HomeBanner, id=banner_id)
    banner.delete()
    messages.success(request, "تم حذف البانر")
    return redirect("dashboard:promo_home_banners")


# ---------- Admin-Created Promo Campaign ----------


@staff_member_required
@dashboard_access_required("promo", write=True)
def promo_campaign_create(request: HttpRequest) -> HttpResponse:
    """Allow staff to create a promo campaign directly (without a client request)."""

    if request.method == "POST":
        title = (request.POST.get("title") or "").strip()
        ad_type = (request.POST.get("ad_type") or "").strip()
        start_at_str = (request.POST.get("start_at") or "").strip()
        end_at_str = (request.POST.get("end_at") or "").strip()
        send_at_str = (request.POST.get("send_at") or "").strip()
        frequency = (request.POST.get("frequency") or PromoFrequency.S60).strip()
        position = (request.POST.get("position") or PromoPosition.NORMAL).strip()
        search_scope = (request.POST.get("search_scope") or "").strip()
        search_position = (request.POST.get("search_position") or "").strip()
        target_category = (request.POST.get("target_category") or "").strip()
        target_city = (request.POST.get("target_city") or "").strip()
        redirect_url = (request.POST.get("redirect_url") or "").strip()
        provider_id = (request.POST.get("provider") or "").strip()
        portfolio_item_id = (request.POST.get("portfolio_item") or "").strip()
        status_val = (request.POST.get("status") or PromoRequestStatus.ACTIVE).strip()
        service_types = [svc for svc in request.POST.getlist("service_types") if svc in PromoServiceType.values]
        promo_message_title = (request.POST.get("promo_message_title") or "").strip()
        promo_message_body = (request.POST.get("promo_message_body") or "").strip()
        promo_attachment_specs = (request.POST.get("promo_attachment_specs") or "").strip()
        sponsor_name = (request.POST.get("sponsor_name") or "").strip()
        sponsor_url = (request.POST.get("sponsor_url") or "").strip()
        sponsorship_months_raw = (request.POST.get("sponsorship_months") or "").strip()
        sponsorship_message_body = (request.POST.get("sponsorship_message_body") or "").strip()
        sponsorship_attachment_specs = (request.POST.get("sponsorship_attachment_specs") or "").strip()
        use_notification_channel = bool(request.POST.get("use_notification_channel"))
        use_chat_channel = bool(request.POST.get("use_chat_channel"))
        uploaded_assets = [file_obj for file_obj in request.FILES.getlist("assets") if file_obj]
        request_scale_payload = _home_banner_scale_payload(request.POST, prefix="home_banner_")
        applies_home_banner_scales = PromoServiceType.HOME_BANNER in service_types or (
            not service_types and ad_type == PromoAdType.BANNER_HOME
        )

        if not title:
            messages.error(request, "عنوان الحملة مطلوب")
            return redirect("dashboard:promo_campaign_create")

        if not service_types and not ad_type:
            messages.error(request, "نوع الإعلان مطلوب عند إنشاء حملة مباشرة بدون بنود خدمات.")
            return redirect("dashboard:promo_campaign_create")

        start_at = _parse_datetime_local(start_at_str)
        end_at = _parse_datetime_local(end_at_str)
        send_at = _parse_datetime_local(send_at_str)

        if start_at_str and start_at is None:
            messages.error(request, "صيغة تاريخ البداية غير صحيحة")
            return redirect("dashboard:promo_campaign_create")
        if end_at_str and end_at is None:
            messages.error(request, "صيغة تاريخ النهاية غير صحيحة")
            return redirect("dashboard:promo_campaign_create")
        if send_at_str and send_at is None:
            messages.error(request, "صيغة وقت الإرسال غير صحيحة")
            return redirect("dashboard:promo_campaign_create")
        if start_at and end_at and end_at <= start_at:
            messages.error(request, "تاريخ النهاية يجب أن يكون بعد تاريخ البداية")
            return redirect("dashboard:promo_campaign_create")
        if status_val not in {PromoRequestStatus.ACTIVE, PromoRequestStatus.NEW}:
            messages.error(request, "حالة الحملة غير صحيحة")
            return redirect("dashboard:promo_campaign_create")

        provider = None
        if provider_id:
            provider = ProviderProfile.objects.filter(id=provider_id).first()
            if provider is None:
                messages.error(request, "مقدم الخدمة المحدد غير موجود")
                return redirect("dashboard:promo_campaign_create")

        portfolio_item = None
        if portfolio_item_id:
            portfolio_item = ProviderPortfolioItem.objects.select_related("provider").filter(id=portfolio_item_id).first()
            if portfolio_item is None:
                messages.error(request, "عنصر المعرض المحدد غير موجود")
                return redirect("dashboard:promo_campaign_create")
            if provider is not None and portfolio_item.provider_id != provider.id:
                messages.error(request, "عنصر المعرض لا يتبع مقدم الخدمة المحدد")
                return redirect("dashboard:promo_campaign_create")
            provider = provider or portfolio_item.provider

        requires_media_assets = bool(service_types and any(svc in _PROMO_DASHBOARD_MEDIA_SERVICE_TYPES for svc in service_types))
        requires_media_assets = requires_media_assets or (not service_types and ad_type in _PROMO_DASHBOARD_MEDIA_AD_TYPES)
        if requires_media_assets and not uploaded_assets:
            messages.error(request, "هذه الحملة تحتاج رفع صورة أو فيديو واحد على الأقل.")
            return redirect("dashboard:promo_campaign_create")
        if not service_types and ad_type in _PROMO_DASHBOARD_UNSUPPORTED_AD_TYPES:
            messages.error(request, "هذا النوع من الحملات غير متاح للإنشاء المباشر لأنه غير مدعوم على الواجهات العامة.")
            return redirect("dashboard:promo_campaign_create")

        range_service_types = {
            PromoServiceType.HOME_BANNER,
            PromoServiceType.FEATURED_SPECIALISTS,
            PromoServiceType.PORTFOLIO_SHOWCASE,
            PromoServiceType.SNAPSHOTS,
            PromoServiceType.SEARCH_RESULTS,
            PromoServiceType.SPONSORSHIP,
        }
        payload: dict[str, object]
        if service_types:
            if any(svc in range_service_types for svc in service_types) and (start_at is None or end_at is None):
                messages.error(request, "تاريخ البداية والنهاية مطلوبان للخدمات المختارة.")
                return redirect("dashboard:promo_campaign_create")

            items: list[dict[str, object]] = []
            for idx, svc in enumerate(service_types):
                item_payload: dict[str, object] = {
                    "service_type": svc,
                    "title": title,
                    "sort_order": idx,
                }
                if uploaded_assets:
                    item_payload["asset_count"] = len(uploaded_assets)
                if svc in range_service_types:
                    item_payload["start_at"] = start_at
                    item_payload["end_at"] = end_at
                if svc in {
                    PromoServiceType.FEATURED_SPECIALISTS,
                    PromoServiceType.PORTFOLIO_SHOWCASE,
                    PromoServiceType.SNAPSHOTS,
                }:
                    item_payload["frequency"] = frequency
                if target_category:
                    item_payload["target_category"] = target_category
                if target_city:
                    item_payload["target_city"] = target_city
                if redirect_url:
                    item_payload["redirect_url"] = redirect_url
                if provider is not None and svc in {
                    PromoServiceType.FEATURED_SPECIALISTS,
                    PromoServiceType.PORTFOLIO_SHOWCASE,
                    PromoServiceType.SNAPSHOTS,
                    PromoServiceType.SEARCH_RESULTS,
                }:
                    item_payload["target_provider"] = provider.id
                if portfolio_item is not None and svc == PromoServiceType.PORTFOLIO_SHOWCASE:
                    item_payload["target_portfolio_item"] = portfolio_item.id
                if svc == PromoServiceType.SEARCH_RESULTS:
                    item_payload["search_scope"] = search_scope or PromoSearchScope.DEFAULT
                    item_payload["search_position"] = search_position or PromoPosition.FIRST
                if svc == PromoServiceType.PROMO_MESSAGES:
                    item_payload["send_at"] = send_at
                    item_payload["message_title"] = promo_message_title
                    item_payload["message_body"] = promo_message_body
                    item_payload["use_notification_channel"] = use_notification_channel
                    item_payload["use_chat_channel"] = use_chat_channel
                    item_payload["attachment_specs"] = promo_attachment_specs
                if svc == PromoServiceType.SPONSORSHIP:
                    if sponsor_name:
                        item_payload["sponsor_name"] = sponsor_name
                    if sponsor_url:
                        item_payload["sponsor_url"] = sponsor_url
                    if sponsorship_months_raw:
                        item_payload["sponsorship_months"] = sponsorship_months_raw
                    if sponsorship_message_body:
                        item_payload["message_body"] = sponsorship_message_body
                    if sponsorship_attachment_specs:
                        item_payload["attachment_specs"] = sponsorship_attachment_specs
                items.append(item_payload)

            payload = {
                "title": title,
                "items": items,
            }
            if applies_home_banner_scales:
                payload.update(request_scale_payload)
        else:
            if start_at is None or end_at is None:
                messages.error(request, "تاريخ البداية والنهاية مطلوبان للحملة المباشرة.")
                return redirect("dashboard:promo_campaign_create")

            payload = {
                "title": title,
                "ad_type": ad_type,
                "start_at": start_at,
                "end_at": end_at,
                "frequency": frequency,
                "position": position,
            }
            if ad_type == PromoAdType.BANNER_HOME:
                payload.update(request_scale_payload)
            if target_category:
                payload["target_category"] = target_category
            if target_city:
                payload["target_city"] = target_city
            if redirect_url:
                payload["redirect_url"] = redirect_url
            if provider is not None:
                payload["target_provider"] = provider.id
            if portfolio_item is not None:
                payload["target_portfolio_item"] = portfolio_item.id

        serializer = PromoRequestCreateSerializer(data=payload, context={"request": request})
        if not serializer.is_valid():
            error_messages = _promo_dashboard_error_messages(serializer.errors)
            messages.error(request, error_messages[0] if error_messages else "تعذر التحقق من بيانات الحملة")
            return redirect("dashboard:promo_campaign_create")

        with transaction.atomic():
            pr = serializer.save()
            now = timezone.now()
            pr.assigned_to = request.user
            pr.assigned_at = now
            pr.status = status_val
            pr.ops_status = PromoOpsStatus.IN_PROGRESS if status_val == PromoRequestStatus.ACTIVE else PromoOpsStatus.NEW
            pr.activated_at = now if status_val == PromoRequestStatus.ACTIVE else None
            pr.save(
                update_fields=[
                    "assigned_to",
                    "assigned_at",
                    "status",
                    "ops_status",
                    "activated_at",
                    "updated_at",
                ]
            )

            for f in uploaded_assets:
                PromoAsset.objects.create(
                    request=pr,
                    asset_type=_promo_asset_type_from_upload(f),
                    title=f.name,
                    file=f,
                    uploaded_by=request.user,
                )

            _sync_promo_to_unified(pr=pr, changed_by=request.user)

        messages.success(request, f"تم إنشاء الحملة الترويجية: {pr.code}")
        return redirect("dashboard:promo_request_detail", promo_id=pr.id)

    # GET — render the creation form
    ctx = {
        "ad_type_choices": _promo_dashboard_ad_type_choices(),
        "frequency_choices": PromoFrequency.choices,
        "position_choices": PromoPosition.choices,
        "search_scope_choices": PromoSearchScope.choices,
        "search_position_choices": _PROMO_DASHBOARD_SEARCH_POSITION_CHOICES,
        "service_type_choices": PromoServiceType.choices,
        "bundle_value": PromoAdType.BUNDLE,
        "status_choices": [
            (PromoRequestStatus.ACTIVE, "مفعل — تبدأ فوراً"),
            (PromoRequestStatus.NEW, "جديد — تحتاج مراجعة"),
        ],
        "mobile_scale_min": 40,
        "mobile_scale_max": 140,
        "tablet_scale_min": 40,
        "tablet_scale_max": 150,
        "desktop_scale_min": 40,
        "desktop_scale_max": 160,
        "default_banner_scale": 100,
        "can_write": True,
    }
    ctx.update(_promo_dashboard_menu_context(active="create_campaign"))
    return render(request, "dashboard/promo_campaign_create.html", ctx)


@staff_member_required
@dashboard_access_required("subs")
def subscriptions_ops(request: HttpRequest) -> HttpResponse:
    """Unified subscriptions operations page.

    Shows:
    - Subscription inquiries (SupportTicketType.SUBS) codes HDxxxx
    - Subscription requests/accounts (Subscription) with SDxxxx via unified engine when available
    """
    q = (request.GET.get("q") or "").strip()
    inq_status = (request.GET.get("inq_status") or "").strip()
    req_status = (request.GET.get("req_status") or "").strip()

    inq_qs = (
        SupportTicket.objects.select_related("requester", "assigned_team", "assigned_to")
        .filter(ticket_type=SupportTicketType.SUBS)
        .order_by("-id")
    )
    if q:
        inq_qs = inq_qs.filter(Q(code__icontains=q) | Q(requester__phone__icontains=q) | Q(description__icontains=q))
    if inq_status:
        inq_qs = inq_qs.filter(status=inq_status)

    req_qs = Subscription.objects.select_related("user", "plan", "invoice").all().order_by("-id")
    if q:
        req_qs = req_qs.filter(Q(user__phone__icontains=q) | Q(plan__title__icontains=q) | Q(plan__code__icontains=q))
    if req_status:
        req_qs = req_qs.filter(status=req_status)

    inq_qs = apply_user_level_filter(inq_qs, request.user, assigned_field="assigned_to")
    # subscriptions themselves have no assignee; for user-level restrict by user ownership
    from apps.backoffice.models import AccessLevel as _AccessLevel
    _ap = getattr(request.user, "access_profile", None)
    if _ap and _ap.level == _AccessLevel.USER:
        req_qs = req_qs.filter(user=request.user)

    inq_page_obj = Paginator(inq_qs, 15).get_page(request.GET.get("inq_page") or "1")
    req_page_obj = Paginator(req_qs, 15).get_page(request.GET.get("req_page") or "1")

    # Attach unified request rows (SDxxxx) for request table rendering without N+1 loops on template lookups.
    req_ids = [r.id for r in req_page_obj.object_list]
    unified_map = {}
    if req_ids:
        for ur in UnifiedRequest.objects.filter(
            source_app="subscriptions",
            source_model="Subscription",
            source_object_id__in=[str(i) for i in req_ids],
        ).select_related("assigned_user"):
            unified_map[str(ur.source_object_id)] = ur
    for row in req_page_obj.object_list:
        row.unified_request = unified_map.get(str(row.id))

    _s_agg = Subscription.objects.aggregate(
        total=Count("id"),
        active=Count("id", filter=Q(status=SubscriptionStatus.ACTIVE)),
        pending=Count("id", filter=Q(status=SubscriptionStatus.PENDING_PAYMENT)),
        expired=Count("id", filter=Q(status=SubscriptionStatus.EXPIRED)),
    )
    _inq_new = SupportTicket.objects.filter(ticket_type=SupportTicketType.SUBS, status=SupportTicketStatus.NEW).count()
    stats = {
        "total_subscriptions": _s_agg["total"],
        "active": _s_agg["active"],
        "pending_payment": _s_agg["pending"],
        "expired": _s_agg["expired"],
        "new_inquiries": _inq_new,
    }

    return render(
        request,
        "dashboard/subscriptions_ops.html",
        {
            "q": q,
            "inq_status": inq_status,
            "req_status": req_status,
            "inq_page_obj": inq_page_obj,
            "req_page_obj": req_page_obj,
            "inq_status_choices": SupportTicketStatus.choices,
            "req_status_choices": SubscriptionStatus.choices,
            "stats": stats,
        },
    )


@staff_member_required
@dashboard_access_required("subs")
def subscription_inquiry_detail(request: HttpRequest, ticket_id: int) -> HttpResponse:
    ticket = get_object_or_404(
        SupportTicket.objects.select_related("requester", "assigned_team", "assigned_to", "last_action_by"),
        id=ticket_id,
        ticket_type=SupportTicketType.SUBS,
    )

    if not can_access_object(request.user, ticket, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)

    comments = ticket.comments.select_related("created_by").order_by("-id")
    logs = ticket.status_logs.select_related("changed_by").order_by("-id")
    teams = SupportTeam.objects.filter(is_active=True).order_by("sort_order", "id")
    staff_users = dashboard_assignment_users("subs", write=True, limit=150)
    can_write = _dashboard_allowed(request.user, "subs", write=True)

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
            "reported_user_profile_url": "",
            "reported_target_label": "",
            "reported_target_url": "",
            "can_write": can_write,
            "back_url": reverse("dashboard:subscriptions_ops"),
            "assign_action_url": reverse("dashboard:subscription_inquiry_assign_action", args=[ticket.id]),
            "status_action_url": reverse("dashboard:subscription_inquiry_status_action", args=[ticket.id]),
        },
    )


@staff_member_required
@dashboard_access_required("subs", write=True)
@require_POST
def subscription_inquiry_assign_action(request: HttpRequest, ticket_id: int) -> HttpResponse:
    ticket = get_object_or_404(SupportTicket, id=ticket_id, ticket_type=SupportTicketType.SUBS)
    ap = getattr(request.user, "access_profile", None)
    if not can_access_object(request.user, ticket, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
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

    if ap and ap.level == "user" and assigned_to not in (None, request.user.id):
        return HttpResponse("غير مصرح", status=403)
    if assigned_to is not None and dashboard_assignee_user(assigned_to, "subs", write=True) is None:
        messages.error(request, "المكلّف المحدد غير صالح لهذه اللوحة")
        return redirect("dashboard:subscription_inquiry_detail", ticket_id=ticket.id)

    try:
        assign_ticket(ticket=ticket, team_id=team_id, user_id=assigned_to, by_user=request.user, note=note)
        messages.success(request, "تم تحديث التعيين بنجاح")
    except Exception:
        logger.exception("subscription_inquiry_assign_action error")
        messages.error(request, "تعذر تحديث التعيين")
    return redirect("dashboard:subscription_inquiry_detail", ticket_id=ticket.id)


@staff_member_required
@dashboard_access_required("subs", write=True)
@require_POST
def subscription_inquiry_status_action(request: HttpRequest, ticket_id: int) -> HttpResponse:
    ticket = get_object_or_404(SupportTicket, id=ticket_id, ticket_type=SupportTicketType.SUBS)
    if not can_access_object(request.user, ticket, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)

    status_new = (request.POST.get("status") or "").strip()
    note = (request.POST.get("note") or "").strip()
    if not status_new:
        messages.warning(request, "اختر حالة الاستفسار")
        return redirect("dashboard:subscription_inquiry_detail", ticket_id=ticket.id)
    try:
        change_ticket_status(ticket=ticket, new_status=status_new, by_user=request.user, note=note)
        messages.success(request, "تم تحديث حالة الاستفسار")
    except Exception:
        logger.exception("subscription_inquiry_status_action error")
        messages.error(request, "تعذر تحديث الحالة")
    return redirect("dashboard:subscription_inquiry_detail", ticket_id=ticket.id)


@staff_member_required
@dashboard_access_required("subs")
def subscription_request_detail(request: HttpRequest, subscription_id: int) -> HttpResponse:
    sub = get_object_or_404(Subscription.objects.select_related("user", "plan", "invoice"), id=subscription_id)
    if not can_access_object(request.user, sub, owner_field="user", allow_unassigned_for_user_level=False):
        return HttpResponse("غير مصرح", status=403)

    ur = UnifiedRequest.objects.select_related("assigned_user").filter(
        source_app="subscriptions",
        source_model="Subscription",
        source_object_id=str(sub.id),
    ).first()
    ops_notes = []
    if ur:
        md = getattr(ur, "metadata_record", None)
        payload = getattr(md, "payload", {}) or {}
        raw_notes = payload.get("ops_notes") if isinstance(payload, dict) else None
        if isinstance(raw_notes, list):
            ops_notes = [n for n in raw_notes if isinstance(n, dict)]
            ops_notes.sort(key=lambda n: str(n.get("created_at") or ""), reverse=True)
    invoice_url = ""
    if sub.invoice_id and _dashboard_allowed(request.user, "billing", write=False):
        q = getattr(sub.invoice, "code", "") or str(sub.invoice_id)
        invoice_url = f"{reverse('dashboard:billing_invoices_list')}?q={q}"
    staff_users = dashboard_assignment_users("subs", write=True, limit=150)

    return render(
        request,
        "dashboard/subscription_request_detail.html",
        {
            "sub": sub,
            "ur": ur,
            "invoice_url": invoice_url,
            "ops_notes": ops_notes[:30],
            "staff_users": staff_users,
            "can_write": _dashboard_allowed(request.user, "subs", write=True),
            "back_url": reverse("dashboard:subscriptions_ops"),
        },
    )


@staff_member_required
@dashboard_access_required("subs", write=True)
@require_POST
def subscription_request_add_note_action(request: HttpRequest, subscription_id: int) -> HttpResponse:
    sub = get_object_or_404(Subscription, id=subscription_id)
    note = (request.POST.get("note") or "").strip()
    if not note:
        messages.warning(request, "نص الملاحظة مطلوب")
        return redirect("dashboard:subscription_request_detail", subscription_id=sub.id)
    if len(note) > 300:
        messages.warning(request, "الحد الأقصى للملاحظة 300 حرف")
        return redirect("dashboard:subscription_request_detail", subscription_id=sub.id)

    ur = UnifiedRequest.objects.filter(
        source_app="subscriptions",
        source_model="Subscription",
        source_object_id=str(sub.id),
    ).first()
    if not ur:
        messages.error(request, "لا يوجد طلب موحد مرتبط لتخزين الملاحظات")
        return redirect("dashboard:subscription_request_detail", subscription_id=sub.id)

    md, _ = UnifiedRequestMetadata.objects.get_or_create(
        request=ur,
        defaults={"payload": {}, "updated_by": request.user},
    )
    payload = md.payload if isinstance(md.payload, dict) else {}
    notes = payload.get("ops_notes")
    if not isinstance(notes, list):
        notes = []
    notes.append(
        {
            "text": note,
            "created_at": timezone.now().isoformat(),
            "by_user_id": request.user.id,
            "by_user_phone": getattr(request.user, "phone", "") or "",
        }
    )
    payload["ops_notes"] = notes[-50:]
    md.payload = payload
    md.updated_by = request.user
    md.save(update_fields=["payload", "updated_by", "updated_at"])
    try:
        log_action(
            actor=request.user,
            action=AuditAction.SUBSCRIPTION_REQUEST_NOTE_ADDED,
            reference_type="subscription_request.unified",
            reference_id=str(ur.id),
            request=request,
            extra={
                "subscription_id": sub.id,
                "unified_request_id": ur.id,
                "note_length": len(note),
            },
        )
    except Exception:
        logger.exception("subscription_request_add_note_action audit log error")
    messages.success(request, "تم حفظ الملاحظة التشغيلية")
    return redirect("dashboard:subscription_request_detail", subscription_id=sub.id)


@staff_member_required
@dashboard_access_required("subs", write=True)
@require_POST
def subscription_request_set_status_action(request: HttpRequest, subscription_id: int) -> HttpResponse:
    sub = get_object_or_404(Subscription, id=subscription_id)
    policy = SubscriptionManagePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="subscription",
        reference_id=str(sub.id),
        extra={"surface": "dashboard.subscription_request_set_status_action", "action_name": "set_status"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتحديث حالة طلب الاشتراك")
        return redirect("dashboard:subscription_request_detail", subscription_id=sub.id)
    new_status = (request.POST.get("status") or "").strip()
    new_status = canonical_status_for_workflow(
        request_type=UnifiedRequestType.SUBSCRIPTION,
        status=new_status,
    )
    note = (request.POST.get("note") or "").strip()
    allowed_statuses = set(allowed_statuses_for_request_type(UnifiedRequestType.SUBSCRIPTION))
    if new_status not in allowed_statuses:
        messages.warning(request, "حالة طلب الاشتراك غير صالحة")
        return redirect("dashboard:subscription_request_detail", subscription_id=sub.id)

    ur = UnifiedRequest.objects.filter(
        source_app="subscriptions",
        source_model="Subscription",
        source_object_id=str(sub.id),
    ).first()
    if not ur:
        messages.error(request, "لا يوجد طلب موحد مرتبط بطلب الاشتراك")
        return redirect("dashboard:subscription_request_detail", subscription_id=sub.id)

    prev_status = ur.status
    if prev_status == new_status:
        messages.info(request, "الحالة الحالية مطابقة للحالة المطلوبة")
        return redirect("dashboard:subscription_request_detail", subscription_id=sub.id)
    if not is_valid_transition(
        request_type=UnifiedRequestType.SUBSCRIPTION,
        from_status=prev_status,
        to_status=new_status,
    ):
        messages.warning(request, "انتقال الحالة غير مسموح في مسار الاشتراكات")
        return redirect("dashboard:subscription_request_detail", subscription_id=sub.id)

    ur.status = new_status
    if new_status == UnifiedRequestStatus.CLOSED:
        ur.closed_at = ur.closed_at or timezone.now()
    else:
        ur.closed_at = None
    ur.save(update_fields=["status", "closed_at", "updated_at"])

    UnifiedRequestStatusLog.objects.create(
        request=ur,
        from_status=prev_status or "",
        to_status=new_status,
        changed_by=request.user,
        note=(note[:200] if note else "dashboard subscription status"),
    )
    try:
        log_action(
            actor=request.user,
            action=AuditAction.SUBSCRIPTION_REQUEST_STATUS_CHANGED,
            reference_type="subscription_request.unified",
            reference_id=str(ur.id),
            request=request,
            extra={
                "subscription_id": sub.id,
                "unified_request_id": ur.id,
                "from_status": prev_status,
                "to_status": new_status,
                "note": note[:200],
            },
        )
    except Exception:
        logger.exception("subscription_request_set_status_action audit log error")
    messages.success(request, "تم تحديث حالة طلب الاشتراك")
    return redirect("dashboard:subscription_request_detail", subscription_id=sub.id)


@staff_member_required
@dashboard_access_required("subs", write=True)
@require_POST
def subscription_request_assign_action(request: HttpRequest, subscription_id: int) -> HttpResponse:
    sub = get_object_or_404(Subscription, id=subscription_id)
    policy = SubscriptionManagePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="subscription",
        reference_id=str(sub.id),
        extra={"surface": "dashboard.subscription_request_assign_action", "action_name": "assign"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بإسناد طلب الاشتراك")
        return redirect("dashboard:subscription_request_detail", subscription_id=sub.id)
    assigned_to = request.POST.get("assigned_to") or None
    note = (request.POST.get("note") or "").strip()
    try:
        assigned_to = int(assigned_to) if assigned_to else None
    except Exception:
        assigned_to = None

    ur = UnifiedRequest.objects.filter(
        source_app="subscriptions",
        source_model="Subscription",
        source_object_id=str(sub.id),
    ).first()
    if not ur:
        messages.error(request, "لا يوجد طلب موحد مرتبط بطلب الاشتراك")
        return redirect("dashboard:subscription_request_detail", subscription_id=sub.id)

    ap = getattr(request.user, "access_profile", None)
    if not can_access_object(request.user, ur, assigned_field="assigned_user", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)
    if ap and ap.level == "user":
        if assigned_to not in (None, request.user.id):
            return HttpResponse("غير مصرح", status=403)

    if assigned_to is not None and dashboard_assignee_user(assigned_to, "subs", write=True) is None:
        messages.error(request, "المكلّف غير صحيح")
        return redirect("dashboard:subscription_request_detail", subscription_id=sub.id)

    try:
        with transaction.atomic():
            ur = UnifiedRequest.objects.select_for_update().get(id=ur.id)
            old_user_id = ur.assigned_user_id
            old_team = ur.assigned_team_code or ""
            ur.assigned_team_code = "subs"
            ur.assigned_team_name = "الاشتراكات"
            ur.assigned_user_id = assigned_to
            ur.assigned_at = timezone.now() if assigned_to else None
            ur.save(update_fields=["assigned_team_code", "assigned_team_name", "assigned_user", "assigned_at", "updated_at"])
            if old_user_id != ur.assigned_user_id or old_team != (ur.assigned_team_code or ""):
                UnifiedRequestAssignmentLog.objects.create(
                    request=ur,
                    from_team_code=old_team,
                    to_team_code=ur.assigned_team_code or "",
                    from_user_id=old_user_id,
                    to_user=ur.assigned_user,
                    changed_by=request.user,
                    note=note[:200],
                )
                try:
                    log_action(
                        actor=request.user,
                        action=AuditAction.SUBSCRIPTION_REQUEST_ASSIGNED,
                        reference_type="subscription_request.unified",
                        reference_id=str(ur.id),
                        request=request,
                        extra={
                            "subscription_id": sub.id,
                            "unified_request_id": ur.id,
                            "from_team": old_team,
                            "to_team": ur.assigned_team_code or "",
                            "from_user_id": old_user_id,
                            "to_user_id": ur.assigned_user_id,
                            "note": note[:200],
                        },
                    )
                except Exception:
                    logger.exception("subscription_request_assign_action audit log error")
        messages.success(request, "تم تحديث إسناد طلب الاشتراك")
    except Exception:
        logger.exception("subscription_request_assign_action error")
        messages.error(request, "تعذر تحديث الإسناد")
    return redirect("dashboard:subscription_request_detail", subscription_id=sub.id)


@staff_member_required
@dashboard_access_required("extras")
def extras_ops(request: HttpRequest) -> HttpResponse:
    """Unified extras operations page.

    Shows:
    - Extras inquiries (SupportTicketType.EXTRAS) codes HDxxxx
    - Extras operational requests (UnifiedRequestType.EXTRAS) codes Pxxxx
    """

    q = (request.GET.get("q") or "").strip()
    inq_status = (request.GET.get("inq_status") or "").strip()
    req_status = (request.GET.get("req_status") or "").strip()

    inq_qs = (
        SupportTicket.objects.select_related("requester", "assigned_team", "assigned_to")
        .filter(ticket_type=SupportTicketType.EXTRAS)
        .order_by("-id")
    )
    if q:
        inq_qs = inq_qs.filter(Q(code__icontains=q) | Q(requester__phone__icontains=q) | Q(description__icontains=q))
    if inq_status:
        inq_qs = inq_qs.filter(status=inq_status)

    req_qs = (
        UnifiedRequest.objects.select_related("requester", "assigned_user")
        .filter(request_type=UnifiedRequestType.EXTRAS)
        .order_by("-id")
    )
    if q:
        req_qs = req_qs.filter(
            Q(code__icontains=q)
            | Q(summary__icontains=q)
            | Q(requester__phone__icontains=q)
            | Q(source_object_id__icontains=q)
        )
    if req_status:
        req_qs = req_qs.filter(status=req_status)

    inq_qs = apply_user_level_filter(inq_qs, request.user, assigned_field="assigned_to")
    req_qs = apply_user_level_filter(req_qs, request.user, assigned_field="assigned_user")

    inq_page_obj = Paginator(inq_qs, 15).get_page(request.GET.get("inq_page") or "1")
    req_page_obj = Paginator(req_qs, 15).get_page(request.GET.get("req_page") or "1")

    _e_agg = UnifiedRequest.objects.filter(request_type=UnifiedRequestType.EXTRAS).aggregate(
        total=Count("id"),
        open=Count(
            "id",
            filter=Q(
                status__in=[
                    UnifiedRequestStatus.NEW,
                    UnifiedRequestStatus.IN_PROGRESS,
                    UnifiedRequestStatus.RETURNED,
                ]
            ),
        ),
        pending=Count(
            "id",
            filter=Q(status__in=[UnifiedRequestStatus.PENDING_PAYMENT, UnifiedRequestStatus.NEW]),
        ),
    )
    _inq_new = SupportTicket.objects.filter(ticket_type=SupportTicketType.EXTRAS, status=SupportTicketStatus.NEW).count()
    _purchases_active = ExtraPurchase.objects.filter(status=ExtraPurchaseStatus.ACTIVE).count()
    stats = {
        "total_requests": _e_agg["total"],
        "open_requests": _e_agg["open"],
        "pending_payment": _e_agg["pending"],
        "purchases_active": _purchases_active,
        "new_inquiries": _inq_new,
    }

    return render(
        request,
        "dashboard/extras_ops.html",
        {
            "q": q,
            "inq_status": inq_status,
            "req_status": req_status,
            "inq_page_obj": inq_page_obj,
            "req_page_obj": req_page_obj,
            "inq_status_choices": SupportTicketStatus.choices,
            "req_status_choices": [(v, l) for v, l in UnifiedRequestStatus.choices if v in set(THREE_STAGE_ALLOWED_STATUSES)],
            "stats": stats,
        },
    )


@staff_member_required
@dashboard_access_required("extras")
def extras_inquiry_detail(request: HttpRequest, ticket_id: int) -> HttpResponse:
    ticket = get_object_or_404(
        SupportTicket.objects.select_related("requester", "assigned_team", "assigned_to", "last_action_by"),
        id=ticket_id,
        ticket_type=SupportTicketType.EXTRAS,
    )

    ap = getattr(request.user, "access_profile", None)
    if not can_access_object(request.user, ticket, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)

    comments = ticket.comments.select_related("created_by").order_by("-id")
    logs = ticket.status_logs.select_related("changed_by").order_by("-id")
    teams = SupportTeam.objects.filter(is_active=True).order_by("sort_order", "id")
    staff_users = dashboard_assignment_users("extras", write=True, limit=150)
    can_write = _dashboard_allowed(request.user, "extras", write=True)

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
            "reported_user_profile_url": "",
            "reported_target_label": "",
            "reported_target_url": "",
            "can_write": can_write,
            "back_url": reverse("dashboard:extras_ops"),
            "assign_action_url": reverse("dashboard:extras_inquiry_assign_action", args=[ticket.id]),
            "status_action_url": reverse("dashboard:extras_inquiry_status_action", args=[ticket.id]),
        },
    )


@staff_member_required
@dashboard_access_required("extras", write=True)
@require_POST
def extras_inquiry_assign_action(request: HttpRequest, ticket_id: int) -> HttpResponse:
    ticket = get_object_or_404(SupportTicket, id=ticket_id, ticket_type=SupportTicketType.EXTRAS)
    policy = ExtrasManagePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="support.ticket",
        reference_id=str(ticket.id),
        extra={"surface": "dashboard.extras_inquiry_assign_action", "action_name": "assign"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بإسناد استفسار الخدمات الإضافية")
        return redirect("dashboard:extras_inquiry_detail", ticket_id=ticket.id)
    ap = getattr(request.user, "access_profile", None)
    if not can_access_object(request.user, ticket, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
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

    if ap and ap.level == "user" and assigned_to not in (None, request.user.id):
        return HttpResponse("غير مصرح", status=403)
    if assigned_to is not None and dashboard_assignee_user(assigned_to, "extras", write=True) is None:
        messages.error(request, "المكلّف المحدد غير صالح لهذه اللوحة")
        return redirect("dashboard:extras_inquiry_detail", ticket_id=ticket.id)

    try:
        assign_ticket(ticket=ticket, team_id=team_id, user_id=assigned_to, by_user=request.user, note=note)
        messages.success(request, "تم تحديث التعيين بنجاح")
    except Exception:
        logger.exception("extras_inquiry_assign_action error")
        messages.error(request, "تعذر تحديث التعيين")
    return redirect("dashboard:extras_inquiry_detail", ticket_id=ticket.id)


@staff_member_required
@dashboard_access_required("extras", write=True)
@require_POST
def extras_inquiry_status_action(request: HttpRequest, ticket_id: int) -> HttpResponse:
    ticket = get_object_or_404(SupportTicket, id=ticket_id, ticket_type=SupportTicketType.EXTRAS)
    policy = ExtrasManagePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="support.ticket",
        reference_id=str(ticket.id),
        extra={"surface": "dashboard.extras_inquiry_status_action", "action_name": "status"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتحديث استفسار الخدمات الإضافية")
        return redirect("dashboard:extras_inquiry_detail", ticket_id=ticket.id)
    ap = getattr(request.user, "access_profile", None)
    if not can_access_object(request.user, ticket, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)

    status_new = (request.POST.get("status") or "").strip()
    status_new = canonical_status_for_workflow(
        request_type=UnifiedRequestType.EXTRAS,
        status=status_new,
    )
    note = (request.POST.get("note") or "").strip()
    if not status_new:
        messages.warning(request, "اختر حالة الاستفسار")
        return redirect("dashboard:extras_inquiry_detail", ticket_id=ticket.id)
    try:
        change_ticket_status(ticket=ticket, new_status=status_new, by_user=request.user, note=note)
        messages.success(request, "تم تحديث حالة الاستفسار")
    except Exception:
        logger.exception("extras_inquiry_status_action error")
        messages.error(request, "تعذر تحديث الحالة")
    return redirect("dashboard:extras_inquiry_detail", ticket_id=ticket.id)


@staff_member_required
@dashboard_access_required("extras")
def extras_request_detail(request: HttpRequest, unified_request_id: int) -> HttpResponse:
    ur = get_object_or_404(
        UnifiedRequest.objects.select_related("requester", "assigned_user")
        .prefetch_related(
            "status_logs__changed_by",
            "assignment_logs__from_user",
            "assignment_logs__to_user",
            "assignment_logs__changed_by",
        ),
        id=unified_request_id,
        request_type=UnifiedRequestType.EXTRAS,
    )

    ap = getattr(request.user, "access_profile", None)
    if not can_access_object(request.user, ur, assigned_field="assigned_user", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)

    metadata_record = getattr(ur, "metadata_record", None)
    metadata_payload = getattr(metadata_record, "payload", {}) or {}
    quick_links = _unified_request_quick_links(request.user, ur, metadata_payload)

    purchase = None
    invoice_url = ""
    if ur.source_app == "extras" and ur.source_model == "ExtraPurchase" and (ur.source_object_id or "").strip():
        purchase = ExtraPurchase.objects.select_related("user", "invoice").filter(id=int(ur.source_object_id)).first()
        if purchase and purchase.invoice_id and _dashboard_allowed(request.user, "billing", write=False):
            q = getattr(purchase.invoice, "code", "") or str(purchase.invoice_id)
            invoice_url = f"{reverse('dashboard:billing_invoices_list')}?q={q}"

    staff_users = dashboard_assignment_users("extras", write=True, limit=150)

    return render(
        request,
        "dashboard/extras_request_detail.html",
        {
            "ur": ur,
            "purchase": purchase,
            "invoice_url": invoice_url,
            "metadata_payload": metadata_payload,
            "metadata_record": metadata_record,
            "quick_links": quick_links,
            "status_logs": ur.status_logs.all(),
            "assignment_logs": ur.assignment_logs.all(),
            "status_choices": [(v, l) for v, l in UnifiedRequestStatus.choices if v in set(THREE_STAGE_ALLOWED_STATUSES)],
            "staff_users": staff_users,
            "can_write": _dashboard_allowed(request.user, "extras", write=True),
            "back_url": reverse("dashboard:extras_ops"),
        },
    )


@staff_member_required
@dashboard_access_required("extras", write=True)
@require_POST
def extras_request_assign_action(request: HttpRequest, unified_request_id: int) -> HttpResponse:
    ur = get_object_or_404(UnifiedRequest, id=unified_request_id, request_type=UnifiedRequestType.EXTRAS)
    policy = ExtrasManagePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="unified_request",
        reference_id=str(ur.id),
        extra={"surface": "dashboard.extras_request_assign_action", "action_name": "assign"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بإسناد طلب الخدمات الإضافية")
        return redirect("dashboard:extras_request_detail", unified_request_id=ur.id)
    ap = getattr(request.user, "access_profile", None)
    if not can_access_object(request.user, ur, assigned_field="assigned_user", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)

    assigned_to = request.POST.get("assigned_to") or None
    note = (request.POST.get("note") or "").strip()
    try:
        assigned_to = int(assigned_to) if assigned_to else None
    except Exception:
        assigned_to = None

    if ap and ap.level == "user" and assigned_to not in (None, request.user.id):
        return HttpResponse("غير مصرح", status=403)

    if assigned_to is not None and dashboard_assignee_user(assigned_to, "extras", write=True) is None:
        messages.error(request, "المكلّف غير صحيح")
        return redirect("dashboard:extras_request_detail", unified_request_id=ur.id)

    try:
        with transaction.atomic():
            ur = UnifiedRequest.objects.select_for_update().get(id=ur.id)
            old_user_id = ur.assigned_user_id
            old_team = ur.assigned_team_code or ""

            ur.assigned_team_code = "extras"
            ur.assigned_team_name = "الخدمات الإضافية"
            ur.assigned_user_id = assigned_to
            ur.assigned_at = timezone.now() if assigned_to else None
            ur.save(update_fields=["assigned_team_code", "assigned_team_name", "assigned_user", "assigned_at", "updated_at"])

            if old_user_id != ur.assigned_user_id or old_team != (ur.assigned_team_code or ""):
                UnifiedRequestAssignmentLog.objects.create(
                    request=ur,
                    from_team_code=old_team,
                    to_team_code=ur.assigned_team_code or "",
                    from_user_id=old_user_id,
                    to_user=ur.assigned_user,
                    changed_by=request.user,
                    note=note[:200],
                )
        messages.success(request, "تم تحديث الإسناد")
    except Exception:
        logger.exception("extras_request_assign_action error")
        messages.error(request, "تعذر تحديث الإسناد")
    return redirect("dashboard:extras_request_detail", unified_request_id=ur.id)


@staff_member_required
@dashboard_access_required("extras", write=True)
@require_POST
def extras_request_status_action(request: HttpRequest, unified_request_id: int) -> HttpResponse:
    ur = get_object_or_404(UnifiedRequest, id=unified_request_id, request_type=UnifiedRequestType.EXTRAS)
    policy = ExtrasManagePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="unified_request",
        reference_id=str(ur.id),
        extra={"surface": "dashboard.extras_request_status_action", "action_name": "status"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتحديث طلب الخدمات الإضافية")
        return redirect("dashboard:extras_request_detail", unified_request_id=ur.id)
    ap = getattr(request.user, "access_profile", None)
    if not can_access_object(request.user, ur, assigned_field="assigned_user", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)

    status_new = (request.POST.get("status") or "").strip()
    note = (request.POST.get("note") or "").strip()
    allowed_statuses = set(allowed_statuses_for_request_type(UnifiedRequestType.EXTRAS))
    if not status_new or status_new not in allowed_statuses:
        messages.warning(request, "اختر حالة صحيحة")
        return redirect("dashboard:extras_request_detail", unified_request_id=ur.id)

    try:
        with transaction.atomic():
            ur = UnifiedRequest.objects.select_for_update().get(id=ur.id)
            old = ur.status
            if old != status_new:
                if not is_valid_transition(
                    request_type=UnifiedRequestType.EXTRAS,
                    from_status=old,
                    to_status=status_new,
                ):
                    messages.warning(request, "انتقال الحالة غير مسموح في مسار الخدمات الإضافية")
                    return redirect("dashboard:extras_request_detail", unified_request_id=ur.id)
                ur.status = status_new
                if status_new == UnifiedRequestStatus.CLOSED and ur.closed_at is None:
                    ur.closed_at = timezone.now()
                    ur.save(update_fields=["status", "closed_at", "updated_at"])
                else:
                    ur.save(update_fields=["status", "updated_at"])
                UnifiedRequestStatusLog.objects.create(
                    request=ur,
                    from_status=old,
                    to_status=status_new,
                    changed_by=request.user,
                    note=note[:200],
                )
        messages.success(request, "تم تحديث حالة الطلب")
    except Exception:
        logger.exception("extras_request_status_action error")
        messages.error(request, "تعذر تحديث الحالة")
    return redirect("dashboard:extras_request_detail", unified_request_id=ur.id)


@staff_member_required
@dashboard_access_required("subs")
def subscription_account_detail(request: HttpRequest, subscription_id: int) -> HttpResponse:
    sub = get_object_or_404(Subscription.objects.select_related("user", "plan", "invoice"), id=subscription_id)
    if not can_access_object(request.user, sub, owner_field="user", allow_unassigned_for_user_level=False):
        return HttpResponse("غير مصرح", status=403)

    plans = SubscriptionPlan.objects.filter(is_active=True).order_by("price", "id")
    recent_for_user = Subscription.objects.select_related("plan", "invoice").filter(user=sub.user).exclude(id=sub.id).order_by("-id")[:10]
    unified_rows = UnifiedRequest.objects.filter(
        source_app="subscriptions",
        source_model="Subscription",
        source_object_id=str(sub.id),
    ).order_by("-id")[:1]
    ur = unified_rows.first()
    account_ops_notes = []
    if ur:
        md = getattr(ur, "metadata_record", None)
        payload = getattr(md, "payload", {}) or {}
        raw_notes = payload.get("account_ops_notes") if isinstance(payload, dict) else None
        if isinstance(raw_notes, list):
            account_ops_notes = [n for n in raw_notes if isinstance(n, dict)]
            account_ops_notes.sort(key=lambda n: str(n.get("created_at") or ""), reverse=True)
    payment_attempts = []
    if sub.invoice_id:
        payment_attempts = list(PaymentAttempt.objects.filter(invoice_id=sub.invoice_id).order_by("-created_at")[:10])

    now = timezone.now()
    alerts: list[dict] = []
    if sub.status == SubscriptionStatus.PENDING_PAYMENT:
        alerts.append({"level": "warning", "text": "الاشتراك بانتظار سداد الفاتورة لإكمال التفعيل."})
    if sub.status == SubscriptionStatus.ACTIVE and sub.end_at:
        days_left = (sub.end_at - now).days
        if sub.end_at <= now:
            alerts.append({"level": "danger", "text": "تاريخ نهاية الاشتراك مضى؛ راجع التحديث/التجديد."})
        elif days_left <= 7:
            alerts.append({"level": "warning", "text": f"الاشتراك سينتهي قريبًا خلال {max(days_left, 0)} يوم."})
        else:
            alerts.append({"level": "success", "text": "الاشتراك نشط ولا توجد تنبيهات حرجة حاليًا."})
    if sub.status == SubscriptionStatus.GRACE:
        alerts.append({"level": "warning", "text": "الاشتراك داخل فترة السماح؛ يوصى بإنشاء طلب تجديد."})
    if sub.status == SubscriptionStatus.EXPIRED:
        alerts.append({"level": "danger", "text": "الاشتراك منتهي؛ أنشئ طلب تجديد لإعادة التفعيل."})
    if sub.status == SubscriptionStatus.CANCELLED:
        alerts.append({"level": "danger", "text": "الاشتراك ملغي (إيقاف تشغيلي)."})

    timeline: list[dict] = []
    timeline.append({"at": sub.created_at, "title": "إنشاء سجل الاشتراك", "detail": f"تم إنشاء السجل على الباقة {sub.plan.code}."})
    if sub.invoice_id:
        timeline.append({
            "at": sub.invoice.created_at,
            "title": "إنشاء الفاتورة",
            "detail": f"الفاتورة {sub.invoice.code or sub.invoice_id} بحالة {sub.invoice.get_status_display()}",
        })
        if sub.invoice.paid_at:
            timeline.append({
                "at": sub.invoice.paid_at,
                "title": "سداد الفاتورة",
                "detail": f"تم السداد بقيمة {sub.invoice.total} {sub.invoice.currency}",
            })
    for att in payment_attempts:
        timeline.append({
            "at": att.created_at,
            "title": "محاولة دفع",
            "detail": f"{att.get_status_display()} - {att.provider} - {att.amount} {att.currency}",
        })
    if sub.start_at:
        timeline.append({"at": sub.start_at, "title": "تفعيل الاشتراك", "detail": "تم تفعيل الاشتراك."})
    if sub.end_at:
        timeline.append({"at": sub.end_at, "title": "موعد نهاية الاشتراك", "detail": "نهاية مدة الاشتراك الحالية."})
    if sub.grace_end_at:
        timeline.append({"at": sub.grace_end_at, "title": "نهاية فترة السماح", "detail": "آخر موعد قبل التحول إلى منتهي."})
    if ur:
        for log in ur.status_logs.select_related("changed_by").all()[:10]:
            who = getattr(getattr(log, "changed_by", None), "phone", "") or "النظام"
            timeline.append({
                "at": log.created_at,
                "title": "تحديث حالة الطلب الموحد",
                "detail": f"{log.from_status or '—'} -> {log.to_status} بواسطة {who}",
            })

    timeline = [t for t in timeline if t.get("at")]
    timeline.sort(key=lambda x: x["at"], reverse=True)

    invoice_url = ""
    if sub.invoice_id and _dashboard_allowed(request.user, "billing", write=False):
        q = getattr(sub.invoice, "code", "") or str(sub.invoice_id)
        invoice_url = f"{reverse('dashboard:billing_invoices_list')}?q={q}"

    return render(
        request,
        "dashboard/subscription_account_detail.html",
        {
            "sub": sub,
            "ur": ur,
            "plans": plans,
            "recent_for_user": recent_for_user,
            "invoice_url": invoice_url,
            "payment_attempts": payment_attempts,
            "alerts": alerts,
            "timeline": timeline[:20],
            "account_ops_notes": account_ops_notes[:30],
            "can_write": _dashboard_allowed(request.user, "subs", write=True),
            "back_url": reverse("dashboard:subscriptions_list"),
        },
    )


@staff_member_required
@dashboard_access_required("subs")
def subscription_plans_compare(request: HttpRequest) -> HttpResponse:
    target_sub_id = (request.GET.get("subscription_id") or "").strip()
    target_sub = None
    if target_sub_id:
        try:
            target_sub = Subscription.objects.select_related("user", "plan").filter(id=int(target_sub_id)).first()
        except Exception:
            target_sub = None

    plans = list(SubscriptionPlan.objects.filter(is_active=True).order_by("price", "id"))
    feature_labels = dict(FeatureKey.choices)
    verification_keys = {"verify_blue", "verify_green"}
    all_keys = []
    seen = set()
    for p in plans:
        for key in (p.features or []):
            if key in verification_keys:
                continue
            if key not in seen:
                seen.add(key)
                all_keys.append(key)

    rows = []
    def _pricing_cell(plan: SubscriptionPlan, badge_type: str) -> str:
        pricing = verification_pricing_for_plan(plan)
        amount = verification_price_amount(pricing, badge_type)
        return "مجاني" if str(amount) == "0.00" else f"{amount} ر.س"

    rows.extend(
        [
            {
                "key": "subscription_tier",
                "label": "فئة الباقة",
                "values": [verification_pricing_for_plan(p).get("tier_label", "أساسية") for p in plans],
            },
            {
                "key": "verification_blue_fee",
                "label": "رسوم التوثيق الأزرق",
                "values": [_pricing_cell(p, "blue") for p in plans],
            },
            {
                "key": "verification_green_fee",
                "label": "رسوم التوثيق الأخضر",
                "values": [_pricing_cell(p, "green") for p in plans],
            },
        ]
    )
    for key in all_keys:
        rows.append(
            {
                "key": key,
                "label": feature_labels.get(key, key),
                "values": [("نعم" if key in (p.features or []) else "—") for p in plans],
            }
        )

    return render(
        request,
        "dashboard/subscription_plans_compare.html",
        {
            "plans": plans,
            "feature_rows": rows,
            "target_sub": target_sub,
        },
    )


@staff_member_required
@dashboard_access_required("subs")
def subscription_upgrade_summary(request: HttpRequest, subscription_id: int) -> HttpResponse:
    sub = get_object_or_404(Subscription.objects.select_related("user", "plan"), id=subscription_id)
    plan_id = (request.GET.get("plan_id") or "").strip()
    plan = None
    if plan_id:
        try:
            plan = SubscriptionPlan.objects.filter(id=int(plan_id), is_active=True).first()
        except Exception:
            plan = None

    if not can_access_object(request.user, sub, owner_field="user", allow_unassigned_for_user_level=False):
        return HttpResponse("غير مصرح", status=403)

    vat_percent = Decimal("15.00")
    subtotal = Decimal("0.00")
    vat_amount = Decimal("0.00")
    total = Decimal("0.00")
    if plan:
        subtotal = money_round(Decimal(plan.price or 0))
        vat_amount = money_round((subtotal * vat_percent) / Decimal("100"))
        total = money_round(subtotal + vat_amount)

    return render(
        request,
        "dashboard/subscription_upgrade_summary.html",
        {
            "sub": sub,
            "plan": plan,
            "plans": SubscriptionPlan.objects.filter(is_active=True).order_by("price", "id"),
            "subtotal": subtotal,
            "vat_percent": vat_percent,
            "vat_amount": vat_amount,
            "total": total,
            "back_url": reverse("dashboard:subscription_account_detail", args=[sub.id]),
        },
    )


@staff_member_required
@dashboard_access_required("subs", write=True)
@require_POST
def subscription_account_add_note_action(request: HttpRequest, subscription_id: int) -> HttpResponse:
    sub = get_object_or_404(Subscription, id=subscription_id)
    note = (request.POST.get("note") or "").strip()
    if not note:
        messages.warning(request, "نص الملاحظة مطلوب")
        return redirect("dashboard:subscription_account_detail", subscription_id=sub.id)
    if len(note) > 300:
        messages.warning(request, "الحد الأقصى للملاحظة 300 حرف")
        return redirect("dashboard:subscription_account_detail", subscription_id=sub.id)

    ur = UnifiedRequest.objects.filter(
        source_app="subscriptions",
        source_model="Subscription",
        source_object_id=str(sub.id),
    ).first()
    if not ur:
        messages.error(request, "لا يوجد طلب موحد مرتبط لتخزين ملاحظات الحساب")
        return redirect("dashboard:subscription_account_detail", subscription_id=sub.id)

    md, _ = UnifiedRequestMetadata.objects.get_or_create(
        request=ur,
        defaults={"payload": {}, "updated_by": request.user},
    )
    payload = md.payload if isinstance(md.payload, dict) else {}
    notes = payload.get("account_ops_notes")
    if not isinstance(notes, list):
        notes = []
    notes.append(
        {
            "text": note,
            "created_at": timezone.now().isoformat(),
            "by_user_id": request.user.id,
            "by_user_phone": getattr(request.user, "phone", "") or "",
        }
    )
    payload["account_ops_notes"] = notes[-50:]
    md.payload = payload
    md.updated_by = request.user
    md.save(update_fields=["payload", "updated_by", "updated_at"])
    try:
        log_action(
            actor=request.user,
            action=AuditAction.SUBSCRIPTION_ACCOUNT_NOTE_ADDED,
            reference_type="subscription_account.unified",
            reference_id=str(ur.id),
            request=request,
            extra={
                "subscription_id": sub.id,
                "unified_request_id": ur.id,
                "note_length": len(note),
            },
        )
    except Exception:
        logger.exception("subscription_account_add_note_action audit log error")
    messages.success(request, "تم حفظ ملاحظة الحساب")
    return redirect("dashboard:subscription_account_detail", subscription_id=sub.id)


@staff_member_required
@dashboard_access_required("subs", write=True)
@require_POST
def subscription_account_renew_action(request: HttpRequest, subscription_id: int) -> HttpResponse:
    sub = get_object_or_404(Subscription.objects.select_related("user", "plan"), id=subscription_id)
    try:
        new_sub = start_subscription_renewal_checkout(user=sub.user, plan=sub.plan)
        try:
            log_action(
                actor=request.user,
                action=AuditAction.SUBSCRIPTION_ACCOUNT_RENEW_REQUESTED,
                reference_type="subscription.account",
                reference_id=str(sub.id),
                request=request,
                extra={
                    "subscription_id": sub.id,
                    "new_subscription_id": new_sub.id,
                    "user_id": sub.user_id,
                    "plan_id": sub.plan_id,
                    "invoice_id": new_sub.invoice_id,
                },
            )
        except Exception:
            logger.exception("subscription_account_renew_action audit log error")
        messages.success(request, "تم إنشاء طلب تجديد الاشتراك وفاتورته بنجاح")
        return redirect("dashboard:subscription_payment_checkout", subscription_id=new_sub.id)
    except Exception as e:
        messages.error(request, str(e) or "تعذر إنشاء طلب التجديد")
        return redirect("dashboard:subscription_account_detail", subscription_id=sub.id)


@staff_member_required
@dashboard_access_required("subs", write=True)
@require_POST
def subscription_account_upgrade_action(request: HttpRequest, subscription_id: int) -> HttpResponse:
    sub = get_object_or_404(Subscription.objects.select_related("user", "plan"), id=subscription_id)
    plan_id = request.POST.get("plan_id") or request.GET.get("plan_id") or ""
    try:
        plan = SubscriptionPlan.objects.get(id=int(plan_id), is_active=True)
    except Exception:
        messages.warning(request, "اختر باقة ترقية صالحة")
        return redirect("dashboard:subscription_account_detail", subscription_id=sub.id)
    try:
        new_sub = start_subscription_checkout(user=sub.user, plan=plan)
        try:
            log_action(
                actor=request.user,
                action=AuditAction.SUBSCRIPTION_ACCOUNT_UPGRADE_REQUESTED,
                reference_type="subscription.account",
                reference_id=str(sub.id),
                request=request,
                extra={
                    "subscription_id": sub.id,
                    "new_subscription_id": new_sub.id,
                    "user_id": sub.user_id,
                    "from_plan_id": sub.plan_id,
                    "to_plan_id": plan.id,
                    "invoice_id": new_sub.invoice_id,
                },
            )
        except Exception:
            logger.exception("subscription_account_upgrade_action audit log error")
        messages.success(request, "تم إنشاء طلب ترقية الاشتراك وفاتورته بنجاح")
        return redirect("dashboard:subscription_payment_checkout", subscription_id=new_sub.id)
    except Exception as e:
        messages.error(request, str(e) or "تعذر إنشاء طلب الترقية")
        return redirect("dashboard:subscription_account_detail", subscription_id=sub.id)


@staff_member_required
@dashboard_access_required("subs", write=True)
@require_POST
def subscription_account_cancel_action(request: HttpRequest, subscription_id: int) -> HttpResponse:
    sub = get_object_or_404(Subscription, id=subscription_id)
    if sub.status == SubscriptionStatus.CANCELLED:
        messages.info(request, "الاشتراك ملغي مسبقًا")
        return redirect("dashboard:subscription_account_detail", subscription_id=sub.id)
    sub.status = SubscriptionStatus.CANCELLED
    sub.save(update_fields=["status", "updated_at"])
    try:
        from apps.subscriptions.services import _sync_subscription_to_unified
        _sync_subscription_to_unified(sub=sub, changed_by=request.user)
    except Exception:
        pass
    try:
        log_action(
            actor=request.user,
            action=AuditAction.SUBSCRIPTION_ACCOUNT_CANCELLED,
            reference_type="subscription.account",
            reference_id=str(sub.id),
            request=request,
            extra={
                "subscription_id": sub.id,
                "user_id": sub.user_id,
                "plan_id": sub.plan_id,
                "status": sub.status,
            },
        )
    except Exception:
        logger.exception("subscription_account_cancel_action audit log error")
    messages.success(request, "تم إيقاف/إلغاء الاشتراك")
    return redirect("dashboard:subscription_account_detail", subscription_id=sub.id)


@staff_member_required
@dashboard_access_required("subs")
def subscription_payment_checkout(request: HttpRequest, subscription_id: int) -> HttpResponse:
    sub = get_object_or_404(Subscription.objects.select_related("user", "plan", "invoice"), id=subscription_id)
    if not can_access_object(request.user, sub, owner_field="user", allow_unassigned_for_user_level=False):
        return HttpResponse("غير مصرح", status=403)
    if not sub.invoice_id:
        messages.warning(request, "لا توجد فاتورة مرتبطة بهذا الطلب")
        return redirect("dashboard:subscription_request_detail", subscription_id=sub.id)

    attempt = None
    try:
        # Stable idempotency key keeps the same mock payment attempt for repeated opens.
        attempt = init_payment(
            invoice=sub.invoice,
            provider="mock",
            by_user=request.user,
            idempotency_key=f"dashboard-subs-{sub.id}",
        )
    except Exception:
        # If invoice already paid or any init issue, render screen without blocking.
        attempt = PaymentAttempt.objects.filter(invoice=sub.invoice).order_by("-created_at").first()
    try:
        log_action(
            actor=request.user,
            action=AuditAction.SUBSCRIPTION_PAYMENT_CHECKOUT_OPENED,
            reference_type="subscription.payment",
            reference_id=str(sub.id),
            request=request,
            extra={
                "subscription_id": sub.id,
                "invoice_id": sub.invoice_id,
                "invoice_status": getattr(sub.invoice, "status", ""),
                "payment_attempt_id": (str(getattr(attempt, "id", "")) if getattr(attempt, "id", None) else None),
            },
        )
    except Exception:
        logger.exception("subscription_payment_checkout audit log error")

    return render(
        request,
        "dashboard/subscription_payment_checkout.html",
        {
            "sub": sub,
            "attempt": attempt,
            "back_url": reverse("dashboard:subscription_upgrade_summary", args=[sub.id]),
            "request_url": reverse("dashboard:subscription_request_detail", args=[sub.id]),
        },
    )


@staff_member_required
@dashboard_access_required("subs", write=True)
@require_POST
def subscription_payment_complete_action(request: HttpRequest, subscription_id: int) -> HttpResponse:
    sub = get_object_or_404(Subscription.objects.select_related("invoice", "user", "plan"), id=subscription_id)
    if not sub.invoice_id:
        messages.error(request, "لا توجد فاتورة لإتمام الدفع")
        return redirect("dashboard:subscription_request_detail", subscription_id=sub.id)

    try:
        attempt = init_payment(
            invoice=sub.invoice,
            provider="mock",
            by_user=request.user,
            idempotency_key=f"dashboard-subs-{sub.id}",
        )
    except Exception:
        attempt = PaymentAttempt.objects.filter(invoice=sub.invoice).order_by("-created_at").first()

    try:
        if sub.invoice.status != InvoiceStatus.PAID:
            payload = {
                "provider_reference": getattr(attempt, "provider_reference", ""),
                "invoice_code": sub.invoice.code,
                "status": "success",
                "amount": str(sub.invoice.total),
                "currency": sub.invoice.currency,
            }
            event_id = f"dashboard-subs-{sub.id}"
            signature = sign_webhook_payload(provider="mock", payload=payload, event_id=event_id)
            handle_webhook(provider="mock", payload=payload, signature=signature, event_id=event_id)
            sub.invoice.refresh_from_db()
        activate_subscription_after_payment(sub=sub)
        try:
            log_action(
                actor=request.user,
                action=AuditAction.SUBSCRIPTION_PAYMENT_COMPLETED,
                reference_type="subscription.payment",
                reference_id=str(sub.id),
                request=request,
                extra={
                    "subscription_id": sub.id,
                    "invoice_id": sub.invoice_id,
                    "invoice_status": getattr(sub.invoice, "status", ""),
                    "payment_attempt_id": (str(getattr(attempt, "id", "")) if getattr(attempt, "id", None) else None),
                },
            )
        except Exception:
            logger.exception("subscription_payment_complete_action audit log error")
        messages.success(request, "تمت عملية سداد الرسوم بنجاح وتفعيل الاشتراك")
        return redirect("dashboard:subscription_payment_success", subscription_id=sub.id)
    except Exception as e:
        messages.error(request, str(e) or "تعذر إتمام الدفع/تفعيل الاشتراك")
        return redirect("dashboard:subscription_payment_checkout", subscription_id=sub.id)


@staff_member_required
@dashboard_access_required("subs")
def subscription_payment_success(request: HttpRequest, subscription_id: int) -> HttpResponse:
    sub = get_object_or_404(Subscription.objects.select_related("user", "plan", "invoice"), id=subscription_id)
    if not can_access_object(request.user, sub, owner_field="user", allow_unassigned_for_user_level=False):
        return HttpResponse("غير مصرح", status=403)
    return render(
        request,
        "dashboard/subscription_payment_success.html",
        {
            "sub": sub,
            "account_url": reverse("dashboard:subscription_account_detail", args=[sub.id]),
            "request_url": reverse("dashboard:subscription_request_detail", args=[sub.id]),
            "ops_url": reverse("dashboard:subscriptions_ops"),
        },
    )


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
        for s in _limited_export_queryset(request, qs):
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
    return redirect(safe_redirect_url(request, reverse("dashboard:subscriptions_list")))


@staff_member_required
@dashboard_access_required("subs", write=True)
@require_POST
def subscription_activate_action(request: HttpRequest, subscription_id: int) -> HttpResponse:
    sub = get_object_or_404(Subscription, id=subscription_id)
    policy = SubscriptionManagePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="subscription",
        reference_id=str(sub.id),
        extra={"surface": "dashboard.subscription_activate_action", "action_name": "activate"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتفعيل هذا الاشتراك")
        return redirect(safe_redirect_url(request, reverse("dashboard:subscriptions_list")))
    try:
        activate_subscription_after_payment(sub=sub)
        messages.success(request, "تم تفعيل الاشتراك")
    except Exception as e:
        messages.error(request, str(e) or "تعذر تفعيل الاشتراك")
    return redirect(safe_redirect_url(request, reverse("dashboard:subscriptions_list")))


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
        for e in _limited_export_queryset(request, qs):
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
    policy = ExtrasManagePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="extra_purchase",
        reference_id=str(purchase.id),
        extra={"surface": "dashboard.extra_activate_action", "action_name": "activate"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتفعيل هذه الإضافة")
        return redirect("dashboard:extras_list")
    try:
        activate_extra_after_payment(purchase=purchase)
        messages.success(request, "تم تفعيل الإضافة")
    except Exception as e:
        messages.error(request, str(e) or "تعذر تفعيل الإضافة")
    return redirect("dashboard:extras_list")


# ── Extras: Finance / IBAN ──────────────────────────────────────────

@staff_member_required
@dashboard_access_required("extras")
def extras_finance_list(request: HttpRequest) -> HttpResponse:
    """عرض البيانات المالية (IBAN) لمقدمي الخدمات الإضافية."""
    from apps.extras_portal.models import ExtrasPortalFinanceSettings

    qs = (
        ExtrasPortalFinanceSettings.objects.select_related("provider", "provider__user")
        .all()
        .order_by("-updated_at")
    )
    q = (request.GET.get("q") or "").strip()
    if q:
        qs = qs.filter(
            Q(provider__user__phone__icontains=q)
            | Q(iban__icontains=q)
            | Q(bank_name__icontains=q)
            | Q(account_name__icontains=q)
        )

    if _want_csv(request):
        rows = []
        for fs in _limited_export_queryset(request, qs):
            rows.append([
                fs.provider.user.phone if fs.provider and fs.provider.user else "",
                fs.bank_name,
                fs.account_name,
                fs.iban,
                fs.updated_at.isoformat() if fs.updated_at else "",
            ])
        return _csv_response(
            "extras_finance.csv",
            ["جوال المزود", "اسم البنك", "اسم صاحب الحساب", "IBAN", "آخر تحديث"],
            rows,
        )

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    return render(
        request,
        "dashboard/extras_finance_list.html",
        {"page_obj": page_obj, "q": q},
    )


# ── Extras: Client list ─────────────────────────────────────────────

@staff_member_required
@dashboard_access_required("extras")
def extras_clients_list(request: HttpRequest) -> HttpResponse:
    """عرض قائمة عملاء الخدمات الإضافية."""
    from apps.extras_portal.models import ExtrasPortalSubscription

    qs = (
        ExtrasPortalSubscription.objects
        .select_related("user", "provider", "provider__user")
        .all()
        .order_by("-created_at")
    )
    q = (request.GET.get("q") or "").strip()
    if q:
        qs = qs.filter(
            Q(user__phone__icontains=q) | Q(provider__user__phone__icontains=q)
        )
    active_filter = (request.GET.get("active") or "").strip()
    if active_filter == "1":
        qs = qs.filter(is_active=True)
    elif active_filter == "0":
        qs = qs.filter(is_active=False)

    if _want_csv(request):
        rows = []
        for s in _limited_export_queryset(request, qs):
            rows.append([
                s.user.phone if s.user else "",
                s.provider.user.phone if s.provider and s.provider.user else "",
                s.is_active,
                s.created_at.isoformat() if s.created_at else "",
            ])
        return _csv_response(
            "extras_clients.csv",
            ["جوال العميل", "جوال المزود", "فعّال", "تاريخ الاشتراك"],
            rows,
        )

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    return render(
        request,
        "dashboard/extras_clients_list.html",
        {"page_obj": page_obj, "q": q, "active_filter": active_filter},
    )


@staff_member_required
@dashboard_access_required("analytics")
def features_overview(request: HttpRequest) -> HttpResponse:
    users_qs = User.objects.all().order_by("-id")
    q = (request.GET.get("q") or "").strip()
    if q:
        users_qs = users_qs.filter(Q(phone__icontains=q) | Q(username__icontains=q) | Q(email__icontains=q))
    paginator = Paginator(users_qs, 20)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    page_user_ids = [user.id for user in page_obj.object_list]
    active_sub_by_user_id = get_effective_active_subscriptions_map(page_user_ids)

    rows = []
    for user in page_obj.object_list:
        active_sub = active_sub_by_user_id.get(user.id)
        pricing = verification_pricing_for_plan(getattr(active_sub, "plan", None))
        prices = pricing.get("prices") or {}
        rows.append(
            {
                "user": user,
                "subscription_tier": pricing.get("tier_label", "أساسية"),
                "verify_blue_fee": verification_price_amount(pricing, "blue"),
                "verify_green_fee": verification_price_amount(pricing, "green"),
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
                row["subscription_tier"],
                row["verify_blue_fee"],
                row["verify_green_fee"],
                row["promo_ads"],
                row["priority_support"],
                row["extra_uploads"],
                row["max_upload_mb"],
            ]
            for row in rows
        ]
        return _csv_response(
            "features_overview.csv",
            ["user_id", "phone", "subscription_tier", "verify_blue_fee", "verify_green_fee", "promo_ads", "priority_support", "extra_uploads", "max_upload_mb"],
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
    # Moved to admin_views.py — this stub kept for any direct import references.
    from . import admin_views
    return admin_views.access_profiles_list(request)


@staff_member_required
@dashboard_access_required("access", write=True)
@require_POST
def access_profile_create_action(request: HttpRequest) -> HttpResponse:
    from . import admin_views
    return admin_views.access_profile_create_action(request)


@staff_member_required
@dashboard_access_required("access", write=True)
@require_POST
def access_profile_update_action(request: HttpRequest, profile_id: int) -> HttpResponse:
    from . import admin_views
    return admin_views.access_profile_update_action(request, profile_id)


@staff_member_required
@dashboard_access_required("access", write=True)
@require_POST
def access_profile_toggle_revoke_action(request: HttpRequest, profile_id: int) -> HttpResponse:
    from . import admin_views
    return admin_views.access_profile_toggle_revoke_action(request, profile_id)
