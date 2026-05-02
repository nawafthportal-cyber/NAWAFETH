from django.contrib import admin
from django.core.exceptions import PermissionDenied
from django.db.models import Q
from django.utils import timezone
from .models import AccessPermission, Dashboard, UserAccessProfile


@admin.register(Dashboard)
class DashboardAdmin(admin.ModelAdmin):
    list_display = ("code", "name_ar", "name_en", "is_active", "sort_order")
    list_filter = ("is_active",)
    search_fields = ("code", "name_ar", "name_en")
    ordering = ("sort_order", "code")


@admin.register(UserAccessProfile)
class UserAccessProfileAdmin(admin.ModelAdmin):
    list_display = ("user", "level", "expires_at", "revoked_at", "created_at")
    list_filter = ("level",)
    search_fields = ("user__phone", "user__email")
    filter_horizontal = ("allowed_dashboards", "granted_permissions")

    @staticmethod
    def _is_active_admin(ap: UserAccessProfile) -> bool:
        if ap.level != "admin":
            return False
        if ap.revoked_at is not None:
            return False
        if ap.expires_at and ap.expires_at <= timezone.now():
            return False
        return True

    @staticmethod
    def _active_admin_count() -> int:
        now = timezone.now()
        return UserAccessProfile.objects.filter(
            level="admin",
            revoked_at__isnull=True,
        ).filter(
            Q(expires_at__isnull=True) | Q(expires_at__gt=now),
        ).count()

    def save_model(self, request, obj, form, change):
        # Prevent demoting/disabling the last active admin in admin panel.
        if change:
            current = UserAccessProfile.objects.filter(pk=obj.pk).first()
            if current and self._is_active_admin(current):
                will_still_be_active_admin = (
                    obj.level == "admin"
                    and obj.revoked_at is None
                    and (obj.expires_at is None or obj.expires_at > timezone.now())
                )
                if not will_still_be_active_admin and self._active_admin_count() <= 1:
                    raise PermissionDenied("لا يمكن خفض/تعطيل آخر Admin فعّال في المنصة.")
        super().save_model(request, obj, form, change)

    def delete_model(self, request, obj):
        if self._is_active_admin(obj) and self._active_admin_count() <= 1:
            raise PermissionDenied("لا يمكن حذف آخر Admin فعّال في المنصة.")
        super().delete_model(request, obj)

    def delete_queryset(self, request, queryset):
        now = timezone.now()
        active_admin_in_queryset = queryset.filter(
            level="admin",
            revoked_at__isnull=True,
        ).filter(
            Q(expires_at__isnull=True) | Q(expires_at__gt=now),
        ).count()
        if active_admin_in_queryset > 0:
            remaining = self._active_admin_count() - active_admin_in_queryset
            if remaining < 1:
                raise PermissionDenied("لا يمكن حذف آخر Admin فعّال في المنصة.")
        super().delete_queryset(request, queryset)


@admin.register(AccessPermission)
class AccessPermissionAdmin(admin.ModelAdmin):
    list_display = ("code", "name_ar", "name_en", "dashboard_code", "is_active", "sort_order")
    list_filter = ("dashboard_code", "is_active")
    search_fields = ("code", "name_ar", "name_en", "description", "description_en")
    ordering = ("sort_order", "code")
