"""
نماذج الإعدادات المركزية للمنصة.
Singleton PlatformConfig يُدار من Django Admin ويُستخدم كمرجع
للقيم التشغيلية/التجارية في كل مكان بدلًا من hardcoded constants.
"""

from __future__ import annotations

from decimal import Decimal

from django.core.cache import cache
from django.db import models

PLATFORM_CONFIG_CACHE_KEY = "nawafeth:platform_config"
PLATFORM_CONFIG_CACHE_TTL = 300  # 5 minutes


def default_promo_base_prices() -> dict[str, int]:
    return {
        "banner_home": 400,
        "banner_category": 300,
        "banner_search": 250,
        "popup_home": 600,
        "popup_category": 500,
        "featured_top5": 800,
        "featured_top10": 600,
        "boost_profile": 350,
        "push_notification": 700,
    }


def default_promo_position_multipliers() -> dict[str, float]:
    return {
        "first": 1.5,
        "second": 1.2,
        "top5": 1.35,
        "top10": 1.15,
        "normal": 1.0,
    }


def default_promo_frequency_multipliers() -> dict[str, float]:
    return {
        "10s": 1.6,
        "20s": 1.3,
        "30s": 1.1,
        "60s": 1.0,
    }


class PlatformConfig(models.Model):
    """
    Singleton — صف واحد فقط. يحتوي على القيم التشغيلية المشتركة
    القابلة للتعديل من Django Admin.
    """

    # ── الضريبة ──
    vat_percent = models.DecimalField(
        "نسبة ضريبة القيمة المضافة (%)",
        max_digits=5, decimal_places=2, default=Decimal("15.00"),
    )

    # ── الاشتراكات ──
    subscription_grace_days = models.PositiveIntegerField(
        "أيام السماح بعد انتهاء الاشتراك", default=7,
    )
    subscription_yearly_duration_days = models.PositiveIntegerField(
        "مدة الاشتراك السنوي (أيام)", default=365,
    )
    subscription_monthly_duration_days = models.PositiveIntegerField(
        "مدة الاشتراك الشهري (أيام)", default=30,
    )

    # ── التوثيق ──
    verification_validity_days = models.PositiveIntegerField(
        "مدة صلاحية التوثيق (أيام)", default=365,
    )
    verification_currency = models.CharField(
        "عملة رسوم التوثيق", max_length=10, default="SAR",
    )
    verification_reminder_days_before = models.PositiveIntegerField(
        "تنبيه قبل انتهاء التوثيق (أيام)", default=30,
    )

    # ── الترويج ──
    promo_vat_percent = models.DecimalField(
        "نسبة ضريبة الترويج (%)",
        max_digits=5, decimal_places=2, default=Decimal("15.00"),
    )
    promo_min_campaign_hours = models.PositiveIntegerField(
        "الحد الأدنى لمدة الحملة (ساعات)", default=24,
    )
    promo_base_prices = models.JSONField(
        "الأسعار الأساسية legacy للترويج",
        default=default_promo_base_prices,
        blank=True,
    )
    promo_position_multipliers = models.JSONField(
        "مضاعفات مواقع الظهور legacy للترويج",
        default=default_promo_position_multipliers,
        blank=True,
    )
    promo_frequency_multipliers = models.JSONField(
        "مضاعفات تكرار الظهور legacy للترويج",
        default=default_promo_frequency_multipliers,
        blank=True,
    )

    # ── الاشتراكات — تنبيهات ──
    subscription_reminder_days_before = models.CharField(
        "تنبيهات قبل انتهاء الاشتراك (أيام، مفصولة بفاصلة)",
        max_length=100, default="7,3,1",
        help_text="مثال: 7,3,1 — يعني تنبيه قبل 7 و 3 و 1 أيام",
    )

    # ── الخدمات الإضافية ──
    extras_default_duration_days = models.PositiveIntegerField(
        "مدة الخدمة الإضافية الافتراضية (أيام)", default=30,
    )
    extras_short_duration_days = models.PositiveIntegerField(
        "المدة القصيرة للخدمات الإضافية (أيام)", default=7,
    )
    extras_currency = models.CharField(
        "عملة الخدمات الإضافية", max_length=10, default="SAR",
    )

    # ── حدود الرفع ──
    upload_max_file_size_mb = models.PositiveIntegerField(
        "الحد الأقصى لحجم الملف (MB)", default=100,
    )

    # ── التميز ──
    excellence_review_cycle_days = models.PositiveIntegerField(
        "دورة مراجعة التميز (أيام)", default=90,
    )
    excellence_min_rating = models.DecimalField(
        "الحد الأدنى للتقييم للخدمة المتميزة",
        max_digits=3, decimal_places=2, default=Decimal("4.50"),
    )
    excellence_min_orders = models.PositiveIntegerField(
        "الحد الأدنى للطلبات المكتملة (الإنجاز العالي)", default=5,
    )
    excellence_top_n_club = models.PositiveIntegerField(
        "حجم نادي الكبار (top N)", default=100,
    )

    # ── التصدير ──
    export_pdf_max_rows = models.PositiveIntegerField(
        "الحد الأقصى لصفوف PDF", default=200,
    )
    export_xlsx_max_rows = models.PositiveIntegerField(
        "الحد الأقصى لصفوف XLSX", default=2000,
    )

    # ── عام ──
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "إعدادات المنصة"
        verbose_name_plural = "إعدادات المنصة"

    def __str__(self) -> str:
        return "إعدادات المنصة"

    def save(self, *args, **kwargs):
        # Singleton: force pk=1
        self.pk = 1
        super().save(*args, **kwargs)
        cache.delete(PLATFORM_CONFIG_CACHE_KEY)

    def delete(self, *args, **kwargs):
        # Prevent deletion
        pass

    def get_subscription_reminder_days(self) -> list[int]:
        """Parse comma-separated days string into sorted list of ints."""
        raw = self.subscription_reminder_days_before or ""
        days = []
        for part in raw.split(","):
            part = part.strip()
            if part.isdigit():
                days.append(int(part))
        return sorted(set(days), reverse=True)

    def get_verification_reminder_days(self) -> list[int]:
        """Return a list with the single verification reminder threshold."""
        d = self.verification_reminder_days_before
        return [d] if d else []

    def _json_numeric_map(self, value, default: dict[str, object]) -> dict[str, str]:
        source = value if isinstance(value, dict) and value else default
        payload: dict[str, str] = {}
        for key, raw_value in (source or {}).items():
            text_key = str(key or "").strip()
            if not text_key:
                continue
            payload[text_key] = str(raw_value)
        return payload

    def get_promo_base_prices(self) -> dict[str, str]:
        return self._json_numeric_map(self.promo_base_prices, default_promo_base_prices())

    def get_promo_position_multipliers(self) -> dict[str, str]:
        return self._json_numeric_map(
            self.promo_position_multipliers,
            default_promo_position_multipliers(),
        )

    def get_promo_frequency_multipliers(self) -> dict[str, str]:
        return self._json_numeric_map(
            self.promo_frequency_multipliers,
            default_promo_frequency_multipliers(),
        )

    @classmethod
    def load(cls) -> "PlatformConfig":
        """
        Return the singleton instance (cached).
        Creates it with defaults if it doesn't exist.
        """
        obj = cache.get(PLATFORM_CONFIG_CACHE_KEY)
        if obj is not None:
            return obj
        obj, _ = cls.objects.get_or_create(pk=1)
        cache.set(PLATFORM_CONFIG_CACHE_KEY, obj, PLATFORM_CONFIG_CACHE_TTL)
        return obj


