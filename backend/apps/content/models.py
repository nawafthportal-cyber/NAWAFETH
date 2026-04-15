from __future__ import annotations

import os

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.validators import FileExtensionValidator
from django.db import models
from django.utils import timezone


MAX_LEGAL_FILE_SIZE_BYTES = 10 * 1024 * 1024
ALLOWED_LEGAL_FILE_EXTENSIONS = ["pdf", "doc", "docx", "txt"]
ALLOWED_LEGAL_MIME_TYPES = {
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "text/plain",
}
MAX_CONTENT_BLOCK_MEDIA_SIZE_BYTES = 25 * 1024 * 1024
CONTENT_BLOCK_IMAGE_EXTENSIONS = {"jpg", "jpeg", "png", "gif", "webp"}
CONTENT_BLOCK_VIDEO_EXTENSIONS = {"mp4", "mov", "webm", "m4v"}
ALLOWED_CONTENT_BLOCK_MEDIA_EXTENSIONS = sorted(CONTENT_BLOCK_IMAGE_EXTENSIONS | CONTENT_BLOCK_VIDEO_EXTENSIONS)
ALLOWED_CONTENT_BLOCK_MEDIA_MIME_TYPES = {
    "image/jpeg",
    "image/png",
    "image/gif",
    "image/webp",
    "video/mp4",
    "video/quicktime",
    "video/webm",
    "video/x-m4v",
}


