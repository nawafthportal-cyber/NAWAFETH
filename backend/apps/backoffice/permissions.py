from __future__ import annotations

from rest_framework.permissions import BasePermission, SAFE_METHODS

from apps.dashboard.access import is_active_access_profile


class BackofficeDashboardMixin:
    """Shared helpers for permissions that guard backoffice + client endpoints.

    Subclasses set ``dashboard_code`` to the dashboard key (e.g. "verify",
    "support", "promo", "extras", "subs").
    """

    dashboard_code: str = ""
    message: str = "غير مصرح."

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
        return ap.is_allowed(self.dashboard_code)

    def _check_assigned_to(self, request, obj) -> bool:
        """For user-level staff, enforce assigned_to boundary."""
        ap = getattr(request.user, "access_profile", None)
        if ap and ap.level == "user":
            assigned_to_id = getattr(obj, "assigned_to_id", None)
            if assigned_to_id is not None and assigned_to_id != request.user.id:
                self.message = "غير مصرح: هذا العنصر ليس ضمن المهام المكلّف بها."
                return False
        return True


class BackofficeAccessPermission(BasePermission):
    """
    صلاحيات Backoffice:
    - يجب أن يكون المستخدم authenticated
    - يجب أن يملك access_profile صالح
    - إذا QA => يسمح فقط بالقراءة
    - يمنع الدخول إذا revoked أو expired
    """

    message = "لا تملك صلاحية الوصول لهذه اللوحة."

    def has_permission(self, request, view) -> bool:
        user = getattr(request, "user", None)
        if not user or not user.is_authenticated:
            return False
        if not (getattr(user, "is_staff", False) or getattr(user, "is_superuser", False)):
            self.message = "هذا الحساب ليس حساب تشغيل."
            return False

        # staff بدون access_profile لا نعطيه صلاحية تلقائية هنا
        access_profile = getattr(user, "access_profile", None)
        if not access_profile:
            return False

        if not is_active_access_profile(access_profile):
            self.message = "صلاحيتك منتهية أو تم إيقافها."
            return False

        # QA => قراءة فقط
        if access_profile.is_readonly() and request.method not in SAFE_METHODS:
            self.message = "حساب QA يسمح بالعرض فقط."
            return False

        return True
