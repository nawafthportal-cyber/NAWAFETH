from django.contrib import admin

from .models import SiteContentBlock, SiteLegalDocument, SiteLinks


@admin.register(SiteContentBlock)
class SiteContentBlockAdmin(admin.ModelAdmin):
    list_display = ("key", "title_ar", "is_active", "updated_at", "updated_by")
    list_filter = ("is_active",)
    search_fields = ("key", "title_ar", "body_ar")


@admin.register(SiteLegalDocument)
class SiteLegalDocumentAdmin(admin.ModelAdmin):
    list_display = ("doc_type", "version", "is_active", "published_at", "uploaded_at", "uploaded_by")
    list_filter = ("doc_type", "is_active")
    search_fields = ("doc_type", "version")


@admin.register(SiteLinks)
class SiteLinksAdmin(admin.ModelAdmin):
    list_display = ("id", "email", "updated_at", "updated_by")