class ReminderLog(models.Model):
    """
    يمنع إرسال تنبيه مكرر لنفس المستخدم/السبب/الفترة.
    الـ Celery task يتحقق من وجود سجل قبل الإرسال.
    """

    class ReminderType(models.TextChoices):
        SUBSCRIPTION_EXPIRY = "sub_expiry", "انتهاء الاشتراك"
        VERIFICATION_EXPIRY = "ver_expiry", "انتهاء التوثيق"
        PROMO_COMPLETION = "promo_complete", "انتهاء الحملة الترويجية"

    user = models.ForeignKey(
        "accounts.User",
        on_delete=models.CASCADE,
        related_name="reminder_logs",
    )
    reminder_type = models.CharField(max_length=30, choices=ReminderType.choices)
    reference_id = models.PositiveIntegerField(
        help_text="PK of the related object (Subscription, Badge, Campaign…)",
    )
    days_before = models.PositiveIntegerField(
        help_text="How many days before expiry this reminder was sent",
    )
    sent_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "سجل التنبيهات"
        verbose_name_plural = "سجلات التنبيهات"
        unique_together = ("user", "reminder_type", "reference_id", "days_before")
        indexes = [
            models.Index(fields=["reminder_type", "reference_id", "days_before"]),
        ]

    def __str__(self) -> str:
        return f"{self.reminder_type} → user={self.user_id} ref={self.reference_id} d-{self.days_before}"
