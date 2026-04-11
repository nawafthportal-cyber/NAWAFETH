from django.contrib import admin

from .models import ExtraPurchase, ExtrasBundlePricingRule, ServiceCatalog
from .option_catalog import option_label_for, section_title_for


@admin.register(ServiceCatalog)
class ServiceCatalogAdmin(admin.ModelAdmin):
    list_display = ("sku", "title", "price", "currency", "is_active", "sort_order", "updated_at")
    list_filter = ("is_active", "currency")
    search_fields = ("sku", "title")
    list_editable = ("price", "is_active", "sort_order")
    ordering = ("sort_order", "sku")


@admin.register(ExtrasBundlePricingRule)
class ExtrasBundlePricingRuleAdmin(admin.ModelAdmin):
    list_display = (
        "section_title",
        "option_key",
        "option_label",
        "fee",
        "currency",
        "apply_year_multiplier",
        "is_active",
        "sort_order",
    )
    list_filter = ("section_key", "is_active", "apply_year_multiplier", "currency")
    search_fields = ("option_key",)
    list_editable = ("fee", "currency", "apply_year_multiplier", "is_active", "sort_order")
    ordering = ("section_key", "sort_order", "option_key")

    @admin.display(description="القسم")
    def section_title(self, obj):
        return section_title_for(obj.section_key)

    @admin.display(description="عنوان البند")
    def option_label(self, obj):
        return option_label_for(obj.section_key, obj.option_key)


@admin.register(ExtraPurchase)
class ExtraPurchaseAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "sku", "extra_type", "status", "subtotal", "start_at", "end_at", "credits_total", "credits_used")
    list_filter = ("extra_type", "status", "sku")
    search_fields = ("user__phone", "sku", "title")
    ordering = ("-id",)
