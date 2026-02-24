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


class ProviderPublicSerializer(serializers.ModelSerializer):
    followers_count = serializers.IntegerField(read_only=True)
    likes_count = serializers.IntegerField(read_only=True)
    following_count = serializers.SerializerMethodField()
    phone = serializers.CharField(source="user.phone", read_only=True)

    class Meta:
        model = ProviderProfile
        fields = (
            "id",
            "display_name",
            "profile_image",
            "cover_image",
            "bio",
            "years_experience",
            "phone",
            "whatsapp",
            "city",
            "lat",
            "lng",
            "accepts_urgent",
            "is_verified_blue",
            "is_verified_green",
            "rating_avg",
            "rating_count",
            "created_at",
            "followers_count",
            "likes_count",
            "following_count",
        )

    def get_following_count(self, obj):
        # Count providers this provider's user follows (if any)
        try:
            return obj.user.provider_follows.count()
        except Exception:
            return 0


class ProviderPortfolioItemSerializer(serializers.ModelSerializer):
    provider_id = serializers.IntegerField(source="provider.id", read_only=True)
    provider_display_name = serializers.CharField(source="provider.display_name", read_only=True)
    provider_username = serializers.CharField(source="provider.user.username", read_only=True)
    file_url = serializers.SerializerMethodField()
    thumbnail_url = serializers.SerializerMethodField()

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
            "created_at",
        )

    @staticmethod
    def _safe_file_url(field_file):
        if not field_file:
            return ""
        try:
            name = (field_file.name or "").strip()
            if not name:
                return ""
            if not field_file.storage.exists(name):
                return ""
            return field_file.url
        except Exception:
            return ""

    def get_file_url(self, obj):
        return self._safe_file_url(getattr(obj, "file", None))

    def get_thumbnail_url(self, obj):
        return self._safe_file_url(getattr(obj, "thumbnail", None))


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
    file_url = serializers.SerializerMethodField()
    thumbnail_url = serializers.SerializerMethodField()

    class Meta:
        model = ProviderSpotlightItem
        fields = (
            "id",
            "provider_id",
            "provider_display_name",
            "provider_username",
            "file_type",
            "file_url",
            "thumbnail_url",
            "caption",
            "created_at",
        )

    @staticmethod
    def _safe_file_url(field_file):
        if not field_file:
            return ""
        try:
            name = (field_file.name or "").strip()
            if not name:
                return ""
            if not field_file.storage.exists(name):
                return ""
            return field_file.url
        except Exception:
            return ""

    def get_file_url(self, obj):
        return self._safe_file_url(getattr(obj, "file", None))

    def get_thumbnail_url(self, obj):
        return self._safe_file_url(getattr(obj, "thumbnail", None))


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

    class Meta:
        model = User
        fields = (
            "id",
            "username",
            "display_name",
        )

    def get_display_name(self, obj: User) -> str:
        first = (getattr(obj, "first_name", "") or "").strip()
        last = (getattr(obj, "last_name", "") or "").strip()
        if first or last:
            return (f"{first} {last}").strip()
        username = (getattr(obj, "username", "") or "").strip()
        return username or "مستخدم"


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
