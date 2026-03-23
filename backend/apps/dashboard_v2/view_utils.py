from __future__ import annotations

from datetime import datetime
from functools import wraps

from django.contrib import messages
from django.db.models import Q
from django.http import HttpResponse
from django.shortcuts import redirect
from django.urls import reverse

from apps.backoffice.models import AccessLevel
from apps.dashboard.access import (
    active_access_profile_for_user,
    first_allowed_dashboard_route,
    has_dashboard_access,
)
from apps.dashboard.auth import (
    SESSION_NEXT_URL_KEY,
    is_dashboard_otp_verified,
)
from apps.dashboard.contracts import DashboardCode, TEAM_CODE_TO_NAME_AR
from apps.dashboard.security import is_safe_redirect_url


SIDEBAR_ORDER: tuple[str, ...] = (
    DashboardCode.ANALYTICS,
    DashboardCode.SUPPORT,
    DashboardCode.CONTENT,
    DashboardCode.MODERATION,
    DashboardCode.REVIEWS,
    "excellence",
    DashboardCode.PROMO,
    DashboardCode.VERIFY,
    DashboardCode.SUBS,
    DashboardCode.EXTRAS,
    DashboardCode.ADMIN_CONTROL,
    DashboardCode.CLIENT_EXTRAS,
)


SIDEBAR_ICONS: dict[str, str] = {
    DashboardCode.ANALYTICS: "chart-bar",
    DashboardCode.SUPPORT: "life-buoy",
    DashboardCode.CONTENT: "document-text",
    DashboardCode.MODERATION: "shield-check",
    DashboardCode.REVIEWS: "star",
    "excellence": "trophy",
    DashboardCode.PROMO: "megaphone",
    DashboardCode.VERIFY: "badge-check",
    DashboardCode.SUBS: "credit-card",
    DashboardCode.EXTRAS: "sparkles",
    DashboardCode.ADMIN_CONTROL: "users",
    DashboardCode.CLIENT_EXTRAS: "briefcase",
}


ROLE_LABELS_AR: dict[str, str] = {
    AccessLevel.ADMIN: "ADMIN",
    AccessLevel.POWER: "POWER USER",
    AccessLevel.USER: "USER",
    AccessLevel.QA: "QA",
    AccessLevel.CLIENT: "CLIENT",
}


SIDEBAR_LABEL_OVERRIDES: dict[str, str] = {
    "excellence": "التميز",
}


def _route_for_code(code: str) -> str:
    if code == DashboardCode.ANALYTICS:
        return reverse("dashboard_v2:analytics_overview")
    if code == DashboardCode.SUPPORT:
        return reverse("dashboard_v2:support_list")
    if code == DashboardCode.CONTENT:
        return reverse("dashboard_v2:content_home")
    if code == DashboardCode.MODERATION:
        return reverse("dashboard_v2:moderation_list")
    if code == DashboardCode.REVIEWS:
        return reverse("dashboard_v2:reviews_list")
    if code == "excellence":
        return reverse("dashboard_v2:excellence_home")
    if code == DashboardCode.ADMIN_CONTROL:
        return reverse("dashboard_v2:users_list")
    if code == DashboardCode.CLIENT_EXTRAS:
        return reverse("dashboard_v2:client_portal_home")
    if code == DashboardCode.PROMO:
        return reverse("dashboard_v2:promo_requests_list")
    if code == DashboardCode.VERIFY:
        return reverse("dashboard_v2:verification_requests_list")
    if code == DashboardCode.SUBS:
        return reverse("dashboard_v2:subscriptions_list")
    if code == DashboardCode.EXTRAS:
        return reverse("dashboard_v2:extras_requests_list")
    return reverse("dashboard_v2:home")


def first_allowed_v2_route(user) -> str | None:
    for code in SIDEBAR_ORDER:
        if _has_sidebar_access(user, code):
            return _route_for_code(code)
    return None


def _role_key(user) -> str:
    if getattr(user, "is_superuser", False):
        return "superuser"
    access_profile = active_access_profile_for_user(user)
    if not access_profile:
        return "none"
    return access_profile.level


def user_role_label(user) -> str:
    role_key = _role_key(user)
    if role_key == "superuser":
        return "SUPERUSER"
    return ROLE_LABELS_AR.get(role_key, "NO ACCESS")


