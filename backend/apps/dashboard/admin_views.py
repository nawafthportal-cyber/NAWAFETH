"""
Dashboard views for gap features:
- Staff comment on support tickets
- Staff ticket creation
- Audit log browser
- User management (list/detail/toggle-active)
- Subscription plan CRUD
"""
from __future__ import annotations

import logging

from django.contrib import messages
from django.core.paginator import Paginator
from django.db.models import Q
from django.http import HttpRequest, HttpResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.utils import timezone
from django.views.decorators.http import require_POST

from apps.accounts.models import User, UserRole
from apps.audit.models import AuditLog, AuditAction
from apps.audit.services import log_action
from apps.support.models import (
    SupportComment,
    SupportTicket,
    SupportTicketStatus,
    SupportTicketType,
    SupportPriority,
    SupportTeam,
)
from apps.subscriptions.models import SubscriptionPlan, FeatureKey
from apps.subscriptions.bootstrap import infer_plan_tier
from apps.backoffice.models import UserAccessProfile
from .access import sync_dashboard_user_access

from .auth import dashboard_staff_required as staff_member_required
from .views import require_dashboard_access as dashboard_access_required, _want_csv, _csv_response, _dashboard_allowed

logger = logging.getLogger(__name__)


# ──────────────────────────────────────────────────────────────
# 1) Staff comment on support ticket
# ──────────────────────────────────────────────────────────────
@require_POST
@staff_member_required
@dashboard_access_required("support", write=True)
def support_ticket_add_comment(request: HttpRequest, ticket_id: int) -> HttpResponse:
    ticket = get_object_or_404(SupportTicket, pk=ticket_id)
    text = (request.POST.get("text") or "").strip()
    if not text:
        messages.error(request, "يرجى كتابة تعليق")
        return redirect("dashboard:support_ticket_detail", ticket_id=ticket.pk)

    is_internal = request.POST.get("is_internal") == "1"
    SupportComment.objects.create(
        ticket=ticket,
        text=text[:300],
        is_internal=is_internal,
        created_by=request.user,
    )
    messages.success(request, "تم إضافة التعليق")
    return redirect("dashboard:support_ticket_detail", ticket_id=ticket.pk)


# ──────────────────────────────────────────────────────────────
# 2) Staff ticket creation
# ──────────────────────────────────────────────────────────────
@staff_member_required
@dashboard_access_required("support", write=True)
def support_ticket_create(request: HttpRequest) -> HttpResponse:
    teams = SupportTeam.objects.filter(is_active=True)
    staff_users = User.objects.filter(is_staff=True, is_active=True).order_by("phone")
    type_choices = SupportTicketType.choices
    priority_choices = SupportPriority.choices

    if request.method == "POST":
        phone = (request.POST.get("requester_phone") or "").strip()
        ticket_type = (request.POST.get("ticket_type") or "").strip()
        priority = (request.POST.get("priority") or "normal").strip()
        description = (request.POST.get("description") or "").strip()
        team_id = request.POST.get("assigned_team") or None
        assigned_to_id = request.POST.get("assigned_to") or None

        requester = User.objects.filter(phone=phone).first() if phone else None
        if not requester:
            messages.error(request, "المستخدم غير موجود (رقم الجوال)")
            return render(request, "dashboard/support_ticket_create.html", {
                "teams": teams, "staff_users": staff_users,
                "type_choices": type_choices, "priority_choices": priority_choices,
            })

        if not description:
            messages.error(request, "وصف الطلب مطلوب")
            return render(request, "dashboard/support_ticket_create.html", {
                "teams": teams, "staff_users": staff_users,
                "type_choices": type_choices, "priority_choices": priority_choices,
            })

        ticket = SupportTicket.objects.create(
            requester=requester,
            ticket_type=ticket_type or SupportTicketType.TECH,
            priority=priority,
            description=description[:300],
            assigned_team_id=int(team_id) if team_id else None,
            assigned_to_id=int(assigned_to_id) if assigned_to_id else None,
            assigned_at=timezone.now() if assigned_to_id else None,
            last_action_by=request.user,
        )

        try:
            log_action(
                actor=request.user,
                action=AuditAction.CONTENT_BLOCK_UPDATED,  # reuse closest action
                reference_type="support_ticket",
                reference_id=str(ticket.pk),
                request=request,
                extra={"note": "إنشاء تذكرة من الداشبورد"},
            )
        except Exception:
            pass

        messages.success(request, f"تم إنشاء التذكرة {ticket.code}")
        return redirect("dashboard:support_ticket_detail", ticket_id=ticket.pk)

    return render(request, "dashboard/support_ticket_create.html", {
        "teams": teams,
        "staff_users": staff_users,
        "type_choices": type_choices,
        "priority_choices": priority_choices,
    })


