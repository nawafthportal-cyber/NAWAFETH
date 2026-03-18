from __future__ import annotations

from datetime import timedelta

from django.conf import settings
from django.db import models
from django.utils import timezone


class ModerationStatus(models.TextChoices):
    NEW = "new", "جديد"
    UNDER_REVIEW = "under_review", "قيد المراجعة"
    ACTION_TAKEN = "action_taken", "تم اتخاذ إجراء"
    DISMISSED = "dismissed", "مرفوض / بدون إجراء"
    ESCALATED = "escalated", "مصعّد"


class ModerationSeverity(models.TextChoices):
    LOW = "low", "منخفضة"
    NORMAL = "normal", "عادية"
    HIGH = "high", "عالية"
    CRITICAL = "critical", "حرجة"


class ModerationActionType(models.TextChoices):
    CREATED = "created", "تم الإنشاء"
    ASSIGNED = "assigned", "تم الإسناد"
    STATUS_CHANGED = "status_changed", "تغيير الحالة"
    DECISION_RECORDED = "decision_recorded", "تسجيل قرار"
    NOTE_ADDED = "note_added", "إضافة ملاحظة"


class ModerationDecisionCode(models.TextChoices):
    HIDE = "hide", "إخفاء"
    DELETE = "delete", "حذف"
    WARN = "warn", "تنبيه"
    NO_ACTION = "no_action", "بدون إجراء"
    ESCALATE = "escalate", "تصعيد"
    CLOSE = "close", "إغلاق"


class ModerationCase(models.Model):
    code = models.CharField(max_length=20, unique=True, blank=True)
    reporter = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="moderation_cases_reported",
    )
    reported_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="moderation_cases_targeted",
    )
    source_app = models.CharField(max_length=50, blank=True)
    source_model = models.CharField(max_length=80, blank=True)
    source_object_id = models.CharField(max_length=50, blank=True)
    source_label = models.CharField(max_length=120, blank=True)
    category = models.CharField(max_length=40, blank=True, default="")
    reason = models.CharField(max_length=120)
    details = models.CharField(max_length=500, blank=True)
    summary = models.CharField(max_length=300, blank=True)
    status = models.CharField(max_length=20, choices=ModerationStatus.choices, default=ModerationStatus.NEW)
    severity = models.CharField(max_length=20, choices=ModerationSeverity.choices, default=ModerationSeverity.NORMAL)
    assigned_team_code = models.SlugField(max_length=50, blank=True)
    assigned_team_name = models.CharField(max_length=120, blank=True)
    assigned_to = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="moderation_cases_assigned",
    )
    assigned_at = models.DateTimeField(null=True, blank=True)
    sla_due_at = models.DateTimeField(null=True, blank=True)
    closed_at = models.DateTimeField(null=True, blank=True)
    linked_support_ticket_id = models.CharField(max_length=50, blank=True, default="")
    linked_support_ticket_code = models.CharField(max_length=20, blank=True, default="")
    snapshot = models.JSONField(default=dict, blank=True)
    meta = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-id"]
        indexes = [
            models.Index(fields=["status", "severity", "created_at"]),
            models.Index(fields=["source_app", "source_model", "source_object_id"]),
            models.Index(fields=["assigned_to", "status"]),
        ]

    def save(self, *args, **kwargs):
        if not self.summary:
            parts = [self.source_label, self.reason, self.details]
            self.summary = " - ".join([p for p in parts if p]).strip()[:300]
        is_new = self.pk is None
        super().save(*args, **kwargs)
        if is_new and not self.code:
            self.code = f"MC{self.pk:06d}"
            type(self).objects.filter(pk=self.pk).update(code=self.code)

    def __str__(self) -> str:
        return self.code or f"MC#{self.pk}"

    @property
    def is_closed(self) -> bool:
        return self.status in {
            ModerationStatus.ACTION_TAKEN,
            ModerationStatus.DISMISSED,
        }

    @property
    def is_terminal(self) -> bool:
        return self.status in {
            ModerationStatus.ACTION_TAKEN,
            ModerationStatus.DISMISSED,
            ModerationStatus.ESCALATED,
        }

    def sla_state(self, *, now=None) -> str:
        now = now or timezone.now()
        if self.is_terminal:
            return "closed"
        if not self.sla_due_at:
            return "none"
        if self.sla_due_at <= now:
            return "overdue"
        if self.sla_due_at <= now + timedelta(hours=12):
            return "due_soon"
        return "open"


class ModerationActionLog(models.Model):
    case = models.ForeignKey(ModerationCase, on_delete=models.CASCADE, related_name="action_logs")
    action_type = models.CharField(max_length=30, choices=ModerationActionType.choices)
    from_status = models.CharField(max_length=20, blank=True)
    to_status = models.CharField(max_length=20, blank=True)
    from_assigned_to = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="moderation_assignment_from_logs",
    )
    to_assigned_to = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="moderation_assignment_to_logs",
    )
    note = models.CharField(max_length=500, blank=True)
    payload = models.JSONField(default=dict, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="moderation_action_logs",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-id"]


class ModerationDecision(models.Model):
    case = models.ForeignKey(ModerationCase, on_delete=models.CASCADE, related_name="decisions")
    decision_code = models.CharField(max_length=20, choices=ModerationDecisionCode.choices)
    note = models.CharField(max_length=500, blank=True)
    outcome = models.JSONField(default=dict, blank=True)
    is_final = models.BooleanField(default=True)
    applied_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="moderation_decisions_applied",
    )
    applied_at = models.DateTimeField(default=timezone.now)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-id"]
