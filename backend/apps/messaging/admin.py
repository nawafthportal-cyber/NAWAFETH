from django.contrib import admin

from apps.core.admin_mixins import HiddenFromAdminIndexMixin

from .models import Message, MessageRead, Thread, ThreadUserState


class MessageInline(admin.TabularInline):
    model = Message
    extra = 0
    readonly_fields = ("sender", "body", "attachment", "attachment_type", "attachment_name", "created_at")
    can_delete = False
    show_change_link = True


@admin.register(Thread)
class ThreadAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "request",
        "is_direct",
        "is_system_thread",
        "system_thread_key",
        "participant_1",
        "participant_2",
        "reply_restricted_to",
        "context_mode",
        "created_at",
    )
    list_filter = ("is_direct", "is_system_thread", "context_mode")
    search_fields = ("request__title", "participant_1__phone", "participant_2__phone")
    ordering = ("-id",)
    list_select_related = ("request", "participant_1", "participant_2")
    inlines = [MessageInline]


@admin.register(Message)
class MessageAdmin(admin.ModelAdmin):
    list_display = ("id", "thread", "sender", "is_system_generated", "sender_team_name", "attachment_type", "created_at")
    list_filter = ("is_system_generated", "attachment_type")
    search_fields = ("body", "sender__phone", "sender__username")
    ordering = ("-id",)
    list_select_related = ("thread", "sender")


@admin.register(MessageRead)
class MessageReadAdmin(HiddenFromAdminIndexMixin, admin.ModelAdmin):
    list_display = ("id", "message", "user", "read_at")
    search_fields = ("message__body", "user__phone", "user__username")
    ordering = ("-id",)
    list_select_related = ("message", "user")


@admin.register(ThreadUserState)
class ThreadUserStateAdmin(HiddenFromAdminIndexMixin, admin.ModelAdmin):
    list_display = (
        "id",
        "thread",
        "user",
        "is_favorite",
        "favorite_label",
        "client_label",
        "is_archived",
        "is_blocked",
        "updated_at",
    )
    list_filter = ("is_favorite", "is_archived", "is_blocked", "favorite_label", "client_label")
    search_fields = ("thread__request__title", "user__phone", "user__username")
    ordering = ("-id",)
    list_select_related = ("thread", "user")
    readonly_fields = ("created_at", "updated_at")
