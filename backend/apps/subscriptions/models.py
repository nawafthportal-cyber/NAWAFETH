from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.db import models, transaction
from django.utils import timezone

from .tiering import canonical_tier_from_inputs


def _normalized_string_list(value) -> list[str]:
    if isinstance(value, dict):
        raw_items = value.keys()
    elif isinstance(value, (list, tuple, set)):
        raw_items = value
    else:
        return []

    items = []
    for item in raw_items:
        text = str(item or "").strip()
        if text:
            items.append(text)
    return items


def _normalized_int_list(value) -> list[int]:
    items = []
    for item in value or []:
        try:
            items.append(int(item))
        except (TypeError, ValueError):
            continue
    return items


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
    feature_bullets = models.JSONField(default=list, blank=True)

    notifications_enabled = models.BooleanField(null=True, blank=True)

    competitive_visibility_delay_hours = models.PositiveIntegerField(null=True, blank=True)
    competitive_visibility_label = models.CharField(max_length=80, blank=True)

    banner_images_limit = models.PositiveIntegerField(null=True, blank=True)
    banner_images_label = models.CharField(max_length=80, blank=True)

    direct_chat_quota = models.PositiveIntegerField(null=True, blank=True)
    direct_chat_label = models.CharField(max_length=80, blank=True)

    promotional_chat_messages_enabled = models.BooleanField(null=True, blank=True)
    promotional_notification_messages_enabled = models.BooleanField(null=True, blank=True)

    reminder_schedule_hours = models.JSONField(default=list, blank=True)
    reminder_policy_label = models.CharField(max_length=120, blank=True)

    support_priority = models.CharField(max_length=20, blank=True)
    support_is_priority = models.BooleanField(null=True, blank=True)
    support_sla_hours = models.PositiveIntegerField(null=True, blank=True)
    support_sla_label = models.CharField(max_length=80, blank=True)

    storage_policy = models.CharField(max_length=30, blank=True)
    storage_label = models.CharField(max_length=80, blank=True)
    storage_multiplier = models.PositiveIntegerField(null=True, blank=True)
    storage_upload_max_mb = models.PositiveIntegerField(null=True, blank=True)

    verification_blue_fee = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    verification_green_fee = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)

    is_active = models.BooleanField(default=True)

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["price", "id"]

    def __str__(self):
        return f"{self.code} ({self.get_period_display()})"

    def feature_keys(self) -> list[str]:
        return _normalized_string_list(self.features)

    def marketing_bullets(self) -> list[str]:
        return _normalized_string_list(self.feature_bullets)

    def reminder_schedule(self) -> list[int]:
        return _normalized_int_list(self.reminder_schedule_hours)

    def normalized_tier(self) -> str:
        return canonical_tier_from_inputs(
            tier=self.tier,
            code=self.code,
            title=self.title,
            features=self.feature_keys(),
        )

    def _derived_label_values(self) -> dict[str, str]:
        from .capabilities import (
            _banner_images_label,
            _direct_chat_label,
            _reminders_label,
            _storage_label,
            _support_sla_label,
            _visibility_label,
        )

        reminder_schedule = self.reminder_schedule()
        storage_policy = str(self.storage_policy or "").strip().lower()
        return {
            "competitive_visibility_label": _visibility_label(
                int(self.competitive_visibility_delay_hours or 0)
            ),
            "banner_images_label": _banner_images_label(int(self.banner_images_limit or 0)),
            "direct_chat_label": _direct_chat_label(int(self.direct_chat_quota or 0)),
            "reminder_policy_label": _reminders_label(reminder_schedule),
            "support_sla_label": _support_sla_label(int(self.support_sla_hours or 0)),
            "storage_label": _storage_label(
                policy=storage_policy,
                multiplier=self.storage_multiplier,
                upload_max_mb=int(self.storage_upload_max_mb or 0),
            ),
        }

    def _label_source_snapshots(self) -> dict[str, tuple[object, ...]]:
        return {
            "competitive_visibility_label": (self.competitive_visibility_delay_hours,),
            "banner_images_label": (self.banner_images_limit,),
            "direct_chat_label": (self.direct_chat_quota,),
            "reminder_policy_label": tuple(self.reminder_schedule()),
            "support_sla_label": (self.support_sla_hours,),
            "storage_label": (
                str(self.storage_policy or "").strip().lower(),
                self.storage_multiplier,
                self.storage_upload_max_mb,
            ),
        }

    def _sync_derived_labels(self) -> set[str]:
        derived_labels = self._derived_label_values()
        synchronized_fields: set[str] = set()

        previous = None
        if self.pk:
            previous = type(self).objects.filter(pk=self.pk).only(
                "competitive_visibility_delay_hours",
                "competitive_visibility_label",
                "banner_images_limit",
                "banner_images_label",
                "direct_chat_quota",
                "direct_chat_label",
                "reminder_schedule_hours",
                "reminder_policy_label",
                "support_sla_hours",
                "support_sla_label",
                "storage_policy",
                "storage_label",
                "storage_multiplier",
                "storage_upload_max_mb",
            ).first()

        previous_snapshots = previous._label_source_snapshots() if previous is not None else {}
        current_snapshots = self._label_source_snapshots()

        for field_name, derived_value in derived_labels.items():
            current_label = str(getattr(self, field_name, "") or "").strip()
            if not current_label:
                setattr(self, field_name, derived_value)
                synchronized_fields.add(field_name)
                continue

            if previous is None:
                continue

            previous_label = str(getattr(previous, field_name, "") or "").strip()
            if (
                current_label == previous_label
                and current_snapshots.get(field_name) != previous_snapshots.get(field_name)
            ):
                setattr(self, field_name, derived_value)
                synchronized_fields.add(field_name)

        return synchronized_fields

    def save(self, *args, **kwargs):
        synchronized_fields = self._sync_derived_labels()
        update_fields = kwargs.get("update_fields")
        if update_fields is not None and synchronized_fields:
            kwargs["update_fields"] = list(dict.fromkeys([*update_fields, *sorted(synchronized_fields)]))
        return super().save(*args, **kwargs)


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
