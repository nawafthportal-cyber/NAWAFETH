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


class SiteContentBlock(models.Model):
    key = models.CharField(max_length=80, unique=True, choices=ContentBlockKey.choices)
    title_ar = models.CharField(max_length=255)
    body_ar = models.TextField(blank=True)
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

    def __str__(self):
        return f"{self.key}"


class SiteLegalDocument(models.Model):
    doc_type = models.CharField(max_length=40, choices=LegalDocumentType.choices)
    file = models.FileField(
        upload_to="site_legal/%Y/%m/",
        validators=[
            FileExtensionValidator(allowed_extensions=ALLOWED_LEGAL_FILE_EXTENSIONS),
            validate_legal_document_file,
        ],
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
