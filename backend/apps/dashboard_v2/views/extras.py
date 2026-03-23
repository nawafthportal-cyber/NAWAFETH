from __future__ import annotations

from django.contrib import messages
from django.core.paginator import Paginator
from django.db import transaction
from django.db.models import Count, Q
from django.http import HttpResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.utils import timezone
from django.views.decorators.http import require_POST

from apps.audit.models import AuditAction
from apps.audit.services import log_action
from apps.backoffice.models import AccessLevel
from apps.backoffice.policies import ExtrasManagePolicy
from apps.dashboard.access import (
    active_access_profile_for_user,
    can_access_object,
    dashboard_assignee_user,
    dashboard_assignment_users,
    has_action_permission,
    has_dashboard_access,
)
from apps.dashboard.contracts import DashboardCode, TEAM_CODE_TO_NAME_AR
from apps.extras.models import ExtraPurchase, ExtraPurchaseStatus, ServiceCatalog
from apps.extras.services import activate_extra_after_payment
from apps.extras_portal.models import (
    ExtrasPortalFinanceSettings,
    ExtrasPortalSubscription,
    ExtrasPortalSubscriptionStatus,
)
from apps.unified_requests.models import (
    UnifiedRequest,
    UnifiedRequestAssignmentLog,
    UnifiedRequestStatus,
    UnifiedRequestStatusLog,
    UnifiedRequestType,
)
from apps.unified_requests.workflows import (
    allowed_statuses_for_request_type,
    canonical_status_for_workflow,
    is_valid_transition,
)

from ..view_utils import apply_role_scope, build_layout_context, dashboard_v2_access_required


def _extras_requests_queryset():
    return (
        UnifiedRequest.objects.select_related("requester", "assigned_user")
        .prefetch_related(
            "status_logs__changed_by",
            "assignment_logs__changed_by",
            "assignment_logs__from_user",
            "assignment_logs__to_user",
        )
        .filter(request_type=UnifiedRequestType.EXTRAS)
        .order_by("-id")
    )


def _extras_status_choices() -> list[tuple[str, str]]:
    status_labels = dict(UnifiedRequestStatus.choices)
    return [
        (value, status_labels.get(value, value))
        for value in allowed_statuses_for_request_type(UnifiedRequestType.EXTRAS)
    ]


def _scope_extra_purchases_queryset(qs, *, user):
    if getattr(user, "is_superuser", False):
        return qs
    access_profile = active_access_profile_for_user(user)
    if not access_profile:
        return qs.none()
    if access_profile.level in (AccessLevel.ADMIN, AccessLevel.POWER, AccessLevel.QA):
        return qs
    return qs.filter(user=user)


def _scope_provider_bound_queryset(qs, *, user):
    if getattr(user, "is_superuser", False):
        return qs
    access_profile = active_access_profile_for_user(user)
    if not access_profile:
        return qs.none()
    if access_profile.level in (AccessLevel.ADMIN, AccessLevel.POWER, AccessLevel.QA):
        return qs
    return qs.filter(provider__user=user)


def _can_access_extras_request(user, ur: UnifiedRequest) -> bool:
    return can_access_object(
        user,
        ur,
        assigned_field="assigned_user",
        owner_field="requester",
        allow_unassigned_for_user_level=False,
    ) or can_access_object(
        user,
        ur,
        assigned_field="assigned_user",
        allow_unassigned_for_user_level=False,
    )


def _can_operate_extras_request(user, ur: UnifiedRequest) -> bool:
    return can_access_object(
        user,
        ur,
        assigned_field="assigned_user",
        owner_field="requester",
        allow_unassigned_for_user_level=True,
    ) or can_access_object(
        user,
        ur,
        assigned_field="assigned_user",
        allow_unassigned_for_user_level=True,
    )


def _linked_extra_unified_request(*, purchase_id: int):
    return (
        UnifiedRequest.objects.select_related("requester", "assigned_user")
        .filter(
            request_type=UnifiedRequestType.EXTRAS,
            source_app="extras",
            source_model="ExtraPurchase",
            source_object_id=str(purchase_id),
        )
        .order_by("-id")
        .first()
    )


