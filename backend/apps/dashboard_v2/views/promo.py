from __future__ import annotations

from decimal import Decimal

from django.contrib import messages
from django.core.paginator import Paginator
from django.db.models import Count, Q
from django.http import HttpResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.utils import timezone
from django.views.decorators.http import require_POST

from apps.backoffice.models import AccessLevel
from apps.backoffice.policies import PromoQuoteActivatePolicy
from apps.dashboard.access import (
    can_access_object,
    dashboard_assignee_user,
    dashboard_assignment_users,
    has_action_permission,
    has_dashboard_access,
)
from apps.dashboard.contracts import DashboardCode
from apps.promo.models import (
    HomeBanner,
    PromoInquiryProfile,
    PromoOpsStatus,
    PromoPricingRule,
    PromoRequest,
    PromoRequestItem,
    PromoRequestStatus,
    PromoServiceType,
)
from apps.promo.services import (
    _sync_promo_to_unified,
    activate_after_payment,
    ensure_default_pricing_rules,
    quote_and_create_invoice,
    reject_request,
    set_promo_ops_status,
)
from apps.support.models import SupportPriority, SupportTeam, SupportTicket, SupportTicketStatus, SupportTicketType
from apps.support.services import assign_ticket, change_ticket_status
from apps.unified_requests.models import UnifiedRequest

from ..view_utils import apply_role_scope, build_layout_context, dashboard_v2_access_required


PROMO_MODULE_MENU: tuple[tuple[str, str], ...] = (
    (PromoServiceType.HOME_BANNER, "بنر الصفحة الرئيسية"),
    (PromoServiceType.FEATURED_SPECIALISTS, "شريط أبرز المختصين"),
    (PromoServiceType.PORTFOLIO_SHOWCASE, "شريط البنرات والمشاريع"),
    (PromoServiceType.SNAPSHOTS, "شريط اللمحات"),
    (PromoServiceType.SEARCH_RESULTS, "الظهور في قوائم البحث"),
    (PromoServiceType.PROMO_MESSAGES, "الرسائل الدعائية"),
    (PromoServiceType.SPONSORSHIP, "الرعاية"),
)


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


def _promo_unified_request(pr: PromoRequest):
    return (
        UnifiedRequest.objects.select_related("assigned_user")
        .prefetch_related("status_logs__changed_by", "assignment_logs__changed_by", "assignment_logs__to_user")
        .filter(source_app="promo", source_model="PromoRequest", source_object_id=str(pr.id))
        .first()
    )


def _promo_can_access_request(user, pr: PromoRequest) -> bool:
    return can_access_object(
        user,
        pr,
        assigned_field="assigned_to",
        allow_unassigned_for_user_level=True,
    )


def _promo_can_access_ticket(user, ticket: SupportTicket) -> bool:
    return can_access_object(
        user,
        ticket,
        assigned_field="assigned_to",
        allow_unassigned_for_user_level=True,
    )


def _promo_service_counts() -> list[dict[str, object]]:
    counts = {
        row["service_type"]: row["count"]
        for row in PromoRequestItem.objects.values("service_type").annotate(count=Count("id"))
    }
    return [{"key": key, "label": label, "count": counts.get(key, 0)} for key, label in PROMO_MODULE_MENU]


