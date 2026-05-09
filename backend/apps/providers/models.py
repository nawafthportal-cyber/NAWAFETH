from decimal import Decimal

from django.conf import settings
from django.db import models
from django.utils import timezone

from apps.accounts.models import User


class RoleContext(models.TextChoices):
    CLIENT = "client", "عميل"
    PROVIDER = "provider", "مزود خدمة"

class Category(models.Model):
    name = models.CharField(max_length=100)
    is_active = models.BooleanField(default=True)

    def __str__(self) -> str:
        return self.name


class SubCategory(models.Model):
    category = models.ForeignKey(
        Category,
        on_delete=models.CASCADE,
        related_name="subcategories",
    )
    name = models.CharField(max_length=100)
    requires_geo_scope = models.BooleanField(default=True)
    allows_urgent_requests = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)

    def __str__(self) -> str:
        return f"{self.category.name} - {self.name}"


class SaudiRegion(models.Model):
    name_ar = models.CharField(max_length=120, unique=True)
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["sort_order", "name_ar", "id"]

    def __str__(self) -> str:
        return self.name_ar


class SaudiCity(models.Model):
    region = models.ForeignKey(SaudiRegion, on_delete=models.CASCADE, related_name="cities")
    name_ar = models.CharField(max_length=120)
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["region__sort_order", "sort_order", "name_ar", "id"]
        constraints = [
            models.UniqueConstraint(fields=["region", "name_ar"], name="uniq_saudi_city_per_region"),
        ]

    def __str__(self) -> str:
        return f"{self.region.name_ar} - {self.name_ar}"


class ProviderProfile(models.Model):
    PROVIDER_TYPE_CHOICES = (
        ("individual", "فرد"),
        ("company", "منشأة"),
    )

    user = models.OneToOneField(
        User,
        on_delete=models.CASCADE,
        related_name="provider_profile",
    )

    provider_type = models.CharField(max_length=20, choices=PROVIDER_TYPE_CHOICES)
    display_name = models.CharField(max_length=150)
    profile_image = models.FileField(upload_to="providers/profile/%Y/%m/", null=True, blank=True)
    cover_image = models.FileField(upload_to="providers/cover/%Y/%m/", null=True, blank=True)
    bio = models.TextField(max_length=300)
    years_experience = models.PositiveIntegerField(default=0)

    whatsapp = models.CharField(max_length=30, null=True, blank=True)
    website = models.URLField(blank=True, default="")
    social_links = models.JSONField(default=list, blank=True)
    languages = models.JSONField(default=list, blank=True)

    country = models.CharField(max_length=100, blank=True, default="")
    region = models.CharField(max_length=100, blank=True, default="")
    city = models.CharField(max_length=100, blank=True, default="")
    lat = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    lng = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    coverage_radius_km = models.PositiveIntegerField(default=10)

    about_details = models.TextField(blank=True, default="")
    qualifications = models.JSONField(default=list, blank=True)
    experiences = models.JSONField(default=list, blank=True)
    content_sections = models.JSONField(default=list, blank=True)
    seo_title = models.CharField(max_length=160, blank=True, default="")
    seo_keywords = models.CharField(max_length=500, blank=True, default="")
    seo_meta_description = models.CharField(max_length=500, blank=True, default="")
    seo_slug = models.CharField(max_length=150, blank=True, default="")

    accepts_urgent = models.BooleanField(default=False)

    is_verified_blue = models.BooleanField(default=False)
    is_verified_green = models.BooleanField(default=False)
    excellence_badges_cache = models.JSONField(default=list, blank=True)

    rating_avg = models.DecimalField(
        max_digits=3,
        decimal_places=2,
        default=Decimal("0.00"),
    )
    rating_count = models.PositiveIntegerField(default=0)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def ordered_cover_gallery(self):
        prefetched = getattr(self, "_prefetched_objects_cache", {}).get("cover_gallery")
        if prefetched is not None:
            return sorted(prefetched, key=lambda item: (int(getattr(item, "sort_order", 0) or 0), int(getattr(item, "id", 0) or 0)))
        return list(self.cover_gallery.all().order_by("sort_order", "id"))

    def seed_cover_gallery_from_legacy_cover(self):
        if not getattr(self, "cover_image", None):
            return None
        existing = self.cover_gallery.order_by("sort_order", "id").first()
        if existing is not None:
            return existing
        return ProviderCoverImage.objects.create(
            provider=self,
            image=self.cover_image,
            sort_order=0,
        )

    def sync_cover_image_from_gallery(self, *, save: bool = True):
        primary = self.cover_gallery.order_by("sort_order", "id").first()
        next_image = getattr(primary, "image", None)
        current_name = str(getattr(getattr(self, "cover_image", None), "name", "") or "").strip()
        next_name = str(getattr(next_image, "name", "") or "").strip()
        if current_name == next_name:
            return primary
        self.cover_image = next_image
        if save:
            self.save(update_fields=["cover_image", "updated_at"])
        return primary

    def __str__(self) -> str:
        return self.display_name


