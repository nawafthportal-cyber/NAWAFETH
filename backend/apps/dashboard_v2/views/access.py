from __future__ import annotations

from datetime import datetime

from django.contrib import messages
from django.core.paginator import Paginator
from django.db.models import Q
from django.shortcuts import get_object_or_404, redirect, render
from django.utils import timezone
from django.views.decorators.http import require_POST

from apps.accounts.models import User, UserRole
from apps.audit.models import AuditAction, AuditLog
from apps.audit.services import log_action
from apps.backoffice.models import AccessLevel, AccessPermission, Dashboard, UserAccessProfile
from apps.dashboard.access import has_action_permission, has_dashboard_access, sync_dashboard_user_access
from apps.dashboard.contracts import DashboardCode

from ..view_utils import build_layout_context, dashboard_v2_access_required


def _parse_datetime_local(raw_value: str) -> datetime | None:
    value = (raw_value or "").strip()
    if not value:
        return None
    for fmt in ("%Y-%m-%dT%H:%M", "%Y-%m-%d %H:%M", "%Y-%m-%d"):
        try:
            parsed = datetime.strptime(value, fmt)
            if timezone.is_naive(parsed):
                return timezone.make_aware(parsed, timezone.get_current_timezone())
            return parsed
        except Exception:
            continue
    return None


def _format_datetime_local(value: datetime | None) -> str:
    if not value:
        return ""
    local_value = timezone.localtime(value)
    return local_value.strftime("%Y-%m-%dT%H:%M")


def _is_active_admin_profile(access_profile: UserAccessProfile | None) -> bool:
    if not access_profile:
        return False
    if access_profile.level != AccessLevel.ADMIN:
        return False
    if access_profile.revoked_at is not None:
        return False
    if access_profile.expires_at and access_profile.expires_at <= timezone.now():
        return False
    return True


def _active_admin_profiles_count() -> int:
    now = timezone.now()
    return (
        UserAccessProfile.objects.filter(level=AccessLevel.ADMIN, revoked_at__isnull=True)
        .filter(Q(expires_at__isnull=True) | Q(expires_at__gt=now))
        .count()
    )


def _can_manage_access(user) -> bool:
    return bool(
        has_dashboard_access(user, DashboardCode.ADMIN_CONTROL, write=True)
        and has_action_permission(user, "admin_control.manage_access")
    )


