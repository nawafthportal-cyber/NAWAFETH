from django.contrib import admin

from apps.core.admin_mixins import HiddenFromAdminIndexMixin

from .models import (
    HomeBanner,
    PromoAdPrice,
    PromoAdType,
    PromoAsset,
    PromoInquiryProfile,
    PromoPricingRule,
    PromoRequest,
    PromoRequestItem,
    PromoServiceType,
)
from .validators import promo_asset_upload_limit_mb


class PromoAssetInline(admin.TabularInline):
    model = PromoAsset
    extra = 0
    readonly_fields = ("uploaded_by", "uploaded_at")


class PromoRequestItemInline(admin.TabularInline):
    model = PromoRequestItem
    extra = 0
    readonly_fields = ("subtotal", "duration_days", "pricing_rule_code", "created_at", "updated_at")


@admin.register(PromoRequest)
class PromoRequestAdmin(admin.ModelAdmin):
    list_display = ("code", "requester", "ad_type", "status", "ops_status", "start_at", "end_at", "subtotal", "invoice", "created_at")
    list_filter = ("ad_type", "status", "ops_status")
    search_fields = ("code", "title", "requester__phone")
    ordering = ("-id",)
    inlines = [PromoRequestItemInline, PromoAssetInline]
    readonly_fields = ("created_at", "updated_at", "reviewed_at", "activated_at", "ops_started_at", "ops_completed_at")
    list_select_related = ("requester", "assigned_to", "invoice")


@admin.register(HomeBanner)
class HomeBannerAdmin(admin.ModelAdmin):
    list_display = (
        "title",
        "media_type",
        "mobile_scale",
        "tablet_scale",
        "desktop_scale",
        "is_active",
        "display_order",
        "start_at",
        "end_at",
        "created_at",
    )
    list_filter = ("media_type", "is_active")
    search_fields = ("title",)
    ordering = ("display_order", "-created_at")


@admin.register(PromoPricingRule)
class PromoPricingRuleAdmin(admin.ModelAdmin):
    list_display = ("code", "service_type", "title", "unit", "amount", "is_active", "sort_order")
    list_filter = ("service_type", "unit", "is_active")
    search_fields = ("code", "title")
    ordering = ("sort_order", "id")


@admin.register(PromoInquiryProfile)
class PromoInquiryProfileAdmin(admin.ModelAdmin):
    list_display = ("ticket", "linked_request", "detailed_request_url", "updated_at")
    search_fields = ("ticket__code", "linked_request__code", "detailed_request_url")
    list_select_related = ("ticket", "linked_request")


@admin.register(PromoRequestItem)
class PromoRequestItemAdmin(HiddenFromAdminIndexMixin, admin.ModelAdmin):
    list_display = (
        "id",
        "request",
        "service_type",
        "title",
        "start_at",
        "end_at",
        "send_at",
        "subtotal",
        "duration_days",
        "sort_order",
    )
    list_filter = ("service_type", "search_scope", "search_position")
    search_fields = ("request__code", "title", "target_category", "target_city", "pricing_rule_code")
    ordering = ("request", "sort_order", "id")
    list_select_related = ("request", "target_provider", "target_portfolio_item")
    readonly_fields = ("created_at", "updated_at")


@admin.register(PromoAsset)
class PromoAssetAdmin(HiddenFromAdminIndexMixin, admin.ModelAdmin):
    list_display = (
        "id",
        "request",
        "item",
        "asset_type",
        "file_size_mb",
        "max_allowed_size_mb",
        "title",
        "uploaded_by",
        "uploaded_at",
    )
    list_filter = ("asset_type",)
    search_fields = ("request__code", "title", "uploaded_by__phone", "uploaded_by__username")
    ordering = ("-uploaded_at", "-id")
    list_select_related = ("request", "item", "uploaded_by")
    readonly_fields = ("uploaded_at",)

    def _requires_home_banner_dims(self, obj: PromoAsset) -> bool:
        item = getattr(obj, "item", None)
        if item is not None and str(getattr(item, "service_type", "") or "").strip() == PromoServiceType.HOME_BANNER:
            return True
        return str(getattr(getattr(obj, "request", None), "ad_type", "") or "").strip() == PromoAdType.BANNER_HOME

    def file_size_mb(self, obj: PromoAsset) -> str:
        size_bytes = int(getattr(getattr(obj, "file", None), "size", 0) or 0)
        size_mb = size_bytes / (1024 * 1024) if size_bytes else 0
        return f"{size_mb:.2f}"

    file_size_mb.short_description = "الحجم الفعلي (MB)"

    def max_allowed_size_mb(self, obj: PromoAsset) -> int:
        return promo_asset_upload_limit_mb(
            asset_type=str(getattr(obj, "asset_type", "") or ""),
            requires_home_banner_dims=self._requires_home_banner_dims(obj),
        )

    max_allowed_size_mb.short_description = "الحد المسموح (MB)"


@admin.register(PromoAdPrice)
class PromoAdPriceAdmin(admin.ModelAdmin):
    list_display = ("ad_type", "price_per_day", "is_active", "updated_at")
    list_filter = ("ad_type", "is_active")
    search_fields = ("ad_type",)
    ordering = ("ad_type",)
