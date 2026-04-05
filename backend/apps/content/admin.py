from django.contrib import admin
from django.utils.html import format_html

from .models import BrandingContentBlock, HomePageFallbackBannerBlock, SiteContentBlock, SiteLegalDocument, SiteLinks


BRANDING_KEYS = (
    "topbar_brand_logo",
    "topbar_brand_title",
    "topbar_brand_subtitle",
    "footer_brand_title",
    "footer_brand_description",
    "footer_copyright",
)
HOME_FALLBACK_BANNER_KEY = "home_banners_fallback"


@admin.register(SiteContentBlock)
class SiteContentBlockAdmin(admin.ModelAdmin):
    list_display = ("key", "title_ar", "is_active", "updated_at", "updated_by")
    list_filter = ("is_active", "key")
    search_fields = ("key", "title_ar", "body_ar")


@admin.register(BrandingContentBlock)
class BrandingContentBlockAdmin(admin.ModelAdmin):
    list_display = ("key_label", "title_ar", "is_active", "updated_at", "media_preview")
    list_filter = ("is_active",)
    search_fields = ("key", "title_ar", "body_ar")
    readonly_fields = ("key", "media_preview", "updated_at", "updated_by")
    fields = ("key", "title_ar", "body_ar", "media_file", "media_preview", "is_active", "updated_at", "updated_by")

    def get_queryset(self, request):
        return super().get_queryset(request).filter(key__in=BRANDING_KEYS)

    def has_add_permission(self, request):
        return False

    @admin.display(description="نوع العنصر")
    def key_label(self, obj):
        return obj.get_key_display() or obj.key

    @admin.display(description="معاينة الشعار")
    def media_preview(self, obj):
        if not obj.media_file:
            return "لا توجد وسائط"
        if obj.media_type == "image":
            return format_html(
                '<img src="{}" alt="{}" style="max-height:80px; max-width:180px; border-radius:8px; border:1px solid #ddd; padding:4px; background:#fff;">',
                obj.media_file.url,
                obj.title_ar or obj.key,
            )
        return format_html('<a href="{}" target="_blank" rel="noopener">فتح الوسائط</a>', obj.media_file.url)


@admin.register(HomePageFallbackBannerBlock)
class HomePageFallbackBannerBlockAdmin(admin.ModelAdmin):
    list_display = ("key_label", "title_ar", "is_active", "updated_at", "media_preview")
    list_filter = ("is_active",)
    search_fields = ("key", "title_ar", "body_ar")
    readonly_fields = ("key", "usage_note", "media_preview", "updated_at", "updated_by")
    fields = ("key", "title_ar", "body_ar", "media_file", "media_preview", "usage_note", "is_active", "updated_at", "updated_by")

    def get_queryset(self, request):
        return super().get_queryset(request).filter(key=HOME_FALLBACK_BANNER_KEY)

    def has_add_permission(self, request):
        return False

    @admin.display(description="نوع العنصر")
    def key_label(self, obj):
        return obj.get_key_display() or obj.key

    @admin.display(description="معاينة البنر")
    def media_preview(self, obj):
        if not obj.media_file:
            return "لا توجد وسائط"
        if obj.media_type == "image":
            return format_html(
                '<img src="{}" alt="{}" style="max-height:120px; max-width:220px; border-radius:8px; border:1px solid #ddd; padding:4px; background:#fff;">',
                obj.media_file.url,
                obj.title_ar or obj.key,
            )
        return format_html('<a href="{}" target="_blank" rel="noopener">فتح الوسائط</a>', obj.media_file.url)

    @admin.display(description="طريقة الاستخدام")
    def usage_note(self, obj):
        return "يظهر هذا البنر تلقائيًا في الصفحة الرئيسية عندما لا توجد إعلانات أو بنرات ترويجية فعالة."


@admin.register(SiteLegalDocument)
class SiteLegalDocumentAdmin(admin.ModelAdmin):
    list_display = ("doc_type", "version", "is_active", "published_at", "uploaded_at", "uploaded_by")
    list_filter = ("doc_type", "is_active")
    search_fields = ("doc_type", "version")


@admin.register(SiteLinks)
class SiteLinksAdmin(admin.ModelAdmin):
    list_display = ("id", "email", "website_url", "updated_at", "updated_by")

    def has_add_permission(self, request):
        return not SiteLinks.objects.exists()

    def has_delete_permission(self, request, obj=None):
        return False
