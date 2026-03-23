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


class AccessPermission(models.Model):
    """
    كتالوج صلاحيات الأفعال الحساسة داخل التشغيل الداخلي.
    """
    code = models.SlugField(max_length=80, unique=True)
    name_ar = models.CharField(max_length=120)
    dashboard_code = models.SlugField(max_length=50, blank=True)
    description = models.CharField(max_length=255, blank=True)
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
    granted_permissions = models.ManyToManyField(
        AccessPermission,
        blank=True,
        related_name="access_profiles",
    )

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
    CLIENT_ALLOWED_DASHBOARDS = frozenset({"client_extras"})

    # Dashboards that admin/power should NOT access (client-only portals)
    CLIENT_ONLY_DASHBOARDS = frozenset({"client_extras"})

    def is_allowed(self, dashboard_code: str) -> bool:
        normalized_dashboard_code = str(dashboard_code or "").strip().lower()
        if normalized_dashboard_code in {"access", "admin"}:
            normalized_dashboard_code = "admin_control"
        if self.level == AccessLevel.ADMIN:
            return normalized_dashboard_code not in self.CLIENT_ONLY_DASHBOARDS
        if self.level == AccessLevel.CLIENT:
            return normalized_dashboard_code in self.CLIENT_ALLOWED_DASHBOARDS
        return self.allowed_dashboards.filter(code=normalized_dashboard_code, is_active=True).exists()

    def granted_permission_codes(self) -> list[str]:
        if self.level in (AccessLevel.ADMIN, AccessLevel.POWER):
            return list(
                AccessPermission.objects.filter(is_active=True)
                .order_by("sort_order", "id")
                .values_list("code", flat=True)
            )
        return list(
            self.granted_permissions.filter(is_active=True)
            .order_by("sort_order", "id")
            .values_list("code", flat=True)
        )

    def has_permission_code(self, permission_code: str) -> bool:
        code = (permission_code or "").strip().lower()
        if not code:
            return False
        if self.level in (AccessLevel.ADMIN, AccessLevel.POWER):
            return True
        if self.level == AccessLevel.CLIENT:
            return False
        return self.granted_permissions.filter(code=code, is_active=True).exists()

    def __str__(self) -> str:
        return f"{self.user_id} access={self.level}"