@dashboard_v2_access_required(DashboardCode.ADMIN_CONTROL, write=False)
def users_list_view(request):
    qs = (
        User.objects.select_related("access_profile")
        .prefetch_related("access_profile__allowed_dashboards")
        .order_by("-id")
    )

    q = (request.GET.get("q") or "").strip()
    role_filter = (request.GET.get("role") or "").strip()
    status_filter = (request.GET.get("status") or "").strip()

    if q:
        qs = qs.filter(
            Q(phone__icontains=q)
            | Q(first_name__icontains=q)
            | Q(last_name__icontains=q)
            | Q(username__icontains=q)
            | Q(email__icontains=q)
        )
    if role_filter == "none":
        qs = qs.filter(access_profile__isnull=True)
    elif role_filter in {level for level, _ in AccessLevel.choices}:
        qs = qs.filter(access_profile__level=role_filter)
    if status_filter == "active":
        qs = qs.filter(is_active=True)
    elif status_filter == "inactive":
        qs = qs.filter(is_active=False)

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    query = request.GET.copy()
    query.pop("page", None)

    context = build_layout_context(
        request,
        title="المستخدمون والصلاحيات",
        subtitle="مراجعة المستخدمين وحالة الوصول التشغيلي",
        active_code=DashboardCode.ADMIN_CONTROL,
        breadcrumbs=[{"label": "لوحة التحكم", "url": "dashboard_v2:home"}],
    )
    role_matrix = [
        {
            "level": "Admin",
            "description": "الدخول على جميع لوحات التحكم وإجراء جميع العمليات.",
        },
        {
            "level": "Power User",
            "description": "الدخول على لوحات تشغيل متعددة وتنفيذ عمليات موسعة حسب التفويض.",
        },
        {
            "level": "User",
            "description": "الدخول على لوحات محددة وإجراء العمليات المصرح بها فقط.",
        },
        {
            "level": "QA",
            "description": "وصول قراءة فقط على لوحات التشغيل بدون تنفيذ إجراءات تعديلية.",
        },
        {
            "level": "Client",
            "description": "وصول محدود على بوابة العميل ولوحات الخدمات الإضافية فقط.",
        },
    ]

    dashboard_matrix = [
        {"index": 1, "label": "لوحة إدارة الصلاحيات وتقارير المنصة", "code": DashboardCode.ADMIN_CONTROL},
        {"index": 2, "label": "فريق الدعم والمساعدة", "code": DashboardCode.SUPPORT},
        {"index": 3, "label": "فريق إدارة المحتوى", "code": DashboardCode.CONTENT},
        {"index": 4, "label": "فريق إدارة الإعلانات والترويج", "code": DashboardCode.PROMO},
        {"index": 5, "label": "فريق إدارة التوثيق", "code": DashboardCode.VERIFY},
        {"index": 6, "label": "فريق إدارة الترقية والاشتراكات", "code": DashboardCode.SUBS},
        {"index": 7, "label": "فريق إدارة الخدمات الإضافية", "code": DashboardCode.EXTRAS},
        {"index": 8, "label": "بوابة تحكم العملاء للخدمات الإضافية", "code": DashboardCode.CLIENT_EXTRAS},
    ]
    context.update(
        {
            "page_obj": page_obj,
            "query_string": query.urlencode(),
            "q": q,
            "role_filter": role_filter,
            "status_filter": status_filter,
            "role_choices": AccessLevel.choices,
            "can_manage_access": _can_manage_access(request.user),
            "all_dashboards": list(Dashboard.objects.filter(is_active=True).order_by("sort_order", "id")),
            "access_level_choices": AccessLevel.choices,
            "role_matrix": role_matrix,
            "dashboard_matrix": dashboard_matrix,
            "table_headers": [
                "المستخدم",
                "المستوى",
                "الحالة",
                "اللوحات",
                "انتهاء صلاحية الدخول",
                "تاريخ سحب الوصول",
                "رقم الجوال",
                "تحديث",
                "تعطيل/تفعيل",
            ],
        }
    )
    return render(request, "dashboard_v2/access/users_list.html", context)


@dashboard_v2_access_required(DashboardCode.ADMIN_CONTROL, write=False)
def user_detail_view(request, user_id: int):
    target_user = get_object_or_404(
        User.objects.select_related("access_profile")
        .prefetch_related("access_profile__allowed_dashboards", "access_profile__granted_permissions"),
        id=user_id,
    )
    access_profile = getattr(target_user, "access_profile", None)

    audit_qs = AuditLog.objects.select_related("actor").filter(
        Q(actor_id=target_user.id)
        | Q(extra__target_user_id=target_user.id)
        | Q(reference_type="accounts.user", reference_id=str(target_user.id))
    )
    audit_entries = list(audit_qs.order_by("-id")[:20])
    can_manage_access = _can_manage_access(request.user)
    all_dashboards = list(Dashboard.objects.filter(is_active=True).order_by("sort_order", "id"))
    permission_catalog = list(AccessPermission.objects.filter(is_active=True).order_by("dashboard_code", "sort_order", "id"))
    selected_dashboard_ids = list(access_profile.allowed_dashboards.values_list("id", flat=True)) if access_profile else []
    selected_permission_ids = list(access_profile.granted_permissions.values_list("id", flat=True)) if access_profile else []

    context = build_layout_context(
        request,
        title=f"المستخدم: {target_user.phone or target_user.id}",
        subtitle="تفاصيل الحساب والصلاحيات وسجل التغييرات",
        active_code=DashboardCode.ADMIN_CONTROL,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "المستخدمون", "url": "dashboard_v2:users_list"},
        ],
    )
    context.update(
        {
            "target_user": target_user,
            "access_profile": access_profile,
            "allowed_dashboards": list(access_profile.allowed_dashboards.all()) if access_profile else [],
            "granted_permissions": list(access_profile.granted_permissions.filter(is_active=True)) if access_profile else [],
            "audit_entries": audit_entries,
            "can_manage_access": can_manage_access,
            "can_write_access": has_dashboard_access(request.user, DashboardCode.ADMIN_CONTROL, write=True),
            "role_state_choices": UserRole.choices,
            "access_level_choices": AccessLevel.choices,
            "all_dashboards": all_dashboards,
            "permission_catalog": permission_catalog,
            "selected_dashboard_ids": selected_dashboard_ids,
            "selected_permission_ids": selected_permission_ids,
            "expires_at_local": _format_datetime_local(access_profile.expires_at if access_profile else None),
        }
    )
    return render(request, "dashboard_v2/access/user_detail.html", context)


