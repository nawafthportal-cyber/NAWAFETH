from __future__ import annotations

import uuid
from decimal import Decimal, ROUND_HALF_UP

from django.conf import settings
from django.db import models
from django.utils import timezone


def money_round(val: Decimal) -> Decimal:
    """
    تقريب الأموال لرقمين عشريين
    """
    return (val or Decimal("0.00")).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


class InvoiceStatus(models.TextChoices):
    DRAFT = "draft", "مسودة"
    PENDING = "pending", "بانتظار الدفع"
    PAID = "paid", "مدفوعة"
    FAILED = "failed", "فشلت"
    CANCELLED = "cancelled", "ملغاة"
    REFUNDED = "refunded", "مسترجعة"


class PaymentAttemptStatus(models.TextChoices):
    INITIATED = "initiated", "بدأت"
    REDIRECTED = "redirected", "تم التحويل"
    SUCCESS = "success", "ناجحة"
    FAILED = "failed", "فشلت"
    CANCELLED = "cancelled", "ملغاة"
    REFUNDED = "refunded", "مسترجعة"


class PaymentProvider(models.TextChoices):
    MANUAL = "manual", "تحويل يدوي"
    MOCK = "mock", "اختبار"
    # لاحقًا: moyasar / hyperpay / tap / stcpay


TRUSTED_PAYMENT_REFERENCE_TYPES = {"subscription", "verify_request"}


class Invoice(models.Model):
    """
    فاتورة عامة قابلة للربط بأي خدمة عبر reference fields
    """
    code = models.CharField(max_length=20, unique=True, blank=True)

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="invoices",
    )

    title = models.CharField(max_length=160, default="فاتورة")
    description = models.CharField(max_length=300, blank=True)

    currency = models.CharField(max_length=10, default="SAR")

    subtotal = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal("0.00"))
    vat_percent = models.DecimalField(max_digits=5, decimal_places=2, default=Decimal("15.00"))
    vat_amount = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal("0.00"))
    total = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal("0.00"))

    status = models.CharField(max_length=20, choices=InvoiceStatus.choices, default=InvoiceStatus.DRAFT)

    # ربط عام
    reference_type = models.CharField(max_length=50, blank=True)  # verify_request / promo_request / subs / extras ...
    reference_id = models.CharField(max_length=50, blank=True)

    paid_at = models.DateTimeField(null=True, blank=True)
    cancelled_at = models.DateTimeField(null=True, blank=True)
    payment_confirmed = models.BooleanField(default=False)
    payment_confirmed_at = models.DateTimeField(null=True, blank=True)
    payment_provider = models.CharField(max_length=30, blank=True)
    payment_reference = models.CharField(max_length=120, blank=True)
    payment_event_id = models.CharField(max_length=120, blank=True)
    payment_amount = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    payment_currency = models.CharField(max_length=10, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def recalc(self):
        # If line items exist, subtotal is derived from them.
        if self.pk and hasattr(self, "lines") and self.lines.exists():
            from django.db.models import Sum

            raw = self.lines.aggregate(s=Sum("amount")).get("s")
            st = money_round(Decimal(raw or 0))
        else:
            st = money_round(Decimal(self.subtotal))
        vp = Decimal(self.vat_percent or 0)
        va = money_round((st * vp) / Decimal("100"))
        tt = money_round(st + va)
        self.subtotal = st
        self.vat_amount = va
        self.total = tt

    def mark_pending(self):
        if self.status == InvoiceStatus.DRAFT:
            self.status = InvoiceStatus.PENDING

    def mark_paid(self, when=None):
        self.status = InvoiceStatus.PAID
        self.paid_at = when or timezone.now()

    def mark_payment_confirmed(
        self,
        *,
        provider: str,
        provider_reference: str,
        event_id: str,
        amount: Decimal,
        currency: str,
        when=None,
    ):
        confirmed_at = when or timezone.now()
        self.mark_paid(when=confirmed_at)
        self.payment_confirmed = True
        self.payment_confirmed_at = confirmed_at
        self.payment_provider = (provider or "")[:30]
        self.payment_reference = (provider_reference or "")[:120]
        self.payment_event_id = (event_id or "")[:120]
        self.payment_amount = money_round(Decimal(amount or 0))
        self.payment_currency = (currency or "")[:10]
        self.cancelled_at = None

    def clear_payment_confirmation(self):
        self.payment_confirmed = False
        self.payment_confirmed_at = None
        self.payment_provider = ""
        self.payment_reference = ""
        self.payment_event_id = ""
        self.payment_amount = None
        self.payment_currency = ""

    def mark_failed(self):
        if self.status not in (InvoiceStatus.PAID, InvoiceStatus.CANCELLED):
            self.status = InvoiceStatus.FAILED

    def mark_cancelled(self, *, force: bool = False):
        if force or self.status != InvoiceStatus.PAID:
            self.status = InvoiceStatus.CANCELLED
            self.cancelled_at = timezone.now()

    def mark_refunded(self):
        self.status = InvoiceStatus.REFUNDED
        self.cancelled_at = timezone.now()

    def requires_payment_confirmation(self) -> bool:
        return money_round(Decimal(self.total or 0)) > Decimal("0.00")

    def is_payment_effective(self) -> bool:
        if self.status != InvoiceStatus.PAID:
            return False
        if not self.requires_payment_confirmation():
            return True
        return bool(self.payment_confirmed)

    def uses_trusted_payment_flow(self) -> bool:
        return self.reference_type in TRUSTED_PAYMENT_REFERENCE_TYPES

    def _ensure_code(self):
        if not self.code and self.pk:
            self.code = f"IV{self.pk:06d}"
            Invoice.objects.filter(pk=self.pk).update(code=self.code)

    def save(self, *args, **kwargs):
        self.recalc()
        is_new = self.pk is None
        super().save(*args, **kwargs)
        if is_new:
            # توليد code بعد pk
            self._ensure_code()

    def __str__(self):
        return self.code or f"Invoice#{self.pk}"


class InvoiceLineItem(models.Model):
    invoice = models.ForeignKey(Invoice, on_delete=models.CASCADE, related_name="lines")

    item_code = models.CharField(max_length=20, blank=True, default="")
    title = models.CharField(max_length=160)
    amount = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal("0.00"))

    sort_order = models.PositiveIntegerField(default=0)

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["sort_order", "id"]

    def __str__(self):
        return f"{self.invoice_id} {self.item_code or ''} {self.amount}"


