from __future__ import annotations

from rest_framework.permissions import BasePermission

from apps.backoffice.permissions import BackofficeDashboardMixin


class IsOwnerOrBackofficePromo(BackofficeDashboardMixin, BasePermission):
    """
    - المالك يرى طلبه
    - فريق الإعلانات يتطلب وصول لوحة promo
    - QA عرض فقط
    """
    dashboard_code = "promo"

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False
        if self._is_backoffice_request(request):
            return self._has_backoffice_access(request)
        try:
            provider_profile = user.provider_profile
        except Exception:
            provider_profile = None
        return provider_profile is not None

    def has_object_permission(self, request, view, obj):
        if self._is_backoffice_request(request):
            if not self._has_backoffice_access(request):
                return False
            if not self._check_assigned_to(request, obj):
                return False
            return True

        if obj.requester_id == request.user.id:
            return True

        return self._has_backoffice_access(request)
