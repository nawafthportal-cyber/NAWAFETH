from __future__ import annotations

from django.conf import settings
from django.db import models
from django.utils import timezone


class AccessLevel(models.TextChoices):
    ADMIN = "admin", "Admin"
    POWER = "power", "Power User"
    USER = "user", "User"
    QA = "qa", "QA (Read Only)"
    CLIENT = "client", "Client Portal"


class Dashboard(models.Model):
    """
    تمثل لوحة تشغيل داخل النظام.
    أمثلة: support, content, promo, verify, subs, extras, analytics
    """
    code = models.SlugField(max_length=50, unique=True)
    name_ar = models.CharField(max_length=120)
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["sort_order", "id"]

    def __str__(self) -> str:
        return f"{self.code} - {self.name_ar}"


class UserAccessProfile(models.Model):
    """
    ربط المستخدم بصلاحيات التشغيل.
    - level: مستوى الصلاحيات
    - allowed_dashboards: اللوحات المسموحة
    - expires_at: تاريخ انتهاء صلاحية الدخول للوحات التشغيل (اختياري)
    - revoked_at: سحب الصلاحية (اختياري)
    """
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="access_profile",
    )
    level = models.CharField(max_length=20, choices=AccessLevel.choices, default=AccessLevel.USER)
    allowed_dashboards = models.ManyToManyField(Dashboard, blank=True, related_name="users")

    expires_at = models.DateTimeField(null=True, blank=True)
    revoked_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def is_expired(self) -> bool:
        if self.expires_at and timezone.now() >= self.expires_at:
            return True
        return False

    def is_revoked(self) -> bool:
        return self.revoked_at is not None

    def is_readonly(self) -> bool:
        return self.level == AccessLevel.QA

    # Dashboards that Client-level users can access
    CLIENT_ALLOWED_DASHBOARDS = frozenset({"extras"})

    def is_allowed(self, dashboard_code: str) -> bool:
        if self.level in (AccessLevel.ADMIN, AccessLevel.POWER):
            return True
        if self.level == AccessLevel.CLIENT:
            return dashboard_code in self.CLIENT_ALLOWED_DASHBOARDS
        return self.allowed_dashboards.filter(code=dashboard_code, is_active=True).exists()

    def __str__(self) -> str:
        return f"{self.user_id} access={self.level}"
