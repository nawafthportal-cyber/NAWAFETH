from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.db import models
from django.utils import timezone

from .validators import validate_file_size, validate_extension


class VerificationBadgeType(models.TextChoices):
    BLUE = "blue", "شارة زرقاء"
    GREEN = "green", "شارة خضراء"


class VerificationBlueSubjectType(models.TextChoices):
    INDIVIDUAL = "individual", "فرد"
    BUSINESS = "business", "منشأة"


class VerificationStatus(models.TextChoices):
    NEW = "new", "جديد"
    IN_REVIEW = "in_review", "تحت المعالجة"
    REJECTED = "rejected", "مرفوض"
    APPROVED = "approved", "معتمد"
    PENDING_PAYMENT = "pending_payment", "بانتظار الدفع"
    ACTIVE = "active", "مفعل"
    EXPIRED = "expired", "منتهي"


class VerificationDocType(models.TextChoices):
    ID = "id", "هوية وطنية/إقامة"
    CR = "cr", "سجل تجاري"
    IBAN = "iban", "آيبان/حساب بنكي"
    LICENSE = "license", "ترخيص/تصريح"
    OTHER = "other", "مستند إضافي"


class VerificationRequest(models.Model):
    """
    ADxxxx - طلب توثيق
    """
    code = models.CharField(max_length=20, unique=True, blank=True)

    requester = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="verification_requests",
    )

    # Backoffice assignment (for AccessLevel.USER scoping)
    assigned_to = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="assigned_verification_requests",
    )
    assigned_at = models.DateTimeField(null=True, blank=True)

    # Legacy field: historically the request was for a single badge type.
    # New flow can include multiple requirement items (blue/green) in one request.
    badge_type = models.CharField(
        max_length=20,
        choices=VerificationBadgeType.choices,
        null=True,
        blank=True,
    )

    # Priority shown in ops dashboard (1 أعلى، 3 أدنى) — default وسط.
    priority = models.PositiveSmallIntegerField(default=2)

    status = models.CharField(max_length=25, choices=VerificationStatus.choices, default=VerificationStatus.NEW)

    admin_note = models.CharField(max_length=300, blank=True)
    reject_reason = models.CharField(max_length=300, blank=True)

    # ربط الفاتورة (Sprint 3)
    invoice = models.ForeignKey(
        "billing.Invoice",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="verification_requests",
    )

    requested_at = models.DateTimeField(auto_now_add=True)
    reviewed_at = models.DateTimeField(null=True, blank=True)
    approved_at = models.DateTimeField(null=True, blank=True)

    activated_at = models.DateTimeField(null=True, blank=True)
    expires_at = models.DateTimeField(null=True, blank=True)

    updated_at = models.DateTimeField(auto_now=True)

    def _ensure_code(self):
        if not self.code and self.pk:
            self.code = f"AD{self.pk:06d}"
            VerificationRequest.objects.filter(pk=self.pk).update(code=self.code)

    def save(self, *args, **kwargs):
        is_new = self.pk is None
        super().save(*args, **kwargs)
        if is_new:
            # لا نعتمد على on_commit لأن اختبارات pytest تعمل داخل transaction
            # وقد تؤخر توليد code حتى نهاية الاختبار.
            self._ensure_code()

    def __str__(self) -> str:
        return self.code or f"AD-request-{self.pk}"

    def activation_window(self):
        from apps.core.models import PlatformConfig

        return timedelta(days=int(PlatformConfig.load().verification_validity_days or 365))


class VerificationDocument(models.Model):
    """
    مستند ضمن طلب التوثيق + قرار (approve/reject)
    """
    request = models.ForeignKey(VerificationRequest, on_delete=models.CASCADE, related_name="documents")

    doc_type = models.CharField(max_length=30, choices=VerificationDocType.choices)
    title = models.CharField(max_length=160, blank=True)

    file = models.FileField(
        upload_to="verification/docs/%Y/%m/",
        validators=[validate_file_size, validate_extension],
    )

    # قرار المراجع
    is_approved = models.BooleanField(null=True, blank=True)  # None => لم يقرر
    decision_note = models.CharField(max_length=300, blank=True)
    decided_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="verification_doc_decisions",
    )
    decided_at = models.DateTimeField(null=True, blank=True)

    uploaded_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    uploaded_at = models.DateTimeField(auto_now_add=True)

    def __str__(self) -> str:
        return f"{self.request.code} doc#{self.pk}"


