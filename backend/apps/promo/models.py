from __future__ import annotations

from decimal import Decimal
from django.conf import settings
from django.db import models
from django.utils import timezone

from apps.providers.models import ProviderProfile, ProviderPortfolioItem

from .validators import validate_file_size, validate_extension


class PromoRequestStatus(models.TextChoices):
    NEW = "new", "جديد"
    IN_REVIEW = "in_review", "قيد المراجعة"
    QUOTED = "quoted", "تم التسعير"
    PENDING_PAYMENT = "pending_payment", "بانتظار الدفع"
    ACTIVE = "active", "مفعل"
    REJECTED = "rejected", "مرفوض"
    EXPIRED = "expired", "منتهي"
    CANCELLED = "cancelled", "ملغي"


class PromoAdType(models.TextChoices):
    BANNER_HOME = "banner_home", "بانر الصفحة الرئيسية"
    BANNER_CATEGORY = "banner_category", "بانر صفحة القسم"
    BANNER_SEARCH = "banner_search", "بانر صفحة البحث"
    POPUP_HOME = "popup_home", "نافذة منبثقة رئيسية"
    POPUP_CATEGORY = "popup_category", "نافذة منبثقة داخل قسم"
    FEATURED_TOP5 = "featured_top5", "تمييز ضمن أول 5"
    FEATURED_TOP10 = "featured_top10", "تمييز ضمن أول 10"
    BOOST_PROFILE = "boost_profile", "تعزيز ملف مقدم الخدمة"
    PUSH_NOTIFICATION = "push_notification", "إشعار دفع (Push)"


class PromoPosition(models.TextChoices):
    FIRST = "first", "الأول"
    SECOND = "second", "الثاني"
    TOP5 = "top5", "ضمن أول 5"
    TOP10 = "top10", "ضمن أول 10"
    NORMAL = "normal", "عادي"


class PromoFrequency(models.TextChoices):
    S10 = "10s", "كل 10 ثواني"
    S20 = "20s", "كل 20 ثانية"
    S30 = "30s", "كل 30 ثانية"
    S60 = "60s", "كل 60 ثانية"


class PromoAssetType(models.TextChoices):
    IMAGE = "image", "صورة"
    VIDEO = "video", "فيديو"
    PDF = "pdf", "ملف PDF"
    OTHER = "other", "ملف إضافي"


class PromoRequest(models.Model):
    """
    MDxxxx - طلب إعلان
    """
    code = models.CharField(max_length=20, unique=True, blank=True)

    requester = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="promo_requests",
    )

    # Backoffice assignment (for AccessLevel.USER scoping)
    assigned_to = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="assigned_promo_requests",
    )
    assigned_at = models.DateTimeField(null=True, blank=True)

    title = models.CharField(max_length=160)
    ad_type = models.CharField(max_length=30, choices=PromoAdType.choices)

    # جدولة الحملة
    start_at = models.DateTimeField()
    end_at = models.DateTimeField()

    # معدل الظهور + موقع الظهور
    frequency = models.CharField(max_length=10, choices=PromoFrequency.choices, default=PromoFrequency.S60)
    position = models.CharField(max_length=10, choices=PromoPosition.choices, default=PromoPosition.NORMAL)

    # مستهدفات (اختياري)
    target_category = models.CharField(max_length=80, blank=True)  # مثال: "صالات", "كهرباء"...
    target_city = models.CharField(max_length=80, blank=True)

    # Target entities (optional; used for featured strips / boosts / sponsored content)
    target_provider = models.ForeignKey(
        ProviderProfile,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="promo_requests",
    )
    target_portfolio_item = models.ForeignKey(
        ProviderPortfolioItem,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="promo_requests",
    )

    # Promo message/push payload (optional)
    message_title = models.CharField(max_length=160, blank=True, default="")
    message_body = models.CharField(max_length=500, blank=True, default="")

    # رابط توجيه (اختياري)
    redirect_url = models.URLField(blank=True)

    status = models.CharField(max_length=25, choices=PromoRequestStatus.choices, default=PromoRequestStatus.NEW)

    # التسعير (يحسب بالسيرفس)
    subtotal = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal("0.00"))
    total_days = models.PositiveIntegerField(default=0)

    quote_note = models.CharField(max_length=300, blank=True)
    reject_reason = models.CharField(max_length=300, blank=True)

    invoice = models.ForeignKey(
        "billing.Invoice",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="promo_requests",
    )

    reviewed_at = models.DateTimeField(null=True, blank=True)
    activated_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def _ensure_code(self):
        if not self.code and self.pk:
            self.code = f"MD{self.pk:06d}"
            PromoRequest.objects.filter(pk=self.pk).update(code=self.code)

    def save(self, *args, **kwargs):
        is_new = self.pk is None
        super().save(*args, **kwargs)
        if is_new:
            # لا نعتمد على on_commit لأن اختبارات pytest تعمل داخل transaction
            # وقد تؤخر توليد code حتى نهاية الاختبار.
            self._ensure_code()

    def __str__(self):
        return self.code or f"MD-request-{self.pk}"


class PromoAsset(models.Model):
    request = models.ForeignKey(PromoRequest, on_delete=models.CASCADE, related_name="assets")

    asset_type = models.CharField(max_length=20, choices=PromoAssetType.choices, default=PromoAssetType.IMAGE)
    title = models.CharField(max_length=160, blank=True)

    file = models.FileField(
        upload_to="promo/assets/%Y/%m/",
        validators=[validate_file_size, validate_extension],
    )

    uploaded_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    uploaded_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.request.code} asset#{self.pk}"


class PromoAdPrice(models.Model):
    """DB-backed base price per day for each promo ad type.

    Used by dashboard pricing screen. When present, it overrides
    settings.PROMO_BASE_PRICES for that ad_type.
    """

    ad_type = models.CharField(max_length=30, choices=PromoAdType.choices, unique=True)
    price_per_day = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal("0.00"))
    is_active = models.BooleanField(default=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["ad_type"]

    def __str__(self):
        return f"{self.ad_type}: {self.price_per_day}"