class ProviderCoverImage(models.Model):
    provider = models.ForeignKey(
        ProviderProfile,
        on_delete=models.CASCADE,
        related_name="cover_gallery",
    )
    image = models.FileField(upload_to="providers/cover_gallery/%Y/%m/")
    sort_order = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["sort_order", "id"]

    def __str__(self) -> str:
        return f"CoverImage {self.pk} for Provider {self.provider_id}"


class ProviderPortfolioItem(models.Model):
    FILE_TYPE_CHOICES = (
        ("image", "صورة"),
        ("video", "فيديو"),
        ("document", "ملف PDF"),
    )

    provider = models.ForeignKey(
        ProviderProfile,
        on_delete=models.CASCADE,
        related_name="portfolio_items",
    )
    category = models.ForeignKey(
        Category,
        on_delete=models.SET_NULL,
        related_name="portfolio_items",
        null=True,
        blank=True,
    )
    file_type = models.CharField(max_length=20, choices=FILE_TYPE_CHOICES)
    file = models.FileField(upload_to="providers/portfolio/%Y/%m/")
    thumbnail = models.ImageField(upload_to="providers/portfolio/%Y/%m/thumbs/", null=True, blank=True)
    caption = models.CharField(max_length=200, blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self) -> str:
        return f"PortfolioItem {self.pk} ({self.file_type}) for Provider {self.provider_id}"


class ProviderSpotlightItem(models.Model):
    FILE_TYPE_CHOICES = (
        ("image", "صورة"),
        ("video", "فيديو"),
    )

    provider = models.ForeignKey(
        ProviderProfile,
        on_delete=models.CASCADE,
        related_name="spotlight_items",
    )
    file_type = models.CharField(max_length=20, choices=FILE_TYPE_CHOICES)
    file = models.FileField(upload_to="providers/spotlights/%Y/%m/")
    thumbnail = models.ImageField(upload_to="providers/spotlights/%Y/%m/thumbs/", null=True, blank=True)
    caption = models.CharField(max_length=200, blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self) -> str:
        return f"SpotlightItem {self.pk} ({self.file_type}) for Provider {self.provider_id}"


class ProviderPortfolioLike(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="portfolio_likes",
    )
    item = models.ForeignKey(
        ProviderPortfolioItem,
        on_delete=models.CASCADE,
        related_name="likes",
    )
    role_context = models.CharField(
        max_length=20,
        choices=RoleContext.choices,
        default=RoleContext.CLIENT,
        db_index=True,
    )
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["user", "item", "role_context"], name="uniq_like_user_portfolio_item_role"),
        ]


class ProviderPortfolioSave(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="portfolio_saves",
    )
    item = models.ForeignKey(
        ProviderPortfolioItem,
        on_delete=models.CASCADE,
        related_name="saves",
    )
    role_context = models.CharField(
        max_length=20,
        choices=RoleContext.choices,
        default=RoleContext.CLIENT,
        db_index=True,
    )
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["user", "item", "role_context"], name="uniq_save_user_portfolio_item_role"),
        ]


