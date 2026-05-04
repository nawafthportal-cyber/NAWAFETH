from django.contrib import admin

from apps.core.admin_mixins import HiddenFromAdminIndexMixin

from .models import (
    Category,
    ProviderCategory,
    ProviderContentComment,
    ProviderContentShare,
    ProviderFollow,
    ProviderLike,
    ProviderPortfolioItem,
    ProviderPortfolioLike,
    ProviderPortfolioSave,
    ProviderProfile,
    ProviderService,
    ProviderSpotlightItem,
    ProviderSpotlightLike,
    ProviderSpotlightSave,
    SaudiCity,
    SaudiRegion,
    SubCategory,
)


@admin.register(Category)
class CategoryAdmin(admin.ModelAdmin):
    list_display = ("id", "name", "is_active")
    list_filter = ("is_active",)
    search_fields = ("name",)
    ordering = ("name",)


@admin.register(SubCategory)
class SubCategoryAdmin(admin.ModelAdmin):
    list_display = ("id", "name", "category", "requires_geo_scope", "allows_urgent_requests", "is_active")
    list_filter = ("is_active", "category", "requires_geo_scope", "allows_urgent_requests")
    search_fields = ("name", "category__name")
    ordering = ("category__name", "name")
    list_select_related = ("category",)


@admin.register(ProviderProfile)
class ProviderProfileAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "display_name",
        "provider_type",
        "user",
        "region",
        "city",
        "accepts_urgent",
        "rating_avg",
        "rating_count",
        "is_verified_blue",
        "is_verified_green",
        "updated_at",
    )
    list_filter = (
        "provider_type",
        "accepts_urgent",
        "is_verified_blue",
        "is_verified_green",
        "region",
        "city",
    )
    search_fields = ("display_name", "region", "city", "user__phone", "user__username", "seo_slug")
    ordering = ("-id",)
    list_select_related = ("user",)
    readonly_fields = ("created_at", "updated_at")


@admin.register(SaudiRegion)
class SaudiRegionAdmin(admin.ModelAdmin):
    list_display = ("id", "name_ar", "is_active", "sort_order")
    list_filter = ("is_active",)
    search_fields = ("name_ar",)
    ordering = ("sort_order", "name_ar", "id")


@admin.register(SaudiCity)
class SaudiCityAdmin(admin.ModelAdmin):
    list_display = ("id", "name_ar", "region", "is_active", "sort_order")
    list_filter = ("is_active", "region")
    search_fields = ("name_ar", "region__name_ar")
    ordering = ("region__sort_order", "sort_order", "name_ar", "id")
    list_select_related = ("region",)


@admin.register(ProviderCategory)
class ProviderCategoryAdmin(admin.ModelAdmin):
    list_display = ("id", "provider", "subcategory", "accepts_urgent")
    list_filter = ("accepts_urgent", "subcategory__category", "subcategory")
    search_fields = ("provider__display_name", "provider__user__phone", "subcategory__name")
    ordering = ("-id",)
    list_select_related = ("provider", "provider__user", "subcategory", "subcategory__category")


@admin.register(ProviderService)
class ProviderServiceAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "provider",
        "subcategory",
        "title",
        "price_from",
        "price_to",
        "price_unit",
        "is_active",
        "updated_at",
    )
    list_filter = ("is_active", "price_unit", "subcategory__category", "subcategory")
    search_fields = ("title", "provider__display_name", "provider__user__phone", "subcategory__name")
    ordering = ("-updated_at", "-id")
    list_select_related = ("provider", "provider__user", "subcategory", "subcategory__category")
    readonly_fields = ("created_at", "updated_at")


@admin.register(ProviderPortfolioItem)
class ProviderPortfolioItemAdmin(admin.ModelAdmin):
    list_display = ("id", "provider", "file_type", "caption", "created_at")
    list_filter = ("file_type",)
    search_fields = ("provider__display_name", "provider__user__phone", "caption")
    ordering = ("-id",)
    list_select_related = ("provider", "provider__user")
    readonly_fields = ("created_at",)


