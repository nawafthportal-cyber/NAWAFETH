from __future__ import annotations

from rest_framework.permissions import BasePermission

from apps.backoffice.permissions import BackofficeDashboardMixin


class IsRequesterOrBackofficeSupport(BackofficeDashboardMixin, BasePermission):
    """
    - العميل يرى/يعدل تذكرته (ضمن حدود معينة)
    - فريق الدعم يتطلب Backoffice access للوحة support
    """
    dashboard_code = "support"

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False
        if self._is_backoffice_request(request):
            return self._has_backoffice_access(request)
        return True

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
