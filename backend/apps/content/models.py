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