@dashboard_v2_access_required(DashboardCode.ADMIN_CONTROL, write=True)
@require_POST
def user_toggle_active_action(request, user_id: int):
    if not _can_manage_access(request.user):
        messages.error(request, "ليس لديك صلاحية تعديل حسابات المستخدمين.")
        return redirect("dashboard_v2:users_list")

    target_user = get_object_or_404(User, id=user_id)
    if target_user.id == request.user.id:
        messages.error(request, "لا يمكن تعطيل حسابك الحالي.")
        return redirect("dashboard_v2:user_detail", user_id=target_user.id)
    if target_user.is_superuser:
        messages.error(request, "لا يمكن تعطيل حساب مدير عام.")
        return redirect("dashboard_v2:user_detail", user_id=target_user.id)

    target_user.is_active = not target_user.is_active
    target_user.save(update_fields=["is_active"])

    log_action(
        actor=request.user,
        action=AuditAction.ACCESS_PROFILE_UPDATED,
        reference_type="accounts.user",
        reference_id=str(target_user.id),
        request=request,
        extra={
            "target_user_id": target_user.id,
            "field": "is_active",
            "new_value": target_user.is_active,
        },
    )

    action_label = "تفعيل" if target_user.is_active else "تعطيل"
    messages.success(request, f"تم {action_label} الحساب بنجاح.")
    return redirect("dashboard_v2:user_detail", user_id=target_user.id)


@dashboard_v2_access_required(DashboardCode.ADMIN_CONTROL, write=True)
@require_POST
def user_update_role_action(request, user_id: int):
    if not _can_manage_access(request.user):
        messages.error(request, "ليس لديك صلاحية تعديل أدوار المستخدمين.")
        return redirect("dashboard_v2:user_detail", user_id=user_id)

    target_user = get_object_or_404(User, id=user_id)
    new_role = (request.POST.get("role_state") or "").strip()
    if new_role not in dict(UserRole.choices):
        messages.error(request, "الدور غير صالح.")
        return redirect("dashboard_v2:user_detail", user_id=target_user.id)
    if target_user.is_superuser and not request.user.is_superuser:
        messages.error(request, "لا يمكن تغيير دور مدير عام.")
        return redirect("dashboard_v2:user_detail", user_id=target_user.id)
    if target_user.id == request.user.id:
        messages.error(request, "لا يمكن تغيير دور حسابك الحالي.")
        return redirect("dashboard_v2:user_detail", user_id=target_user.id)

    access_profile = UserAccessProfile.objects.filter(user=target_user).first()
    if access_profile and new_role != UserRole.STAFF and _is_active_admin_profile(access_profile) and _active_admin_profiles_count() <= 1:
        messages.error(request, "لا يمكن سحب صلاحية آخر Admin فعّال.")
        return redirect("dashboard_v2:user_detail", user_id=target_user.id)

    old_role = target_user.role_state
    old_is_staff = target_user.is_staff

    target_user.role_state = new_role
    target_user.is_staff = new_role == UserRole.STAFF
    target_user.save(update_fields=["role_state", "is_staff"])

    if access_profile and new_role != UserRole.STAFF and access_profile.revoked_at is None:
        access_profile.revoked_at = timezone.now()
        access_profile.save(update_fields=["revoked_at", "updated_at"])
    elif access_profile and new_role == UserRole.STAFF and access_profile.revoked_at is not None:
        access_profile.revoked_at = None
        access_profile.save(update_fields=["revoked_at", "updated_at"])

    if access_profile:
        changed_fields = sync_dashboard_user_access(
            target_user,
            access_profile=access_profile,
            force_staff_role_state=(new_role == UserRole.STAFF),
        )
        if changed_fields:
            target_user.save(update_fields=changed_fields)

    log_action(
        actor=request.user,
        action=AuditAction.ACCESS_PROFILE_UPDATED,
        reference_type="accounts.user",
        reference_id=str(target_user.id),
        request=request,
        extra={
            "target_user_id": target_user.id,
            "before": {"role_state": old_role, "is_staff": old_is_staff},
            "after": {"role_state": target_user.role_state, "is_staff": target_user.is_staff},
        },
    )

    if new_role == UserRole.STAFF:
        messages.success(request, "تم تحديث الدور إلى موظف.")
    else:
        messages.success(request, f"تم تحديث الدور من {old_role} إلى {new_role}.")
    return redirect("dashboard_v2:user_detail", user_id=target_user.id)


