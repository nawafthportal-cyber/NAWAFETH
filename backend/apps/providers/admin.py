from django.contrib import admin

from .models import (
    Category,
    ProviderCategory,
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
    list_display = ("id", "name", "category", "is_active")
    list_filter = ("is_active", "category")
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
        "city",
    )
    search_fields = ("display_name", "city", "user__phone", "user__username", "seo_slug")
    ordering = ("-id",)
    list_select_related = ("user",)
    readonly_fields = ("created_at", "updated_at")


@admin.register(ProviderCategory)
class ProviderCategoryAdmin(admin.ModelAdmin):
    list_display = ("id", "provider", "subcategory")
    list_filter = ("subcategory__category", "subcategory")
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
class ProviderPortfolioLikeAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "item", "role_context", "created_at")
    list_filter = ("role_context",)
    search_fields = ("user__phone", "user__username", "item__provider__display_name")
    ordering = ("-id",)
    list_select_related = ("user", "item", "item__provider")
    readonly_fields = ("created_at",)


@admin.register(ProviderPortfolioSave)
class ProviderPortfolioSaveAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "item", "role_context", "created_at")
    list_filter = ("role_context",)
    search_fields = ("user__phone", "user__username", "item__provider__display_name")
    ordering = ("-id",)
    list_select_related = ("user", "item", "item__provider")
    readonly_fields = ("created_at",)


@admin.register(ProviderSpotlightLike)
class ProviderSpotlightLikeAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "item", "role_context", "created_at")
    list_filter = ("role_context",)
    search_fields = ("user__phone", "user__username", "item__provider__display_name")
    ordering = ("-id",)
    list_select_related = ("user", "item", "item__provider")
    readonly_fields = ("created_at",)


@admin.register(ProviderSpotlightSave)
class ProviderSpotlightSaveAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "item", "role_context", "created_at")
    list_filter = ("role_context",)
    search_fields = ("user__phone", "user__username", "item__provider__display_name")
    ordering = ("-id",)
    list_select_related = ("user", "item", "item__provider")
    readonly_fields = ("created_at",)


@admin.register(ProviderFollow)
class ProviderFollowAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "provider", "role_context", "created_at")
    list_filter = ("role_context",)
    search_fields = ("user__phone", "user__username", "provider__display_name", "provider__user__phone")
    ordering = ("-id",)
    list_select_related = ("user", "provider", "provider__user")
    readonly_fields = ("created_at",)


@admin.register(ProviderLike)
class ProviderLikeAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "provider", "role_context", "created_at")
    list_filter = ("role_context",)
    search_fields = ("user__phone", "user__username", "provider__display_name", "provider__user__phone")
    ordering = ("-id",)
    list_select_related = ("user", "provider", "provider__user")
    readonly_fields = ("created_at",)
