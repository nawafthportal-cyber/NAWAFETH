from __future__ import annotations

from django.contrib import messages
from django.core.paginator import Paginator
from django.db import transaction
from django.db.models import Count, Q
from django.http import HttpResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.urls import reverse
from django.utils import timezone
from django.views.decorators.http import require_POST

from apps.audit.models import AuditAction
from apps.audit.services import log_action
from apps.backoffice.models import AccessLevel
from apps.backoffice.policies import SubscriptionManagePolicy
from apps.billing.models import PaymentAttempt
from apps.dashboard.access import (
    active_access_profile_for_user,
    can_access_object,
    dashboard_assignee_user,
    dashboard_assignment_users,
    has_action_permission,
    has_dashboard_access,
)
from apps.dashboard.contracts import DashboardCode
from apps.dashboard.security import safe_redirect_url
from apps.subscriptions.models import Subscription, SubscriptionPlan, SubscriptionStatus
from apps.subscriptions.services import (
    activate_subscription_after_payment,
    refresh_subscription_status,
)
from apps.unified_requests.models import (
    UnifiedRequest,
    UnifiedRequestAssignmentLog,
    UnifiedRequestMetadata,
    UnifiedRequestStatus,
    UnifiedRequestStatusLog,
    UnifiedRequestType,
)
from apps.unified_requests.workflows import (
    allowed_statuses_for_request_type,
    canonical_status_for_workflow,
    is_valid_transition,
)

from ..view_utils import build_layout_context, dashboard_v2_access_required


def _scope_subscriptions_queryset(qs, *, user):
    if getattr(user, "is_superuser", False):
        return qs
    access_profile = active_access_profile_for_user(user)
    if not access_profile:
        return qs.none()
    if access_profile.level in (AccessLevel.ADMIN, AccessLevel.POWER, AccessLevel.QA):
        return qs
    if access_profile.level in (AccessLevel.USER, AccessLevel.CLIENT):
        return qs.filter(user=user)
    return qs.none()


def _can_access_subscription(user, sub: Subscription) -> bool:
    return can_access_object(user, sub, owner_field="user", allow_unassigned_for_user_level=False)


def _subscription_unified_request(sub: Subscription):
    return UnifiedRequest.objects.select_related("assigned_user").filter(
        source_app="subscriptions",
        source_model="Subscription",
        source_object_id=str(sub.id),
    ).first()


def _metadata_notes(ur: UnifiedRequest | None, key: str) -> list[dict]:
    if not ur:
        return []
    md = getattr(ur, "metadata_record", None)
    payload = getattr(md, "payload", {}) or {}
    raw_notes = payload.get(key) if isinstance(payload, dict) else None
    if not isinstance(raw_notes, list):
        return []
    rows = [row for row in raw_notes if isinstance(row, dict)]
    rows.sort(key=lambda row: str(row.get("created_at") or ""), reverse=True)
    return rows


def _subscription_alerts(sub: Subscription) -> list[dict[str, str]]:
    now = timezone.now()
    alerts: list[dict[str, str]] = []
    if sub.status == SubscriptionStatus.PENDING_PAYMENT:
        alerts.append({"level": "warning", "text": "الاشتراك بانتظار سداد الفاتورة."})
    elif sub.status == SubscriptionStatus.ACTIVE and sub.end_at:
        days_left = (sub.end_at - now).days
        if sub.end_at <= now:
            alerts.append({"level": "danger", "text": "انتهت مدة الاشتراك الفعالة."})
        elif days_left <= 7:
            alerts.append({"level": "warning", "text": f"الاشتراك سينتهي خلال {max(days_left, 0)} يوم."})
        else:
            alerts.append({"level": "success", "text": "الاشتراك نشط بدون تنبيهات حرجة."})
    elif sub.status == SubscriptionStatus.GRACE:
        alerts.append({"level": "warning", "text": "الاشتراك في فترة السماح."})
    elif sub.status == SubscriptionStatus.EXPIRED:
        alerts.append({"level": "danger", "text": "الاشتراك منتهي."})
    elif sub.status == SubscriptionStatus.CANCELLED:
        alerts.append({"level": "danger", "text": "الاشتراك ملغي."})
    return alerts