@dashboard_v2_access_required(DashboardCode.ADMIN_CONTROL, write=True)
@require_POST
def access_profile_upsert_action(request, user_id: int):
    if not _can_manage_access(request.user):
        messages.error(request, "ليس لديك صلاحية إدارة ملفات الوصول.")
        return redirect("dashboard_v2:user_detail", user_id=user_id)

    target_user = get_object_or_404(User, id=user_id)
    level = (request.POST.get("level") or "").strip().lower()
    if level not in {choice[0] for choice in AccessLevel.choices}:
        messages.error(request, "مستوى الصلاحية غير صالح.")
        return redirect("dashboard_v2:user_detail", user_id=target_user.id)

    expires_at_raw = (request.POST.get("expires_at") or "").strip()
    expires_at = _parse_datetime_local(expires_at_raw) if expires_at_raw else None
    if expires_at_raw and expires_at is None:
        messages.error(request, "صيغة تاريخ الانتهاء غير صحيحة.")
        return redirect("dashboard_v2:user_detail", user_id=target_user.id)

    dashboard_ids = request.POST.getlist("dashboard_ids")
    permission_ids = request.POST.getlist("permission_ids")
    selected_dashboards = Dashboard.objects.filter(id__in=dashboard_ids, is_active=True)
    selected_permissions = AccessPermission.objects.filter(id__in=permission_ids, is_active=True)

    if level == AccessLevel.CLIENT:
        selected_dashboards = Dashboard.objects.filter(code__in=UserAccessProfile.CLIENT_ALLOWED_DASHBOARDS, is_active=True)
        selected_permissions = AccessPermission.objects.none()

    access_profile = UserAccessProfile.objects.filter(user=target_user).first()
    created = access_profile is None
    old_payload: dict[str, object] = {}
    if access_profile:
        old_payload = {
            "level": access_profile.level,
            "expires_at": access_profile.expires_at.isoformat() if access_profile.expires_at else None,
            "dashboards": list(access_profile.allowed_dashboards.values_list("code", flat=True)),
            "permissions": list(access_profile.granted_permissions.values_list("code", flat=True)),
            "revoked_at": access_profile.revoked_at.isoformat() if access_profile.revoked_at else None,
        }
        will_still_be_active_admin = (
            level == AccessLevel.ADMIN
            and access_profile.revoked_at is None
            and (expires_at is None or expires_at > timezone.now())
        )
        if _is_active_admin_profile(access_profile) and not will_still_be_active_admin and _active_admin_profiles_count() <= 1:
            messages.error(request, "لا يمكن خفض صلاحيات آخر Admin فعّال.")
            return redirect("dashboard_v2:user_detail", user_id=target_user.id)
    else:
        access_profile = UserAccessProfile.objects.create(user=target_user, level=level, expires_at=expires_at)

    access_profile.level = level
    access_profile.expires_at = expires_at
    access_profile.save(update_fields=["level", "expires_at", "updated_at"])
    access_profile.allowed_dashboards.set(selected_dashboards)
    access_profile.granted_permissions.set(selected_permissions)

    changed_fields = sync_dashboard_user_access(target_user, access_profile=access_profile, force_staff_role_state=True)
    if changed_fields:
        target_user.save(update_fields=changed_fields)

    new_payload = {
        "level": access_profile.level,
        "expires_at": access_profile.expires_at.isoformat() if access_profile.expires_at else None,
        "dashboards": list(access_profile.allowed_dashboards.values_list("code", flat=True)),
        "permissions": list(access_profile.granted_permissions.values_list("code", flat=True)),
        "revoked_at": access_profile.revoked_at.isoformat() if access_profile.revoked_at else None,
    }
    log_action(
        actor=request.user,
        action=AuditAction.ACCESS_PROFILE_CREATED if created else AuditAction.ACCESS_PROFILE_UPDATED,
        reference_type="backoffice.user_access_profile",
        reference_id=str(access_profile.id),
        request=request,
        extra={"target_user_id": target_user.id, "before": old_payload, "after": new_payload},
    )

    if created:
        messages.success(request, "تم إنشاء ملف الصلاحيات بنجاح.")
    else:
        messages.success(request, "تم تحديث ملف الصلاحيات بنجاح.")
    return redirect("dashboard_v2:user_detail", user_id=target_user.id)