def user_can_write(user) -> bool:
    if getattr(user, "is_superuser", False):
        return True
    access_profile = active_access_profile_for_user(user)
    if not access_profile:
        return False
    return not access_profile.is_readonly()


def build_sidebar_items(user, *, active_code: str = "") -> list[dict[str, str | bool]]:
    items: list[dict[str, str | bool]] = []
    for code in SIDEBAR_ORDER:
        if not _has_sidebar_access(user, code):
            continue
        items.append(
            {
                "code": code,
                "label": SIDEBAR_LABEL_OVERRIDES.get(code, TEAM_CODE_TO_NAME_AR.get(code, code)),
                "icon": SIDEBAR_ICONS.get(code, "square-2x2"),
                "url": _route_for_code(code),
                "active": code == active_code,
            }
        )
    return items


def _has_sidebar_access(user, code: str) -> bool:
    if code == DashboardCode.REVIEWS:
        return has_dashboard_access(user, DashboardCode.REVIEWS, write=False) or has_dashboard_access(
            user, DashboardCode.CONTENT, write=False
        )
    return has_dashboard_access(user, code, write=False)


def build_layout_context(
    request,
    *,
    title: str,
    active_code: str = "",
    subtitle: str = "",
    breadcrumbs: list[dict[str, str]] | None = None,
) -> dict:
    return {
        "page_title": title,
        "page_subtitle": subtitle,
        "sidebar_items": build_sidebar_items(request.user, active_code=active_code),
        "active_dashboard_code": active_code,
        "breadcrumbs": breadcrumbs or [],
        "user_role_label": user_role_label(request.user),
        "can_write_global": user_can_write(request.user),
        "notifications_count": 0,
        "global_search_url": reverse("dashboard_v2:requests_list"),
    }


def dashboard_v2_login_required(view_func):
    @wraps(view_func)
    def wrapped(request, *args, **kwargs):
        user = getattr(request, "user", None)
        if not getattr(user, "is_authenticated", False):
            try:
                request.session[SESSION_NEXT_URL_KEY] = request.get_full_path()
            except Exception:
                pass
            return redirect("dashboard_v2:login")

        if not is_dashboard_otp_verified(request):
            try:
                request.session[SESSION_NEXT_URL_KEY] = request.get_full_path()
            except Exception:
                pass
            return redirect("dashboard_v2:otp")

        return view_func(request, *args, **kwargs)

    return wrapped


def dashboard_v2_access_required(dashboard_code: str, *, write: bool = False):
    def decorator(view_func):
        @dashboard_v2_login_required
        @wraps(view_func)
        def wrapped(request, *args, **kwargs):
            if has_dashboard_access(request.user, dashboard_code, write=write):
                return view_func(request, *args, **kwargs)

            messages.error(request, "ليس لديك صلاحية الوصول إلى هذه الصفحة.")
            fallback = first_allowed_v2_route(request.user) or first_allowed_dashboard_route(request.user)
            if fallback and fallback != getattr(request, "path", ""):
                return redirect(fallback)
            return HttpResponse("غير مصرح", status=403)

        return wrapped

    return decorator


def safe_post_login_redirect(request, *, user) -> str:
    next_url = (request.session.pop(SESSION_NEXT_URL_KEY, "") or "").strip()
    if is_safe_redirect_url(next_url):
        return next_url
    return first_allowed_v2_route(user) or first_allowed_dashboard_route(user) or reverse("dashboard_v2:home")


def apply_role_scope(
    qs,
    *,
    user,
    assigned_field: str,
    owner_field: str | None = None,
    include_unassigned_for_user: bool = False,
):
    if getattr(user, "is_superuser", False):
        return qs

    access_profile = active_access_profile_for_user(user)
    if not access_profile:
        return qs.none()

    if access_profile.level in (AccessLevel.ADMIN, AccessLevel.POWER, AccessLevel.QA):
        return qs

    if access_profile.level == AccessLevel.CLIENT:
        if owner_field:
            return qs.filter(**{owner_field: user})
        return qs.none()

    filters = Q(**{assigned_field: user})
    if include_unassigned_for_user:
        filters |= Q(**{f"{assigned_field}__isnull": True})
    if owner_field:
        filters |= Q(**{owner_field: user})
    return qs.filter(filters)


def parse_date_yyyy_mm_dd(raw: str) -> datetime | None:
    value = (raw or "").strip()
    if not value:
        return None
    try:
        return datetime.strptime(value, "%Y-%m-%d")
    except Exception:
        return None
