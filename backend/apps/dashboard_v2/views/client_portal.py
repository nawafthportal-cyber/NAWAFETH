from __future__ import annotations

from django.core.paginator import Paginator
from django.db.models import Count, Q, Sum
from django.http import HttpResponse
from django.shortcuts import get_object_or_404, render

from apps.billing.models import Invoice, InvoiceStatus, PaymentAttempt
from apps.dashboard.access import can_access_object, has_dashboard_access
from apps.dashboard.contracts import CANONICAL_OPERATIONAL_STATUSES, DashboardCode
from apps.extras.models import ExtraPurchase, ExtraPurchaseStatus
from apps.unified_requests.models import UnifiedRequest, UnifiedRequestStatus, UnifiedRequestType

from ..view_utils import build_layout_context, dashboard_v2_access_required


def _portal_requests_queryset(*, user):
    return (
        UnifiedRequest.objects.select_related("requester", "assigned_user")
        .prefetch_related("status_logs__changed_by", "assignment_logs__changed_by")
        .filter(request_type=UnifiedRequestType.EXTRAS, requester=user)
        .order_by("-updated_at", "-id")
    )


def _portal_purchases_queryset(*, user):
    return ExtraPurchase.objects.select_related("invoice").filter(user=user).order_by("-id")


def _portal_invoices_queryset(*, user):
    return Invoice.objects.filter(user=user).order_by("-created_at", "-id")


def _can_access_portal_request(user, ur: UnifiedRequest) -> bool:
    return can_access_object(
        user,
        ur,
        assigned_field="assigned_user",
        owner_field="requester",
        allow_unassigned_for_user_level=False,
    )


def _can_access_portal_purchase(user, purchase: ExtraPurchase) -> bool:
    return can_access_object(user, purchase, owner_field="user", allow_unassigned_for_user_level=False)


def _can_access_portal_invoice(user, invoice: Invoice) -> bool:
    return can_access_object(user, invoice, owner_field="user", allow_unassigned_for_user_level=False)


@dashboard_v2_access_required(DashboardCode.CLIENT_EXTRAS, write=False)
def client_portal_home_view(request):
    requests_qs = _portal_requests_queryset(user=request.user)
    purchases_qs = _portal_purchases_queryset(user=request.user)
    invoices_qs = _portal_invoices_queryset(user=request.user)

    cards = {
        "requests_open": requests_qs.filter(
            status__in=[
                UnifiedRequestStatus.NEW,
                UnifiedRequestStatus.IN_PROGRESS,
                UnifiedRequestStatus.RETURNED,
            ]
        ).count(),
        "services_total": purchases_qs.count(),
        "services_active": purchases_qs.filter(status=ExtraPurchaseStatus.ACTIVE).count(),
        "invoices_pending": invoices_qs.filter(status=InvoiceStatus.PENDING).count(),
    }

    context = build_layout_context(
        request,
        title="بوابة العميل",
        subtitle="متابعة طلباتك وخدماتك وفواتيرك من مكان واحد",
        active_code=DashboardCode.CLIENT_EXTRAS,
        breadcrumbs=[{"label": "لوحة التحكم", "url": "dashboard_v2:home"}],
    )
    context.update(
        {
            "cards": cards,
            "recent_requests": list(requests_qs[:6]),
            "recent_services": list(purchases_qs[:6]),
            "quick_links": [
                {"label": "طلباتي", "url": "dashboard_v2:client_portal_requests_list"},
                {"label": "خدماتي", "url": "dashboard_v2:client_portal_services_list"},
                {"label": "تقاريري", "url": "dashboard_v2:client_portal_reports"},
                {"label": "كشف الحساب", "url": "dashboard_v2:client_portal_account_statement"},
                {"label": "الملف الشخصي", "url": "dashboard_v2:client_portal_profile"},
                {"label": "الإعدادات", "url": "dashboard_v2:client_portal_settings"},
            ],
        }
    )
    return render(request, "dashboard_v2/client_portal/home.html", context)