@dashboard_v2_access_required(DashboardCode.PROMO, write=False)
def promo_requests_list_view(request):
    qs = _promo_requests_queryset()

    q = (request.GET.get("q") or "").strip()
    status_val = (request.GET.get("status") or "").strip()
    ops_status_val = (request.GET.get("ops_status") or "").strip()

    if q:
        qs = qs.filter(Q(code__icontains=q) | Q(title__icontains=q) | Q(requester__phone__icontains=q))
    if status_val:
        qs = qs.filter(status=status_val)
    if ops_status_val:
        qs = qs.filter(ops_status=ops_status_val)

    qs = apply_role_scope(
        qs,
        user=request.user,
        assigned_field="assigned_to",
        owner_field=None,
        include_unassigned_for_user=False,
    )

    inquiries_qs = apply_role_scope(
        _promo_inquiries_queryset(),
        user=request.user,
        assigned_field="assigned_to",
        owner_field=None,
        include_unassigned_for_user=False,
    )

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    query = request.GET.copy()
    query.pop("page", None)

    summary = qs.aggregate(
        total=Count("id"),
        new=Count("id", filter=Q(status=PromoRequestStatus.NEW)),
        active=Count("id", filter=Q(status=PromoRequestStatus.ACTIVE)),
        completed=Count("id", filter=Q(ops_status=PromoOpsStatus.COMPLETED)),
    )

    can_write = has_dashboard_access(request.user, DashboardCode.PROMO, write=True)
    can_manage = can_write and has_action_permission(request.user, "promo.quote_activate")

    context = build_layout_context(
        request,
        title="الترويج",
        subtitle="طلبات الترويج + استفسارات التأهيل + التسعير",
        active_code=DashboardCode.PROMO,
        breadcrumbs=[{"label": "لوحة التحكم", "url": "dashboard_v2:home"}],
    )
    context.update(
        {
            "page_obj": page_obj,
            "query_string": query.urlencode(),
            "q": q,
            "status_val": status_val,
            "ops_status_val": ops_status_val,
            "status_choices": PromoRequestStatus.choices,
            "ops_status_choices": PromoOpsStatus.choices,
            "service_counts": _promo_service_counts(),
            "summary": {
                "total": summary.get("total") or 0,
                "new": summary.get("new") or 0,
                "active": summary.get("active") or 0,
                "completed": summary.get("completed") or 0,
                "new_inquiries": inquiries_qs.filter(status=SupportTicketStatus.NEW).count(),
            },
            "can_manage": can_manage,
            "table_headers": ["الطلب", "العميل", "الحالة", "التنفيذ", "المكلّف", "آخر تحديث", "إجراءات"],
        }
    )
    return render(request, "dashboard_v2/promo/requests_list.html", context)


@dashboard_v2_access_required(DashboardCode.PROMO, write=False)
def promo_request_detail_view(request, promo_id: int):
    pr = get_object_or_404(
        PromoRequest.objects.select_related("requester", "invoice", "assigned_to").prefetch_related(
            "items__assets",
            "assets",
        ),
        id=promo_id,
    )
    if not _promo_can_access_request(request.user, pr):
        return HttpResponse("غير مصرح", status=403)

    ur = _promo_unified_request(pr)
    status_logs = list(getattr(ur, "status_logs", []).all()) if ur else []
    assignment_logs = list(getattr(ur, "assignment_logs", []).all()) if ur else []
    items = list(pr.items.all().order_by("sort_order", "id"))
    assets = list(pr.assets.select_related("item").all().order_by("-id"))
    invoice_lines = list(pr.invoice.lines.all().order_by("sort_order", "id")) if pr.invoice_id and hasattr(pr.invoice, "lines") else []

    assignees = dashboard_assignment_users(DashboardCode.PROMO, write=True, limit=120)
    can_write = has_dashboard_access(request.user, DashboardCode.PROMO, write=True)
    can_manage = can_write and has_action_permission(request.user, "promo.quote_activate")

    context = build_layout_context(
        request,
        title=f"طلب ترويج {pr.code or pr.id}",
        subtitle="تفاصيل الحملة والمرفقات والسجل التشغيلي",
        active_code=DashboardCode.PROMO,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "الترويج", "url": "dashboard_v2:promo_requests_list"},
        ],
    )
    context.update(
        {
            "pr": pr,
            "ur": ur,
            "status_logs": status_logs[:60],
            "assignment_logs": assignment_logs[:60],
            "items": items,
            "assets": assets,
            "invoice_lines": invoice_lines,
            "assignees": assignees,
            "can_manage": can_manage,
            "ops_status_choices": PromoOpsStatus.choices,
        }
    )
    return render(request, "dashboard_v2/promo/request_detail.html", context)


