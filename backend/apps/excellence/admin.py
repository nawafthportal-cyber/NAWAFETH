from django.contrib import admin

from .models import ExcellenceBadgeAward, ExcellenceBadgeCandidate, ExcellenceBadgeType


@admin.register(ExcellenceBadgeType)
class ExcellenceBadgeTypeAdmin(admin.ModelAdmin):
    list_display = ("code", "name_ar", "review_cycle_days", "is_active", "sort_order")
    list_filter = ("is_active",)
    search_fields = ("code", "name_ar")


@admin.register(ExcellenceBadgeCandidate)
class ExcellenceBadgeCandidateAdmin(admin.ModelAdmin):
    list_display = (
        "provider",
        "badge_type",
        "rank_position",
        "followers_count",
        "completed_orders_count",
        "rating_avg",
        "status",
        "evaluation_period_end",
    )
    list_filter = ("badge_type", "status", "evaluation_period_end")
    search_fields = ("provider__display_name", "provider__user__phone")
    raw_id_fields = ("provider", "badge_type", "category", "subcategory", "reviewed_by")


@admin.register(ExcellenceBadgeAward)
class ExcellenceBadgeAwardAdmin(admin.ModelAdmin):
    list_display = (
        "provider",
        "badge_type",
        "rank_position",
        "valid_until",
        "is_active",
        "approved_by",
    )
    list_filter = ("badge_type", "is_active")
    search_fields = ("provider__display_name", "provider__user__phone")
    raw_id_fields = ("provider", "badge_type", "candidate", "approved_by", "revoked_by")
