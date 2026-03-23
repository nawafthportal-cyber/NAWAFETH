from django.contrib import admin

from .models import (
    ExtrasPortalFinanceSettings,
    ExtrasPortalScheduledMessage,
    ExtrasPortalScheduledMessageRecipient,
    ExtrasPortalSubscription,
)


@admin.register(ExtrasPortalSubscription)
class ExtrasPortalSubscriptionAdmin(admin.ModelAdmin):
    list_display = ("id", "provider", "status", "plan_title", "started_at", "ends_at", "updated_at")
    list_filter = ("status",)
    search_fields = ("provider__display_name", "provider__user__phone", "provider__user__username", "plan_title")
    ordering = ("-updated_at",)
    readonly_fields = ("updated_at",)
    list_select_related = ("provider", "provider__user")


@admin.register(ExtrasPortalFinanceSettings)
class ExtrasPortalFinanceSettingsAdmin(admin.ModelAdmin):
    list_display = ("id", "provider", "bank_name", "account_name", "iban", "updated_at")
    search_fields = ("provider__display_name", "provider__user__phone", "bank_name", "account_name", "iban")
    ordering = ("-updated_at",)
    readonly_fields = ("updated_at",)
    list_select_related = ("provider", "provider__user")


@admin.register(ExtrasPortalScheduledMessage)
class ExtrasPortalScheduledMessageAdmin(admin.ModelAdmin):
    list_display = ("id", "provider", "status", "send_at", "created_by", "created_at", "sent_at")
    list_filter = ("status",)
    search_fields = ("provider__display_name", "provider__user__phone", "body", "error")
    ordering = ("-id",)
    readonly_fields = ("created_at", "sent_at")
    list_select_related = ("provider", "provider__user", "created_by")


@admin.register(ExtrasPortalScheduledMessageRecipient)
class ExtrasPortalScheduledMessageRecipientAdmin(admin.ModelAdmin):
    list_display = ("id", "scheduled_message", "user", "created_at")
    search_fields = (
        "scheduled_message__provider__display_name",
        "scheduled_message__provider__user__phone",
        "user__phone",
        "user__username",
    )
    ordering = ("-id",)
    readonly_fields = ("created_at",)
    list_select_related = ("scheduled_message", "user", "scheduled_message__provider", "scheduled_message__provider__user")
