from django.contrib import admin

from .models import HomeBanner, PromoAsset, PromoInquiryProfile, PromoPricingRule, PromoRequest, PromoRequestItem


class PromoAssetInline(admin.TabularInline):
    model = PromoAsset
    extra = 0


class PromoRequestItemInline(admin.TabularInline):
    model = PromoRequestItem
    extra = 0


@admin.register(PromoRequest)
class PromoRequestAdmin(admin.ModelAdmin):
    list_display = ("code", "requester", "ad_type", "status", "ops_status", "start_at", "end_at", "subtotal", "invoice", "created_at")
    list_filter = ("ad_type", "status", "ops_status")
    search_fields = ("code", "title", "requester__phone")
    ordering = ("-id",)
    inlines = [PromoRequestItemInline, PromoAssetInline]


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