class PaymentAttempt(models.Model):
    """
    محاولة دفع مرتبطة بفواتير.
    Idempotency مهم لتجنب تكرار الدفع.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    invoice = models.ForeignKey(Invoice, on_delete=models.CASCADE, related_name="attempts")

    provider = models.CharField(max_length=30, choices=PaymentProvider.choices, default=PaymentProvider.MOCK)
    status = models.CharField(max_length=20, choices=PaymentAttemptStatus.choices, default=PaymentAttemptStatus.INITIATED)

    idempotency_key = models.CharField(max_length=80, blank=True)  # من الكلاينت أو يولد تلقائيًا

    amount = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal("0.00"))
    currency = models.CharField(max_length=10, default="SAR")

    # روابط الدفع
    checkout_url = models.URLField(blank=True)
    provider_reference = models.CharField(max_length=120, blank=True)

    request_payload = models.JSONField(default=dict, blank=True)
    response_payload = models.JSONField(default=dict, blank=True)

    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="payment_attempts",
    )

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=["provider", "provider_reference"]),
            models.Index(fields=["idempotency_key"]),
        ]

    def __str__(self):
        return f"{self.provider} attempt {self.id} ({self.status})"


class WebhookEvent(models.Model):
    """
    حفظ webhook raw لحماية idempotency + التدقيق
    """
    provider = models.CharField(max_length=30, choices=PaymentProvider.choices, default=PaymentProvider.MOCK)
    event_id = models.CharField(max_length=120, blank=True)
    signature = models.CharField(max_length=200, blank=True)

    payload = models.JSONField(default=dict, blank=True)

    received_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=["provider", "event_id"]),
        ]
        constraints = [
            models.UniqueConstraint(
                fields=["provider", "event_id"],
                condition=models.Q(event_id__gt=""),
                name="billing_webhookevent_provider_event_unique",
            ),
        ]

    def __str__(self):
        return f"{self.provider} webhook {self.event_id or self.pk}"
