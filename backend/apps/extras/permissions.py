from __future__ import annotations

from rest_framework.permissions import BasePermission, SAFE_METHODS


class IsOwnerOrBackofficeExtras(BasePermission):
    """
    - مستخدم التطبيق: مسموح له على endpoints العميل العادية (مع تقييد queryset في views)
    - Backoffice: يتطلب وصول لوحة extras
    - QA: قراءة فقط
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

        return ap.is_allowed("extras")

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False
        if self._is_backoffice_request(request):
            return self._has_backoffice_access(request)
        return True

    def has_object_permission(self, request, view, obj):
        if self._is_backoffice_request(request):
            return self._has_backoffice_access(request)

        user = request.user
        owner_id = getattr(obj, "user_id", None)
        if owner_id is not None:
            return owner_id == getattr(user, "id", None)
        return True