@dashboard_v2_access_required(DashboardCode.CLIENT_EXTRAS, write=False)
def client_portal_requests_list_view(request):
    qs = _portal_requests_queryset(user=request.user)
    q = (request.GET.get("q") or "").strip()
    status_val = (request.GET.get("status") or "").strip()

    if q:
        qs = qs.filter(Q(code__icontains=q) | Q(summary__icontains=q) | Q(source_object_id__icontains=q))
    if status_val:
        qs = qs.filter(status=status_val)

    paginator = Paginator(qs, 20)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    query = request.GET.copy()
    query.pop("page", None)
    status_labels = dict(UnifiedRequestStatus.choices)
    status_choices = [(value, status_labels.get(value, value)) for value in CANONICAL_OPERATIONAL_STATUSES]

    context = build_layout_context(
        request,
        title="طلباتي",
        subtitle="الطلبات التشغيلية المرتبطة بالخدمات الإضافية",
        active_code=DashboardCode.CLIENT_EXTRAS,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "بوابة العميل", "url": "dashboard_v2:client_portal_home"},
        ],
    )
    context.update(
        {
            "page_obj": page_obj,
            "query_string": query.urlencode(),
            "q": q,
            "status_val": status_val,
            "status_choices": status_choices,
            "table_headers": ["الكود", "الحالة", "الملخص", "المكلّف", "آخر تحديث", "إجراءات"],
        }
    )
    return render(request, "dashboard_v2/client_portal/requests_list.html", context)


@dashboard_v2_access_required(DashboardCode.CLIENT_EXTRAS, write=False)
def client_portal_request_detail_view(request, request_id: int):
    ur = get_object_or_404(
        UnifiedRequest.objects.select_related("requester", "assigned_user")
        .prefetch_related("status_logs__changed_by", "assignment_logs__changed_by")
        .filter(request_type=UnifiedRequestType.EXTRAS),
        id=request_id,
    )
    if not _can_access_portal_request(request.user, ur):
        return HttpResponse("غير مصرح", status=403)

    metadata_payload = getattr(getattr(ur, "metadata_record", None), "payload", {}) or {}
    timeline = []
    for status_log in ur.status_logs.all():
        timeline.append(
            {
                "title": "تغيير حالة",
                "detail": f"{status_log.from_status or '—'} -> {status_log.to_status}",
                "at": status_log.created_at,
                "note": status_log.note or "",
            }
        )
    for assign_log in ur.assignment_logs.all():
        timeline.append(
            {
                "title": "تحديث إسناد",
                "detail": f"{assign_log.from_team_code or '—'} -> {assign_log.to_team_code or '—'}",
                "at": assign_log.created_at,
                "note": assign_log.note or "",
            }
        )
    timeline.sort(key=lambda item: item["at"], reverse=True)

    context = build_layout_context(
        request,
        title=f"تفاصيل الطلب {ur.code or ur.id}",
        subtitle="مسار الحالة والملاحظات التشغيلية",
        active_code=DashboardCode.CLIENT_EXTRAS,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "بوابة العميل", "url": "dashboard_v2:client_portal_home"},
            {"label": "طلباتي", "url": "dashboard_v2:client_portal_requests_list"},
        ],
    )
    context.update({"ur": ur, "metadata_payload": metadata_payload, "timeline": timeline[:80]})
    return render(request, "dashboard_v2/client_portal/request_detail.html", context)


@dashboard_v2_access_required(DashboardCode.CLIENT_EXTRAS, write=False)
def client_portal_services_list_view(request):
    qs = _portal_purchases_queryset(user=request.user)
    q = (request.GET.get("q") or "").strip()
    status_val = (request.GET.get("status") or "").strip()

    if q:
        qs = qs.filter(Q(sku__icontains=q) | Q(title__icontains=q))
    if status_val:
        qs = qs.filter(status=status_val)

    paginator = Paginator(qs, 20)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    query = request.GET.copy()
    query.pop("page", None)

    summary = qs.aggregate(
        total=Count("id"),
        active=Count("id", filter=Q(status=ExtraPurchaseStatus.ACTIVE)),
        pending=Count("id", filter=Q(status=ExtraPurchaseStatus.PENDING_PAYMENT)),
        expired=Count("id", filter=Q(status=ExtraPurchaseStatus.EXPIRED)),
    )

    context = build_layout_context(
        request,
        title="خدماتي",
        subtitle="إدارة مشتريات الخدمات الإضافية وحالتها",
        active_code=DashboardCode.CLIENT_EXTRAS,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "بوابة العميل", "url": "dashboard_v2:client_portal_home"},
        ],
    )
    context.update(
        {
            "page_obj": page_obj,
            "query_string": query.urlencode(),
            "q": q,
            "status_val": status_val,
            "status_choices": ExtraPurchaseStatus.choices,
            "summary": {
                "total": summary.get("total") or 0,
                "active": summary.get("active") or 0,
                "pending": summary.get("pending") or 0,
                "expired": summary.get("expired") or 0,
            },
            "table_headers": ["#", "الخدمة", "SKU", "الحالة", "الفاتورة", "آخر تحديث", "إجراءات"],
        }
    )
    return render(request, "dashboard_v2/client_portal/services_list.html", context)


