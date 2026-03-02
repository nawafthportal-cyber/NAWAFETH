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
    is_active = models.BooleanField(default=True)

    def __str__(self) -> str:
        return f"{self.category.name} - {self.name}"


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

    city = models.CharField(max_length=100, blank=True, default="")
    lat = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    lng = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    coverage_radius_km = models.PositiveIntegerField(default=10)

    about_details = models.TextField(blank=True, default="")
    qualifications = models.JSONField(default=list, blank=True)
    experiences = models.JSONField(default=list, blank=True)
    content_sections = models.JSONField(default=list, blank=True)
    seo_keywords = models.CharField(max_length=500, blank=True, default="")
    seo_meta_description = models.CharField(max_length=500, blank=True, default="")
    seo_slug = models.CharField(max_length=150, blank=True, default="")

    accepts_urgent = models.BooleanField(default=False)

    is_verified_blue = models.BooleanField(default=False)
    is_verified_green = models.BooleanField(default=False)

    rating_avg = models.DecimalField(
        max_digits=3,
        decimal_places=2,
        default=Decimal("0.00"),
    )
    rating_count = models.PositiveIntegerField(default=0)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return self.display_name


class ProviderPortfolioItem(models.Model):
    FILE_TYPE_CHOICES = (
        ("image", "صورة"),
        ("video", "فيديو"),
    )

    provider = models.ForeignKey(
        ProviderProfile,
        on_delete=models.CASCADE,
        related_name="portfolio_items",
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


class ProviderCategory(models.Model):
    provider = models.ForeignKey(ProviderProfile, on_delete=models.CASCADE)
    subcategory = models.ForeignKey(SubCategory, on_delete=models.CASCADE)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["provider", "subcategory"],
                name="uniq_provider_subcategory",
            )
        ]


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