@dashboard_v2_access_required(DashboardCode.SUBS, write=False)
def subscriptions_list_view(request):
    qs = Subscription.objects.select_related("user", "plan", "invoice").order_by("-id")
    q = (request.GET.get("q") or "").strip()
    status_val = (request.GET.get("status") or "").strip()
    if q:
        qs = qs.filter(Q(user__phone__icontains=q) | Q(plan__title__icontains=q) | Q(plan__code__icontains=q))
    if status_val:
        qs = qs.filter(status=status_val)

    qs = _scope_subscriptions_queryset(qs, user=request.user)
    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    query = request.GET.copy()
    query.pop("page", None)

    summary = qs.aggregate(
        total=Count("id"),
        active=Count("id", filter=Q(status=SubscriptionStatus.ACTIVE)),
        pending=Count("id", filter=Q(status=SubscriptionStatus.PENDING_PAYMENT)),
        expired=Count("id", filter=Q(status=SubscriptionStatus.EXPIRED)),
    )

    context = build_layout_context(
        request,
        title="الاشتراكات",
        subtitle="طلبات/حسابات الاشتراك مع الربط المالي والتشغيلي",
        active_code=DashboardCode.SUBS,
        breadcrumbs=[{"label": "لوحة التحكم", "url": "dashboard_v2:home"}],
    )
    context.update(
        {
            "page_obj": page_obj,
            "query_string": query.urlencode(),
            "q": q,
            "status_val": status_val,
            "status_choices": SubscriptionStatus.choices,
            "summary": {
                "total": summary.get("total") or 0,
                "active": summary.get("active") or 0,
                "pending": summary.get("pending") or 0,
                "expired": summary.get("expired") or 0,
            },
            "can_manage": has_dashboard_access(request.user, DashboardCode.SUBS, write=True)
            and has_action_permission(request.user, "subscriptions.manage"),
            "table_headers": ["#", "المستخدم", "الخطة", "الحالة", "الفترة", "الفاتورة", "إجراءات"],
        }
    )
    return render(request, "dashboard_v2/subscriptions/subscriptions_list.html", context)


@dashboard_v2_access_required(DashboardCode.SUBS, write=False)
def subscriptions_plans_list_view(request):
    q = (request.GET.get("q") or "").strip()
    active_val = (request.GET.get("active") or "").strip().lower()

    plans_qs = SubscriptionPlan.objects.order_by("price", "id")
    if q:
        plans_qs = plans_qs.filter(Q(code__icontains=q) | Q(title__icontains=q))
    if active_val in {"1", "true", "yes"}:
        plans_qs = plans_qs.filter(is_active=True)
    elif active_val in {"0", "false", "no"}:
        plans_qs = plans_qs.filter(is_active=False)

    paginator = Paginator(plans_qs, 30)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    query = request.GET.copy()
    query.pop("page", None)
    context = build_layout_context(
        request,
        title="خطط الاشتراك",
        subtitle="عرض الباقات والميزات والرسوم المرجعية",
        active_code=DashboardCode.SUBS,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "الاشتراكات", "url": "dashboard_v2:subscriptions_list"},
        ],
    )
    context.update(
        {
            "page_obj": page_obj,
            "query_string": query.urlencode(),
            "q": q,
            "active_val": active_val,
            "table_headers": ["الخطة", "المدة", "السعر", "الميزات", "رسوم التوثيق", "الحالة"],
        }
    )
    return render(request, "dashboard_v2/subscriptions/plans_list.html", context)


@dashboard_v2_access_required(DashboardCode.SUBS, write=False)
def subscription_request_detail_view(request, subscription_id: int):
    sub = get_object_or_404(Subscription.objects.select_related("user", "plan", "invoice"), id=subscription_id)
    if not _can_access_subscription(request.user, sub):
        return HttpResponse("غير مصرح", status=403)

    ur = _subscription_unified_request(sub)
    ops_notes = _metadata_notes(ur, "ops_notes")
    assignees = dashboard_assignment_users(DashboardCode.SUBS, write=True, limit=120)
    invoice_lines = list(sub.invoice.lines.all().order_by("sort_order", "id")) if sub.invoice_id and hasattr(sub.invoice, "lines") else []

    can_manage = has_dashboard_access(request.user, DashboardCode.SUBS, write=True) and has_action_permission(
        request.user,
        "subscriptions.manage",
    )
    status_choices = []
    if ur:
        allowed = set(allowed_statuses_for_request_type(UnifiedRequestType.SUBSCRIPTION))
        status_labels = dict(UnifiedRequestStatus.choices)
        status_choices = [(status, status_labels.get(status, status)) for status in allowed]

    context = build_layout_context(
        request,
        title=f"طلب اشتراك #{sub.id}",
        subtitle="تفاصيل الطلب التشغيلي SD + الحالة والإسناد",
        active_code=DashboardCode.SUBS,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "الاشتراكات", "url": "dashboard_v2:subscriptions_list"},
        ],
    )
    context.update(
        {
            "sub": sub,
            "ur": ur,
            "ops_notes": ops_notes[:40],
            "assignees": assignees,
            "invoice_lines": invoice_lines,
            "status_choices": status_choices,
            "can_manage": can_manage,
        }
    )
    return render(request, "dashboard_v2/subscriptions/request_detail.html", context)