@admin.register(ProviderSpotlightItem)
class ProviderSpotlightItemAdmin(admin.ModelAdmin):
    list_display = ("id", "provider", "file_type", "caption", "created_at")
    list_filter = ("file_type",)
    search_fields = ("provider__display_name", "provider__user__phone", "caption")
    ordering = ("-id",)
    list_select_related = ("provider", "provider__user")
    readonly_fields = ("created_at",)


@admin.register(ProviderPortfolioLike)
class ProviderPortfolioLikeAdmin(HiddenFromAdminIndexMixin, admin.ModelAdmin):
    list_display = ("id", "user", "item", "role_context", "created_at")
    list_filter = ("role_context",)
    search_fields = ("user__phone", "user__username", "item__provider__display_name")
    ordering = ("-id",)
    list_select_related = ("user", "item", "item__provider")
    readonly_fields = ("created_at",)


@admin.register(ProviderPortfolioSave)
class ProviderPortfolioSaveAdmin(HiddenFromAdminIndexMixin, admin.ModelAdmin):
    list_display = ("id", "user", "item", "role_context", "created_at")
    list_filter = ("role_context",)
    search_fields = ("user__phone", "user__username", "item__provider__display_name")
    ordering = ("-id",)
    list_select_related = ("user", "item", "item__provider")
    readonly_fields = ("created_at",)


@admin.register(ProviderSpotlightLike)
class ProviderSpotlightLikeAdmin(HiddenFromAdminIndexMixin, admin.ModelAdmin):
    list_display = ("id", "user", "item", "role_context", "created_at")
    list_filter = ("role_context",)
    search_fields = ("user__phone", "user__username", "item__provider__display_name")
    ordering = ("-id",)
    list_select_related = ("user", "item", "item__provider")
    readonly_fields = ("created_at",)


@admin.register(ProviderSpotlightSave)
class ProviderSpotlightSaveAdmin(HiddenFromAdminIndexMixin, admin.ModelAdmin):
    list_display = ("id", "user", "item", "role_context", "created_at")
    list_filter = ("role_context",)
    search_fields = ("user__phone", "user__username", "item__provider__display_name")
    ordering = ("-id",)
    list_select_related = ("user", "item", "item__provider")
    readonly_fields = ("created_at",)


@admin.register(ProviderFollow)
class ProviderFollowAdmin(HiddenFromAdminIndexMixin, admin.ModelAdmin):
    list_display = ("id", "user", "provider", "role_context", "created_at")
    list_filter = ("role_context",)
    search_fields = ("user__phone", "user__username", "provider__display_name", "provider__user__phone")
    ordering = ("-id",)
    list_select_related = ("user", "provider", "provider__user")
    readonly_fields = ("created_at",)


@admin.register(ProviderLike)
class ProviderLikeAdmin(HiddenFromAdminIndexMixin, admin.ModelAdmin):
    list_display = ("id", "user", "provider", "role_context", "created_at")
    list_filter = ("role_context",)
    search_fields = ("user__phone", "user__username", "provider__display_name", "provider__user__phone")
    ordering = ("-id",)
    list_select_related = ("user", "provider", "provider__user")
    readonly_fields = ("created_at",)


@admin.register(ProviderContentShare)
class ProviderContentShareAdmin(admin.ModelAdmin):
    list_display = ("id", "provider", "user", "content_type", "channel", "created_at")
    list_filter = ("content_type", "channel")
    search_fields = ("provider__display_name", "provider__user__phone", "user__phone", "user__username")
    ordering = ("-id",)
    list_select_related = ("provider", "provider__user", "user")
    readonly_fields = ("created_at",)


@admin.register(ProviderContentComment)
class ProviderContentCommentAdmin(admin.ModelAdmin):
    list_display = ("id", "provider", "user", "body_preview", "is_approved", "created_at")
    list_filter = ("is_approved",)
    search_fields = ("provider__display_name", "provider__user__phone", "user__phone", "user__username", "body")
    ordering = ("-id",)
    list_select_related = ("provider", "provider__user", "user")
    readonly_fields = ("created_at",)

    @admin.display(description="معاينة")
    def body_preview(self, obj):
        return (obj.body or "")[:80]