@dashboard_v2_access_required(DashboardCode.CLIENT_EXTRAS, write=False)
def client_portal_service_detail_view(request, purchase_id: int):
    purchase = get_object_or_404(_portal_purchases_queryset(user=request.user), id=purchase_id)
    if not _can_access_portal_purchase(request.user, purchase):
        return HttpResponse("غير مصرح", status=403)

    linked_request = UnifiedRequest.objects.filter(
        request_type=UnifiedRequestType.EXTRAS,
        source_app="extras",
        source_model="ExtraPurchase",
        source_object_id=str(purchase.id),
        requester=request.user,
    ).first()
    line_items = list(purchase.invoice.lines.all().order_by("sort_order", "id")) if purchase.invoice_id else []

    context = build_layout_context(
        request,
        title=f"تفاصيل الخدمة #{purchase.id}",
        subtitle="حالة الخدمة والفاتورة المرتبطة",
        active_code=DashboardCode.CLIENT_EXTRAS,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "بوابة العميل", "url": "dashboard_v2:client_portal_home"},
            {"label": "خدماتي", "url": "dashboard_v2:client_portal_services_list"},
        ],
    )
    context.update({"purchase": purchase, "linked_request": linked_request, "line_items": line_items})
    return render(request, "dashboard_v2/client_portal/service_detail.html", context)


@dashboard_v2_access_required(DashboardCode.CLIENT_EXTRAS, write=False)
def client_portal_reports_view(request):
    requests_qs = _portal_requests_queryset(user=request.user)
    purchases_qs = _portal_purchases_queryset(user=request.user)
    invoices_qs = _portal_invoices_queryset(user=request.user)

    request_breakdown = list(
        requests_qs.values("status")
        .annotate(count=Count("id"))
        .order_by("-count", "status")
    )
    purchase_breakdown = list(
        purchases_qs.values("status")
        .annotate(count=Count("id"))
        .order_by("-count", "status")
    )
    invoice_breakdown = list(
        invoices_qs.values("status")
        .annotate(count=Count("id"), total=Sum("total"))
        .order_by("-count", "status")
    )

    context = build_layout_context(
        request,
        title="تقارير العميل",
        subtitle="ملخص استخدام الطلبات والخدمات والفواتير",
        active_code=DashboardCode.CLIENT_EXTRAS,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "بوابة العميل", "url": "dashboard_v2:client_portal_home"},
        ],
    )
    context.update(
        {
            "request_breakdown": request_breakdown,
            "purchase_breakdown": purchase_breakdown,
            "invoice_breakdown": invoice_breakdown,
            "totals": {
                "requests_total": requests_qs.count(),
                "services_total": purchases_qs.count(),
                "paid_invoices": invoices_qs.filter(status=InvoiceStatus.PAID).count(),
                "pending_invoices": invoices_qs.filter(status=InvoiceStatus.PENDING).count(),
            },
            "latest_requests": list(requests_qs[:5]),
            "latest_services": list(purchases_qs[:5]),
            "latest_invoices": list(invoices_qs[:5]),
        }
    )
    return render(request, "dashboard_v2/client_portal/reports.html", context)