@dashboard_v2_access_required(DashboardCode.SUBS, write=False)
def subscription_account_detail_view(request, subscription_id: int):
    sub = get_object_or_404(Subscription.objects.select_related("user", "plan", "invoice"), id=subscription_id)
    if not _can_access_subscription(request.user, sub):
        return HttpResponse("غير مصرح", status=403)

    ur = _subscription_unified_request(sub)
    account_ops_notes = _metadata_notes(ur, "account_ops_notes")
    recent_for_user = list(
        Subscription.objects.select_related("plan", "invoice")
        .filter(user=sub.user)
        .exclude(id=sub.id)
        .order_by("-id")[:10]
    )
    payment_attempts = list(PaymentAttempt.objects.filter(invoice_id=sub.invoice_id).order_by("-created_at")[:10]) if sub.invoice_id else []

    timeline: list[dict[str, object]] = [{"at": sub.created_at, "title": "إنشاء سجل الاشتراك", "detail": f"الباقة {sub.plan.code}"}]
    if sub.invoice_id:
        timeline.append(
            {
                "at": sub.invoice.created_at,
                "title": "إنشاء الفاتورة",
                "detail": f"{sub.invoice.code or sub.invoice_id} - {sub.invoice.get_status_display()}",
            }
        )
        if sub.invoice.paid_at:
            timeline.append(
                {
                    "at": sub.invoice.paid_at,
                    "title": "سداد الفاتورة",
                    "detail": f"{sub.invoice.total} {sub.invoice.currency}",
                }
            )
    if ur:
        for log in ur.status_logs.select_related("changed_by").all()[:12]:
            who = getattr(getattr(log, "changed_by", None), "phone", "") or "النظام"
            timeline.append(
                {
                    "at": log.created_at,
                    "title": "تحديث حالة SD",
                    "detail": f"{log.from_status or '—'} -> {log.to_status} بواسطة {who}",
                }
            )
    timeline = [row for row in timeline if row.get("at")]
    timeline.sort(key=lambda row: row["at"], reverse=True)

    context = build_layout_context(
        request,
        title=f"حساب الاشتراك #{sub.id}",
        subtitle="عرض الحالة التشغيلية والمالية للحساب المشترك",
        active_code=DashboardCode.SUBS,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "الاشتراكات", "url": "dashboard_v2:subscriptions_list"},
        ],
    )
    context.update(
        {
            "sub": sub,
            "ur": ur,
            "account_ops_notes": account_ops_notes[:40],
            "recent_for_user": recent_for_user,
            "payment_attempts": payment_attempts,
            "alerts": _subscription_alerts(sub),
            "timeline": timeline[:20],
            "can_manage": has_dashboard_access(request.user, DashboardCode.SUBS, write=True)
            and has_action_permission(request.user, "subscriptions.manage"),
        }
    )
    return render(request, "dashboard_v2/subscriptions/account_detail.html", context)


@dashboard_v2_access_required(DashboardCode.SUBS, write=False)
def subscription_payment_detail_view(request, subscription_id: int):
    sub = get_object_or_404(Subscription.objects.select_related("user", "plan", "invoice"), id=subscription_id)
    if not _can_access_subscription(request.user, sub):
        return HttpResponse("غير مصرح", status=403)

    invoice = sub.invoice
    attempts = list(PaymentAttempt.objects.filter(invoice_id=sub.invoice_id).order_by("-created_at")[:20]) if invoice else []
    line_items = list(invoice.lines.all().order_by("sort_order", "id")) if invoice and hasattr(invoice, "lines") else []

    context = build_layout_context(
        request,
        title=f"الدفع - اشتراك #{sub.id}",
        subtitle="تفاصيل الفاتورة ومحاولات الدفع",
        active_code=DashboardCode.SUBS,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "الاشتراكات", "url": "dashboard_v2:subscriptions_list"},
        ],
    )
    context.update({"sub": sub, "invoice": invoice, "attempts": attempts, "line_items": line_items})
    return render(request, "dashboard_v2/subscriptions/payment_detail.html", context)


