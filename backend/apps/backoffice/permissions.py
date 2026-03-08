from __future__ import annotations

from rest_framework.permissions import BasePermission, SAFE_METHODS

from apps.dashboard.access import is_active_access_profile


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
