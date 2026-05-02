from __future__ import annotations

from dataclasses import dataclass

from apps.accounts.models import UserRole


@dataclass(frozen=True)
class ProviderAccessState:
    allowed: bool
    code: str
    detail: str
    has_provider_profile: bool
    has_provider_role: bool


class ProviderAccessError(PermissionError):
    def __init__(self, detail: str, *, code: str):
        super().__init__(detail)
        self.code = code
        self.detail = detail


def provider_access_state(user) -> ProviderAccessState:
    if not user or not getattr(user, "is_authenticated", False):
        return ProviderAccessState(
            allowed=False,
            code="authentication_required",
            detail="تسجيل الدخول مطلوب.",
            has_provider_profile=False,
            has_provider_role=False,
        )

    try:
        has_provider_profile = bool(getattr(user, "provider_profile", None))
    except Exception:
        has_provider_profile = False

    role_state = (getattr(user, "role_state", "") or "").strip().lower()
    has_provider_role = role_state == UserRole.PROVIDER

    # Compatibility-safe rule for legacy/admin-created providers:
    # a real ProviderProfile is the canonical provider entitlement even if role_state drifted.
    if has_provider_profile:
        return ProviderAccessState(
            allowed=True,
            code="provider_allowed",
            detail="",
            has_provider_profile=True,
            has_provider_role=has_provider_role,
        )

    if has_provider_role:
        return ProviderAccessState(
            allowed=False,
            code="provider_profile_required",
            detail="يجب استكمال ملف مقدم الخدمة أولًا.",
            has_provider_profile=False,
            has_provider_role=True,
        )

    return ProviderAccessState(
        allowed=False,
        code="provider_required",
        detail="هذه الخدمة متاحة فقط لمقدمي الخدمات المسجلين.",
        has_provider_profile=False,
        has_provider_role=False,
    )


def ensure_provider_access(user) -> ProviderAccessState:
    state = provider_access_state(user)
    if not state.allowed:
        raise ProviderAccessError(state.detail, code=state.code)
    return state


class HasProviderProfile:
    """Permission class that allows any authenticated user with a ProviderProfile.

    This is the correct gate for provider-owned resource endpoints (listing,
    retrieving, or modifying content the provider themselves created).

    Unlike ``IsAtLeastProvider``, this also accepts legacy / admin-created
    providers whose ``role_state`` may have drifted to ``client`` without a
    matching profile upgrade – consistent with ``provider_access_state()``.
    """

    message = "هذه الخدمة متاحة فقط لمقدمي الخدمات المسجلين."

    def has_permission(self, request, view):
        user = getattr(request, "user", None)
        state = provider_access_state(user)
        if not state.allowed:
            self.message = state.detail or self.message
            return False
        return True
