from __future__ import annotations

from decimal import Decimal
from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.utils import timezone

from apps.providers.models import ProviderProfile, ProviderPortfolioItem
from apps.support.models import SupportTicket

from .home_banner_media import normalize_home_banner_media_upload
from .validators import validate_file_size, validate_extension, validate_home_banner_media_dimensions


_HOME_BANNER_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png"}
_HOME_BANNER_VIDEO_EXTENSIONS = {".mp4"}


def _file_extension(file_obj) -> str:
    name = str(getattr(file_obj, "name", "") or "").lower().strip()
    if "." not in name:
        return ""
    return "." + name.rsplit(".", 1)[-1]


def _detect_home_banner_media_type(file_obj) -> str | None:
    ext = _file_extension(file_obj)
    content_type = str(getattr(file_obj, "content_type", "") or "").lower().strip()
    if content_type.startswith("image/") or ext in _HOME_BANNER_IMAGE_EXTENSIONS:
        return HomeBannerMediaType.IMAGE
    if content_type.startswith("video/") or ext in _HOME_BANNER_VIDEO_EXTENSIONS:
        return HomeBannerMediaType.VIDEO
    return None


class PromoRequestStatus(models.TextChoices):
    NEW = "new", "جديد"
    IN_REVIEW = "in_review", "قيد المراجعة"
    QUOTED = "quoted", "تم التسعير"
    PENDING_PAYMENT = "pending_payment", "بانتظار الدفع"
    ACTIVE = "active", "مفعل"
    COMPLETED = "completed", "مكتمل"
    REJECTED = "rejected", "مرفوض"
    EXPIRED = "expired", "منتهي"
    CANCELLED = "cancelled", "ملغي"


class PromoAdType(models.TextChoices):
    BUNDLE = "bundle", "طلب ترويج متعدد الخدمات"
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


class PromoOpsStatus(models.TextChoices):
    NEW = "new", "جديد"
    IN_PROGRESS = "in_progress", "تحت المعالجة"
    COMPLETED = "completed", "مكتمل"


class PromoServiceType(models.TextChoices):
    HOME_BANNER = "home_banner", "بنر الصفحة الرئيسية"
    FEATURED_SPECIALISTS = "featured_specialists", "شريط أبرز المختصين"
    PORTFOLIO_SHOWCASE = "portfolio_showcase", "شريط البنرات والمشاريع"
    SNAPSHOTS = "snapshots", "شريط اللمحات"
    SEARCH_RESULTS = "search_results", "الظهور في قوائم البحث"
    PROMO_MESSAGES = "promo_messages", "الرسائل الدعائية"
    SPONSORSHIP = "sponsorship", "الرعاية"


class PromoSearchScope(models.TextChoices):
    DEFAULT = "default", "قائمة البحث الافتراضية"
    MAIN_RESULTS = "main_results", "نتائج البحث الرئيسية"
    CATEGORY_MATCH = "category_match", "نتائج البحث المطابقة لتصنيف المختص"


class PromoMessageChannel(models.TextChoices):
    NOTIFICATION = "notification", "رسائل التنبيه الدعائية"
    CHAT = "chat", "رسائل المحادثات الدعائية"


