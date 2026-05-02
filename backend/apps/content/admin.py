from django.contrib import admin
from django import forms
from django.http import HttpResponseRedirect
from django.urls import reverse
from django.utils.html import format_html

from .models import BrandingContentBlock, HomePageFallbackBannerBlock, PlatformLogoBlock, SiteContentBlock, SiteLegalDocument, SiteLinks


PLATFORM_LOGO_KEY = "topbar_brand_logo"
BRANDING_KEYS = (
    "topbar_brand_title",
    "topbar_brand_subtitle",
    "footer_brand_title",
    "footer_brand_description",
    "footer_copyright",
)
HOME_FALLBACK_BANNER_KEY = "home_banners_fallback"


class PlatformLogoAdminForm(forms.ModelForm):
    class Meta:
        model = PlatformLogoBlock
        fields = "__all__"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["title_ar"].label = "النص البديل للشعار"
        self.fields["title_ar"].help_text = "يُستخدم كنص بديل للصورة لتحسين الوصول ومحركات البحث."
        self.fields["title_en"].label = "النص البديل للشعار بالإنجليزية"
        self.fields["title_en"].help_text = "يُستخدم عند التبديل إلى الإنجليزية."
        self.fields["media_file"].label = "ملف الشعار"
        self.fields["media_file"].help_text = "ارفع صورة الشعار فقط. يُفضّل PNG أو WebP بخلفية شفافة."
        self.fields["is_active"].label = "تفعيل الشعار"

    def clean_media_file(self):
        media_file = self.cleaned_data.get("media_file")
        if media_file in (None, False):
            return media_file

        content_type = (getattr(media_file, "content_type", "") or "").strip().lower()
        name = (getattr(media_file, "name", "") or "").lower()
        if content_type and not content_type.startswith("image/"):
            raise forms.ValidationError("يجب أن يكون شعار المنصة ملف صورة فقط.")
        if not content_type and not name.endswith((".jpg", ".jpeg", ".png", ".gif", ".webp")):
            raise forms.ValidationError("امتداد شعار المنصة يجب أن يكون صورة مدعومة.")
        return media_file


@admin.register(SiteContentBlock)
class SiteContentBlockAdmin(admin.ModelAdmin):
    list_display = ("key", "title_ar", "title_en", "is_active", "updated_at", "updated_by")
    list_filter = ("is_active", "key")
    search_fields = ("key", "title_ar", "title_en", "body_ar", "body_en")


@admin.register(PlatformLogoBlock)
class PlatformLogoBlockAdmin(admin.ModelAdmin):
    form = PlatformLogoAdminForm
    list_display = ("key_label", "title_ar", "title_en", "is_active", "updated_at", "media_preview")
    readonly_fields = ("key", "usage_note", "media_preview", "updated_at", "updated_by")
    fields = ("key", "title_ar", "title_en", "media_file", "media_preview", "usage_note", "is_active", "updated_at", "updated_by")

    def get_queryset(self, request):
        return super().get_queryset(request).filter(key=PLATFORM_LOGO_KEY)

    def has_add_permission(self, request):
        if not super().has_add_permission(request):
            return False
        return not self.get_queryset(request).exists()

    def changelist_view(self, request, extra_context=None):
        obj = self.get_queryset(request).first()
        if obj is not None:
            url = reverse("admin:content_platformlogoblock_change", args=[obj.pk])
            return HttpResponseRedirect(url)
        url = reverse("admin:content_platformlogoblock_add")
        return HttpResponseRedirect(url)

    def has_delete_permission(self, request, obj=None):
        return False

    def get_changeform_initial_data(self, request):
        initial = super().get_changeform_initial_data(request)
        initial.setdefault("title_ar", "شعار نوافذ")
        initial.setdefault("is_active", True)
        return initial

    def save_model(self, request, obj, form, change):
        obj.key = PLATFORM_LOGO_KEY
        obj.body_ar = ""
        obj.body_en = ""
        if hasattr(obj, "updated_by"):
            obj.updated_by = getattr(request, "user", None)
        super().save_model(request, obj, form, change)

    @admin.display(description="العنصر")
    def key_label(self, obj):
        return "شعار المنصة"

    @admin.display(description="معاينة الشعار")
    def media_preview(self, obj):
        if not obj.media_file:
            return "لا يوجد شعار مرفوع"
        return format_html(
            '<img src="{}" alt="{}" style="max-height:96px; max-width:220px; border-radius:10px; border:1px solid #ddd; padding:6px; background:#fff; object-fit:contain;">',
            obj.media_file.url,
            obj.title_ar or "شعار المنصة",
        )

    @admin.display(description="طريقة الاستخدام")
    def usage_note(self, obj):
        return "هذا الشعار يظهر في أعلى الموقع وفوتر الموقع. عند تعطيله يعود النظام إلى الحرف الافتراضي بدل الصورة."


