from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.db import models, transaction
from django.utils import timezone


class PlanPeriod(models.TextChoices):
    MONTH = "month", "شهري"
    YEAR = "year", "سنوي"


class PlanTier(models.TextChoices):
    BASIC = "basic", "أساسية"
    RIYADI = "riyadi", "ريادية"
    PRO = "pro", "احترافية"


class SubscriptionStatus(models.TextChoices):
    PENDING_PAYMENT = "pending_payment", "بانتظار الدفع"
    ACTIVE = "active", "نشط"
    GRACE = "grace", "فترة سماح"
    EXPIRED = "expired", "منتهي"
    CANCELLED = "cancelled", "ملغي"


class FeatureKey(models.TextChoices):
    VERIFY_BLUE = "verify_blue", "توثيق (شارة زرقاء)"
    VERIFY_GREEN = "verify_green", "توثيق (شارة خضراء)"
    PROMO_ADS = "promo_ads", "إعلانات وترويج"
    PRIORITY_SUPPORT = "priority_support", "دعم أولوية"
    EXTRA_UPLOADS = "extra_uploads", "سعة مرفقات إضافية"
    ADVANCED_ANALYTICS = "advanced_analytics", "تحليلات متقدمة"


class SubscriptionPlan(models.Model):
    """
    خطط الاشتراك (باقات).
    """
    code = models.CharField(max_length=30, unique=True)  # BASIC / PRO / ENTERPRISE ...
    tier = models.CharField(max_length=20, choices=PlanTier.choices, default=PlanTier.BASIC)
    title = models.CharField(max_length=80)
    description = models.CharField(max_length=300, blank=True)

    period = models.CharField(max_length=10, choices=PlanPeriod.choices, default=PlanPeriod.MONTH)
    price = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal("0.00"))

    # features: JSON قائمة مفاتيح
    features = models.JSONField(default=list, blank=True)

    is_active = models.BooleanField(default=True)

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["price", "id"]

    def __str__(self):
        return f"{self.code} ({self.get_period_display()})"

    def normalized_tier(self) -> str:
        tier = (self.tier or "").strip().lower()
        if tier in {PlanTier.BASIC, PlanTier.RIYADI, PlanTier.PRO}:
            return tier
        code = (self.code or "").strip().lower()
        if "riyadi" in code or "entrepreneur" in code or "leading" in code:
            return PlanTier.RIYADI
        if "pro" in code or "professional" in code:
            return PlanTier.PRO
        return PlanTier.BASIC


class Subscription(models.Model):
    """
    اشتراك مستخدم في خطة.
    """
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="subscriptions")

    plan = models.ForeignKey(SubscriptionPlan, on_delete=models.PROTECT, related_name="subscriptions")

    status = models.CharField(max_length=20, choices=SubscriptionStatus.choices, default=SubscriptionStatus.PENDING_PAYMENT)

    start_at = models.DateTimeField(null=True, blank=True)
    end_at = models.DateTimeField(null=True, blank=True)

    grace_end_at = models.DateTimeField(null=True, blank=True)

    auto_renew = models.BooleanField(default=True)

    invoice = models.ForeignKey(
        "billing.Invoice",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="subscriptions",
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def calc_end_date(self, start: timezone.datetime):
        if self.plan.period == PlanPeriod.YEAR:
            return start + timedelta(days=365)
        return start + timedelta(days=30)

    def __str__(self):
        return f"SUB#{self.pk} {self.user_id} {self.plan.code} {self.status}"