class PromoPriceUnit(models.TextChoices):
    DAY = "day", "لكل يوم"
    CAMPAIGN = "campaign", "لكل حملة"
    MONTH = "month", "لكل شهر"


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

    # موقع الظهور
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
    mobile_scale = models.PositiveSmallIntegerField(
        "حجم محتوى بانر الرئيسية للجوال (%)",
        default=100,
        validators=[MinValueValidator(40), MaxValueValidator(140)],
    )
    tablet_scale = models.PositiveSmallIntegerField(
        "حجم محتوى بانر الرئيسية للأجهزة المتوسطة (%)",
        default=100,
        validators=[MinValueValidator(40), MaxValueValidator(150)],
    )
    desktop_scale = models.PositiveSmallIntegerField(
        "حجم محتوى بانر الرئيسية للديسكتوب (%)",
        default=100,
        validators=[MinValueValidator(40), MaxValueValidator(160)],
    )

    status = models.CharField(max_length=25, choices=PromoRequestStatus.choices, default=PromoRequestStatus.NEW)

    # التسعير (يحسب بالسيرفس)
    subtotal = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal("0.00"))
    total_days = models.PositiveIntegerField(default=0)

    quote_note = models.CharField(max_length=300, blank=True)
    reject_reason = models.CharField(max_length=300, blank=True)
    ops_status = models.CharField(max_length=20, choices=PromoOpsStatus.choices, default=PromoOpsStatus.NEW)

    invoice = models.ForeignKey(
        "billing.Invoice",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="promo_requests",
    )

    reviewed_at = models.DateTimeField(null=True, blank=True)
    activated_at = models.DateTimeField(null=True, blank=True)
    ops_started_at = models.DateTimeField(null=True, blank=True)
    ops_completed_at = models.DateTimeField(null=True, blank=True)

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


class PromoRequestItem(models.Model):
    request = models.ForeignKey(PromoRequest, on_delete=models.CASCADE, related_name="items")
    service_type = models.CharField(max_length=40, choices=PromoServiceType.choices)
    title = models.CharField(max_length=160, blank=True, default="")

    start_at = models.DateTimeField(null=True, blank=True)
    end_at = models.DateTimeField(null=True, blank=True)
    send_at = models.DateTimeField(null=True, blank=True)

    search_scope = models.CharField(max_length=30, choices=PromoSearchScope.choices, blank=True, default="")
    search_position = models.CharField(max_length=10, choices=PromoPosition.choices, blank=True, default="")

    target_category = models.CharField(max_length=80, blank=True, default="")
    target_city = models.CharField(max_length=80, blank=True, default="")
    target_provider = models.ForeignKey(
        ProviderProfile,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="promo_request_items",
    )
    target_portfolio_item = models.ForeignKey(
        ProviderPortfolioItem,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="promo_request_items",
    )

    redirect_url = models.URLField(blank=True)
    message_title = models.CharField(max_length=160, blank=True, default="")
    message_body = models.CharField(max_length=500, blank=True, default="")
    use_notification_channel = models.BooleanField(default=False)
    use_chat_channel = models.BooleanField(default=False)
    message_sent_at = models.DateTimeField(null=True, blank=True)
    message_recipients_count = models.PositiveIntegerField(default=0)
    message_dispatch_error = models.CharField(max_length=255, blank=True, default="")
    sponsor_name = models.CharField(max_length=160, blank=True, default="")
    sponsor_url = models.URLField(blank=True)
    sponsorship_months = models.PositiveIntegerField(default=0)
    attachment_specs = models.CharField(max_length=300, blank=True, default="")
    operator_note = models.CharField(max_length=300, blank=True, default="")

    subtotal = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal("0.00"))
    duration_days = models.PositiveIntegerField(default=0)
    pricing_rule_code = models.CharField(max_length=50, blank=True, default="")
    sort_order = models.PositiveIntegerField(default=0)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["sort_order", "id"]
        verbose_name = "بند طلب ترويج"
        verbose_name_plural = "بنود طلبات الترويج"

    def __str__(self):
        return f"{self.request.code} item#{self.pk} {self.service_type}"


class PromoAsset(models.Model):
    request = models.ForeignKey(PromoRequest, on_delete=models.CASCADE, related_name="assets")
    item = models.ForeignKey(
        PromoRequestItem,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="assets",
    )

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


class PromoPricingRule(models.Model):
    code = models.CharField(max_length=50, unique=True)
    service_type = models.CharField(max_length=40, choices=PromoServiceType.choices)
    title = models.CharField(max_length=160)
    unit = models.CharField(max_length=20, choices=PromoPriceUnit.choices, default=PromoPriceUnit.DAY)
    search_position = models.CharField(max_length=10, choices=PromoPosition.choices, blank=True, default="")
    message_channel = models.CharField(max_length=20, choices=PromoMessageChannel.choices, blank=True, default="")
    amount = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal("0.00"))
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveIntegerField(default=0)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["sort_order", "id"]
        verbose_name = "قاعدة تسعير ترويجي"
        verbose_name_plural = "قواعد التسعير الترويجي"

    def __str__(self):
        return f"{self.code}: {self.amount}"