@dashboard_v2_access_required(DashboardCode.ADMIN_CONTROL, write=True)
@require_POST
def access_profile_toggle_revoke_action(request, user_id: int):
    if not _can_manage_access(request.user):
        messages.error(request, "ليس لديك صلاحية إدارة ملفات الوصول.")
        return redirect("dashboard_v2:user_detail", user_id=user_id)

    access_profile = get_object_or_404(UserAccessProfile.objects.select_related("user"), user_id=user_id)
    if access_profile.user_id == request.user.id:
        messages.warning(request, "لا يمكن سحب صلاحيات حسابك الحالي.")
        return redirect("dashboard_v2:user_detail", user_id=access_profile.user_id)

    was_revoked = access_profile.revoked_at is not None
    if was_revoked:
        access_profile.revoked_at = None
        access_profile.save(update_fields=["revoked_at", "updated_at"])
        changed_fields = sync_dashboard_user_access(
            access_profile.user,
            access_profile=access_profile,
            force_staff_role_state=True,
        )
        if changed_fields:
            access_profile.user.save(update_fields=changed_fields)
        log_action(
            actor=request.user,
            action=AuditAction.ACCESS_PROFILE_UNREVOKED,
            reference_type="backoffice.user_access_profile",
            reference_id=str(access_profile.id),
            request=request,
            extra={"target_user_id": access_profile.user_id, "revoked": False},
        )
        messages.success(request, "تم إلغاء سحب الصلاحيات.")
        return redirect("dashboard_v2:user_detail", user_id=access_profile.user_id)

    if _is_active_admin_profile(access_profile) and _active_admin_profiles_count() <= 1:
        messages.error(request, "لا يمكن سحب صلاحيات آخر Admin فعّال.")
        return redirect("dashboard_v2:user_detail", user_id=access_profile.user_id)

    access_profile.revoked_at = timezone.now()
    access_profile.save(update_fields=["revoked_at", "updated_at"])
    changed_fields = sync_dashboard_user_access(access_profile.user, access_profile=access_profile)
    if changed_fields:
        access_profile.user.save(update_fields=changed_fields)

    log_action(
        actor=request.user,
        action=AuditAction.ACCESS_PROFILE_REVOKED,
        reference_type="backoffice.user_access_profile",
        reference_id=str(access_profile.id),
        request=request,
        extra={"target_user_id": access_profile.user_id, "revoked": True},
    )
    messages.success(request, "تم سحب الصلاحيات.")
    return redirect("dashboard_v2:user_detail", user_id=access_profile.user_id)


