from __future__ import annotations

from django.db.models import Q
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import User, UserRole
from apps.backoffice.models import AccessLevel, Dashboard, UserAccessProfile


DASHBOARD_ROUTE_CANDIDATES: list[tuple[str, str]] = [
    ("analytics", "dashboard:home"),
    ("content", "dashboard:requests_list"),
    ("billing", "dashboard:billing_invoices_list"),
    ("support", "dashboard:support_tickets_list"),
    ("moderation", "dashboard:moderation_cases_list"),
    ("verify", "dashboard:verification_ops"),
    ("excellence", "dashboard:excellence_dashboard"),
    ("promo", "dashboard:promo_requests_list"),
    ("subs", "dashboard:subscriptions_list"),
    ("extras", "dashboard:extras_list"),
    ("access", "dashboard:access_profiles_list"),
]

BACKOFFICE_ACCESS_LEVELS = frozenset(
    {
        AccessLevel.ADMIN,
        AccessLevel.POWER,
        AccessLevel.USER,
        AccessLevel.QA,
    }
)


def is_active_access_profile(access_profile: UserAccessProfile | None) -> bool:
    return bool(access_profile and not access_profile.is_revoked() and not access_profile.is_expired())


def active_access_profile_for_user(user) -> UserAccessProfile | None:
    return access_profile if is_active_access_profile(access_profile := getattr(user, "access_profile", None)) else None


def access_profile_grants_any_dashboard(access_profile: UserAccessProfile | None) -> bool:
    if not is_active_access_profile(access_profile):
        return False
    if access_profile.level in (AccessLevel.ADMIN, AccessLevel.POWER):
        return True
    if access_profile.level == AccessLevel.CLIENT:
        # Client always gets extras; check it's active
        return Dashboard.objects.filter(
            code__in=UserAccessProfile.CLIENT_ALLOWED_DASHBOARDS, is_active=True
        ).exists()
    return access_profile.allowed_dashboards.filter(is_active=True).exists()


def dashboard_portal_eligible(user) -> bool:
    if not getattr(user, "is_authenticated", False):
        return False
    if getattr(user, "is_superuser", False):
        return True
    return access_profile_grants_any_dashboard(active_access_profile_for_user(user))


def backoffice_portal_eligible(user) -> bool:
    if not getattr(user, "is_authenticated", False):
        return False
    if getattr(user, "is_superuser", False):
        return True
    access_profile = active_access_profile_for_user(user)
    if not access_profile:
        return False
    return access_profile.level in BACKOFFICE_ACCESS_LEVELS and access_profile_grants_any_dashboard(access_profile)


def dashboard_allowed(user, dashboard_code: str, write: bool = False) -> bool:
    if not getattr(user, "is_authenticated", False):
        return False
    if getattr(user, "is_superuser", False):
        return True
    access_profile = active_access_profile_for_user(user)
    if not access_profile:
        return False
    if write and access_profile.is_readonly():
        return False
    if access_profile.level in (AccessLevel.ADMIN, AccessLevel.POWER):
        return True
    if access_profile.level == AccessLevel.CLIENT:
        return dashboard_code in UserAccessProfile.CLIENT_ALLOWED_DASHBOARDS
    return access_profile.allowed_dashboards.filter(code=dashboard_code, is_active=True).exists()


def _dashboard_eligible_users_queryset():
    now = timezone.now()
    return (
        User.objects.filter(is_active=True)
        .select_related("access_profile")
        .filter(
            Q(is_superuser=True)
            | (
                Q(access_profile__isnull=False)
                & Q(access_profile__revoked_at__isnull=True)
                & (Q(access_profile__expires_at__isnull=True) | Q(access_profile__expires_at__gt=now))
            )
        )
        .distinct()
        .order_by("-id")
    )


def dashboard_assignment_users(
    dashboard_code: str,
    *,
    write: bool = True,
    limit: int = 150,
) -> list[User]:
    candidates: list[User] = []
    sample_size = max(limit * 4, 300)
    for user in _dashboard_eligible_users_queryset()[:sample_size]:
        if dashboard_allowed(user, dashboard_code, write=write):
            candidates.append(user)
            if len(candidates) >= limit:
                break
    return candidates


def backoffice_assignment_users(*, write: bool = True, limit: int = 150) -> list[User]:
    candidates: list[User] = []
    sample_size = max(limit * 4, 300)
    for user in _dashboard_eligible_users_queryset()[:sample_size]:
        if not backoffice_portal_eligible(user):
            continue
        if write and not getattr(user, "is_superuser", False):
            access_profile = active_access_profile_for_user(user)
            if access_profile and access_profile.is_readonly():
                continue
        candidates.append(user)
        if len(candidates) >= limit:
            break
    return candidates


def dashboard_assignee_user(user_id: int | None, dashboard_code: str, *, write: bool = True) -> User | None:
    if user_id in (None, ""):
        return None
    user = User.objects.filter(id=user_id, is_active=True).select_related("access_profile").first()
    if not user:
        return None
    if not dashboard_allowed(user, dashboard_code, write=write):
        return None
    return user


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
    should_be_staff = bool(
        access_profile_grants_any_dashboard(access_profile)
        and getattr(access_profile, "level", None) in BACKOFFICE_ACCESS_LEVELS
    )

    changed_fields: list[str] = []
    if getattr(user, "is_staff", False) != should_be_staff:
        user.is_staff = should_be_staff
        changed_fields.append("is_staff")

    if should_be_staff and force_staff_role_state and getattr(user, "role_state", None) != UserRole.STAFF:
        user.role_state = UserRole.STAFF
        changed_fields.append("role_state")

    return changed_fields


def active_dashboard_choices() -> list[Dashboard]:
    return list(Dashboard.objects.filter(is_active=True).order_by("sort_order", "id"))
