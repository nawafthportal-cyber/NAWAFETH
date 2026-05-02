from __future__ import annotations

from decimal import Decimal

from django.conf import settings
from django.db import models
from django.db.models import Q
from django.utils import timezone

from apps.providers.models import Category, ProviderProfile, SubCategory


class ExcellenceBadgeType(models.Model):
    code = models.SlugField(max_length=50, unique=True)
    name_ar = models.CharField(max_length=120)
    name_en = models.CharField(max_length=120, blank=True, default="")
    icon = models.CharField(max_length=50, default="workspace_premium")
    color = models.CharField(max_length=20, default="#C0841A")
    description = models.CharField(max_length=255, blank=True, default="")
    description_en = models.CharField(max_length=255, blank=True, default="")
    review_cycle_days = models.PositiveSmallIntegerField(default=90)
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["sort_order", "id"]

    def __str__(self) -> str:
        return self.name_ar


class ExcellenceBadgeCandidateStatus(models.TextChoices):
    PENDING = "pending", "بانتظار الاعتماد"
    APPROVED = "approved", "معتمد"
    REVOKED = "revoked", "مسحوب"
    EXPIRED = "expired", "منتهي"


class ExcellenceBadgeCandidate(models.Model):
    badge_type = models.ForeignKey(
        ExcellenceBadgeType,
        on_delete=models.CASCADE,
        related_name="candidates",
    )
    provider = models.ForeignKey(
        ProviderProfile,
        on_delete=models.CASCADE,
        related_name="excellence_candidates",
    )
    category = models.ForeignKey(
        Category,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="excellence_candidates",
    )
    subcategory = models.ForeignKey(
        SubCategory,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="excellence_candidates",
    )
    evaluation_period_start = models.DateTimeField()
    evaluation_period_end = models.DateTimeField()
    metric_value = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal("0.00"))
    rank_position = models.PositiveIntegerField(default=1)
    followers_count = models.PositiveIntegerField(default=0)
    completed_orders_count = models.PositiveIntegerField(default=0)
    rating_avg = models.DecimalField(max_digits=4, decimal_places=2, default=Decimal("0.00"))
    rating_count = models.PositiveIntegerField(default=0)
    status = models.CharField(
        max_length=20,
        choices=ExcellenceBadgeCandidateStatus.choices,
        default=ExcellenceBadgeCandidateStatus.PENDING,
        db_index=True,
    )
    review_note = models.CharField(max_length=300, blank=True, default="")
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="reviewed_excellence_candidates",
    )
    reviewed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["badge_type__sort_order", "rank_position", "provider_id"]
        constraints = [
            models.UniqueConstraint(
                fields=["badge_type", "provider", "evaluation_period_start", "evaluation_period_end"],
                name="uniq_excellence_candidate_cycle",
            ),
        ]
        indexes = [
            models.Index(fields=["badge_type", "status", "evaluation_period_end"]),
            models.Index(fields=["provider", "evaluation_period_end"]),
        ]

    def __str__(self) -> str:
        return f"{self.provider_id} {self.badge_type.code} rank={self.rank_position}"


class ExcellenceBadgeAward(models.Model):
    badge_type = models.ForeignKey(
        ExcellenceBadgeType,
        on_delete=models.CASCADE,
        related_name="awards",
    )
    provider = models.ForeignKey(
        ProviderProfile,
        on_delete=models.CASCADE,
        related_name="excellence_awards",
    )
    candidate = models.ForeignKey(
        ExcellenceBadgeCandidate,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="awards",
    )
    category_name = models.CharField(max_length=100, blank=True, default="")
    subcategory_name = models.CharField(max_length=100, blank=True, default="")
    metric_value = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal("0.00"))
    rank_position = models.PositiveIntegerField(default=1)
    followers_count = models.PositiveIntegerField(default=0)
    completed_orders_count = models.PositiveIntegerField(default=0)
    rating_avg = models.DecimalField(max_digits=4, decimal_places=2, default=Decimal("0.00"))
    rating_count = models.PositiveIntegerField(default=0)
    awarded_at = models.DateTimeField(default=timezone.now)
    valid_until = models.DateTimeField()
    approved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="approved_excellence_awards",
    )
    approval_note = models.CharField(max_length=300, blank=True, default="")
    is_active = models.BooleanField(default=True)
    revoked_at = models.DateTimeField(null=True, blank=True)
    revoked_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="revoked_excellence_awards",
    )
    revoke_note = models.CharField(max_length=300, blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-is_active", "-awarded_at", "-id"]
        constraints = [
            models.UniqueConstraint(
                fields=["badge_type", "provider"],
                condition=Q(is_active=True),
                name="uniq_active_excellence_award_per_type",
            ),
        ]
        indexes = [
            models.Index(fields=["provider", "is_active", "valid_until"]),
            models.Index(fields=["badge_type", "is_active", "valid_until"]),
        ]

    def __str__(self) -> str:
        return f"{self.provider_id} {self.badge_type.code} active={self.is_active}"