@dashboard_v2_access_required(DashboardCode.ADMIN_CONTROL, write=True)
@require_POST
def create_access_user_action(request):
    if not _can_manage_access(request.user):
        messages.error(request, "ليس لديك صلاحية إنشاء حسابات تشغيل.")
        return redirect("dashboard_v2:users_list")

    username = (request.POST.get("username") or "").strip()
    phone = (request.POST.get("phone") or "").strip()
    password = (request.POST.get("password") or "").strip()
    level = (request.POST.get("level") or "").strip().lower()
    expires_at_raw = (request.POST.get("expires_at") or "").strip()
    revoked_at_raw = (request.POST.get("revoked_at") or "").strip()
    dashboard_ids = request.POST.getlist("dashboard_ids")

    if not phone:
        messages.error(request, "رقم الجوال مطلوب.")
        return redirect("dashboard_v2:users_list")
    if not password or len(password) < 8:
        messages.error(request, "كلمة المرور يجب ألا تقل عن 8 أحرف.")
        return redirect("dashboard_v2:users_list")
    if level not in {choice[0] for choice in AccessLevel.choices}:
        messages.error(request, "مستوى الصلاحية غير صالح.")
        return redirect("dashboard_v2:users_list")
    if User.objects.filter(phone=phone).exists():
        messages.error(request, "يوجد حساب بهذا الرقم بالفعل.")
        return redirect("dashboard_v2:users_list")
    if username and User.objects.filter(username=username).exists():
        messages.error(request, "اسم المستخدم مستخدم بالفعل.")
        return redirect("dashboard_v2:users_list")

    expires_at = _parse_datetime_local(expires_at_raw) if expires_at_raw else None
    if expires_at_raw and expires_at is None:
        messages.error(request, "صيغة تاريخ انتهاء كلمة المرور غير صحيحة.")
        return redirect("dashboard_v2:users_list")

    revoked_at = _parse_datetime_local(revoked_at_raw) if revoked_at_raw else None
    if revoked_at_raw and revoked_at is None:
        messages.error(request, "صيغة تاريخ انتهاء الحساب غير صحيحة.")
        return redirect("dashboard_v2:users_list")

    user = User.objects.create_user(
        phone=phone,
        password=password,
        username=username or None,
        role_state=UserRole.STAFF,
        is_staff=True,
    )

    selected_dashboards = Dashboard.objects.filter(id__in=dashboard_ids, is_active=True)
    if level == AccessLevel.CLIENT:
        selected_dashboards = Dashboard.objects.filter(
            code__in=UserAccessProfile.CLIENT_ALLOWED_DASHBOARDS,
            is_active=True,
        )

    access_profile = UserAccessProfile.objects.create(
        user=user,
        level=level,
        expires_at=expires_at,
        revoked_at=revoked_at,
    )
    access_profile.allowed_dashboards.set(selected_dashboards)

    changed_fields = sync_dashboard_user_access(user, access_profile=access_profile, force_staff_role_state=True)
    if changed_fields:
        user.save(update_fields=changed_fields)

    log_action(
        actor=request.user,
        action=AuditAction.ACCESS_PROFILE_CREATED,
        reference_type="backoffice.user_access_profile",
        reference_id=str(access_profile.id),
        request=request,
        extra={
            "target_user_id": user.id,
            "after": {
                "level": access_profile.level,
                "expires_at": access_profile.expires_at.isoformat() if access_profile.expires_at else None,
                "revoked_at": access_profile.revoked_at.isoformat() if access_profile.revoked_at else None,
                "dashboards": list(access_profile.allowed_dashboards.values_list("code", flat=True)),
            },
        },
    )

    messages.success(request, "تم إنشاء الحساب وملف الصلاحيات بنجاح.")
    return redirect("dashboard_v2:user_detail", user_id=user.id)
