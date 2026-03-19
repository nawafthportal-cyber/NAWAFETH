from django.contrib import admin
from .models import ExtraPurchase, ServiceCatalog


@admin.register(ServiceCatalog)
class ServiceCatalogAdmin(admin.ModelAdmin):
    list_display = ("sku", "title", "price", "currency", "is_active", "sort_order", "updated_at")
    list_filter = ("is_active", "currency")
    search_fields = ("sku", "title")
    list_editable = ("price", "is_active", "sort_order")
    ordering = ("sort_order", "sku")


@admin.register(ExtraPurchase)
class ExtraPurchaseAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "sku", "extra_type", "status", "subtotal", "start_at", "end_at", "credits_total", "credits_used")
    list_filter = ("extra_type", "status", "sku")
    search_fields = ("user__phone", "sku", "title")
    ordering = ("-id",)
