from __future__ import annotations

from django.conf import settings
from django.db import models


class UnifiedRequestType(models.TextChoices):
    HELPDESK = "helpdesk", "دعم ومساعدة (HD)"
    PROMO = "promo", "إعلانات وترويج (MD)"
    VERIFICATION = "verification", "توثيق (AD)"
    SUBSCRIPTION = "subscription", "ترقية واشتراكات (SD)"
    EXTRAS = "extras", "خدمات إضافية (P)"


UNIFIED_REQUEST_PREFIX_MAP: dict[str, str] = {
    UnifiedRequestType.HELPDESK: "HD",
    UnifiedRequestType.PROMO: "MD",
    UnifiedRequestType.VERIFICATION: "AD",
    UnifiedRequestType.SUBSCRIPTION: "SD",
    UnifiedRequestType.EXTRAS: "P",
}


class UnifiedRequestStatus(models.TextChoices):
    NEW = "new", "جديد"
    IN_PROGRESS = "in_progress", "تحت المعالجة"
    RETURNED = "returned", "معاد للعميل"
    CLOSED = "closed", "مغلق"
    COMPLETED = "completed", "مكتمل"
    REJECTED = "rejected", "مرفوض"
    PENDING_PAYMENT = "pending_payment", "بانتظار الدفع"
    ACTIVE = "active", "مفعل"
    EXPIRED = "expired", "منتهي"
    CANCELLED = "cancelled", "ملغي"


class UnifiedRequestPriority(models.TextChoices):
    BASIC = "basic", "الأساسية"
    LEADING = "leading", "الريادية"
    PROFESSIONAL = "professional", "الاحترافية"
    LOW = "low", "منخفضة"
    NORMAL = "normal", "عادية"
    HIGH = "high", "عالية"


class UnifiedRequest(models.Model):
    code = models.CharField(max_length=20, unique=True, blank=True)
    request_type = models.CharField(max_length=20, choices=UnifiedRequestType.choices)
    status = models.CharField(max_length=30, choices=UnifiedRequestStatus.choices, default=UnifiedRequestStatus.NEW)
    priority = models.CharField(max_length=20, choices=UnifiedRequestPriority.choices, default=UnifiedRequestPriority.NORMAL)

    requester = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="unified_requests",
    )
    assigned_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="assigned_unified_requests",
    )

    # Team is kept generic to avoid coupling the engine to one module's team table.
    assigned_team_code = models.SlugField(max_length=50, blank=True)
    assigned_team_name = models.CharField(max_length=120, blank=True)

    # Link to source module record (incremental integration path)
    source_app = models.CharField(max_length=50, blank=True)
    source_model = models.CharField(max_length=80, blank=True)
    source_object_id = models.CharField(max_length=50, blank=True)

    summary = models.CharField(max_length=300, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    assigned_at = models.DateTimeField(null=True, blank=True)
    closed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-id"]
        indexes = [
            models.Index(fields=["request_type", "status"]),
            models.Index(fields=["assigned_user", "status"]),
            models.Index(fields=["source_app", "source_model", "source_object_id"]),
        ]
        constraints = [
            models.UniqueConstraint(
                fields=["source_app", "source_model", "source_object_id"],
                condition=(
                    models.Q(source_app__gt="")
                    & models.Q(source_model__gt="")
                    & models.Q(source_object_id__gt="")
                ),
                name="uq_unified_request_source_ref",
            )
        ]

    def __str__(self) -> str:
        return self.code or f"UR#{self.pk}"

    def _ensure_code(self):
        if self.code or not self.pk:
            return
        prefix = UNIFIED_REQUEST_PREFIX_MAP.get(self.request_type, "UR")
        self.code = f"{prefix}{self.pk:06d}"
        UnifiedRequest.objects.filter(pk=self.pk).update(code=self.code)

    def save(self, *args, **kwargs):
        is_new = self.pk is None
        super().save(*args, **kwargs)
        if is_new:
            self._ensure_code()


class UnifiedRequestMetadata(models.Model):
    request = models.OneToOneField(UnifiedRequest, on_delete=models.CASCADE, related_name="metadata_record")
    payload = models.JSONField(default=dict, blank=True)
    updated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="updated_unified_request_metadata",
    )
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return f"{self.request.code} metadata"


class UnifiedRequestAssignmentLog(models.Model):
    request = models.ForeignKey(UnifiedRequest, on_delete=models.CASCADE, related_name="assignment_logs")
    from_team_code = models.SlugField(max_length=50, blank=True)
    to_team_code = models.SlugField(max_length=50, blank=True)
    from_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="unified_request_assignment_from_logs",
    )
    to_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="unified_request_assignment_to_logs",
    )
    changed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="unified_request_assignment_changed_logs",
    )
    note = models.CharField(max_length=200, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-id"]


class UnifiedRequestStatusLog(models.Model):
    request = models.ForeignKey(UnifiedRequest, on_delete=models.CASCADE, related_name="status_logs")
    from_status = models.CharField(max_length=30, blank=True)
    to_status = models.CharField(max_length=30, choices=UnifiedRequestStatus.choices)
    changed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="unified_request_status_changed_logs",
    )
    note = models.CharField(max_length=200, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-id"]
