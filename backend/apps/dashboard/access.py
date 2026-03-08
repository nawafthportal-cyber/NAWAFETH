from __future__ import annotations

from django.urls import reverse

from apps.accounts.models import UserRole
from apps.backoffice.models import AccessLevel, Dashboard, UserAccessProfile


DASHBOARD_ROUTE_CANDIDATES: list[tuple[str, str]] = [
    ("analytics", "dashboard:home"),
    ("content", "dashboard:requests_list"),
    ("billing", "dashboard:billing_invoices_list"),
    ("support", "dashboard:support_tickets_list"),
    ("verify", "dashboard:verification_ops"),
    ("excellence", "dashboard:excellence_dashboard"),
    ("promo", "dashboard:promo_requests_list"),
    ("subs", "dashboard:subscriptions_list"),
    ("extras", "dashboard:extras_list"),
    ("access", "dashboard:access_profiles_list"),
]


def is_active_access_profile(access_profile: UserAccessProfile | None) -> bool:
    return bool(access_profile and not access_profile.is_revoked() and not access_profile.is_expired())


def access_profile_grants_any_dashboard(access_profile: UserAccessProfile | None) -> bool:
    if not is_active_access_profile(access_profile):
        return False
    if access_profile.level in (AccessLevel.ADMIN, AccessLevel.POWER):
        return True
    return access_profile.allowed_dashboards.filter(is_active=True).exists()


def dashboard_allowed(user, dashboard_code: str, write: bool = False) -> bool:
    if not getattr(user, "is_authenticated", False):
        return False
    if getattr(user, "is_superuser", False):
        return True
    if not getattr(user, "is_staff", False):
        return False

    access_profile = getattr(user, "access_profile", None)
    if not is_active_access_profile(access_profile):
        return False
    if write and access_profile.is_readonly():
        return False
    if access_profile.level in (AccessLevel.ADMIN, AccessLevel.POWER):
        return True
    return access_profile.allowed_dashboards.filter(code=dashboard_code, is_active=True).exists()


def first_allowed_dashboard_route(user) -> str | None:
    for dashboard_code, route_name in DASHBOARD_ROUTE_CANDIDATES:
        if dashboard_allowed(user, dashboard_code, write=False):
            return reverse(route_name)
    return None


def sync_dashboard_user_access(
    user,
    *,
    access_profile: UserAccessProfile | None = None,
    force_staff_role_state: bool = False,
) -> list[str]:
    if getattr(user, "is_superuser", False):
        changed_fields: list[str] = []
        if not getattr(user, "is_staff", False):
            user.is_staff = True
            changed_fields.append("is_staff")
        if getattr(user, "role_state", None) != UserRole.STAFF:
            user.role_state = UserRole.STAFF
            changed_fields.append("role_state")
        return changed_fields

    access_profile = access_profile if access_profile is not None else getattr(user, "access_profile", None)
    should_be_staff = access_profile_grants_any_dashboard(access_profile)

    changed_fields: list[str] = []
    if getattr(user, "is_staff", False) != should_be_staff:
        user.is_staff = should_be_staff
        changed_fields.append("is_staff")

    if should_be_staff and (force_staff_role_state or getattr(user, "role_state", None) != UserRole.STAFF):
        user.role_state = UserRole.STAFF
        changed_fields.append("role_state")

    return changed_fields


def active_dashboard_choices() -> list[Dashboard]:
    return list(Dashboard.objects.filter(is_active=True).order_by("sort_order", "id"))