class ContentBlockKey(models.TextChoices):
    ONBOARDING_FIRST_TIME = "onboarding_first_time", "الدخول أول مرة"
    ONBOARDING_INTRO = "onboarding_intro", "صفحة التعريف"
    ONBOARDING_GET_STARTED = "onboarding_get_started", "صفحة الانطلاق"
    APP_INTRO_PREVIEW = "app_intro_preview", "بروفة التعريف بالتطبيق"
    HOME_CATEGORIES_TITLE = "home_categories_title", "الرئيسية - عنوان التصنيفات"
    HOME_PROVIDERS_TITLE = "home_providers_title", "الرئيسية - عنوان مزودي الخدمة"
    HOME_BANNERS_TITLE = "home_banners_title", "الرئيسية - عنوان العروض الترويجية"
    HOME_BANNERS_FALLBACK = "home_banners_fallback", "الرئيسية - البنر الافتراضي"
    TOPBAR_BRAND_LOGO = "topbar_brand_logo", "الشريط العلوي - شعار المنصة"
    TOPBAR_BRAND_TITLE = "topbar_brand_title", "الشريط العلوي - اسم المنصة"
    TOPBAR_BRAND_SUBTITLE = "topbar_brand_subtitle", "الشريط العلوي - وصف المنصة"
    FOOTER_BRAND_TITLE = "footer_brand_title", "الفوتر - اسم المنصة"
    FOOTER_BRAND_DESCRIPTION = "footer_brand_description", "الفوتر - وصف المنصة"
    FOOTER_COPYRIGHT = "footer_copyright", "الفوتر - حقوق النشر"
    LOGIN_TITLE = "login_title", "الدخول - العنوان"
    LOGIN_DESCRIPTION = "login_description", "الدخول - الوصف"
    LOGIN_PHONE_HINT = "login_phone_hint", "الدخول - تلميح الجوال"
    LOGIN_SUBMIT_LABEL = "login_submit_label", "الدخول - زر الإرسال"
    LOGIN_GUEST_LABEL = "login_guest_label", "الدخول - زر الزائر"
    SIGNUP_TITLE = "signup_title", "التسجيل - العنوان"
    SIGNUP_DESCRIPTION = "signup_description", "التسجيل - الوصف"
    SIGNUP_SUBMIT_LABEL = "signup_submit_label", "التسجيل - زر الإكمال"
    SIGNUP_TERMS_LABEL = "signup_terms_label", "التسجيل - نص الشروط"
    TWOFA_TITLE = "twofa_title", "التحقق - العنوان"
    TWOFA_DESCRIPTION = "twofa_description", "التحقق - الوصف"
    TWOFA_SUBMIT_LABEL = "twofa_submit_label", "التحقق - زر التأكيد"
    TWOFA_RESEND_LABEL = "twofa_resend_label", "التحقق - إعادة الإرسال"
    TWOFA_CHANGE_PHONE_LABEL = "twofa_change_phone_label", "التحقق - تغيير الجوال"
    TWOFA_SUCCESS_RESEND_LABEL = "twofa_success_resend_label", "التحقق - نجاح إعادة الإرسال"
    TWOFA_PHONE_NOTICE = "twofa_phone_notice", "التحقق - تم إرسال الرمز إلى"
    TWOFA_RESEND_PROMPT = "twofa_resend_prompt", "التحقق - لم يصلك الرمز"
    ABOUT_HERO_TITLE = "about_hero_title", "من نحن - عنوان الهيرو"
    ABOUT_HERO_SUBTITLE = "about_hero_subtitle", "من نحن - الوصف المختصر"
    ABOUT_SECTION_ABOUT = "about_section_about", "من نحن - قسم من نحن"
    ABOUT_SECTION_VISION = "about_section_vision", "من نحن - قسم الرؤية"
    ABOUT_SECTION_GOALS = "about_section_goals", "من نحن - قسم الأهداف"
    ABOUT_SECTION_VALUES = "about_section_values", "من نحن - قسم القيم"
    ABOUT_SECTION_APP = "about_section_app", "من نحن - قسم التطبيق"
    ABOUT_SOCIAL_TITLE = "about_social_title", "من نحن - عنوان التواصل"
    ABOUT_WEBSITE_LABEL = "about_website_label", "من نحن - زر الموقع الرسمي"
    TERMS_PAGE_TITLE = "terms_page_title", "الشروط - عنوان الصفحة"
    TERMS_EMPTY_LABEL = "terms_empty_label", "الشروط - حالة الفراغ"
    TERMS_OPEN_DOCUMENT_LABEL = "terms_open_document_label", "الشروط - زر فتح المستند"
    TERMS_FILE_ONLY_HINT = "terms_file_only_hint", "الشروط - تلميح المستند المرفق"
    TERMS_MISSING_DOCUMENT_HINT = "terms_missing_document_hint", "الشروط - تلميح غياب المستند"
    CONTACT_GATE_TITLE = "contact_gate_title", "التواصل - عنوان بوابة الدخول"
    CONTACT_GATE_DESCRIPTION = "contact_gate_description", "التواصل - وصف بوابة الدخول"
    CONTACT_GATE_LOGIN_LABEL = "contact_gate_login_label", "التواصل - زر تسجيل الدخول"
    CONTACT_PAGE_TITLE = "contact_page_title", "التواصل - عنوان الصفحة"
    CONTACT_REFRESH_LABEL = "contact_refresh_label", "التواصل - زر التحديث"
    CONTACT_NEW_TICKET_LABEL = "contact_new_ticket_label", "التواصل - زر بلاغ جديد"
    CONTACT_LIST_TITLE = "contact_list_title", "التواصل - عنوان قائمة البلاغات"
    CONTACT_CREATE_TITLE = "contact_create_title", "التواصل - عنوان إنشاء البلاغ"
    CONTACT_DETAIL_TITLE = "contact_detail_title", "التواصل - عنوان تفاصيل البلاغ"
    CONTACT_EMPTY_LABEL = "contact_empty_label", "التواصل - حالة فراغ البلاغات"
    CONTACT_TEAM_PLACEHOLDER = "contact_team_placeholder", "التواصل - اختيار فريق الدعم"
    CONTACT_DESCRIPTION_LABEL = "contact_description_label", "التواصل - حقل التفاصيل"
    CONTACT_ATTACHMENTS_LABEL = "contact_attachments_label", "التواصل - حقل المرفقات"
    CONTACT_CANCEL_LABEL = "contact_cancel_label", "التواصل - زر الإلغاء"
    CONTACT_SUBMIT_LABEL = "contact_submit_label", "التواصل - زر إرسال البلاغ"
    CONTACT_REPLY_PLACEHOLDER = "contact_reply_placeholder", "التواصل - حقل التعليق"
    CONTACT_REPLY_SUBMIT_LABEL = "contact_reply_submit_label", "التواصل - زر إرسال التعليق"
    SETTINGS_HELP = "settings_help", "معلومات المساعدة"
    SETTINGS_INFO = "settings_info", "معلومات الإعدادات"


class LegalDocumentType(models.TextChoices):
    TERMS = "terms", "الشروط والأحكام"
    PRIVACY = "privacy", "سياسة الخصوصية"
    REGULATIONS = "regulations", "الأنظمة والتشريعات"
    PROHIBITED_SERVICES = "prohibited_services", "الخدمات الممنوعة"


def validate_legal_document_file(uploaded_file):
    if uploaded_file is None:
        return

    size = getattr(uploaded_file, "size", 0) or 0
    if size > MAX_LEGAL_FILE_SIZE_BYTES:
        raise ValidationError("حجم الملف يتجاوز الحد المسموح (10MB).")

    content_type = (getattr(uploaded_file, "content_type", "") or "").strip().lower()
    if content_type and content_type not in ALLOWED_LEGAL_MIME_TYPES:
        raise ValidationError("نوع الملف غير مسموح.")

    ext = os.path.splitext((getattr(uploaded_file, "name", "") or "").lower())[1].lstrip(".")
    if ext and ext not in ALLOWED_LEGAL_FILE_EXTENSIONS:
        raise ValidationError("امتداد الملف غير مسموح.")