@admin.register(BrandingContentBlock)
class BrandingContentBlockAdmin(admin.ModelAdmin):
    list_display = ("key_label", "title_ar", "title_en", "is_active", "updated_at", "media_preview")
    list_filter = ("is_active",)
    search_fields = ("key", "title_ar", "title_en", "body_ar", "body_en")
    readonly_fields = ("key", "media_preview", "updated_at", "updated_by")
    fields = ("key", "title_ar", "title_en", "body_ar", "body_en", "media_file", "media_preview", "is_active", "updated_at", "updated_by")

    def get_queryset(self, request):
        return super().get_queryset(request).filter(key__in=BRANDING_KEYS)

    def has_add_permission(self, request):
        return False

    def save_model(self, request, obj, form, change):
        if hasattr(obj, "updated_by"):
            obj.updated_by = getattr(request, "user", None)
        super().save_model(request, obj, form, change)

    @admin.display(description="نوع العنصر")
    def key_label(self, obj):
        return obj.get_key_display() or obj.key

    @admin.display(description="معاينة الوسائط")
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
    list_display = ("key_label", "title_ar", "title_en", "is_active", "updated_at", "media_preview")
    list_filter = ("is_active",)
    search_fields = ("key", "title_ar", "title_en", "body_ar", "body_en")
    readonly_fields = ("key", "usage_note", "media_preview", "updated_at", "updated_by")
    fields = ("key", "title_ar", "title_en", "body_ar", "body_en", "media_file", "media_preview", "usage_note", "is_active", "updated_at", "updated_by")

    def get_queryset(self, request):
        return super().get_queryset(request).filter(key=HOME_FALLBACK_BANNER_KEY)

    def has_add_permission(self, request):
        if not super().has_add_permission(request):
            return False
        return not self.get_queryset(request).exists()

    def has_delete_permission(self, request, obj=None):
        return False

    def get_changeform_initial_data(self, request):
        initial = super().get_changeform_initial_data(request)
        initial.setdefault("title_ar", "البنر الافتراضي")
        initial.setdefault("body_ar", "يظهر هذا البنر تلقائيًا في الصفحة الرئيسية عندما لا توجد إعلانات أو بنرات ترويجية فعالة.")
        initial.setdefault("is_active", True)
        return initial

    def save_model(self, request, obj, form, change):
        obj.key = HOME_FALLBACK_BANNER_KEY
        if hasattr(obj, "updated_by"):
            obj.updated_by = getattr(request, "user", None)
        super().save_model(request, obj, form, change)

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
    search_fields = ("doc_type", "version", "body_ar", "body_en")
    fields = ("doc_type", "body_ar", "body_en", "file", "version", "published_at", "is_active", "uploaded_at", "uploaded_by")
    readonly_fields = ("uploaded_at", "uploaded_by")


@admin.register(SiteLinks)
class SiteLinksAdmin(admin.ModelAdmin):
    list_display = ("id", "email", "website_url", "updated_at", "updated_by")

    def save_model(self, request, obj, form, change):
        if hasattr(obj, "updated_by"):
            obj.updated_by = getattr(request, "user", None)
        super().save_model(request, obj, form, change)

    def has_add_permission(self, request):
        return not SiteLinks.objects.exists()

    def has_delete_permission(self, request, obj=None):
        return False
