from rest_framework import serializers

from apps.accounts.models import User

from .models import (
    Category,
    ProviderPortfolioItem,
    ProviderProfile,
    ProviderService,
    ProviderSpotlightItem,
    SubCategory,
)


def _safe_file_url(field_file):
    """Return the public URL for a file field, or empty string.

    NOTE: We intentionally do NOT call ``storage.exists()`` here.
    - For R2/S3 it would trigger a ``HeadObject`` API call per file (N+1).
    - For local storage on Render the file may be on a persistent disk that
      is not mounted during ``collectstatic`` / startup checks.
    The client should handle 404 gracefully if the file was deleted.
    """
    if not field_file:
        return ""
    try:
        name = (field_file.name or "").strip()
        if not name:
            return ""
        return field_file.url
    except Exception:
        return ""


class SubCategorySerializer(serializers.ModelSerializer):
    class Meta:
        model = SubCategory
        fields = ("id", "name")


class CategorySerializer(serializers.ModelSerializer):
    subcategories = SubCategorySerializer(many=True, read_only=True)

    class Meta:
        model = Category
        fields = ("id", "name", "subcategories")


class ProviderProfileSerializer(serializers.ModelSerializer):
	subcategory_ids = serializers.ListField(
		child=serializers.IntegerField(),
		write_only=True,
		required=False,
		allow_empty=True,
	)

	class Meta:
		model = ProviderProfile
		fields = "__all__"
		read_only_fields = ("user", "is_verified_blue", "is_verified_green")

	def create(self, validated_data):
		subcategory_ids = validated_data.pop("subcategory_ids", [])
		profile = super().create(validated_data)

		# Create ProviderCategory entries
		if subcategory_ids:
			from .models import ProviderCategory, SubCategory

			for sub_id in subcategory_ids:
				try:
					subcategory = SubCategory.objects.get(id=sub_id, is_active=True)
					ProviderCategory.objects.get_or_create(
						provider=profile, subcategory=subcategory
					)
				except SubCategory.DoesNotExist:
					pass  # Skip invalid subcategory IDs

		return profile


class ProviderProfileMeSerializer(serializers.ModelSerializer):
    """Provider profile for the authenticated owner (read + update).

    Keep sensitive/computed fields read-only.
    """

    class Meta:
        model = ProviderProfile
        fields = (
            "id",
            "provider_type",
            "display_name",
            "profile_image",
            "cover_image",
            "bio",
            "about_details",
            "years_experience",
            "whatsapp",
            "website",
            "social_links",
            "languages",
            "city",
            "lat",
            "lng",
            "coverage_radius_km",
            "qualifications",
            "experiences",
            "content_sections",
            "seo_keywords",
            "seo_meta_description",
            "seo_slug",
            "accepts_urgent",
            "is_verified_blue",
            "is_verified_green",
            "rating_avg",
            "rating_count",
            "created_at",
        )
        read_only_fields = (
            "id",
            "is_verified_blue",
            "is_verified_green",
            "rating_avg",
            "rating_count",
            "created_at",
        )

    def to_representation(self, instance):
        data = super().to_representation(instance)
        data["profile_image"] = _safe_file_url(getattr(instance, "profile_image", None))
        data["cover_image"] = _safe_file_url(getattr(instance, "cover_image", None))
        return data


class ProviderPublicSerializer(serializers.ModelSerializer):
    followers_count = serializers.IntegerField(read_only=True)
    likes_count = serializers.IntegerField(read_only=True)
    completed_requests = serializers.IntegerField(read_only=True, required=False)
    following_count = serializers.SerializerMethodField()
    phone = serializers.CharField(source="user.phone", read_only=True)
    username = serializers.CharField(source="user.username", read_only=True)

    class Meta:
        model = ProviderProfile
        fields = (
            "id",
            "display_name",
            "username",
            "profile_image",
            "cover_image",
            "bio",
            "about_details",
            "years_experience",
            "phone",
            "whatsapp",
            "website",
            "social_links",
            "languages",
            "city",
            "lat",
            "lng",
            "coverage_radius_km",
            "accepts_urgent",
            "is_verified_blue",
            "is_verified_green",
            "qualifications",
            "rating_avg",
            "rating_count",
            "created_at",
            "followers_count",
            "likes_count",
            "following_count",
            "completed_requests",
        )

    def get_following_count(self, obj):
        # Count providers this provider's user follows (if any)
        try:
            return obj.user.provider_follows.count()
        except Exception:
            return 0

    def to_representation(self, instance):
        data = super().to_representation(instance)
        data["profile_image"] = _safe_file_url(getattr(instance, "profile_image", None))
        data["cover_image"] = _safe_file_url(getattr(instance, "cover_image", None))
        return data


class ProviderPortfolioItemSerializer(serializers.ModelSerializer):
    provider_id = serializers.IntegerField(source="provider.id", read_only=True)
    provider_display_name = serializers.CharField(source="provider.display_name", read_only=True)
    provider_username = serializers.CharField(source="provider.user.username", read_only=True)
    file_url = serializers.SerializerMethodField()
    thumbnail_url = serializers.SerializerMethodField()
    likes_count = serializers.SerializerMethodField()
    saves_count = serializers.SerializerMethodField()

    class Meta:
        model = ProviderPortfolioItem
        fields = (
            "id",
            "provider_id",
            "provider_display_name",
            "provider_username",
            "file_type",
            "file_url",
            "thumbnail_url",
            "caption",
            "likes_count",
            "saves_count",
            "created_at",
        )

    def get_file_url(self, obj):
        return _safe_file_url(getattr(obj, "file", None))

    def get_thumbnail_url(self, obj):
        return _safe_file_url(getattr(obj, "thumbnail", None))

    def get_likes_count(self, obj):
        try:
            return int(getattr(obj, "likes_count", None) or obj.likes.count())
        except Exception:
            return 0

    def get_saves_count(self, obj):
        try:
            return int(getattr(obj, "saves_count", None) or obj.saves.count())
        except Exception:
            return 0


class ProviderPortfolioItemCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = ProviderPortfolioItem
        fields = (
            "id",
            "file_type",
            "file",
            "caption",
            "created_at",
        )
        read_only_fields = ("id", "created_at")


class ProviderSpotlightItemSerializer(serializers.ModelSerializer):
    provider_id = serializers.IntegerField(source="provider.id", read_only=True)
    provider_display_name = serializers.CharField(source="provider.display_name", read_only=True)
    provider_username = serializers.CharField(source="provider.user.username", read_only=True)
    provider_profile_image = serializers.SerializerMethodField()
    file_url = serializers.SerializerMethodField()
    thumbnail_url = serializers.SerializerMethodField()
    likes_count = serializers.SerializerMethodField()
    saves_count = serializers.SerializerMethodField()
    is_liked = serializers.SerializerMethodField()
    is_saved = serializers.SerializerMethodField()

    class Meta:
        model = ProviderSpotlightItem
        fields = (
            "id",
            "provider_id",
            "provider_display_name",
            "provider_username",
            "provider_profile_image",
            "file_type",
            "file_url",
            "thumbnail_url",
            "caption",
            "likes_count",
            "saves_count",
            "is_liked",
            "is_saved",
            "created_at",
        )

    def get_provider_profile_image(self, obj):
        return _safe_file_url(getattr(obj.provider, "profile_image", None))

    def get_file_url(self, obj):
        return _safe_file_url(getattr(obj, "file", None))

    def get_thumbnail_url(self, obj):
        return _safe_file_url(getattr(obj, "thumbnail", None))

    def get_likes_count(self, obj):
        try:
            return int(getattr(obj, "likes_count", None) or obj.likes.count())
        except Exception:
            return 0

    def get_saves_count(self, obj):
        try:
            return int(getattr(obj, "saves_count", None) or obj.saves.count())
        except Exception:
            return 0

    def get_is_liked(self, obj):
        # Prefer annotated value to avoid N+1 queries
        annotated = getattr(obj, "_is_liked", None)
        if annotated is not None:
            return bool(annotated)
        request = self.context.get("request")
        if request and hasattr(request, "user") and request.user.is_authenticated:
            return obj.likes.filter(user=request.user).exists()
        return False

    def get_is_saved(self, obj):
        annotated = getattr(obj, "_is_saved", None)
        if annotated is not None:
            return bool(annotated)
        request = self.context.get("request")
        if request and hasattr(request, "user") and request.user.is_authenticated:
            return obj.saves.filter(user=request.user).exists()
        return False


class ProviderSpotlightItemCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = ProviderSpotlightItem
        fields = (
            "id",
            "file_type",
            "file",
            "caption",
            "created_at",
        )
        read_only_fields = ("id", "created_at")


class UserPublicSerializer(serializers.ModelSerializer):
    display_name = serializers.SerializerMethodField()
    provider_id = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = (
            "id",
            "username",
            "display_name",
            "provider_id",
        )

    def get_display_name(self, obj: User) -> str:
        first = (getattr(obj, "first_name", "") or "").strip()
        last = (getattr(obj, "last_name", "") or "").strip()
        if first or last:
            return (f"{first} {last}").strip()
        username = (getattr(obj, "username", "") or "").strip()
        return username or "مستخدم"

    def get_provider_id(self, obj: User):
        profile = getattr(obj, "provider_profile", None)
        return profile.id if profile else None


class MyProviderSubcategoriesSerializer(serializers.Serializer):
    subcategory_ids = serializers.ListField(
        child=serializers.IntegerField(min_value=1),
        allow_empty=True,
        required=True,
    )

    def validate_subcategory_ids(self, value):
        ids = list(dict.fromkeys(value))  # de-dupe, keep order
        if not ids:
            return []

        existing = set(
            SubCategory.objects.filter(id__in=ids, is_active=True).values_list("id", flat=True)
        )
        missing = [i for i in ids if i not in existing]
        if missing:
            raise serializers.ValidationError(f"تصنيفات فرعية غير صالحة: {missing}")
        return ids


class SubCategoryWithCategorySerializer(serializers.ModelSerializer):
    category_id = serializers.IntegerField(read_only=True)
    category_name = serializers.CharField(source="category.name", read_only=True)

    class Meta:
        model = SubCategory
        fields = (
            "id",
            "name",
            "category_id",
            "category_name",
        )


class ProviderServiceSerializer(serializers.ModelSerializer):
    provider_id = serializers.IntegerField(read_only=True)
    subcategory_id = serializers.PrimaryKeyRelatedField(
        source="subcategory",
        queryset=SubCategory.objects.filter(is_active=True),
        write_only=True,
    )
    subcategory = SubCategoryWithCategorySerializer(read_only=True)

    class Meta:
        model = ProviderService
        fields = (
            "id",
            "provider_id",
            "title",
            "description",
            "price_from",
            "price_to",
            "price_unit",
            "is_active",
            "subcategory",
            "subcategory_id",
            "created_at",
            "updated_at",
        )
        read_only_fields = (
            "id",
            "provider_id",
            "subcategory",
            "created_at",
            "updated_at",
        )


class ProviderServicePublicSerializer(serializers.ModelSerializer):
    subcategory = SubCategoryWithCategorySerializer(read_only=True)

    class Meta:
        model = ProviderService
        fields = (
            "id",
            "title",
            "description",
            "price_from",
            "price_to",
            "price_unit",
            "subcategory",
            "created_at",
            "updated_at",
        )
        read_only_fields = fields
