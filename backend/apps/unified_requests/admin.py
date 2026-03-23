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
    list_select_related = ("requester", "assigned_user")


@admin.register(UnifiedRequestMetadata)
class UnifiedRequestMetadataAdmin(admin.ModelAdmin):
    list_display = ("id", "request", "updated_by", "updated_at")
    search_fields = ("request__code", "request__summary", "updated_by__phone", "updated_by__username")
    ordering = ("-id",)
    list_select_related = ("request", "updated_by")
    readonly_fields = ("updated_at",)


@admin.register(UnifiedRequestAssignmentLog)
class UnifiedRequestAssignmentLogAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "request",
        "from_team_code",
        "to_team_code",
        "from_user",
        "to_user",
        "changed_by",
        "created_at",
    )
    list_filter = ("from_team_code", "to_team_code")
    search_fields = ("request__code", "note", "from_user__phone", "to_user__phone", "changed_by__phone")
    ordering = ("-id",)
    list_select_related = ("request", "from_user", "to_user", "changed_by")
    readonly_fields = ("created_at",)


@admin.register(UnifiedRequestStatusLog)
class UnifiedRequestStatusLogAdmin(admin.ModelAdmin):
    list_display = ("id", "request", "from_status", "to_status", "changed_by", "created_at")
    list_filter = ("from_status", "to_status")
    search_fields = ("request__code", "note", "changed_by__phone", "changed_by__username")
    ordering = ("-id",)
    list_select_related = ("request", "changed_by")
    readonly_fields = ("created_at",)
