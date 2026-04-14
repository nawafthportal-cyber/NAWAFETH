from django.contrib import admin

from apps.core.admin_mixins import HiddenFromAdminIndexMixin

from .models import (
    ExtrasPortalFinanceSettings,
    ExtrasPortalScheduledMessage,
    ExtrasPortalScheduledMessageRecipient,
    ExtrasPortalSubscription,
    LoyaltyMembership,
    LoyaltyProgram,
    LoyaltyTransaction,
    ProviderPotentialClient,
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
class ExtrasPortalScheduledMessageRecipientAdmin(HiddenFromAdminIndexMixin, admin.ModelAdmin):
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


@admin.register(ProviderPotentialClient)
class ProviderPotentialClientAdmin(admin.ModelAdmin):
    list_display = ("id", "provider", "user", "source", "created_at")
    list_filter = ("source",)
    search_fields = ("provider__display_name", "provider__user__phone", "user__phone", "user__username")
    ordering = ("-id",)
    list_select_related = ("provider", "provider__user", "user")
    readonly_fields = ("created_at",)


@admin.register(LoyaltyProgram)
class LoyaltyProgramAdmin(admin.ModelAdmin):
    list_display = ("id", "provider", "name", "points_per_completed_request", "is_active", "created_at")
    list_filter = ("is_active",)
    search_fields = ("provider__display_name", "provider__user__phone", "name")
    ordering = ("-id",)
    list_select_related = ("provider", "provider__user")
    readonly_fields = ("created_at", "updated_at")


@admin.register(LoyaltyMembership)
class LoyaltyMembershipAdmin(admin.ModelAdmin):
    list_display = ("id", "program", "user", "points_balance", "total_earned", "total_redeemed", "joined_at")
    search_fields = ("program__provider__display_name", "user__phone", "user__username")
    ordering = ("-id",)
    list_select_related = ("program", "program__provider", "user")
    readonly_fields = ("joined_at", "updated_at")


@admin.register(LoyaltyTransaction)
class LoyaltyTransactionAdmin(HiddenFromAdminIndexMixin, admin.ModelAdmin):
    list_display = ("id", "membership", "transaction_type", "points", "description", "created_at")
    list_filter = ("transaction_type",)
    search_fields = ("membership__user__phone", "membership__user__username", "description")
    ordering = ("-id",)
    list_select_related = ("membership", "membership__user", "membership__program")
    readonly_fields = ("created_at",)
