from __future__ import annotations

from decimal import Decimal

from django.conf import settings
from django.db import models
from django.utils import timezone

from apps.providers.models import ProviderProfile


class AnalyticsChannel(models.TextChoices):
    SERVER = "server", "Server"
    FLUTTER = "flutter", "Flutter"
    MOBILE_WEB = "mobile_web", "Mobile Web"


class AnalyticsEvent(models.Model):
    event_name = models.CharField(max_length=80, db_index=True)
    channel = models.CharField(max_length=20, choices=AnalyticsChannel.choices, default=AnalyticsChannel.SERVER)
    surface = models.CharField(max_length=120, blank=True, default="")
    source_app = models.CharField(max_length=50, blank=True, default="")
    object_type = models.CharField(max_length=80, blank=True, default="")
    object_id = models.CharField(max_length=50, blank=True, default="")
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="analytics_events",
    )
    session_id = models.CharField(max_length=64, blank=True, default="")
    dedupe_key = models.CharField(max_length=160, blank=True, default="", db_index=True)
    version = models.PositiveSmallIntegerField(default=1)
    occurred_at = models.DateTimeField(default=timezone.now, db_index=True)
    payload = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-occurred_at", "-id"]
        indexes = [
            models.Index(fields=["event_name", "occurred_at"]),
            models.Index(fields=["channel", "occurred_at"]),
            models.Index(fields=["object_type", "object_id"]),
        ]

    def __str__(self) -> str:
        label = self.object_type or self.source_app or "event"
        return f"{self.event_name} [{label}]"


class ProviderDailyStats(models.Model):
    day = models.DateField(db_index=True)
    provider = models.ForeignKey(
        ProviderProfile,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="analytics_daily_stats",
    )
    profile_views = models.PositiveIntegerField(default=0)
    chat_starts = models.PositiveIntegerField(default=0)
    requests_received = models.PositiveIntegerField(default=0)
    requests_accepted = models.PositiveIntegerField(default=0)
    requests_completed = models.PositiveIntegerField(default=0)
    requests_cancelled = models.PositiveIntegerField(default=0)
    accept_rate = models.DecimalField(max_digits=6, decimal_places=2, default=Decimal("0.00"))
    completion_rate = models.DecimalField(max_digits=6, decimal_places=2, default=Decimal("0.00"))
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-day", "-requests_received", "-profile_views", "provider_id"]
        unique_together = ("day", "provider")
        indexes = [
            models.Index(fields=["day", "provider"]),
        ]

    def __str__(self) -> str:
        return f"ProviderDailyStats({self.day}, provider={self.provider_id})"


class CampaignDailyStats(models.Model):
    day = models.DateField(db_index=True)
    campaign_key = models.CharField(max_length=80, db_index=True)
    campaign_kind = models.CharField(max_length=40, blank=True, default="")
    label = models.CharField(max_length=160, blank=True, default="")
    object_type = models.CharField(max_length=80, blank=True, default="")
    object_id = models.CharField(max_length=50, blank=True, default="")
    source_app = models.CharField(max_length=50, blank=True, default="")
    impressions = models.PositiveIntegerField(default=0)
    popup_opens = models.PositiveIntegerField(default=0)
    clicks = models.PositiveIntegerField(default=0)
    leads = models.PositiveIntegerField(default=0)
    conversions = models.PositiveIntegerField(default=0)
    ctr = models.DecimalField(max_digits=6, decimal_places=2, default=Decimal("0.00"))
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-day", "-impressions", "-clicks", "campaign_key"]
        unique_together = ("day", "campaign_key")
        indexes = [
            models.Index(fields=["day", "campaign_key"]),
            models.Index(fields=["day", "campaign_kind"]),
        ]

    def __str__(self) -> str:
        return f"CampaignDailyStats({self.day}, {self.campaign_key})"


class SubscriptionDailyStats(models.Model):
    day = models.DateField(db_index=True)
    plan_code = models.CharField(max_length=30, blank=True, default="", db_index=True)
    plan_title = models.CharField(max_length=120, blank=True, default="")
    tier = models.CharField(max_length=20, blank=True, default="")
    checkouts_started = models.PositiveIntegerField(default=0)
    activations = models.PositiveIntegerField(default=0)
    upgrades = models.PositiveIntegerField(default=0)
    renewals = models.PositiveIntegerField(default=0)
    churns = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-day", "-activations", "plan_code"]
        unique_together = ("day", "plan_code")
        indexes = [
            models.Index(fields=["day", "plan_code"]),
            models.Index(fields=["day", "tier"]),
        ]

    def __str__(self) -> str:
        return f"SubscriptionDailyStats({self.day}, {self.plan_code or 'unknown'})"


class ExtrasDailyStats(models.Model):
    day = models.DateField(db_index=True)
    sku = models.CharField(max_length=80, db_index=True)
    title = models.CharField(max_length=160, blank=True, default="")
    extra_type = models.CharField(max_length=20, blank=True, default="")
    purchases = models.PositiveIntegerField(default=0)
    activations = models.PositiveIntegerField(default=0)
    consumptions = models.PositiveIntegerField(default=0)
    credits_consumed = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-day", "-purchases", "sku"]
        unique_together = ("day", "sku")
        indexes = [
            models.Index(fields=["day", "sku"]),
            models.Index(fields=["day", "extra_type"]),
        ]

    def __str__(self) -> str:
        return f"ExtrasDailyStats({self.day}, {self.sku})"