@dashboard_v2_access_required(DashboardCode.PROMO, write=True)
@require_POST
def promo_request_assign_action(request, promo_id: int):
    pr = get_object_or_404(PromoRequest, id=promo_id)
    if not _promo_can_access_request(request.user, pr):
        return HttpResponse("غير مصرح", status=403)
    if not has_action_permission(request.user, "promo.quote_activate"):
        messages.error(request, "ليس لديك صلاحية تعديل هذا الطلب.")
        return redirect("dashboard_v2:promo_request_detail", promo_id=pr.id)

    assigned_to_raw = request.POST.get("assigned_to") or None
    note = (request.POST.get("note") or "").strip()
    try:
        assigned_to = int(assigned_to_raw) if assigned_to_raw else None
    except Exception:
        assigned_to = None

    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == AccessLevel.USER and assigned_to not in (None, request.user.id):
        return HttpResponse("غير مصرح", status=403)
    if assigned_to is not None and dashboard_assignee_user(assigned_to, DashboardCode.PROMO, write=True) is None:
        messages.error(request, "المكلّف غير صحيح")
        return redirect("dashboard_v2:promo_request_detail", promo_id=pr.id)

    pr.assigned_to_id = assigned_to
    pr.assigned_at = timezone.now() if assigned_to else None
    pr.save(update_fields=["assigned_to", "assigned_at", "updated_at"])
    _sync_promo_to_unified(pr=pr, changed_by=request.user)
    if note:
        messages.success(request, "تم تحديث الإسناد وحفظ الملاحظة.")
    else:
        messages.success(request, "تم تحديث الإسناد.")
    return redirect("dashboard_v2:promo_request_detail", promo_id=pr.id)


