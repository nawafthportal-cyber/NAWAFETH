from __future__ import annotations

from rest_framework.permissions import BasePermission, SAFE_METHODS

from apps.providers.eligibility import provider_access_state


class IsOwnerOrBackofficeVerify(BasePermission):
    """
    - المالك يرى طلبه
    - فريق التوثيق يتطلب وصول لوحة verify
    - QA عرض فقط
    """
    message = "غير مصرح."

    def _is_backoffice_request(self, request) -> bool:
        return "/backoffice/" in (getattr(request, "path", "") or "")

    def _has_backoffice_access(self, request) -> bool:
        ap = getattr(request.user, "access_profile", None)
        if not ap:
            return False
        if ap.is_revoked() or ap.is_expired():
            return False

        if ap.is_readonly() and request.method not in SAFE_METHODS:
            self.message = "حساب QA للعرض فقط."
            return False

        if ap.level in ("admin", "power"):
            return True

        return ap.is_allowed("verify")

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False
        if self._is_backoffice_request(request):
            return self._has_backoffice_access(request)
        state = provider_access_state(user)
        if not state.allowed:
            self.message = state.detail
            return False
        return True

    def has_object_permission(self, request, view, obj):
        user = request.user

        if self._is_backoffice_request(request):
            if not self._has_backoffice_access(request):
                return False

            ap = getattr(user, "access_profile", None)
            if ap and ap.level == "user":
                assigned_to_id = getattr(obj, "assigned_to_id", None)
                if assigned_to_id is not None and assigned_to_id != user.id:
                    self.message = "غير مصرح: هذا الطلب ليس ضمن المهام المكلّف بها."
                    return False
            return True

        # owner (VerificationRequest) / owner (VerifiedBadge)
        requester_id = getattr(obj, "requester_id", None)
        if requester_id is not None and requester_id == user.id:
            return True

        owner_user_id = getattr(obj, "user_id", None)
        if owner_user_id is not None and owner_user_id == user.id:
            return True

        return self._has_backoffice_access(request)
