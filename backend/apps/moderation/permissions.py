from __future__ import annotations

from rest_framework.permissions import BasePermission

from apps.accounts.permissions import IsAtLeastPhoneOnly
from apps.backoffice.permissions import BackofficeDashboardMixin


class IsModerationReporterOrBackoffice(BackofficeDashboardMixin, BasePermission):
    dashboard_code = "moderation"
    message = "غير مصرح للوصول إلى حالات الإشراف."

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False
        if self._is_backoffice_request(request):
            return self._has_backoffice_access(request)
        return IsAtLeastPhoneOnly().has_permission(request, view)

    def has_object_permission(self, request, view, obj):
        if self._is_backoffice_request(request):
            if not self._has_backoffice_access(request):
                return False
            return self._check_assigned_to(request, obj)
        if obj.reporter_id == request.user.id:
            return True
        return self._has_backoffice_access(request)


class IsBackofficeModeration(BackofficeDashboardMixin, BasePermission):
    dashboard_code = "moderation"
    message = "غير مصرح لإدارة حالات الإشراف."

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False
        return self._has_backoffice_access(request)