@dashboard_v2_access_required(DashboardCode.PROMO, write=True)
@require_POST
def promo_request_ops_status_action(request, promo_id: int):
    pr = get_object_or_404(PromoRequest, id=promo_id)
    if not _promo_can_access_request(request.user, pr):
        return HttpResponse("غير مصرح", status=403)

    policy = PromoQuoteActivatePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="promo.request",
        reference_id=str(pr.id),
        extra={"surface": "dashboard_v2.promo_request_ops_status_action", "action_name": "ops_status"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتحديث تشغيل هذه الحملة.")
        return redirect("dashboard_v2:promo_request_detail", promo_id=pr.id)

    status_new = (request.POST.get("status") or "").strip()
    note = (request.POST.get("note") or "").strip()
    if status_new not in PromoOpsStatus.values:
        messages.warning(request, "حالة التنفيذ غير صحيحة.")
        return redirect("dashboard_v2:promo_request_detail", promo_id=pr.id)

    try:
        set_promo_ops_status(pr=pr, new_status=status_new, by_user=request.user, note=note)
        messages.success(request, "تم تحديث حالة التنفيذ.")
    except Exception as exc:
        messages.error(request, str(exc) or "تعذر تحديث حالة التنفيذ.")
    return redirect("dashboard_v2:promo_request_detail", promo_id=pr.id)


@dashboard_v2_access_required(DashboardCode.PROMO, write=True)
@require_POST
def promo_quote_action(request, promo_id: int):
    pr = get_object_or_404(PromoRequest, id=promo_id)
    if not _promo_can_access_request(request.user, pr):
        return HttpResponse("غير مصرح", status=403)

    policy = PromoQuoteActivatePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="promo.request",
        reference_id=str(pr.id),
        extra={"surface": "dashboard_v2.promo_quote_action", "action_name": "quote"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتسعير هذه الحملة.")
        return redirect("dashboard_v2:promo_request_detail", promo_id=pr.id)

    note = (request.POST.get("quote_note") or "").strip()
    try:
        quote_and_create_invoice(pr=pr, by_user=request.user, quote_note=note)
        messages.success(request, "تم التسعير وإنشاء الفاتورة.")
    except Exception as exc:
        messages.error(request, str(exc) or "تعذر تسعير الطلب.")
    return redirect("dashboard_v2:promo_request_detail", promo_id=pr.id)


@dashboard_v2_access_required(DashboardCode.PROMO, write=True)
@require_POST
def promo_reject_action(request, promo_id: int):
    pr = get_object_or_404(PromoRequest, id=promo_id)
    if not _promo_can_access_request(request.user, pr):
        return HttpResponse("غير مصرح", status=403)

    policy = PromoQuoteActivatePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="promo.request",
        reference_id=str(pr.id),
        extra={"surface": "dashboard_v2.promo_reject_action", "action_name": "reject"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح برفض هذه الحملة.")
        return redirect("dashboard_v2:promo_request_detail", promo_id=pr.id)

    reason = (request.POST.get("reject_reason") or "").strip()
    if not reason:
        messages.warning(request, "سبب الرفض مطلوب.")
        return redirect("dashboard_v2:promo_request_detail", promo_id=pr.id)
    try:
        reject_request(pr=pr, reason=reason, by_user=request.user)
        messages.success(request, "تم رفض الطلب.")
    except Exception as exc:
        messages.error(request, str(exc) or "تعذر رفض الطلب.")
    return redirect("dashboard_v2:promo_request_detail", promo_id=pr.id)


@dashboard_v2_access_required(DashboardCode.PROMO, write=True)
@require_POST
def promo_activate_action(request, promo_id: int):
    pr = get_object_or_404(PromoRequest, id=promo_id)
    if not _promo_can_access_request(request.user, pr):
        return HttpResponse("غير مصرح", status=403)

    policy = PromoQuoteActivatePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="promo.request",
        reference_id=str(pr.id),
        extra={"surface": "dashboard_v2.promo_activate_action", "action_name": "activate"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتفعيل هذه الحملة.")
        return redirect("dashboard_v2:promo_request_detail", promo_id=pr.id)

    try:
        activate_after_payment(pr=pr)
        messages.success(request, "تم تفعيل الحملة بنجاح.")
    except Exception as exc:
        messages.error(request, str(exc) or "تعذر تفعيل الحملة.")
    return redirect("dashboard_v2:promo_request_detail", promo_id=pr.id)


@dashboard_v2_access_required(DashboardCode.PROMO, write=False)
def promo_inquiries_list_view(request):
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

    qs = apply_role_scope(
        qs,
        user=request.user,
        assigned_field="assigned_to",
        owner_field=None,
        include_unassigned_for_user=False,
    )

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    query = request.GET.copy()
    query.pop("page", None)

    context = build_layout_context(
        request,
        title="استفسارات الترويج",
        subtitle="تذاكر التأهيل الأولي قبل التحويل للتنفيذ",
        active_code=DashboardCode.PROMO,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "الترويج", "url": "dashboard_v2:promo_requests_list"},
        ],
    )
    context.update(
        {
            "page_obj": page_obj,
            "query_string": query.urlencode(),
            "q": q,
            "status_val": status_val,
            "priority_val": priority_val,
            "status_choices": SupportTicketStatus.choices,
            "priority_choices": SupportPriority.choices,
            "can_write": has_dashboard_access(request.user, DashboardCode.PROMO, write=True),
            "table_headers": ["الكود", "العميل", "الأولوية", "الحالة", "المكلّف", "آخر تحديث", "إجراءات"],
        }
    )
    return render(request, "dashboard_v2/promo/inquiries_list.html", context)


@dashboard_v2_access_required(DashboardCode.PROMO, write=False)
def promo_inquiry_detail_view(request, ticket_id: int):
    ticket = get_object_or_404(
        SupportTicket.objects.select_related("requester", "assigned_team", "assigned_to", "last_action_by"),
        id=ticket_id,
        ticket_type=SupportTicketType.ADS,
    )
    if not _promo_can_access_ticket(request.user, ticket):
        return HttpResponse("غير مصرح", status=403)

    comments = list(ticket.comments.select_related("created_by").order_by("-id")[:40])
    logs = list(ticket.status_logs.select_related("changed_by").order_by("-id")[:40])
    teams = list(SupportTeam.objects.filter(is_active=True).order_by("sort_order", "id"))
    assignees = dashboard_assignment_users(DashboardCode.PROMO, write=True, limit=120)
    linked_requests = list(_promo_requests_queryset().filter(requester=ticket.requester)[:20])
    profile, _ = PromoInquiryProfile.objects.get_or_create(ticket=ticket)

    can_write = has_dashboard_access(request.user, DashboardCode.PROMO, write=True)
    context = build_layout_context(
        request,
        title=f"استفسار ترويج {ticket.code or ticket.id}",
        subtitle="تتبع الحالة، الإسناد، وربط الاستفسار بطلب ترويج",
        active_code=DashboardCode.PROMO,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "استفسارات الترويج", "url": "dashboard_v2:promo_inquiries_list"},
        ],
    )
    context.update(
        {
            "ticket": ticket,
            "comments": comments,
            "logs": logs,
            "teams": teams,
            "assignees": assignees,
            "linked_requests": linked_requests,
            "profile": profile,
            "status_choices": SupportTicketStatus.choices,
            "can_write": can_write,
        }
    )
    return render(request, "dashboard_v2/promo/inquiry_detail.html", context)