class ProviderSpotlightLike(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="spotlight_likes",
    )
    item = models.ForeignKey(
        ProviderSpotlightItem,
        on_delete=models.CASCADE,
        related_name="likes",
    )
    role_context = models.CharField(
        max_length=20,
        choices=RoleContext.choices,
        default=RoleContext.CLIENT,
        db_index=True,
    )
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["user", "item", "role_context"], name="uniq_like_user_spotlight_item_role"),
        ]


class ProviderSpotlightSave(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="spotlight_saves",
    )
    item = models.ForeignKey(
        ProviderSpotlightItem,
        on_delete=models.CASCADE,
        related_name="saves",
    )
    role_context = models.CharField(
        max_length=20,
        choices=RoleContext.choices,
        default=RoleContext.CLIENT,
        db_index=True,
    )
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["user", "item", "role_context"], name="uniq_save_user_spotlight_item_role"),
        ]


class ProviderVisibilityBlock(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="provider_visibility_blocks",
    )
    provider = models.ForeignKey(
        ProviderProfile,
        on_delete=models.CASCADE,
        related_name="visibility_blocks",
    )
    role_context = models.CharField(
        max_length=20,
        choices=RoleContext.choices,
        default=RoleContext.CLIENT,
        db_index=True,
    )
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["user", "provider", "role_context"], name="uniq_provider_visibility_block_user_provider_role"),
        ]
        indexes = [
            models.Index(fields=["user", "provider", "role_context"], name="provvis_user_provider_role_idx"),
        ]


class ProviderSpotlightVisibilityBlock(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="provider_spotlight_visibility_blocks",
    )
    spotlight_item = models.ForeignKey(
        ProviderSpotlightItem,
        on_delete=models.CASCADE,
        related_name="visibility_blocks",
    )
    role_context = models.CharField(
        max_length=20,
        choices=RoleContext.choices,
        default=RoleContext.CLIENT,
        db_index=True,
    )
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["user", "spotlight_item", "role_context"], name="uniq_spotlight_visibility_block_user_item_role"),
        ]
        indexes = [
            models.Index(fields=["user", "spotlight_item", "role_context"], name="provspt_user_item_role_idx"),
        ]


class ProviderPortfolioVisibilityBlock(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="provider_portfolio_visibility_blocks",
    )
    portfolio_item = models.ForeignKey(
        ProviderPortfolioItem,
        on_delete=models.CASCADE,
        related_name="visibility_blocks",
    )
    role_context = models.CharField(
        max_length=20,
        choices=RoleContext.choices,
        default=RoleContext.CLIENT,
        db_index=True,
    )
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["user", "portfolio_item", "role_context"], name="uniq_portfolio_visibility_block_user_item_role"),
        ]
        indexes = [
            models.Index(fields=["user", "portfolio_item", "role_context"], name="provprt_user_item_role_idx"),
        ]


class ProviderCategory(models.Model):
    provider = models.ForeignKey(ProviderProfile, on_delete=models.CASCADE)
    subcategory = models.ForeignKey(SubCategory, on_delete=models.CASCADE)
    accepts_urgent = models.BooleanField(default=False)
    requires_geo_scope = models.BooleanField(default=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["provider", "subcategory"],
                name="uniq_provider_subcategory",
            )
        ]


def sync_provider_accepts_urgent_flag(provider: ProviderProfile | None) -> bool:
    if provider is None or not getattr(provider, "pk", None):
        return False

    enabled = ProviderCategory.objects.filter(
        provider=provider,
        accepts_urgent=True,
        subcategory__allows_urgent_requests=True,
    ).exists()
    if provider.accepts_urgent != enabled:
        ProviderProfile.objects.filter(pk=provider.pk).update(accepts_urgent=enabled)
        provider.accepts_urgent = enabled
    return enabled