# ──────────────────────────────────────────────────────────────
# 3) Audit log browser
# ──────────────────────────────────────────────────────────────
@staff_member_required
@dashboard_access_required("access")
def audit_log_list(request: HttpRequest) -> HttpResponse:
    qs = AuditLog.objects.select_related("actor").order_by("-id")

    q = (request.GET.get("q") or "").strip()
    action_filter = (request.GET.get("action") or "").strip()

    if q:
        qs = qs.filter(
            Q(actor__phone__icontains=q)
            | Q(reference_type__icontains=q)
            | Q(reference_id__icontains=q)
        )
    if action_filter:
        qs = qs.filter(action=action_filter)

    if _want_csv(request):
        rows = []
        for log in qs[:5000]:
            rows.append([
                log.id,
                log.actor.phone if log.actor else "",
                log.get_action_display(),
                log.reference_type,
                log.reference_id,
                log.ip_address or "",
                log.created_at.strftime("%Y-%m-%d %H:%M"),
            ])
        return _csv_response("audit_logs.csv", [
            "ID", "المستخدم", "الإجراء", "نوع المرجع", "رقم المرجع", "IP", "التاريخ"
        ], rows)

    paginator = Paginator(qs, 30)
    page_obj = paginator.get_page(request.GET.get("page") or "1")

    return render(request, "dashboard/audit_log_list.html", {
        "page_obj": page_obj,
        "q": q,
        "action_filter": action_filter,
        "action_choices": AuditAction.choices,
    })


# ──────────────────────────────────────────────────────────────
# 4) User management
# ──────────────────────────────────────────────────────────────
@staff_member_required
@dashboard_access_required("access")
def users_list(request: HttpRequest) -> HttpResponse:
    qs = User.objects.all().order_by("-id")

    q = (request.GET.get("q") or "").strip()
    role_filter = (request.GET.get("role") or "").strip()
    active_filter = (request.GET.get("active") or "").strip()

    if q:
        qs = qs.filter(
            Q(phone__icontains=q)
            | Q(username__icontains=q)
            | Q(email__icontains=q)
            | Q(first_name__icontains=q)
            | Q(last_name__icontains=q)
        )
    if role_filter:
        qs = qs.filter(role_state=role_filter)
    if active_filter == "1":
        qs = qs.filter(is_active=True)
    elif active_filter == "0":
        qs = qs.filter(is_active=False)

    if _want_csv(request):
        rows = []
        for u in qs[:5000]:
            rows.append([
                u.id,
                u.phone or "",
                u.username or "",
                u.first_name or "",
                u.last_name or "",
                u.email or "",
                u.role_state,
                "نعم" if u.is_active else "لا",
                "نعم" if u.is_staff else "لا",
                u.created_at.strftime("%Y-%m-%d") if u.created_at else "",
            ])
        return _csv_response("users.csv", [
            "ID", "الجوال", "اسم المستخدم", "الاسم الأول", "الاسم الأخير",
            "البريد", "الدور", "نشط", "موظف", "تاريخ الإنشاء"
        ], rows)

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")

    return render(request, "dashboard/users_list.html", {
        "page_obj": page_obj,
        "q": q,
        "role_filter": role_filter,
        "active_filter": active_filter,
        "role_choices": UserRole.choices,
    })


@staff_member_required
@dashboard_access_required("access")
def user_detail(request: HttpRequest, user_id: int) -> HttpResponse:
    target_user = get_object_or_404(User, pk=user_id)
    access_profile = UserAccessProfile.objects.filter(user=target_user).first()

    # Recent audit logs for this user
    recent_logs = AuditLog.objects.filter(actor=target_user).order_by("-id")[:20]

    return render(request, "dashboard/user_detail.html", {
        "target_user": target_user,
        "access_profile": access_profile,
        "recent_logs": recent_logs,
        "can_write": _dashboard_allowed(request.user, "access", write=True),
    })


@require_POST
@staff_member_required
@dashboard_access_required("access", write=True)
def user_toggle_active(request: HttpRequest, user_id: int) -> HttpResponse:
    target_user = get_object_or_404(User, pk=user_id)

    # Prevent deactivating yourself or superusers
    if target_user.pk == request.user.pk:
        messages.error(request, "لا يمكنك تعطيل حسابك")
        return redirect("dashboard:user_detail", user_id=target_user.pk)
    if target_user.is_superuser:
        messages.error(request, "لا يمكن تعطيل حساب مدير عام")
        return redirect("dashboard:user_detail", user_id=target_user.pk)

    target_user.is_active = not target_user.is_active
    target_user.save(update_fields=["is_active"])

    action_label = "تفعيل" if target_user.is_active else "تعطيل"
    messages.success(request, f"تم {action_label} الحساب بنجاح")

    try:
        log_action(
            actor=request.user,
            action=AuditAction.ACCESS_PROFILE_UPDATED,
            reference_type="user",
            reference_id=str(target_user.pk),
            request=request,
            extra={"is_active": target_user.is_active},
        )
    except Exception:
        pass

    return redirect("dashboard:user_detail", user_id=target_user.pk)


