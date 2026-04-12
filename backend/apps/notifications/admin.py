from django.contrib import admin

from apps.core.admin_mixins import HiddenFromAdminIndexMixin

from .models import Notification, DeviceToken, EventLog, NotificationPreference


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "title", "kind", "is_read", "is_pinned", "is_follow_up", "is_urgent", "created_at")
    list_filter = ("kind", "is_read", "is_pinned", "is_follow_up", "is_urgent")
    search_fields = ("title", "body", "user__phone")


@admin.register(DeviceToken)
class DeviceTokenAdmin(HiddenFromAdminIndexMixin, admin.ModelAdmin):
    list_display = ("id", "user", "platform", "masked_token", "is_active", "last_seen_at", "created_at")
    list_filter = ("platform", "is_active")
    search_fields = ("user__phone", "user__username")
    readonly_fields = ("user", "platform", "masked_token", "last_seen_at", "created_at")
    fields = ("user", "platform", "is_active", "masked_token", "last_seen_at", "created_at")
    exclude = ("token",)

    @admin.display(description="Token")
    def masked_token(self, obj):
        token = str(getattr(obj, "token", "") or "")
        if not token:
            return "-"
        if len(token) <= 8:
            return "*" * len(token)
        return f"{token[:4]}...{token[-4:]}"

    def has_add_permission(self, request):
        return False


@admin.register(EventLog)
class EventLogAdmin(HiddenFromAdminIndexMixin, admin.ModelAdmin):
    list_display = ("id", "event_type", "actor", "target_user", "request_id", "created_at")
    list_filter = ("event_type",)
    search_fields = ("actor__phone", "target_user__phone", "request_id", "offer_id", "message_id")
    ordering = ("-id",)
    readonly_fields = ("event_type", "actor", "target_user", "request_id", "offer_id", "message_id", "meta", "created_at")

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(NotificationPreference)
class NotificationPreferenceAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "key", "enabled", "tier", "updated_at")
    list_filter = ("tier", "enabled")
    search_fields = ("user__phone", "key")