def _extra_purchase_from_request(ur: UnifiedRequest):
    if ur.source_app != "extras" or ur.source_model != "ExtraPurchase":
        return None
    source_id = (ur.source_object_id or "").strip()
    if not source_id.isdigit():
        return None
    return ExtraPurchase.objects.select_related("user", "invoice").filter(id=int(source_id)).first()


def _can_access_extra_purchase(user, purchase: ExtraPurchase) -> bool:
    if can_access_object(
        user,
        purchase,
        owner_field="user",
        allow_unassigned_for_user_level=False,
    ):
        return True
    linked_request = _linked_extra_unified_request(purchase_id=purchase.id)
    if linked_request is None:
        return False
    return _can_operate_extras_request(user, linked_request)


@dashboard_v2_access_required(DashboardCode.EXTRAS, write=False)
def extras_requests_list_view(request):
    qs = _extras_requests_queryset()
    q = (request.GET.get("q") or "").strip()
    status_val = (request.GET.get("status") or "").strip()

    if q:
        qs = qs.filter(
            Q(code__icontains=q)
            | Q(summary__icontains=q)
            | Q(source_object_id__icontains=q)
            | Q(requester__phone__icontains=q)
        )
    if status_val:
        qs = qs.filter(status=status_val)

    qs = apply_role_scope(
        qs,
        user=request.user,
        assigned_field="assigned_user",
        owner_field="requester",
        include_unassigned_for_user=False,
    )

    summary = qs.aggregate(
        total=Count("id"),
        new=Count("id", filter=Q(status=UnifiedRequestStatus.NEW)),
        in_progress=Count("id", filter=Q(status=UnifiedRequestStatus.IN_PROGRESS)),
        returned=Count("id", filter=Q(status=UnifiedRequestStatus.RETURNED)),
        closed=Count("id", filter=Q(status=UnifiedRequestStatus.CLOSED)),
    )

    scoped_purchases = _scope_extra_purchases_queryset(
        ExtraPurchase.objects.all(),
        user=request.user,
    )

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    query = request.GET.copy()
    query.pop("page", None)

    can_manage = has_dashboard_access(request.user, DashboardCode.EXTRAS, write=True) and has_action_permission(
        request.user,
        "extras.manage",
    )

    context = build_layout_context(
        request,
        title="الخدمات الإضافية",
        subtitle="طلبات تشغيل الخدمات الإضافية مع الربط بالشراء والفاتورة",
        active_code=DashboardCode.EXTRAS,
        breadcrumbs=[{"label": "لوحة التحكم", "url": "dashboard_v2:home"}],
    )
    context.update(
        {
            "page_obj": page_obj,
            "query_string": query.urlencode(),
            "q": q,
            "status_val": status_val,
            "status_choices": _extras_status_choices(),
            "summary": {
                "total": summary.get("total") or 0,
                "new": summary.get("new") or 0,
                "in_progress": summary.get("in_progress") or 0,
                "returned": summary.get("returned") or 0,
                "closed": summary.get("closed") or 0,
                "active_purchases": scoped_purchases.filter(status=ExtraPurchaseStatus.ACTIVE).count(),
            },
            "can_manage": can_manage,
            "table_headers": ["الكود", "الحالة", "العميل", "الملخص", "المكلّف", "آخر تحديث", "إجراءات"],
        }
    )
    return render(request, "dashboard_v2/extras/requests_list.html", context)


@dashboard_v2_access_required(DashboardCode.EXTRAS, write=False)
def extras_request_detail_view(request, request_id: int):
    ur = get_object_or_404(_extras_requests_queryset(), id=request_id)
    if not _can_access_extras_request(request.user, ur):
        return HttpResponse("غير مصرح", status=403)

    metadata_record = getattr(ur, "metadata_record", None)
    metadata_payload = getattr(metadata_record, "payload", {}) or {}
    purchase = _extra_purchase_from_request(ur)
    assignees = dashboard_assignment_users(DashboardCode.EXTRAS, write=True, limit=120)
    can_manage = has_dashboard_access(request.user, DashboardCode.EXTRAS, write=True) and has_action_permission(
        request.user,
        "extras.manage",
    )

    context = build_layout_context(
        request,
        title=f"طلب خدمات إضافية {ur.code or ur.id}",
        subtitle="تفاصيل الطلب التشغيلي + السجل + الربط المالي",
        active_code=DashboardCode.EXTRAS,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "الخدمات الإضافية", "url": "dashboard_v2:extras_requests_list"},
        ],
    )
    context.update(
        {
            "ur": ur,
            "metadata_payload": metadata_payload,
            "purchase": purchase,
            "status_logs": list(ur.status_logs.all()[:60]),
            "assignment_logs": list(ur.assignment_logs.all()[:60]),
            "assignees": assignees,
            "can_manage": can_manage,
            "status_choices": _extras_status_choices(),
        }
    )
    return render(request, "dashboard_v2/extras/request_detail.html", context)


