from __future__ import annotations

from django.core.paginator import Paginator
from django.db.models import Q
from django.shortcuts import get_object_or_404, render

from apps.accounts.models import User
from apps.audit.models import AuditLog
from apps.backoffice.models import AccessLevel
from apps.dashboard.access import has_action_permission
from apps.dashboard.contracts import DashboardCode

from ..view_utils import build_layout_context, dashboard_v2_access_required


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
    context.update(
        {
            "page_obj": page_obj,
            "query_string": query.urlencode(),
            "q": q,
            "role_filter": role_filter,
            "status_filter": status_filter,
            "role_choices": AccessLevel.choices,
            "can_manage_access": has_action_permission(request.user, "admin_control.manage_access"),
            "table_headers": [
                "المستخدم",
                "الدور",
                "الحالة",
                "اللوحات",
                "تاريخ الإنشاء",
                "إجراءات",
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
            "can_manage_access": has_action_permission(request.user, "admin_control.manage_access"),
        }
    )
    return render(request, "dashboard_v2/access/user_detail.html", context)