@dashboard_v2_access_required(DashboardCode.CLIENT_EXTRAS, write=False)
def client_portal_account_statement_view(request):
    qs = _portal_invoices_queryset(user=request.user)
    q = (request.GET.get("q") or "").strip()
    status_val = (request.GET.get("status") or "").strip()

    if q:
        qs = qs.filter(Q(code__icontains=q) | Q(title__icontains=q) | Q(reference_id__icontains=q))
    if status_val:
        qs = qs.filter(status=status_val)

    paginator = Paginator(qs, 20)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    query = request.GET.copy()
    query.pop("page", None)

    totals = qs.aggregate(
        gross=Sum("total"),
        paid=Sum("total", filter=Q(status=InvoiceStatus.PAID)),
        pending=Sum("total", filter=Q(status=InvoiceStatus.PENDING)),
    )

    context = build_layout_context(
        request,
        title="كشف الحساب",
        subtitle="كل الفواتير المرتبطة بحسابك",
        active_code=DashboardCode.CLIENT_EXTRAS,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "بوابة العميل", "url": "dashboard_v2:client_portal_home"},
        ],
    )
    context.update(
        {
            "page_obj": page_obj,
            "query_string": query.urlencode(),
            "q": q,
            "status_val": status_val,
            "status_choices": InvoiceStatus.choices,
            "totals": {
                "gross": totals.get("gross") or 0,
                "paid": totals.get("paid") or 0,
                "pending": totals.get("pending") or 0,
            },
            "table_headers": ["الفاتورة", "العنوان", "المرجع", "الحالة", "الإجمالي", "تاريخ الإنشاء", "إجراءات"],
        }
    )
    return render(request, "dashboard_v2/client_portal/account_statement.html", context)


@dashboard_v2_access_required(DashboardCode.CLIENT_EXTRAS, write=False)
def client_portal_payment_detail_view(request, invoice_id: int):
    invoice = get_object_or_404(Invoice, id=invoice_id)
    if not _can_access_portal_invoice(request.user, invoice):
        return HttpResponse("غير مصرح", status=403)

    attempts = list(PaymentAttempt.objects.filter(invoice=invoice).order_by("-created_at")[:25])
    line_items = list(invoice.lines.all().order_by("sort_order", "id"))
    linked_purchase = ExtraPurchase.objects.filter(invoice=invoice, user=request.user).first()

    context = build_layout_context(
        request,
        title=f"الدفع - {invoice.code or invoice.id}",
        subtitle="تفاصيل الفاتورة ومحاولات السداد",
        active_code=DashboardCode.CLIENT_EXTRAS,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "بوابة العميل", "url": "dashboard_v2:client_portal_home"},
            {"label": "كشف الحساب", "url": "dashboard_v2:client_portal_account_statement"},
        ],
    )
    context.update(
        {
            "invoice": invoice,
            "line_items": line_items,
            "attempts": attempts,
            "linked_purchase": linked_purchase,
        }
    )
    return render(request, "dashboard_v2/client_portal/payment_detail.html", context)


@dashboard_v2_access_required(DashboardCode.CLIENT_EXTRAS, write=False)
def client_portal_profile_view(request):
    context = build_layout_context(
        request,
        title="الملف الشخصي",
        subtitle="بيانات الحساب الأساسية",
        active_code=DashboardCode.CLIENT_EXTRAS,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "بوابة العميل", "url": "dashboard_v2:client_portal_home"},
        ],
    )
    context.update(
        {
            "user_obj": request.user,
            "can_write_portal": has_dashboard_access(request.user, DashboardCode.CLIENT_EXTRAS, write=True),
        }
    )
    return render(request, "dashboard_v2/client_portal/profile.html", context)


@dashboard_v2_access_required(DashboardCode.CLIENT_EXTRAS, write=False)
def client_portal_settings_view(request):
    context = build_layout_context(
        request,
        title="الإعدادات",
        subtitle="إعدادات العرض والأمان المتاحة ضمن البوابة الحالية",
        active_code=DashboardCode.CLIENT_EXTRAS,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "بوابة العميل", "url": "dashboard_v2:client_portal_home"},
        ],
    )
    context.update(
        {
            "settings_cards": [
                {
                    "title": "أمان الحساب",
                    "text": "تفعيل OTP يتم عبر الباكند الحالي ولا يتطلب إجراء إضافي داخل Dashboard V2.",
                },
                {
                    "title": "إعدادات الإشعارات",
                    "text": "إعدادات الإشعار التفصيلية ستُربط في المرحلة التالية حسب جاهزية الخدمة.",
                },
                {
                    "title": "تفضيلات الواجهة",
                    "text": "تم تفعيل RTL والاستجابة الكاملة بشكل افتراضي لجميع صفحات بوابة العميل.",
                },
            ]
        }
    )
    return render(request, "dashboard_v2/client_portal/settings.html", context)
