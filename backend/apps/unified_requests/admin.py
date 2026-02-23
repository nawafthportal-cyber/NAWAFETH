from django.contrib import admin

from .models import (
    UnifiedRequest,
    UnifiedRequestMetadata,
    UnifiedRequestAssignmentLog,
    UnifiedRequestStatusLog,
)


class UnifiedRequestMetadataInline(admin.StackedInline):
    model = UnifiedRequestMetadata
    extra = 0


class UnifiedRequestAssignmentLogInline(admin.TabularInline):
    model = UnifiedRequestAssignmentLog
    extra = 0
    readonly_fields = ("from_team_code", "to_team_code", "from_user", "to_user", "changed_by", "note", "created_at")


class UnifiedRequestStatusLogInline(admin.TabularInline):
    model = UnifiedRequestStatusLog
    extra = 0
    readonly_fields = ("from_status", "to_status", "changed_by", "note", "created_at")


@admin.register(UnifiedRequest)
class UnifiedRequestAdmin(admin.ModelAdmin):
    list_display = ("code", "request_type", "status", "priority", "requester", "assigned_user", "created_at")
    list_filter = ("request_type", "status", "priority")
    search_fields = ("code", "requester__phone", "summary", "source_app", "source_model", "source_object_id")
    ordering = ("-id",)
    inlines = [UnifiedRequestMetadataInline, UnifiedRequestStatusLogInline, UnifiedRequestAssignmentLogInline]