class VerificationRequirement(models.Model):
    """بند توثيق ضمن طلب.

    أمثلة الأكواد بحسب التصميم:
    - B1 (الزرقاء)
    - G1..G6 (الخضراء)
    """

    request = models.ForeignKey(VerificationRequest, on_delete=models.CASCADE, related_name="requirements")

    badge_type = models.CharField(max_length=20, choices=VerificationBadgeType.choices)
    code = models.CharField(max_length=10)
    title = models.CharField(max_length=220)

    is_approved = models.BooleanField(null=True, blank=True)  # None => لم يقرر
    decision_note = models.CharField(max_length=300, blank=True)
    evidence_expires_at = models.DateTimeField(null=True, blank=True)
    decided_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="verification_requirement_decisions",
    )
    decided_at = models.DateTimeField(null=True, blank=True)

    sort_order = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=["code"]),
            models.Index(fields=["badge_type"]),
        ]
        ordering = ["sort_order", "id"]

    def __str__(self) -> str:
        return f"{self.request.code} {self.code}"


class VerificationRequirementAttachment(models.Model):
    requirement = models.ForeignKey(VerificationRequirement, on_delete=models.CASCADE, related_name="attachments")

    file = models.FileField(
        upload_to="verification/requirements/%Y/%m/",
        validators=[validate_file_size, validate_extension],
    )
    uploaded_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    uploaded_at = models.DateTimeField(auto_now_add=True)

    def __str__(self) -> str:
        return f"{self.requirement_id} attachment#{self.pk}"


class VerificationBlueProfile(models.Model):
    request = models.OneToOneField(
        VerificationRequest,
        on_delete=models.CASCADE,
        related_name="blue_profile",
    )
    subject_type = models.CharField(max_length=20, choices=VerificationBlueSubjectType.choices)
    official_number = models.CharField(max_length=32)
    official_date = models.DateField()
    verified_name = models.CharField(max_length=180)
    is_name_approved = models.BooleanField(default=False)
    verification_source = models.CharField(max_length=40, default="elm")
    verified_at = models.DateTimeField(null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "بيانات الشارة الزرقاء"
        verbose_name_plural = "بيانات الشارة الزرقاء"

    def __str__(self) -> str:
        return f"{self.request.code or self.request_id} blue profile"


class VerificationInquiryProfile(models.Model):
    ticket = models.OneToOneField(
        "support.SupportTicket",
        on_delete=models.CASCADE,
        related_name="verification_profile",
    )
    linked_request = models.ForeignKey(
        VerificationRequest,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="linked_inquiries",
    )
    detailed_request_url = models.URLField(blank=True)
    operator_comment = models.CharField(max_length=300, blank=True, default="")
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "ملف استفسار التوثيق"
        verbose_name_plural = "ملفات استفسارات التوثيق"

    def __str__(self) -> str:
        return f"Verification inquiry profile #{self.pk}"


class VerifiedBadge(models.Model):
    """
    سجل تفعيل الشارات (مرجعي وإداري)
    """
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="badges")

    badge_type = models.CharField(max_length=20, choices=VerificationBadgeType.choices)
    verification_code = models.CharField(max_length=10, blank=True, default="")
    verification_title = models.CharField(max_length=220, blank=True, default="")
    request = models.ForeignKey(VerificationRequest, on_delete=models.CASCADE, related_name="badges")

    activated_at = models.DateTimeField(default=timezone.now)
    expires_at = models.DateTimeField()

    is_active = models.BooleanField(default=True)

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=["user", "badge_type", "is_active"]),
            models.Index(fields=["user", "verification_code", "is_active"]),
        ]

    def __str__(self):
        return f"{self.user_id} {self.badge_type} active={self.is_active}"


class VerificationPricingRule(models.Model):
    """
    قاعدة تسعير توثيق — يُدار من Django Admin.
    DB-first: إن وُجد سجل نشط يُستخدم بدلًا من SubscriptionPlan.verification_*_fee.
    """
    badge_type = models.CharField(
        "نوع الشارة",
        max_length=20,
        choices=VerificationBadgeType.choices,
        unique=True,
    )
    fee = models.DecimalField("رسم التوثيق (شامل الضريبة)", max_digits=10, decimal_places=2)
    currency = models.CharField("العملة", max_length=10, default="SAR")
    is_active = models.BooleanField("نشط", default=True)
    note = models.CharField("ملاحظة", max_length=300, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "قاعدة تسعير توثيق"
        verbose_name_plural = "قواعد تسعير التوثيق"
        ordering = ["badge_type"]

    def __str__(self):
        status = "✓" if self.is_active else "✗"
        return f"[{status}] {self.get_badge_type_display()} — {self.fee} {self.currency}"
