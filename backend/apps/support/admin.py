from django.contrib import admin
from .models import SupportTicket, SupportAttachment, SupportComment, SupportTeam, SupportStatusLog


@admin.register(SupportTeam)
class SupportTeamAdmin(admin.ModelAdmin):
    list_display = ("code", "name_ar", "is_active", "sort_order")
    list_filter = ("is_active",)
    search_fields = ("code", "name_ar")
    ordering = ("sort_order", "code")


class SupportAttachmentInline(admin.TabularInline):
    model = SupportAttachment
    extra = 0


class SupportCommentInline(admin.TabularInline):
    model = SupportComment
    extra = 0


class SupportStatusLogInline(admin.TabularInline):
    model = SupportStatusLog
    extra = 0
    readonly_fields = ("from_status", "to_status", "changed_by", "note", "created_at")


@admin.register(SupportTicket)
class SupportTicketAdmin(admin.ModelAdmin):
    list_display = ("code", "ticket_type", "status", "priority", "requester", "assigned_team", "assigned_to", "created_at")
    list_filter = ("ticket_type", "status", "priority")
    search_fields = ("code", "description", "requester__phone")
    inlines = [SupportAttachmentInline, SupportCommentInline, SupportStatusLogInline]
    ordering = ("-id",)
    list_select_related = ("requester", "assigned_team", "assigned_to")


@admin.register(SupportAttachment)
class SupportAttachmentAdmin(admin.ModelAdmin):
    list_display = ("id", "ticket", "uploaded_by", "created_at")
    search_fields = ("ticket__code", "uploaded_by__phone", "uploaded_by__username")
    ordering = ("-id",)
    list_select_related = ("ticket", "uploaded_by")
    readonly_fields = ("created_at",)


@admin.register(SupportComment)
class SupportCommentAdmin(admin.ModelAdmin):
    list_display = ("id", "ticket", "is_internal", "created_by", "created_at")
    list_filter = ("is_internal",)
    search_fields = ("ticket__code", "text", "created_by__phone", "created_by__username")
    ordering = ("-id",)
    list_select_related = ("ticket", "created_by")
    readonly_fields = ("created_at",)


@admin.register(SupportStatusLog)
class SupportStatusLogAdmin(admin.ModelAdmin):
    list_display = ("id", "ticket", "from_status", "to_status", "changed_by", "created_at")
    list_filter = ("from_status", "to_status")
    search_fields = ("ticket__code", "note", "changed_by__phone", "changed_by__username")
    ordering = ("-id",)
    list_select_related = ("ticket", "changed_by")
    readonly_fields = ("created_at",)