class HomeBannerMediaType(models.TextChoices):
    IMAGE = "image", "صورة"
    VIDEO = "video", "فيديو"


class HomeBanner(models.Model):
    """Dashboard-managed promotional banners displayed on the homepage carousel.

    Admins create/edit these directly from the dashboard promo section.
    Supports static images and short video clips with auto-rotation.
    """

    title = models.CharField("عنوان البانر", max_length=200)
    media_type = models.CharField(
        "نوع الوسائط",
        max_length=10,
        choices=HomeBannerMediaType.choices,
        default=HomeBannerMediaType.IMAGE,
    )
    media_file = models.FileField(
        "ملف الوسائط",
        upload_to="promo/home_banners/%Y/%m/",
        validators=[validate_file_size, validate_extension],
    )
    link_url = models.URLField("رابط التوجيه", blank=True)
    provider = models.ForeignKey(
        ProviderProfile,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        verbose_name="مقدم الخدمة",
        related_name="home_banners",
    )

    display_order = models.PositiveIntegerField("ترتيب العرض", default=0)
    mobile_scale = models.PositiveSmallIntegerField(
        "حجم المحتوى للجوال (%)",
        default=100,
        validators=[MinValueValidator(40), MaxValueValidator(140)],
    )
    tablet_scale = models.PositiveSmallIntegerField(
        "حجم المحتوى للأجهزة المتوسطة (%)",
        default=100,
        validators=[MinValueValidator(40), MaxValueValidator(150)],
    )
    desktop_scale = models.PositiveSmallIntegerField(
        "حجم المحتوى للديسكتوب (%)",
        default=100,
        validators=[MinValueValidator(40), MaxValueValidator(160)],
    )
    is_active = models.BooleanField("مفعل", default=True)
    start_at = models.DateTimeField("تاريخ البداية", null=True, blank=True)
    end_at = models.DateTimeField("تاريخ النهاية", null=True, blank=True)

    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="created_home_banners",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["display_order", "-created_at"]
        verbose_name = "بانر الصفحة الرئيسية"
        verbose_name_plural = "بانرات الصفحة الرئيسية"

    def __str__(self):
        return self.title

    def clean(self):
        super().clean()
        errors = {}
        if self.start_at and self.end_at and self.end_at <= self.start_at:
            errors["end_at"] = "تاريخ النهاية يجب أن يكون بعد تاريخ البداية."

        if self.media_file:
            detected_type = _detect_home_banner_media_type(self.media_file)
            if detected_type is None:
                errors["media_file"] = "بانر الصفحة الرئيسية يقبل الصور أو فيديو MP4 فقط."
            elif self.media_type != detected_type:
                errors["media_type"] = "نوع الوسائط المحدد لا يطابق الملف المرفوع."
            else:
                try:
                    self.media_file = normalize_home_banner_media_upload(
                        self.media_file,
                        asset_type=detected_type,
                        required_validation=True,
                    )
                    validate_home_banner_media_dimensions(self.media_file, asset_type=detected_type)
                except ValidationError as exc:
                    errors["media_file"] = str(exc)

        if errors:
            raise ValidationError(errors)


class PromoInquiryProfile(models.Model):
    ticket = models.OneToOneField(SupportTicket, on_delete=models.CASCADE, related_name="promo_profile")
    linked_request = models.ForeignKey(
        PromoRequest,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="linked_inquiries",
    )
    detailed_request_url = models.URLField(blank=True)
    documentation_note = models.CharField(max_length=300, blank=True, default="")
    operator_comment = models.CharField(max_length=300, blank=True, default="")
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "ملف استفسار ترويجي"
        verbose_name_plural = "ملفات الاستفسارات الترويجية"

    def __str__(self):
        return f"Promo inquiry profile #{self.pk}"