@dashboard_v2_access_required(DashboardCode.EXTRAS, write=True)
@require_POST
def extras_request_assign_action(request, request_id: int):
    ur = get_object_or_404(UnifiedRequest, id=request_id, request_type=UnifiedRequestType.EXTRAS)
    if not _can_operate_extras_request(request.user, ur):
        return HttpResponse("غير مصرح", status=403)

    policy = ExtrasManagePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="unified_request",
        reference_id=str(ur.id),
        extra={"surface": "dashboard_v2.extras_request_assign_action", "action_name": "assign"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بإسناد طلب الخدمات الإضافية.")
        return redirect("dashboard_v2:extras_request_detail", request_id=ur.id)

    assigned_to_raw = request.POST.get("assigned_to") or None
    note = (request.POST.get("note") or "").strip()
    try:
        assigned_to = int(assigned_to_raw) if assigned_to_raw else None
    except Exception:
        assigned_to = None

    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == AccessLevel.USER and assigned_to not in (None, request.user.id):
        return HttpResponse("غير مصرح", status=403)
    if assigned_to is not None and dashboard_assignee_user(assigned_to, DashboardCode.EXTRAS, write=True) is None:
        messages.error(request, "المكلّف المحدد غير صالح.")
        return redirect("dashboard_v2:extras_request_detail", request_id=ur.id)

    team_name = TEAM_CODE_TO_NAME_AR.get(DashboardCode.EXTRAS, "الخدمات الإضافية")
    try:
        with transaction.atomic():
            ur = UnifiedRequest.objects.select_for_update().get(id=ur.id)
            old_user_id = ur.assigned_user_id
            old_team = ur.assigned_team_code or ""
            ur.assigned_team_code = DashboardCode.EXTRAS
            ur.assigned_team_name = team_name
            ur.assigned_user_id = assigned_to
            ur.assigned_at = timezone.now() if assigned_to else None
            ur.save(
                update_fields=[
                    "assigned_team_code",
                    "assigned_team_name",
                    "assigned_user",
                    "assigned_at",
                    "updated_at",
                ]
            )
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
                log_action(
                    actor=request.user,
                    request=request,
                    action=AuditAction.FIELD_CHANGED,
                    reference_type="unified_request",
                    reference_id=str(ur.id),
                    extra={
                        "field": "assigned_user",
                        "from_user_id": old_user_id,
                        "to_user_id": ur.assigned_user_id,
                        "from_team": old_team,
                        "to_team": ur.assigned_team_code or "",
                        "note": note[:200],
                    },
                )
        messages.success(request, "تم تحديث الإسناد.")
    except Exception:
        messages.error(request, "تعذر تحديث الإسناد.")
    return redirect("dashboard_v2:extras_request_detail", request_id=ur.id)


@dashboard_v2_access_required(DashboardCode.EXTRAS, write=True)
@require_POST
def extras_request_status_action(request, request_id: int):
    ur = get_object_or_404(UnifiedRequest, id=request_id, request_type=UnifiedRequestType.EXTRAS)
    if not _can_operate_extras_request(request.user, ur):
        return HttpResponse("غير مصرح", status=403)

    policy = ExtrasManagePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="unified_request",
        reference_id=str(ur.id),
        extra={"surface": "dashboard_v2.extras_request_status_action", "action_name": "status"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتحديث حالة طلب الخدمات الإضافية.")
        return redirect("dashboard_v2:extras_request_detail", request_id=ur.id)

    status_raw = (request.POST.get("status") or "").strip()
    note = (request.POST.get("note") or "").strip()
    new_status = canonical_status_for_workflow(request_type=UnifiedRequestType.EXTRAS, status=status_raw)
    allowed = set(allowed_statuses_for_request_type(UnifiedRequestType.EXTRAS))
    if not new_status or new_status not in allowed:
        messages.warning(request, "حالة غير صالحة.")
        return redirect("dashboard_v2:extras_request_detail", request_id=ur.id)

    try:
        with transaction.atomic():
            ur = UnifiedRequest.objects.select_for_update().get(id=ur.id)
            old_status = ur.status
            if old_status != new_status:
                if not is_valid_transition(
                    request_type=UnifiedRequestType.EXTRAS,
                    from_status=old_status,
                    to_status=new_status,
                ):
                    messages.warning(request, "انتقال الحالة غير مسموح في مسار الخدمات الإضافية.")
                    return redirect("dashboard_v2:extras_request_detail", request_id=ur.id)

                ur.status = new_status
                ur.closed_at = timezone.now() if new_status == UnifiedRequestStatus.CLOSED else None
                ur.save(update_fields=["status", "closed_at", "updated_at"])
                UnifiedRequestStatusLog.objects.create(
                    request=ur,
                    from_status=old_status or "",
                    to_status=new_status,
                    changed_by=request.user,
                    note=note[:200],
                )
                log_action(
                    actor=request.user,
                    request=request,
                    action=AuditAction.FIELD_CHANGED,
                    reference_type="unified_request",
                    reference_id=str(ur.id),
                    extra={
                        "field": "status",
                        "from_status": old_status,
                        "to_status": new_status,
                        "note": note[:200],
                    },
                )
        messages.success(request, "تم تحديث حالة الطلب.")
    except Exception:
        messages.error(request, "تعذر تحديث الحالة.")
    return redirect("dashboard_v2:extras_request_detail", request_id=ur.id)


@dashboard_v2_access_required(DashboardCode.EXTRAS, write=True)
@require_POST
def extra_purchase_activate_action(request, purchase_id: int):
    purchase = get_object_or_404(ExtraPurchase.objects.select_related("user", "invoice"), id=purchase_id)
    if not _can_access_extra_purchase(request.user, purchase):
        return HttpResponse("غير مصرح", status=403)

    policy = ExtrasManagePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="extra_purchase",
        reference_id=str(purchase.id),
        extra={"surface": "dashboard_v2.extra_purchase_activate_action", "action_name": "activate"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتفعيل هذه الخدمة الإضافية.")
        return redirect("dashboard_v2:extras_requests_list")

    try:
        activate_extra_after_payment(purchase=purchase)
        messages.success(request, "تم تفعيل الخدمة الإضافية.")
    except Exception as exc:
        messages.error(request, str(exc) or "تعذر تفعيل الخدمة الإضافية.")

    ur = _linked_extra_unified_request(purchase_id=purchase.id)
    if ur:
        return redirect("dashboard_v2:extras_request_detail", request_id=ur.id)
    return redirect("dashboard_v2:extras_requests_list")


@dashboard_v2_access_required(DashboardCode.EXTRAS, write=False)
def extras_clients_list_view(request):
    qs = (
        ExtrasPortalSubscription.objects.select_related("provider", "provider__user")
        .all()
        .order_by("-updated_at")
    )
    q = (request.GET.get("q") or "").strip()
    status_val = (request.GET.get("status") or "").strip()

    if q:
        qs = qs.filter(
            Q(provider__display_name__icontains=q)
            | Q(provider__user__phone__icontains=q)
            | Q(plan_title__icontains=q)
        )
    if status_val:
        qs = qs.filter(status=status_val)

    qs = _scope_provider_bound_queryset(qs, user=request.user)

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    query = request.GET.copy()
    query.pop("page", None)

    context = build_layout_context(
        request,
        title="عملاء الخدمات الإضافية",
        subtitle="اشتراكات البوابة ومقدمو الخدمة المرتبطون",
        active_code=DashboardCode.EXTRAS,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "الخدمات الإضافية", "url": "dashboard_v2:extras_requests_list"},
        ],
    )
    context.update(
        {
            "page_obj": page_obj,
            "query_string": query.urlencode(),
            "q": q,
            "status_val": status_val,
            "status_choices": ExtrasPortalSubscriptionStatus.choices,
            "table_headers": ["المزوّد", "الهاتف", "حالة الاشتراك", "الخطة", "بداية", "نهاية", "آخر تحديث"],
        }
    )
    return render(request, "dashboard_v2/extras/clients_list.html", context)


@dashboard_v2_access_required(DashboardCode.EXTRAS, write=False)
def extras_finance_list_view(request):
    qs = (
        ExtrasPortalFinanceSettings.objects.select_related("provider", "provider__user")
        .all()
        .order_by("-updated_at")
    )
    q = (request.GET.get("q") or "").strip()
    if q:
        qs = qs.filter(
            Q(provider__display_name__icontains=q)
            | Q(provider__user__phone__icontains=q)
            | Q(bank_name__icontains=q)
            | Q(account_name__icontains=q)
            | Q(iban__icontains=q)
        )

    qs = _scope_provider_bound_queryset(qs, user=request.user)

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    query = request.GET.copy()
    query.pop("page", None)

    context = build_layout_context(
        request,
        title="البيانات المالية",
        subtitle="حسابات IBAN وإعدادات التحصيل لمزوّدي الخدمات الإضافية",
        active_code=DashboardCode.EXTRAS,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "الخدمات الإضافية", "url": "dashboard_v2:extras_requests_list"},
        ],
    )
    context.update(
        {
            "page_obj": page_obj,
            "query_string": query.urlencode(),
            "q": q,
            "table_headers": ["المزوّد", "الهاتف", "اسم البنك", "اسم الحساب", "IBAN", "آخر تحديث"],
        }
    )
    return render(request, "dashboard_v2/extras/finance_list.html", context)


