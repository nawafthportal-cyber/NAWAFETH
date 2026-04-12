from django.contrib import admin

from .models import AuditLog


@admin.register(AuditLog)
class AuditLogAdmin(admin.ModelAdmin):
    list_display = ("id", "action", "actor", "reference_type", "reference_id", "ip_address", "created_at")
    list_filter = ("action", "reference_type")
    search_fields = ("reference_id", "actor__phone", "ip_address", "user_agent")
    ordering = ("-id",)
    readonly_fields = (
        "actor",
        "action",
        "reference_type",
        "reference_id",
        "ip_address",
        "user_agent",
        "extra",
        "created_at",
    )

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
