from __future__ import annotations

from typing import Iterable

from django.contrib.auth import get_user_model

from apps.backoffice.models import AccessLevel, UserAccessProfile


def normalize_dashboard_code(code: str) -> str:
    normalized = str(code or "").strip().lower()
    aliases = {
        "admin": "admin_control",
        "access": "admin_control",
    }
    return aliases.get(normalized, normalized)


def _resolve_client_alias(code: str, access_profile: UserAccessProfile | None = None) -> str:
    normalized = normalize_dashboard_code(code)
    if access_profile and access_profile.level == AccessLevel.CLIENT and normalized == "extras":
        return "client_extras"
    return normalized


def active_access_profile_for_user(user) -> UserAccessProfile | None:
    if not user or not getattr(user, "is_authenticated", False):
        return None
    try:
        access_profile = user.access_profile
    except Exception:
        return None
    if access_profile.is_revoked() or access_profile.is_expired():
        return None
    return access_profile


def dashboard_portal_eligible(user) -> bool:
    if not user or not getattr(user, "is_authenticated", False):
        return False
    if not getattr(user, "is_active", False):
        return False
    if getattr(user, "is_superuser", False):
        return True
    access_profile = active_access_profile_for_user(user)
    if not access_profile:
        return False
    if access_profile.level == AccessLevel.CLIENT:
        return False
    return bool(getattr(user, "is_staff", False))


def dashboard_allowed(user, dashboard_code: str, *, write: bool = False) -> bool:
    if not user or not getattr(user, "is_authenticated", False):
        return False
    if not getattr(user, "is_active", False):
        return False
    if getattr(user, "is_superuser", False):
        return True

    access_profile = active_access_profile_for_user(user)
    if not access_profile:
        return False

    if write and access_profile.is_readonly():
        return False

    normalized_code = _resolve_client_alias(dashboard_code, access_profile=access_profile)
    if not normalized_code:
        return False
    return bool(access_profile.is_allowed(normalized_code))


def has_dashboard_access(user, dashboard_code: str, *, write: bool = False) -> bool:
    return dashboard_allowed(user, dashboard_code, write=write)


def can_access_dashboard(user, dashboard_code: str, *, write: bool = False) -> bool:
    return dashboard_allowed(user, dashboard_code, write=write)


def dashboard_assignee_user(user_id: int | str, dashboard_code: str, *, write: bool = False):
    try:
        target_id = int(user_id)
    except (TypeError, ValueError):
        return None
    User = get_user_model()
    user = User.objects.filter(id=target_id, is_active=True).first()
    if user is None:
        return None
    if not (getattr(user, "is_staff", False) or getattr(user, "is_superuser", False)):
        return None
    if not dashboard_allowed(user, dashboard_code, write=write):
        return None
    return user


def _set_role_state_for_staff_sync(user, *, should_be_staff: bool) -> bool:
    try:
        from apps.accounts.models import UserRole
    except Exception:
        return False

    current_role = getattr(user, "role_state", "")
    if should_be_staff:
        if current_role != UserRole.STAFF:
            user.role_state = UserRole.STAFF
            return True
        return False

    if current_role == UserRole.STAFF:
        user.role_state = UserRole.CLIENT
        return True
    return False


def sync_dashboard_user_access(
    user,
    *,
    access_profile: UserAccessProfile | None = None,
    force_staff_role_state: bool = False,
) -> list[str]:
    changed_fields: list[str] = []

    if access_profile is None:
        try:
            access_profile = user.access_profile
        except Exception:
            access_profile = None

    if getattr(user, "is_superuser", False):
        should_be_staff = True
    elif access_profile is None:
        should_be_staff = False
    else:
        should_be_staff = access_profile.level != AccessLevel.CLIENT

    if bool(getattr(user, "is_staff", False)) != bool(should_be_staff):
        user.is_staff = bool(should_be_staff)
        changed_fields.append("is_staff")

    if force_staff_role_state and _set_role_state_for_staff_sync(user, should_be_staff=bool(should_be_staff)):
        changed_fields.append("role_state")

    return changed_fields


def dashboards_for_user(user) -> Iterable[str]:
    access_profile = active_access_profile_for_user(user)
    if not access_profile:
        return []
    if access_profile.level in (AccessLevel.ADMIN, AccessLevel.POWER):
        return ["*"]
    return list(access_profile.allowed_dashboards.values_list("code", flat=True))

