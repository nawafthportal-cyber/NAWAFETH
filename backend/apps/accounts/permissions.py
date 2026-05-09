from __future__ import annotations

from rest_framework.exceptions import PermissionDenied
from rest_framework.permissions import BasePermission


ROLE_LEVELS: dict[str, int] = {
    # unauthenticated visitor is handled separately (0)
    "visitor": 0,
    "phone_only": 1,
    "client": 2,
    "provider": 3,
    "staff": 99,
}


def role_level(user) -> int:
    if not user or not getattr(user, "is_authenticated", False):
        return 0

    # Staff bypass
    if bool(getattr(user, "is_staff", False)):
        return ROLE_LEVELS["staff"]

    role_state = (getattr(user, "role_state", "") or "").strip().lower()
    return ROLE_LEVELS.get(role_state, 0)


def has_completed_client_registration(user) -> bool:
    if not user or not getattr(user, "is_authenticated", False):
        return False
    if bool(getattr(user, "is_staff", False)):
        return True

    role_state = (getattr(user, "role_state", "") or "").strip().lower()
    if role_state == "provider":
        return True
    if role_state != "client":
        return False

    required_values = (
        getattr(user, "username", ""),
        getattr(user, "first_name", ""),
        getattr(user, "last_name", ""),
        getattr(user, "email", ""),
    )
    return bool(getattr(user, "terms_accepted_at", None)) and all(
        str(value or "").strip() for value in required_values
    )


def profile_completion_required_payload() -> dict[str, object]:
    return {
        "detail": "أكمل بيانات حسابك أولًا لاستخدام هذه الميزة.",
        "error_code": "profile_completion_required",
        "requires_completion": True,
        "redirect_url": "/signup/",
    }


class RoleAtLeast(BasePermission):
    """Require user to be authenticated and at least a given role level.

    Subclasses must set `min_level`.
    """

    min_level: int = 0

    def has_permission(self, request, view):
        return role_level(getattr(request, "user", None)) >= self.min_level


class IsAtLeastPhoneOnly(RoleAtLeast):
    min_level = ROLE_LEVELS["phone_only"]


class IsAtLeastClient(RoleAtLeast):
    min_level = ROLE_LEVELS["client"]


class IsCompleteClient(BasePermission):
    def has_permission(self, request, view):
        user = getattr(request, "user", None)
        if not user or not getattr(user, "is_authenticated", False):
            return False
        if has_completed_client_registration(user):
            return True
        raise PermissionDenied(profile_completion_required_payload())


class IsAtLeastProvider(RoleAtLeast):
    min_level = ROLE_LEVELS["provider"]
