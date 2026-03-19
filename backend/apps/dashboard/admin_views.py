"""
Dashboard admin_control views — consolidated panel:
- Access profiles CRUD
- User management (list/detail/toggle-active/update-role)
- Audit log browser
- Subscription plan CRUD
- Staff comment / ticket creation (support helpers)
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
from apps.backoffice.models import AccessLevel, Dashboard, UserAccessProfile
from .access import (
    active_dashboard_choices,
    dashboard_assignee_user,
    dashboard_assignment_users,
    has_action_permission,
    can_access_dashboard,
    sync_dashboard_user_access,
)

from .auth import dashboard_staff_required as staff_member_required
from .views import (
    require_dashboard_access as dashboard_access_required,
    _csv_response,
    _dashboard_allowed,
    _dashboard_tile_meta,
    _is_active_admin_profile,
    _active_admin_profiles_count,
    _limited_export_queryset,
    _parse_datetime_local,
    _tabular_export_limit,
    _want_csv,
)
from .security import apply_user_level_filter

logger = logging.getLogger(__name__)


# ──────────────────────────────────────────────────────────────
# 0) Admin Control — Landing Page
# ──────────────────────────────────────────────────────────────
@staff_member_required
@dashboard_access_required("access")
def admin_control_home(request: HttpRequest) -> HttpResponse:
    """Admin control landing page with quick stats and navigation."""
    total_users = User.objects.count()
    active_users = User.objects.filter(is_active=True).count()
    staff_users_count = User.objects.filter(is_staff=True).count()

    active_profiles = UserAccessProfile.objects.filter(revoked_at__isnull=True).count()
    total_profiles = UserAccessProfile.objects.count()
    dashboards_count = Dashboard.objects.filter(is_active=True).count()

    recent_audit = (
        AuditLog.objects.select_related("actor")
        .order_by("-id")[:8]
    )

    return render(request, "dashboard/admin_control_home.html", {
        "total_users": total_users,
        "active_users": active_users,
        "staff_users_count": staff_users_count,
        "active_profiles": active_profiles,
        "total_profiles": total_profiles,
        "dashboards_count": dashboards_count,
        "recent_audit": recent_audit,
    })


# ──────────────────────────────────────────────────────────────
# 1) Staff comment on support ticket
# ──────────────────────────────────────────────────────────────
@require_POST
@staff_member_required
@dashboard_access_required("support", write=True)
def support_ticket_add_comment(request: HttpRequest, ticket_id: int) -> HttpResponse:
    ticket = get_object_or_404(SupportTicket, pk=ticket_id)

    # Object-level check: user-level staff can only comment on their assigned tickets
    from apps.backoffice.models import AccessLevel
    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == AccessLevel.USER:
        if ticket.assigned_to_id is not None and ticket.assigned_to_id != request.user.id:
            messages.error(request, "غير مصرح لك بالتعليق على هذه التذكرة")
            return redirect("dashboard:support_ticket_detail", ticket_id=ticket.pk)

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
    staff_users = sorted(
        dashboard_assignment_users("support", write=True, limit=150),
        key=lambda user: ((user.phone or ""), int(getattr(user, "id", 0) or 0)),
    )
    type_choices = SupportTicketType.choices
    priority_choices = SupportPriority.choices

    if request.method == "POST":
        phone = (request.POST.get("requester_phone") or "").strip()
        ticket_type = (request.POST.get("ticket_type") or "").strip()
        priority = (request.POST.get("priority") or "normal").strip()
        description = (request.POST.get("description") or "").strip()
        team_id = request.POST.get("assigned_team") or None
        assigned_to_id = request.POST.get("assigned_to") or None
        assigned_user = None

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

        if assigned_to_id not in (None, ""):
            try:
                assigned_to_id = int(assigned_to_id)
            except Exception:
                assigned_to_id = None
            assigned_user = dashboard_assignee_user(assigned_to_id, "support", write=True)
            if assigned_user is None:
                messages.error(request, "المكلّف المحدد غير صالح لهذه اللوحة")
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
            assigned_to=assigned_user,
            assigned_at=timezone.now() if assigned_user else None,
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
    if not has_action_permission(request.user, "admin_control.view_audit"):
        messages.error(request, "ليس لديك صلاحية عرض سجل التدقيق.")
        return redirect("dashboard:home")

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
        for log in qs[:_tabular_export_limit()]:
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
        for u in qs[:_tabular_export_limit()]:
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
        "can_write": can_access_dashboard(request.user, "access", write=True),
    })


@require_POST
@staff_member_required
@dashboard_access_required("access", write=True)
def user_toggle_active(request: HttpRequest, user_id: int) -> HttpResponse:
    if not has_action_permission(request.user, "admin_control.manage_access"):
        messages.error(request, "ليس لديك صلاحية تعديل حسابات المستخدمين.")
        return redirect("dashboard:users_list")

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
    if not has_action_permission(request.user, "admin_control.manage_access"):
        messages.error(request, "ليس لديك صلاحية تعديل أدوار المستخدمين.")
        return redirect("dashboard:user_detail", user_id=user_id)

    target_user = get_object_or_404(User, pk=user_id)
    new_role = (request.POST.get("role_state") or "").strip()

    if new_role not in dict(UserRole.choices):
        messages.error(request, "الدور غير صالح")
        return redirect("dashboard:user_detail", user_id=target_user.pk)

    # Prevent escalating own role or modifying superusers
    if target_user.is_superuser and not request.user.is_superuser:
        messages.error(request, "لا يمكن تغيير دور مدير عام")
        return redirect("dashboard:user_detail", user_id=target_user.pk)
    if target_user.pk == request.user.pk:
        messages.error(request, "لا يمكنك تغيير دورك الخاص")
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


# ══════════════════════════════════════════════════════════════
# 6) Access Profiles  (moved from views.py → admin_views.py)
# ══════════════════════════════════════════════════════════════

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
        for ap in _limited_export_queryset(request, qs):
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

    all_dashboards = active_dashboard_choices()
    for d in all_dashboards:
        meta = _dashboard_tile_meta(d.code)
        d.ui_icon = meta["icon"]
        d.ui_grad_from = meta["from"]
        d.ui_grad_to = meta["to"]

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
            "all_dashboards": all_dashboards,
            "can_write": can_access_dashboard(request.user, "access", write=True),
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
    if level == AccessLevel.CLIENT:
        selected_dashboards = Dashboard.objects.filter(
            code__in=UserAccessProfile.CLIENT_ALLOWED_DASHBOARDS,
            is_active=True,
        )

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
    changed_fields = sync_dashboard_user_access(target_user, access_profile=ap, force_staff_role_state=True)
    if changed_fields:
        target_user.save(update_fields=changed_fields)

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
    if level == AccessLevel.CLIENT:
        selected_dashboards = Dashboard.objects.filter(
            code__in=UserAccessProfile.CLIENT_ALLOWED_DASHBOARDS,
            is_active=True,
        )

    ap.level = level
    ap.expires_at = expires_at
    ap.save(update_fields=["level", "expires_at", "updated_at"])
    ap.allowed_dashboards.set(selected_dashboards)
    changed_fields = sync_dashboard_user_access(ap.user, access_profile=ap, force_staff_role_state=True)
    if changed_fields:
        ap.user.save(update_fields=changed_fields)

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
        changed_fields = sync_dashboard_user_access(ap.user, access_profile=ap, force_staff_role_state=True)
        if changed_fields:
            ap.user.save(update_fields=changed_fields)
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
        changed_fields = sync_dashboard_user_access(ap.user, access_profile=ap)
        if changed_fields:
            ap.user.save(update_fields=changed_fields)
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


# ---------------------------------------------------------------------------
# ServiceCatalog management
# ---------------------------------------------------------------------------

@staff_member_required
@dashboard_access_required("extras")
def service_catalog_list(request: HttpRequest) -> HttpResponse:
    from apps.extras.models import ServiceCatalog

    items = ServiceCatalog.objects.all().order_by("sort_order", "sku")
    return render(request, "dashboard/service_catalog_list.html", {"items": items})


@require_POST
@staff_member_required
@dashboard_access_required("extras", write=True)
def service_catalog_toggle_active(request: HttpRequest, item_id: int) -> HttpResponse:
    from apps.extras.models import ServiceCatalog

    item = get_object_or_404(ServiceCatalog, id=item_id)
    item.is_active = not item.is_active
    item.save(update_fields=["is_active", "updated_at"])
    log_action(
        actor=request.user,
        action=AuditAction.FIELD_CHANGED,
        reference_type="extras.service_catalog",
        reference_id=str(item.id),
        request=request,
        extra={"field": "is_active", "new_value": item.is_active, "sku": item.sku},
    )
    label = "تفعيل" if item.is_active else "إيقاف"
    messages.success(request, f"تم {label} الخدمة: {item.sku}")
    return redirect("dashboard:service_catalog_list")