class ProviderService(models.Model):
    PRICE_UNIT_CHOICES = (
        ("fixed", "سعر ثابت"),
        ("starting_from", "يبدأ من"),
        ("hour", "بالساعة"),
        ("day", "باليوم"),
        ("negotiable", "قابل للتفاوض"),
    )

    provider = models.ForeignKey(
        ProviderProfile,
        on_delete=models.CASCADE,
        related_name="services",
    )
    subcategory = models.ForeignKey(
        SubCategory,
        on_delete=models.PROTECT,
        related_name="provider_services",
    )

    title = models.CharField(max_length=150)
    description = models.TextField(max_length=1000, blank=True, default="")

    price_from = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    price_to = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    price_unit = models.CharField(max_length=20, choices=PRICE_UNIT_CHOICES, default="fixed")

    is_active = models.BooleanField(default=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=["provider", "is_active", "updated_at"]),
        ]

    def __str__(self) -> str:
        return f"{self.provider_id} - {self.title}"


class ProviderFollow(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="provider_follows",
    )
    provider = models.ForeignKey(
        ProviderProfile,
        on_delete=models.CASCADE,
        related_name="followers",
    )
    role_context = models.CharField(
        max_length=20,
        choices=RoleContext.choices,
        default=RoleContext.CLIENT,
        db_index=True,
    )
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["user", "provider", "role_context"], name="uniq_follow_user_provider_role"),
        ]


class ProviderLike(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="provider_likes",
    )
    provider = models.ForeignKey(
        ProviderProfile,
        on_delete=models.CASCADE,
        related_name="likes",
    )
    role_context = models.CharField(
        max_length=20,
        choices=RoleContext.choices,
        default=RoleContext.CLIENT,
        db_index=True,
    )
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["user", "provider", "role_context"], name="uniq_like_user_provider_role"),
        ]


class ContentShareChannel(models.TextChoices):
    WHATSAPP = "whatsapp", "واتساب"
    TWITTER = "twitter", "تويتر"
    COPY_LINK = "copy_link", "نسخ الرابط"
    OTHER = "other", "أخرى"


class ContentShareContentType(models.TextChoices):
    PROFILE = "profile", "الملف الشخصي"
    PORTFOLIO = "portfolio", "معرض الأعمال"
    SPOTLIGHT = "spotlight", "الأضواء"


class ProviderContentShare(models.Model):
    provider = models.ForeignKey(
        ProviderProfile,
        on_delete=models.CASCADE,
        related_name="content_shares",
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="provider_content_shares",
    )
    content_type = models.CharField(
        max_length=20,
        choices=ContentShareContentType.choices,
        default=ContentShareContentType.PROFILE,
        db_index=True,
    )
    content_id = models.PositiveIntegerField(null=True, blank=True)
    channel = models.CharField(
        max_length=20,
        choices=ContentShareChannel.choices,
        default=ContentShareChannel.OTHER,
    )
    session_id = models.CharField(max_length=64, blank=True, default="")
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ["-created_at"]


class ProviderContentComment(models.Model):
    provider = models.ForeignKey(
        ProviderProfile,
        on_delete=models.CASCADE,
        related_name="content_comments",
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="provider_content_comments",
    )
    portfolio_item = models.ForeignKey(
        "ProviderPortfolioItem",
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name="comments",
    )
    spotlight_item = models.ForeignKey(
        "ProviderSpotlightItem",
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name="comments",
    )
    parent = models.ForeignKey(
        "self",
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name="replies",
    )
    role_context = models.CharField(
        max_length=20,
        choices=RoleContext.choices,
        default=RoleContext.CLIENT,
        db_index=True,
    )
    body = models.TextField(max_length=1000)
    is_approved = models.BooleanField(default=True)
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ["-created_at"]


class ProviderContentCommentLike(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="provider_content_comment_likes",
    )
    comment = models.ForeignKey(
        ProviderContentComment,
        on_delete=models.CASCADE,
        related_name="likes",
    )
    role_context = models.CharField(
        max_length=20,
        choices=RoleContext.choices,
        default=RoleContext.CLIENT,
        db_index=True,
    )
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["user", "comment", "role_context"],
                name="uniq_like_user_content_comment_role",
            ),
        ]