@dashboard_v2_access_required(DashboardCode.PROMO, write=True)
@require_POST
def promo_inquiry_assign_action(request, ticket_id: int):
    ticket = get_object_or_404(SupportTicket, id=ticket_id, ticket_type=SupportTicketType.ADS)
    if not _promo_can_access_ticket(request.user, ticket):
        return HttpResponse("غير مصرح", status=403)

    team_id_raw = request.POST.get("assigned_team") or None
    assigned_to_raw = request.POST.get("assigned_to") or None
    if (request.POST.get("assign_to_me") or "") == "1" and not assigned_to_raw:
        assigned_to_raw = str(request.user.id)
    note = (request.POST.get("note") or "").strip()

    try:
        team_id = int(team_id_raw) if team_id_raw else None
    except Exception:
        team_id = None
    try:
        assigned_to = int(assigned_to_raw) if assigned_to_raw else None
    except Exception:
        assigned_to = None

    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == AccessLevel.USER and assigned_to not in (None, request.user.id):
        return HttpResponse("غير مصرح", status=403)

    if assigned_to is not None and dashboard_assignee_user(assigned_to, DashboardCode.PROMO, write=True) is None:
        messages.error(request, "المستخدم المحدد غير صالح.")
        return redirect("dashboard_v2:promo_inquiry_detail", ticket_id=ticket.id)

    try:
        assign_ticket(ticket=ticket, team_id=team_id, user_id=assigned_to, by_user=request.user, note=note)
        messages.success(request, "تم تحديث التعيين بنجاح.")
    except Exception:
        messages.error(request, "تعذر تحديث التعيين.")
    return redirect("dashboard_v2:promo_inquiry_detail", ticket_id=ticket.id)


@dashboard_v2_access_required(DashboardCode.PROMO, write=True)
@require_POST
def promo_inquiry_status_action(request, ticket_id: int):
    ticket = get_object_or_404(SupportTicket, id=ticket_id, ticket_type=SupportTicketType.ADS)
    if not _promo_can_access_ticket(request.user, ticket):
        return HttpResponse("غير مصرح", status=403)

    status_new = (request.POST.get("status") or "").strip()
    note = (request.POST.get("note") or "").strip()
    if status_new not in set(SupportTicketStatus.values):
        messages.warning(request, "اختر حالة صالحة.")
        return redirect("dashboard_v2:promo_inquiry_detail", ticket_id=ticket.id)
    try:
        change_ticket_status(ticket=ticket, new_status=status_new, by_user=request.user, note=note)
        messages.success(request, "تم تحديث حالة الاستفسار.")
    except Exception:
        messages.error(request, "تعذر تحديث الحالة.")
    return redirect("dashboard_v2:promo_inquiry_detail", ticket_id=ticket.id)


