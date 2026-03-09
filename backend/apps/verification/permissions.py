from __future__ import annotations

from rest_framework.permissions import BasePermission

from apps.backoffice.permissions import BackofficeDashboardMixin
from apps.providers.eligibility import provider_access_state


class IsOwnerOrBackofficeVerify(BackofficeDashboardMixin, BasePermission):
    """
    - المالك يرى طلبه
    - فريق التوثيق يتطلب وصول لوحة verify
    - QA عرض فقط
    """
    dashboard_code = "verify"

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
            if not self._check_assigned_to(request, obj):
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
