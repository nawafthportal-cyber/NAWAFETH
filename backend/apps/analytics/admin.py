from django.contrib import admin

from .models import (
    AnalyticsEvent,
    CampaignDailyStats,
    ExtrasDailyStats,
    ProviderDailyStats,
    SubscriptionDailyStats,
)


@admin.register(AnalyticsEvent)
class AnalyticsEventAdmin(admin.ModelAdmin):
    list_display = ("id", "event_name", "channel", "surface", "source_app", "object_type", "object_id", "actor", "occurred_at")
    list_filter = ("channel", "event_name", "source_app", "object_type")
    search_fields = ("event_name", "surface", "source_app", "object_type", "object_id", "dedupe_key", "session_id")
    readonly_fields = ("created_at",)


@admin.register(ProviderDailyStats)
class ProviderDailyStatsAdmin(admin.ModelAdmin):
    list_display = (
        "day",
        "provider",
        "profile_views",
        "chat_starts",
        "requests_received",
        "requests_accepted",
        "requests_completed",
    )
    list_filter = ("day",)
    search_fields = ("provider__display_name", "provider__user__phone")


@admin.register(CampaignDailyStats)
class CampaignDailyStatsAdmin(admin.ModelAdmin):
    list_display = ("day", "campaign_key", "campaign_kind", "impressions", "clicks", "leads", "conversions", "ctr")
    list_filter = ("day", "campaign_kind", "source_app")
    search_fields = ("campaign_key", "label", "object_type", "object_id")


@admin.register(SubscriptionDailyStats)
class SubscriptionDailyStatsAdmin(admin.ModelAdmin):
    list_display = ("day", "plan_code", "tier", "checkouts_started", "activations", "renewals", "upgrades", "churns")
    list_filter = ("day", "tier")
    search_fields = ("plan_code", "plan_title")


@admin.register(ExtrasDailyStats)
class ExtrasDailyStatsAdmin(admin.ModelAdmin):
    list_display = ("day", "sku", "extra_type", "purchases", "activations", "consumptions", "credits_consumed")
    list_filter = ("day", "extra_type")
    search_fields = ("sku", "title")