def infer_content_block_media_type(uploaded_file) -> str:
    if uploaded_file is None:
        return ""

    content_type = (getattr(uploaded_file, "content_type", "") or "").strip().lower()
    if content_type.startswith("image/"):
        return "image"
    if content_type.startswith("video/"):
        return "video"

    ext = os.path.splitext((getattr(uploaded_file, "name", "") or "").lower())[1].lstrip(".")
    if ext in CONTENT_BLOCK_IMAGE_EXTENSIONS:
        return "image"
    if ext in CONTENT_BLOCK_VIDEO_EXTENSIONS:
        return "video"
    return ""


def validate_content_block_media(uploaded_file):
    if uploaded_file is None:
        return

    size = getattr(uploaded_file, "size", 0) or 0
    if size > MAX_CONTENT_BLOCK_MEDIA_SIZE_BYTES:
        raise ValidationError("حجم الوسائط يتجاوز الحد المسموح (25MB).")

    content_type = (getattr(uploaded_file, "content_type", "") or "").strip().lower()
    if content_type and content_type not in ALLOWED_CONTENT_BLOCK_MEDIA_MIME_TYPES:
        raise ValidationError("نوع الوسائط غير مسموح.")

    ext = os.path.splitext((getattr(uploaded_file, "name", "") or "").lower())[1].lstrip(".")
    if ext and ext not in ALLOWED_CONTENT_BLOCK_MEDIA_EXTENSIONS:
        raise ValidationError("امتداد الوسائط غير مسموح.")

    if not infer_content_block_media_type(uploaded_file):
        raise ValidationError("صيغة الوسائط غير مدعومة. المسموح صور أو فيديو قصير فقط.")


class SiteContentBlock(models.Model):
    key = models.CharField(max_length=80, unique=True, choices=ContentBlockKey.choices)
    title_ar = models.CharField(max_length=255)
    body_ar = models.TextField(blank=True)
    media_file = models.FileField(
        upload_to="site_content/%Y/%m/",
        validators=[
            FileExtensionValidator(allowed_extensions=ALLOWED_CONTENT_BLOCK_MEDIA_EXTENSIONS),
            validate_content_block_media,
        ],
        blank=True,
    )
    is_active = models.BooleanField(default=True)
    updated_at = models.DateTimeField(auto_now=True)
    updated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="updated_site_content_blocks",
    )

    class Meta:
        ordering = ["key"]

    @property
    def media_type(self) -> str:
        return infer_content_block_media_type(getattr(self, "media_file", None))

    def __str__(self):
        return f"{self.key}"


class BrandingContentBlock(SiteContentBlock):
    class Meta:
        proxy = True
        verbose_name = "هوية المنصة"
        verbose_name_plural = "هوية المنصة"


class HomePageFallbackBannerBlock(SiteContentBlock):
    class Meta:
        proxy = True
        verbose_name = "بنر الرئيسية الافتراضي"
        verbose_name_plural = "بنر الرئيسية الافتراضي"


class SiteLegalDocument(models.Model):
    doc_type = models.CharField(max_length=40, choices=LegalDocumentType.choices)
    body_ar = models.TextField(blank=True, default="")
    file = models.FileField(
        upload_to="site_legal/%Y/%m/",
        validators=[
            FileExtensionValidator(allowed_extensions=ALLOWED_LEGAL_FILE_EXTENSIONS),
            validate_legal_document_file,
        ],
        blank=True,
    )
    version = models.CharField(max_length=40, default="1.0")
    published_at = models.DateTimeField(default=timezone.now)
    is_active = models.BooleanField(default=True)
    uploaded_at = models.DateTimeField(auto_now_add=True)
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="uploaded_site_legal_documents",
    )

    class Meta:
        ordering = ["-published_at", "-id"]

    def clean(self):
        super().clean()
        has_body = bool((self.body_ar or "").strip())
        has_file = bool(self.file)
        if not has_body and not has_file:
            raise ValidationError("يجب إدخال نص أو إرفاق ملف واحد على الأقل.")

    def __str__(self):
        return f"{self.doc_type} v{self.version}"


class SiteLinks(models.Model):
    x_url = models.URLField(blank=True)
    instagram_url = models.URLField(blank=True)
    snapchat_url = models.URLField(blank=True)
    tiktok_url = models.URLField(blank=True)
    youtube_url = models.URLField(blank=True)
    whatsapp_url = models.URLField(blank=True)
    email = models.EmailField(blank=True)
    android_store = models.URLField(blank=True)
    ios_store = models.URLField(blank=True)
    website_url = models.URLField(blank=True)
    updated_at = models.DateTimeField(auto_now=True)
    updated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="updated_site_links",
    )

    class Meta:
        verbose_name_plural = "Site links"

    def __str__(self):
        return f"SiteLinks#{self.pk}"

    def save(self, *args, **kwargs):
        self.pk = 1
        super().save(*args, **kwargs)

    @classmethod
    def load(cls):
        obj, _ = cls.objects.get_or_create(pk=1)
        return obj