@require_POST
@staff_member_required
@dashboard_access_required("access", write=True)
def user_update_role(request: HttpRequest, user_id: int) -> HttpResponse:
    target_user = get_object_or_404(User, pk=user_id)
    new_role = (request.POST.get("role_state") or "").strip()

    if new_role not in dict(UserRole.choices):
        messages.error(request, "الدور غير صالح")
        return redirect("dashboard:user_detail", user_id=target_user.pk)

    old_role = target_user.role_state
    old_is_staff = target_user.is_staff
    access_profile = UserAccessProfile.objects.filter(user=target_user).first()
    target_user.role_state = new_role
    target_user.is_staff = new_role == UserRole.STAFF

    if access_profile and new_role != UserRole.STAFF and not access_profile.is_revoked():
        access_profile.revoked_at = timezone.now()
        access_profile.save(update_fields=["revoked_at", "updated_at"])
        sync_dashboard_user_access(target_user, access_profile=access_profile)
    elif access_profile and new_role == UserRole.STAFF:
        if access_profile.revoked_at is not None:
            access_profile.revoked_at = None
            access_profile.save(update_fields=["revoked_at", "updated_at"])
        sync_dashboard_user_access(target_user, access_profile=access_profile, force_staff_role_state=True)

    target_user.save(update_fields=["role_state", "is_staff"])
    if new_role == UserRole.STAFF and target_user.is_staff:
        messages.success(request, "تم تحويل المستخدم إلى موظف وتفعيل صلاحية التشغيل المرتبطة به.")
    elif new_role == UserRole.STAFF and not access_profile:
        messages.success(request, "تم تحويل المستخدم إلى موظف. يلزم الآن منحه لوحات تشغيل من صفحة صلاحيات التشغيل.")
    elif new_role == UserRole.STAFF:
        messages.success(request, "تم تحويل المستخدم إلى موظف، لكن لا توجد لوحات تشغيل فعالة مرتبطة به بعد.")
    else:
        messages.success(request, f"تم تغيير الدور من {old_role} إلى {new_role} وسحب صلاحية التشغيل.")

    try:
        log_action(
            actor=request.user,
            action=AuditAction.ACCESS_PROFILE_UPDATED,
            reference_type="user",
            reference_id=str(target_user.pk),
            request=request,
            extra={"old_role": old_role, "new_role": new_role, "old_is_staff": old_is_staff, "new_is_staff": target_user.is_staff},
        )
    except Exception:
        pass

    return redirect("dashboard:user_detail", user_id=target_user.pk)


# ──────────────────────────────────────────────────────────────
# 5) Subscription plan management
# ──────────────────────────────────────────────────────────────
@staff_member_required
@dashboard_access_required("subs")
def plans_list(request: HttpRequest) -> HttpResponse:
    plans = SubscriptionPlan.objects.all().order_by("price", "id")
    return render(request, "dashboard/plans_list.html", {"plans": plans})


@staff_member_required
@dashboard_access_required("subs", write=True)
def plan_form(request: HttpRequest, plan_id: int = None) -> HttpResponse:
    plan = get_object_or_404(SubscriptionPlan, pk=plan_id) if plan_id else None

    if request.method == "POST":
        code = (request.POST.get("code") or "").strip()
        title = (request.POST.get("title") or "").strip()
        period = (request.POST.get("period") or "month").strip()
        price = (request.POST.get("price") or "0").strip()
        is_active = request.POST.get("is_active") == "1"
        # sort_order is implicit via price ordering

        # Parse features JSON
        features = {}
        for key in FeatureKey.values:
            val = (request.POST.get(f"feature_{key}") or "").strip()
            if val:
                # Try int first, then keep as string
                try:
                    features[key] = int(val)
                except ValueError:
                    features[key] = val

        if not code or not title:
            messages.error(request, "الكود والعنوان مطلوبان")
        else:
            inferred_tier = infer_plan_tier(code=code, title=title, features=features)
            if plan:
                plan.code = code
                plan.tier = inferred_tier
                plan.title = title
                plan.period = period
                plan.price = price
                plan.is_active = is_active
                plan.features = features
                plan.save()
                messages.success(request, "تم تحديث الخطة")
            else:
                plan = SubscriptionPlan.objects.create(
                    code=code, tier=inferred_tier, title=title, period=period,
                    price=price, is_active=is_active,
                    features=features,
                )
                messages.success(request, "تم إنشاء الخطة")
            return redirect("dashboard:plans_list")

    return render(request, "dashboard/plan_form.html", {
        "plan": plan,
        "feature_keys": FeatureKey.choices,
    })


@require_POST
@staff_member_required
@dashboard_access_required("subs", write=True)
def plan_toggle_active(request: HttpRequest, plan_id: int) -> HttpResponse:
    plan = get_object_or_404(SubscriptionPlan, pk=plan_id)
    plan.is_active = not plan.is_active
    plan.save(update_fields=["is_active"])
    action_label = "تفعيل" if plan.is_active else "تعطيل"
    messages.success(request, f"تم {action_label} الخطة")
    return redirect("dashboard:plans_list")