@dashboard_v2_access_required(DashboardCode.PROMO, write=True)
@require_POST
def promo_inquiry_profile_action(request, ticket_id: int):
    ticket = get_object_or_404(SupportTicket, id=ticket_id, ticket_type=SupportTicketType.ADS)
    if not _promo_can_access_ticket(request.user, ticket):
        return HttpResponse("غير مصرح", status=403)

    profile, _ = PromoInquiryProfile.objects.get_or_create(ticket=ticket)
    linked_request_id = (request.POST.get("linked_request") or "").strip()
    profile.linked_request = PromoRequest.objects.filter(id=linked_request_id).first() if linked_request_id else None
    profile.detailed_request_url = (request.POST.get("detailed_request_url") or "").strip()
    profile.documentation_note = (request.POST.get("documentation_note") or "").strip()[:300]
    profile.operator_comment = (request.POST.get("operator_comment") or "").strip()[:300]
    profile.save(
        update_fields=[
            "linked_request",
            "detailed_request_url",
            "documentation_note",
            "operator_comment",
            "updated_at",
        ]
    )
    messages.success(request, "تم حفظ بيانات الاستفسار.")
    return redirect("dashboard_v2:promo_inquiry_detail", ticket_id=ticket.id)


@dashboard_v2_access_required(DashboardCode.PROMO, write=False)
def promo_pricing_view(request):
    ensure_default_pricing_rules()
    rows = list(PromoPricingRule.objects.all().order_by("sort_order", "id"))
    groups = [{"key": key, "label": label, "rows": [row for row in rows if row.service_type == key]} for key, label in PROMO_MODULE_MENU]
    can_write = has_dashboard_access(request.user, DashboardCode.PROMO, write=True)
    can_manage = can_write and has_action_permission(request.user, "promo.quote_activate")

    context = build_layout_context(
        request,
        title="تسعير الترويج",
        subtitle="إدارة قواعد التسعير الداخلية لكل خدمة ترويجية",
        active_code=DashboardCode.PROMO,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "الترويج", "url": "dashboard_v2:promo_requests_list"},
        ],
    )
    context.update({"groups": groups, "can_manage": can_manage})
    return render(request, "dashboard_v2/promo/pricing.html", context)


@dashboard_v2_access_required(DashboardCode.PROMO, write=True)
@require_POST
def promo_pricing_update_action(request):
    if not has_action_permission(request.user, "promo.quote_activate"):
        messages.error(request, "ليس لديك صلاحية تعديل تسعير الحملات.")
        return redirect("dashboard_v2:promo_pricing")

    code = (request.POST.get("code") or "").strip()
    raw_price = (request.POST.get("amount") or "").strip()
    is_active = (request.POST.get("is_active") or "").strip().lower() in {"1", "true", "on", "yes"}

    rule = PromoPricingRule.objects.filter(code=code).first()
    if not rule:
        messages.error(request, "قاعدة التسعير غير صحيحة.")
        return redirect("dashboard_v2:promo_pricing")

    try:
        price = Decimal(raw_price)
        if price < 0:
            raise ValueError
    except Exception:
        messages.error(request, "السعر غير صحيح.")
        return redirect("dashboard_v2:promo_pricing")

    rule.amount = price
    rule.is_active = is_active
    rule.save(update_fields=["amount", "is_active", "updated_at"])
    messages.success(request, "تم حفظ التسعير.")
    return redirect("dashboard_v2:promo_pricing")


@dashboard_v2_access_required(DashboardCode.PROMO, write=False)
def promo_banners_list_view(request):
    qs = HomeBanner.objects.select_related("provider", "created_by").all().order_by("display_order", "-created_at")
    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    query = request.GET.copy()
    query.pop("page", None)

    context = build_layout_context(
        request,
        title="بنرات الترويج",
        subtitle="عرض البنرات الفعالة والوسائط المرتبطة بالحملات",
        active_code=DashboardCode.PROMO,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "الترويج", "url": "dashboard_v2:promo_requests_list"},
        ],
    )
    context.update(
        {
            "page_obj": page_obj,
            "query_string": query.urlencode(),
            "can_manage": has_dashboard_access(request.user, DashboardCode.PROMO, write=True),
            "table_headers": ["العنوان", "النوع", "المزود", "الفترة", "الحالة", "الترتيب", "آخر تحديث"],
        }
    )
    return render(request, "dashboard_v2/promo/banners_list.html", context)
