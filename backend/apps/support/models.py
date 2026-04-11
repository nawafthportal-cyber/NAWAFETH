from __future__ import annotations

from django.conf import settings
from django.db import models
from django.utils import timezone

from .validators import validate_file_size


class SupportTicketType(models.TextChoices):
    TECH = "tech", "دعم فني"
    SUBS = "subs", "اشتراكات"
    VERIFY = "verify", "توثيق"
    SUGGEST = "suggest", "اقتراحات"
    ADS = "ads", "إعلانات"
    COMPLAINT = "complaint", "شكاوى وبلاغات"
    EXTRAS = "extras", "خدمات إضافية"


class SupportTicketStatus(models.TextChoices):
    NEW = "new", "جديد"
    IN_PROGRESS = "in_progress", "تحت المعالجة"
    RETURNED = "returned", "معاد للعميل"
    CLOSED = "closed", "مغلق"


class SupportPriority(models.TextChoices):
    LOW = "low", "منخفضة"
    NORMAL = "normal", "عادية"
    HIGH = "high", "عالية"


class SupportTicketEntrypoint(models.TextChoices):
    CONTACT_PLATFORM = "contact_platform", "تواصل مع المنصة"
    MESSAGING_REPORT = "messaging_report", "بلاغ المحادثات"


class SupportTeam(models.Model):
    """
    فرق الدعم (قابلة للإدارة من الأدمن):
    - الدعم الفني
    - الاشتراكات
    - التوثيق
    - إدارة المحتوى
    - الترويج
    - الخدمات الإضافية
    """
    code = models.SlugField(max_length=50, unique=True)
    name_ar = models.CharField(max_length=120)
    dashboard_code = models.CharField(max_length=50, blank=True, default="")
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["sort_order", "id"]

    def __str__(self) -> str:
        return self.name_ar


class SupportTicket(models.Model):
    """
    تذكرة دعم HDxxxx
    """
    code = models.CharField(max_length=20, unique=True, blank=True)

    requester = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="support_tickets",
    )

    ticket_type = models.CharField(max_length=20, choices=SupportTicketType.choices)
    status = models.CharField(max_length=20, choices=SupportTicketStatus.choices, default=SupportTicketStatus.NEW)
    priority = models.CharField(max_length=20, choices=SupportPriority.choices, default=SupportPriority.NORMAL)
    entrypoint = models.CharField(
        max_length=32,
        choices=SupportTicketEntrypoint.choices,
        default=SupportTicketEntrypoint.CONTACT_PLATFORM,
    )

    description = models.CharField(max_length=300)

    assigned_team = models.ForeignKey(
        SupportTeam, on_delete=models.SET_NULL, null=True, blank=True, related_name="tickets"
    )
    assigned_to = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="assigned_support_tickets",
    )

    assigned_at = models.DateTimeField(null=True, blank=True)
    returned_at = models.DateTimeField(null=True, blank=True)
    closed_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    last_action_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="support_actions",
    )

    # Complaint/Report target (optional)
    reported_kind = models.CharField(max_length=30, blank=True, default="")
    reported_object_id = models.CharField(max_length=50, blank=True, default="")
    reported_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="reported_support_tickets",
    )

    def __str__(self) -> str:
        return self.code or f"HD-ticket-{self.pk}"

    def _ensure_code(self):
        if not self.code and self.pk:
            self.code = f"HD{self.pk:06d}"
            SupportTicket.objects.filter(pk=self.pk).update(code=self.code)

    def save(self, *args, **kwargs):
        is_new = self.pk is None
        super().save(*args, **kwargs)

        if is_new:
            # توليد code بعد الحصول على pk (لا نعتمد على on_commit لأن اختبارات pytest
            # تعمل داخل transaction وقد تؤخر on_commit حتى نهاية الاختبار)
            self._ensure_code()


class SupportAttachment(models.Model):
    ticket = models.ForeignKey(SupportTicket, on_delete=models.CASCADE, related_name="attachments")
    file = models.FileField(upload_to="support/attachments/%Y/%m/", validators=[validate_file_size])

    uploaded_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.ticket.code} attachment #{self.pk}"


class SupportComment(models.Model):
    ticket = models.ForeignKey(SupportTicket, on_delete=models.CASCADE, related_name="comments")
    text = models.CharField(max_length=300)

    is_internal = models.BooleanField(default=False)  # تعليق داخلي للفريق فقط
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.ticket.code} comment #{self.pk}"


class SupportStatusLog(models.Model):
    ticket = models.ForeignKey(SupportTicket, on_delete=models.CASCADE, related_name="status_logs")
    from_status = models.CharField(max_length=20, choices=SupportTicketStatus.choices)
    to_status = models.CharField(max_length=20, choices=SupportTicketStatus.choices)

    changed_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    note = models.CharField(max_length=200, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-id"]
