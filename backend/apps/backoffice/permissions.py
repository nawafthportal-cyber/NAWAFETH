from __future__ import annotations

from rest_framework.permissions import BasePermission, SAFE_METHODS

from apps.dashboard.access import active_access_profile_for_user, dashboard_portal_eligible


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
        ap = active_access_profile_for_user(request.user)
        if not ap:
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
        if not user or not user.is_authenticated or not getattr(user, "is_active", False):
            return False
        if not dashboard_portal_eligible(user):
            self.message = "هذا الحساب لا يملك صلاحية تشغيل فعّالة."
            return False

        access_profile = active_access_profile_for_user(user)
        if not access_profile:
            return False

        # QA => قراءة فقط
        if access_profile.is_readonly() and request.method not in SAFE_METHODS:
            self.message = "حساب QA يسمح بالعرض فقط."
            return False

        return True