@dashboard_v2_access_required(DashboardCode.EXTRAS, write=False)
def extras_catalog_list_view(request):
    qs = ServiceCatalog.objects.all().order_by("sort_order", "sku")
    q = (request.GET.get("q") or "").strip()
    active_val = (request.GET.get("active") or "").strip().lower()

    if q:
        qs = qs.filter(Q(sku__icontains=q) | Q(title__icontains=q))
    if active_val in {"1", "true", "yes"}:
        qs = qs.filter(is_active=True)
    elif active_val in {"0", "false", "no"}:
        qs = qs.filter(is_active=False)

    paginator = Paginator(qs, 30)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    query = request.GET.copy()
    query.pop("page", None)

    can_manage = has_dashboard_access(request.user, DashboardCode.EXTRAS, write=True) and has_action_permission(
        request.user,
        "extras.manage",
    )
    context = build_layout_context(
        request,
        title="كتالوج الخدمات الإضافية",
        subtitle="إدارة العناصر الجاهزة للشراء من بوابة العميل",
        active_code=DashboardCode.EXTRAS,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "الخدمات الإضافية", "url": "dashboard_v2:extras_requests_list"},
        ],
    )
    context.update(
        {
            "page_obj": page_obj,
            "query_string": query.urlencode(),
            "q": q,
            "active_val": active_val,
            "can_manage": can_manage,
            "table_headers": ["SKU", "العنوان", "السعر", "العملة", "الترتيب", "الحالة", "إجراءات"],
        }
    )
    return render(request, "dashboard_v2/extras/catalog_list.html", context)


@dashboard_v2_access_required(DashboardCode.EXTRAS, write=True)
@require_POST
def extras_catalog_toggle_action(request, item_id: int):
    item = get_object_or_404(ServiceCatalog, id=item_id)
    policy = ExtrasManagePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="extras.service_catalog",
        reference_id=str(item.id),
        extra={"surface": "dashboard_v2.extras_catalog_toggle_action", "action_name": "toggle_active"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتعديل كتالوج الخدمات الإضافية.")
        return redirect("dashboard_v2:extras_catalog_list")

    item.is_active = not item.is_active
    item.save(update_fields=["is_active", "updated_at"])
    log_action(
        actor=request.user,
        request=request,
        action=AuditAction.FIELD_CHANGED,
        reference_type="extras.service_catalog",
        reference_id=str(item.id),
        extra={"field": "is_active", "new_value": item.is_active, "sku": item.sku},
    )
    messages.success(request, f"تم تحديث الحالة للخدمة: {item.sku}")
    return redirect("dashboard_v2:extras_catalog_list")