@dashboard_v2_access_required(DashboardCode.SUBS, write=True)
@require_POST
def subscription_refresh_action(request, subscription_id: int):
    sub = get_object_or_404(Subscription, id=subscription_id)
    if not _can_access_subscription(request.user, sub):
        return HttpResponse("غير مصرح", status=403)
    if not has_action_permission(request.user, "subscriptions.manage"):
        messages.error(request, "ليس لديك صلاحية تحديث الاشتراكات.")
        return redirect("dashboard_v2:subscription_request_detail", subscription_id=sub.id)

    try:
        refresh_subscription_status(sub=sub)
        messages.success(request, "تم تحديث حالة الاشتراك.")
    except Exception as exc:
        messages.error(request, str(exc) or "تعذر تحديث الاشتراك.")
    fallback = reverse("dashboard_v2:subscription_request_detail", args=[sub.id])
    return redirect(safe_redirect_url(request, fallback=fallback))


@dashboard_v2_access_required(DashboardCode.SUBS, write=True)
@require_POST
def subscription_activate_action(request, subscription_id: int):
    sub = get_object_or_404(Subscription, id=subscription_id)
    if not _can_access_subscription(request.user, sub):
        return HttpResponse("غير مصرح", status=403)

    policy = SubscriptionManagePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="subscription",
        reference_id=str(sub.id),
        extra={"surface": "dashboard_v2.subscription_activate_action", "action_name": "activate"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتفعيل هذا الاشتراك.")
        return redirect("dashboard_v2:subscription_request_detail", subscription_id=sub.id)

    try:
        activate_subscription_after_payment(sub=sub)
        messages.success(request, "تم تفعيل الاشتراك.")
    except Exception as exc:
        messages.error(request, str(exc) or "تعذر تفعيل الاشتراك.")
    fallback = reverse("dashboard_v2:subscription_request_detail", args=[sub.id])
    return redirect(safe_redirect_url(request, fallback=fallback))


@dashboard_v2_access_required(DashboardCode.SUBS, write=True)
@require_POST
def subscription_request_add_note_action(request, subscription_id: int):
    sub = get_object_or_404(Subscription, id=subscription_id)
    if not _can_access_subscription(request.user, sub):
        return HttpResponse("غير مصرح", status=403)
    if not has_action_permission(request.user, "subscriptions.manage"):
        messages.error(request, "ليس لديك صلاحية إضافة ملاحظات تشغيلية.")
        return redirect("dashboard_v2:subscription_request_detail", subscription_id=sub.id)

    note = (request.POST.get("note") or "").strip()
    if not note:
        messages.warning(request, "نص الملاحظة مطلوب.")
        return redirect("dashboard_v2:subscription_request_detail", subscription_id=sub.id)
    if len(note) > 300:
        messages.warning(request, "الحد الأقصى للملاحظة 300 حرف.")
        return redirect("dashboard_v2:subscription_request_detail", subscription_id=sub.id)

    ur = _subscription_unified_request(sub)
    if not ur:
        messages.error(request, "لا يوجد طلب موحد مرتبط بطلب الاشتراك.")
        return redirect("dashboard_v2:subscription_request_detail", subscription_id=sub.id)

    md, _ = UnifiedRequestMetadata.objects.get_or_create(request=ur, defaults={"payload": {}, "updated_by": request.user})
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

    log_action(
        actor=request.user,
        request=request,
        action=AuditAction.SUBSCRIPTION_REQUEST_NOTE_ADDED,
        reference_type="subscription_request.unified",
        reference_id=str(ur.id),
        extra={"subscription_id": sub.id, "unified_request_id": ur.id, "note_length": len(note)},
    )
    messages.success(request, "تم حفظ الملاحظة التشغيلية.")
    return redirect("dashboard_v2:subscription_request_detail", subscription_id=sub.id)


@dashboard_v2_access_required(DashboardCode.SUBS, write=True)
@require_POST
def subscription_request_set_status_action(request, subscription_id: int):
    sub = get_object_or_404(Subscription, id=subscription_id)
    if not _can_access_subscription(request.user, sub):
        return HttpResponse("غير مصرح", status=403)

    policy = SubscriptionManagePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="subscription",
        reference_id=str(sub.id),
        extra={"surface": "dashboard_v2.subscription_request_set_status_action", "action_name": "set_status"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتحديث حالة طلب الاشتراك.")
        return redirect("dashboard_v2:subscription_request_detail", subscription_id=sub.id)

    ur = _subscription_unified_request(sub)
    if not ur:
        messages.error(request, "لا يوجد طلب موحد مرتبط بطلب الاشتراك.")
        return redirect("dashboard_v2:subscription_request_detail", subscription_id=sub.id)

    status_raw = (request.POST.get("status") or "").strip()
    note = (request.POST.get("note") or "").strip()
    new_status = canonical_status_for_workflow(request_type=UnifiedRequestType.SUBSCRIPTION, status=status_raw)
    allowed = set(allowed_statuses_for_request_type(UnifiedRequestType.SUBSCRIPTION))
    if new_status not in allowed:
        messages.warning(request, "حالة طلب الاشتراك غير صالحة.")
        return redirect("dashboard_v2:subscription_request_detail", subscription_id=sub.id)

    old_status = ur.status
    if old_status == new_status:
        messages.info(request, "الحالة الحالية مطابقة للحالة المطلوبة.")
        return redirect("dashboard_v2:subscription_request_detail", subscription_id=sub.id)
    if not is_valid_transition(
        request_type=UnifiedRequestType.SUBSCRIPTION,
        from_status=old_status,
        to_status=new_status,
    ):
        messages.warning(request, "انتقال الحالة غير مسموح في مسار الاشتراكات.")
        return redirect("dashboard_v2:subscription_request_detail", subscription_id=sub.id)

    ur.status = new_status
    if new_status == UnifiedRequestStatus.CLOSED:
        ur.closed_at = ur.closed_at or timezone.now()
    else:
        ur.closed_at = None
    ur.save(update_fields=["status", "closed_at", "updated_at"])
    UnifiedRequestStatusLog.objects.create(
        request=ur,
        from_status=old_status or "",
        to_status=new_status,
        changed_by=request.user,
        note=(note[:200] if note else "dashboard_v2 subscriptions status"),
    )

    log_action(
        actor=request.user,
        request=request,
        action=AuditAction.SUBSCRIPTION_REQUEST_STATUS_CHANGED,
        reference_type="subscription_request.unified",
        reference_id=str(ur.id),
        extra={
            "subscription_id": sub.id,
            "unified_request_id": ur.id,
            "from_status": old_status,
            "to_status": new_status,
            "note": note[:200],
        },
    )
    messages.success(request, "تم تحديث حالة طلب الاشتراك.")
    return redirect("dashboard_v2:subscription_request_detail", subscription_id=sub.id)


@dashboard_v2_access_required(DashboardCode.SUBS, write=True)
@require_POST
def subscription_request_assign_action(request, subscription_id: int):
    sub = get_object_or_404(Subscription, id=subscription_id)
    if not _can_access_subscription(request.user, sub):
        return HttpResponse("غير مصرح", status=403)

    policy = SubscriptionManagePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="subscription",
        reference_id=str(sub.id),
        extra={"surface": "dashboard_v2.subscription_request_assign_action", "action_name": "assign"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بإسناد طلب الاشتراك.")
        return redirect("dashboard_v2:subscription_request_detail", subscription_id=sub.id)

    ur = _subscription_unified_request(sub)
    if not ur:
        messages.error(request, "لا يوجد طلب موحد مرتبط بطلب الاشتراك.")
        return redirect("dashboard_v2:subscription_request_detail", subscription_id=sub.id)

    assigned_to_raw = request.POST.get("assigned_to") or None
    note = (request.POST.get("note") or "").strip()
    try:
        assigned_to = int(assigned_to_raw) if assigned_to_raw else None
    except Exception:
        assigned_to = None

    if not can_access_object(request.user, ur, assigned_field="assigned_user", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)

    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == AccessLevel.USER and assigned_to not in (None, request.user.id):
        return HttpResponse("غير مصرح", status=403)
    if assigned_to is not None and dashboard_assignee_user(assigned_to, DashboardCode.SUBS, write=True) is None:
        messages.error(request, "المكلّف غير صحيح.")
        return redirect("dashboard_v2:subscription_request_detail", subscription_id=sub.id)

    with transaction.atomic():
        ur = UnifiedRequest.objects.select_for_update().get(id=ur.id)
        old_user_id = ur.assigned_user_id
        old_team = ur.assigned_team_code or ""
        ur.assigned_team_code = DashboardCode.SUBS
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

    log_action(
        actor=request.user,
        request=request,
        action=AuditAction.SUBSCRIPTION_REQUEST_ASSIGNED,
        reference_type="subscription_request.unified",
        reference_id=str(ur.id),
        extra={
            "subscription_id": sub.id,
            "unified_request_id": ur.id,
            "from_user_id": old_user_id,
            "to_user_id": ur.assigned_user_id,
            "note": note[:200],
        },
    )
    messages.success(request, "تم تحديث إسناد طلب الاشتراك.")
    return redirect("dashboard_v2:subscription_request_detail", subscription_id=sub.id)
