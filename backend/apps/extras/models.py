from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.db import models, transaction
from django.utils import timezone


class ServiceCatalog(models.Model):
    """
    كتالوج الخدمات الإضافية — يُدار من Django Admin.
    DB-first: إن وُجد سجل نشط يُستخدم بدلًا من settings.EXTRA_SKUS.
    """
    sku = models.CharField("رمز الخدمة (SKU)", max_length=80, unique=True)
    title = models.CharField("عنوان الخدمة", max_length=160)
    price = models.DecimalField("السعر (بدون ضريبة)", max_digits=10, decimal_places=2)
    currency = models.CharField("العملة", max_length=10, default="SAR")
    is_active = models.BooleanField("نشط", default=True)
    sort_order = models.PositiveIntegerField("الترتيب", default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "خدمة إضافية (كتالوج)"
        verbose_name_plural = "كتالوج الخدمات الإضافية"
        ordering = ["sort_order", "sku"]

    def __str__(self):
        status = "✓" if self.is_active else "✗"
        return f"[{status}] {self.sku} — {self.price} {self.currency}"


class ExtrasBundlePricingRule(models.Model):
    SECTION_REPORTS = "reports"
    SECTION_CLIENTS = "clients"
    SECTION_FINANCE = "finance"

    SECTION_CHOICES = (
        (SECTION_REPORTS, "التقارير"),
        (SECTION_CLIENTS, "إدارة العملاء"),
        (SECTION_FINANCE, "الإدارة المالية"),
    )

    section_key = models.CharField("القسم", max_length=20, choices=SECTION_CHOICES)
    option_key = models.CharField("رمز البند", max_length=80)
    fee = models.DecimalField("السعر قبل الضريبة", max_digits=10, decimal_places=2)
    currency = models.CharField("العملة", max_length=10, default="SAR")
    apply_year_multiplier = models.BooleanField("يضرب في مدة الاشتراك", default=False)
    is_active = models.BooleanField("نشط", default=True)
    sort_order = models.PositiveIntegerField("الترتيب", default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "تسعير بند باقة خدمات إضافية"
        verbose_name_plural = "تسعير بنود باقات الخدمات الإضافية"
        ordering = ["section_key", "sort_order", "option_key"]
        constraints = [
            models.UniqueConstraint(fields=["section_key", "option_key"], name="uniq_extras_bundle_pricing_rule"),
        ]

    def __str__(self):
        state = "✓" if self.is_active else "✗"
        return f"[{state}] {self.section_key}:{self.option_key} — {self.fee} {self.currency}"


class ExtraPurchaseStatus(models.TextChoices):
    PENDING_PAYMENT = "pending_payment", "بانتظار الدفع"
    ACTIVE = "active", "نشط"
    CONSUMED = "consumed", "مستهلك"
    EXPIRED = "expired", "منتهي"
    CANCELLED = "cancelled", "ملغي"


class ExtraType(models.TextChoices):
    TIME_BASED = "time_based", "زمني (مدة)"
    CREDIT_BASED = "credit_based", "رصيد (Credits)"


class ExtraPurchase(models.Model):
    """
    عملية شراء Add-on
    reference_type=extra_purchase
    """
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="extra_purchases")

    sku = models.CharField(max_length=80)  # uploads_10gb_month...
    title = models.CharField(max_length=160)
    extra_type = models.CharField(max_length=20, choices=ExtraType.choices, default=ExtraType.TIME_BASED)

    subtotal = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal("0.00"))
    currency = models.CharField(max_length=10, default="SAR")

    # Time-based
    start_at = models.DateTimeField(null=True, blank=True)
    end_at = models.DateTimeField(null=True, blank=True)

    # Credit-based
    credits_total = models.PositiveIntegerField(default=0)
    credits_used = models.PositiveIntegerField(default=0)

    status = models.CharField(max_length=20, choices=ExtraPurchaseStatus.choices, default=ExtraPurchaseStatus.PENDING_PAYMENT)

    invoice = models.ForeignKey(
        "billing.Invoice",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="extra_purchases",
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def credits_left(self) -> int:
        return max(0, int(self.credits_total) - int(self.credits_used))

    def is_time_active(self) -> bool:
        if not self.start_at or not self.end_at:
            return False
        now = timezone.now()
        return self.start_at <= now < self.end_at

    def __str__(self):
        return f"EXTRA#{self.pk} {self.sku} {self.status}"
