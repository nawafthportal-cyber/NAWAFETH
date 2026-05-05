from rest_framework import serializers
from django.utils.text import slugify

from apps.accounts.models import User
from apps.accounts.role_context import get_active_role
from apps.accounts.phone_validation import normalize_phone_local05, require_phone_local05
from apps.accounts.presence import is_online_value as _presence_is_online_value
from apps.reviews.services import provider_rating_values
from apps.uploads.media_optimizer import optimize_upload_for_storage
from apps.uploads.validators import (
    DOCUMENT_EXTENSIONS,
    DOCUMENT_MIME_TYPES,
    IMAGE_EXTENSIONS,
    IMAGE_MIME_TYPES,
    VIDEO_EXTENSIONS,
    VIDEO_MIME_TYPES,
    validate_secure_upload,
)

from .models import (
    Category,
    ProviderContentComment,
    ProviderContentCommentLike,
    ProviderFollow,
    ProviderCategory,
    ProviderCoverImage,
    ProviderPortfolioItem,
    ProviderProfile,
    RoleContext,
    ProviderService,
    ProviderSpotlightItem,
    ProviderSpotlightVisibilityBlock,
    ProviderVisibilityBlock,
    SaudiCity,
    SaudiRegion,
    SubCategory,
    sync_provider_accepts_urgent_flag,
)
from .location_formatter import format_city_display, resolve_country_city


def _normalize_location_payload(attrs, *, instance=None, require_coordinates=False):
    country_in_payload = "country" in attrs
    city_in_payload = "city" in attrs
    label_in_payload = "location_label" in attrs
    lat_in_payload = "lat" in attrs
    lng_in_payload = "lng" in attrs

    if not any((country_in_payload, city_in_payload, label_in_payload, lat_in_payload, lng_in_payload)):
        return attrs

    existing_country = getattr(instance, "country", "") if instance is not None else ""
    existing_label = getattr(instance, "city", "") if instance is not None else ""

    country, city_name, location_label = resolve_country_city(
        attrs.get("country", existing_country),
        attrs.get("city", ""),
        attrs.get("location_label", existing_label),
    )

    lat = attrs.get("lat", getattr(instance, "lat", None) if instance is not None else None)
    lng = attrs.get("lng", getattr(instance, "lng", None) if instance is not None else None)

    if (lat in (None, "")) != (lng in (None, "")):
        raise serializers.ValidationError({"location_label": "أدخل الإحداثيين معًا أو اتركهما فارغين."})

    if require_coordinates and (lat in (None, "") or lng in (None, "")):
        raise serializers.ValidationError({"location_label": "حدد موقع مزود الخدمة من الخريطة لحفظ الإحداثيات."})

    if lat not in (None, ""):
        lat_value = float(lat)
        if not (-90 <= lat_value <= 90):
            raise serializers.ValidationError({"lat": "خط العرض غير صالح."})
    if lng not in (None, ""):
        lng_value = float(lng)
        if not (-180 <= lng_value <= 180):
            raise serializers.ValidationError({"lng": "خط الطول غير صالح."})

    attrs["country"] = country
    attrs["city"] = location_label
    attrs["region"] = ""
    attrs.pop("location_label", None)
    return attrs


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


def _serialize_provider_cover_gallery(provider, *, serializer_context=None):
    rows = provider.ordered_cover_gallery() if hasattr(provider, "ordered_cover_gallery") else []
    if rows:
        payload = ProviderCoverImageSerializer(rows, many=True, context=serializer_context or {}).data
        return [item for item in payload if str(item.get("image_url") or "").strip()]
    cover_url = _safe_file_url(getattr(provider, "cover_image", None))
    if not cover_url:
        return []
    return [
        {
            "id": None,
            "image_url": cover_url,
            "sort_order": 0,
            "is_primary": True,
            "is_legacy": True,
        }
    ]


def _trim_text(value):
    return " ".join(str(value or "").split()).strip()


def _normalize_keywords_text(value):
    parts = []
    for part in str(value or "").replace("\n", ",").replace("،", ",").split(","):
        cleaned = _trim_text(part)
        if cleaned:
            parts.append(cleaned)
    return "، ".join(dict.fromkeys(parts))


def _normalize_seo_slug(value):
    raw = _trim_text(value)
    if not raw:
        return ""
    normalized = slugify(raw, allow_unicode=True).strip("-")
    if not normalized:
        raise serializers.ValidationError("أدخل رابطًا مخصصًا صالحًا")
    return normalized


def _normalize_whatsapp_local05(value):
    normalized = normalize_phone_local05(str(value or "").strip())
    if not normalized:
        return ""
    try:
        return require_phone_local05(normalized, allow_blank=True)
    except ValueError:
        return ""


def _build_whatsapp_url(value):
    local05 = _normalize_whatsapp_local05(value)
    if not local05:
        return ""
    return f"https://wa.me/966{local05[1:]}"


def _infer_upload_media_type(upload, *, fallback: str = "") -> str:
    if upload is None:
        return fallback
    media_type = str(fallback or "").strip().lower()
    if media_type in {"image", "video", "document"}:
        return media_type
    content_type = str(getattr(upload, "content_type", "") or "").strip().lower()
    filename = str(getattr(upload, "name", "") or "").strip().lower()
    if content_type.startswith("video/") or filename.endswith((".mp4", ".mov", ".avi", ".webm", ".mkv")):
        return "video"
    if content_type.startswith("image/") or filename.endswith((".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp")):
        return "image"
    if content_type in DOCUMENT_MIME_TYPES or filename.endswith((".pdf", ".doc", ".docx", ".txt", ".csv", ".xlsx")):
        return "document"
    return media_type


def _normalize_provider_image_field(attrs: dict, field_name: str, *, prefix: str) -> None:
    upload = attrs.get(field_name)
    if upload is None or isinstance(upload, str):
        return
    validate_secure_upload(
        upload,
        allowed_extensions=IMAGE_EXTENSIONS,
        allowed_mime_types=IMAGE_MIME_TYPES,
        max_size_mb=20,
        rename=True,
        rename_prefix=prefix,
    )
    attrs[field_name] = optimize_upload_for_storage(upload, declared_type="image")


def _normalize_provider_media_upload(upload, *, media_type: str, image_prefix: str, video_prefix: str):
    if media_type == "image":
        validate_secure_upload(
            upload,
            allowed_extensions=IMAGE_EXTENSIONS,
            allowed_mime_types=IMAGE_MIME_TYPES,
            max_size_mb=20,
            rename=True,
            rename_prefix=image_prefix,
        )
        return optimize_upload_for_storage(upload, declared_type="image")
    if media_type == "video":
        validate_secure_upload(
            upload,
            allowed_extensions=VIDEO_EXTENSIONS,
            allowed_mime_types=VIDEO_MIME_TYPES,
            max_size_mb=70,
            rename=True,
            rename_prefix=video_prefix,
        )
        return optimize_upload_for_storage(upload, declared_type="video")
    if media_type == "document":
        validate_secure_upload(
            upload,
            allowed_extensions=DOCUMENT_EXTENSIONS,
            allowed_mime_types=DOCUMENT_MIME_TYPES,
            max_size_mb=20,
            rename=True,
            rename_prefix="provider_portfolio_document",
        )
        return optimize_upload_for_storage(upload, declared_type="document")
    raise serializers.ValidationError({"file_type": "نوع الملف يجب أن يكون صورة أو فيديو أو ملف PDF."})


class ProviderSeoValidationMixin:
    def validate_seo_title(self, value):
        return _trim_text(value)

    def validate_seo_keywords(self, value):
        return _normalize_keywords_text(value)

    def validate_seo_meta_description(self, value):
        return _trim_text(value)

    def validate_seo_slug(self, value):
        return _normalize_seo_slug(value)


class SubCategorySerializer(serializers.ModelSerializer):
    class Meta:
        model = SubCategory
        fields = ("id", "name", "requires_geo_scope", "allows_urgent_requests")


class CategorySerializer(serializers.ModelSerializer):
    subcategories = serializers.SerializerMethodField()

    class Meta:
        model = Category
        fields = ("id", "name", "subcategories")

    def get_subcategories(self, obj):
        active = obj.subcategories.filter(is_active=True)
        return SubCategorySerializer(active, many=True).data


class SaudiCitySerializer(serializers.ModelSerializer):
    class Meta:
        model = SaudiCity
        fields = ("id", "name_ar")


class SaudiRegionSerializer(serializers.ModelSerializer):
    cities = serializers.SerializerMethodField()

    class Meta:
        model = SaudiRegion
        fields = ("id", "name_ar", "cities")

    def get_cities(self, obj):
        rows = obj.cities.filter(is_active=True).order_by("sort_order", "name_ar", "id")
        return SaudiCitySerializer(rows, many=True).data


class ProviderCoverImageSerializer(serializers.ModelSerializer):
    image_url = serializers.SerializerMethodField()
    is_primary = serializers.SerializerMethodField()
    is_legacy = serializers.SerializerMethodField()

    class Meta:
        model = ProviderCoverImage
        fields = ("id", "image_url", "sort_order", "is_primary", "is_legacy", "created_at")

    def get_image_url(self, obj):
        return _safe_file_url(getattr(obj, "image", None))

    def get_is_primary(self, obj):
        return int(getattr(obj, "sort_order", 0) or 0) == 0

    def get_is_legacy(self, obj):
        return False


class ProviderCoverImageUploadSerializer(serializers.Serializer):
    image = serializers.FileField()

    def validate_image(self, value):
        attrs = {"image": value}
        _normalize_provider_image_field(attrs, "image", prefix="provider_cover_gallery")
        return attrs["image"]


class ProviderProfileSerializer(ProviderSeoValidationMixin, serializers.ModelSerializer):
    whatsapp_url = serializers.SerializerMethodField(read_only=True)
    location_label = serializers.CharField(write_only=True, required=False, allow_blank=True, allow_null=True)
    subcategory_ids = serializers.ListField(
        child=serializers.IntegerField(),
        write_only=True,
        required=False,
        allow_empty=True,
    )

    class Meta:
        model = ProviderProfile
        exclude = ("excellence_badges_cache",)
        read_only_fields = ("user", "is_verified_blue", "is_verified_green")

    def validate_whatsapp(self, value):
        text = str(value or "").strip()
        if not text:
            return ""
        try:
            return require_phone_local05(normalize_phone_local05(text), allow_blank=True)
        except ValueError as exc:
            raise serializers.ValidationError(str(exc))

    def get_whatsapp_url(self, obj):
        return _build_whatsapp_url(getattr(obj, "whatsapp", ""))

    def validate_country(self, value):
        return _trim_text(value)

    def validate_region(self, value):
        return _trim_text(value)

    def validate_city(self, value):
        return _trim_text(value)

    def validate(self, attrs):
        attrs = super().validate(attrs)
        _normalize_provider_image_field(attrs, "profile_image", prefix="provider_profile_image")
        _normalize_provider_image_field(attrs, "cover_image", prefix="provider_cover_image")
        return _normalize_location_payload(attrs)

    def create(self, validated_data):
        subcategory_ids = validated_data.pop("subcategory_ids", [])
        profile = super().create(validated_data)

        # Create ProviderCategory entries
        if subcategory_ids:
            for sub_id in subcategory_ids:
                try:
                    subcategory = SubCategory.objects.get(id=sub_id, is_active=True)
                    ProviderCategory.objects.get_or_create(
                        provider=profile,
                        subcategory=subcategory,
                        defaults={
                            "accepts_urgent": bool(
                                profile.accepts_urgent and getattr(subcategory, "allows_urgent_requests", False)
                            ),
                            "requires_geo_scope": bool(getattr(subcategory, "requires_geo_scope", True)),
                        },
                    )
                except SubCategory.DoesNotExist:
                    pass  # Skip invalid subcategory IDs

        sync_provider_accepts_urgent_flag(profile)
        return profile


class ProviderSubcategorySettingSerializer(serializers.Serializer):
    subcategory_id = serializers.IntegerField(min_value=1)
    accepts_urgent = serializers.BooleanField(required=False, default=False)
    requires_geo_scope = serializers.BooleanField(required=False, default=True)


class ProviderProfileMeSerializer(ProviderSeoValidationMixin, serializers.ModelSerializer):
    """Provider profile for the authenticated owner (read + update).

    Keep sensitive/computed fields read-only.
    """

    excellence_badges = serializers.SerializerMethodField()
    provider_type_label = serializers.CharField(source="get_provider_type_display", read_only=True)
    primary_category_name = serializers.SerializerMethodField()
    primary_subcategory_name = serializers.SerializerMethodField()
    main_categories = serializers.SerializerMethodField()
    selected_subcategories = serializers.SerializerMethodField()
    subcategory_ids = serializers.SerializerMethodField()
    whatsapp_url = serializers.SerializerMethodField()
    location_label = serializers.CharField(write_only=True, required=False, allow_blank=True, allow_null=True)
    city_display = serializers.SerializerMethodField()
    rating_avg = serializers.SerializerMethodField()
    rating_count = serializers.SerializerMethodField()
    cover_gallery = serializers.SerializerMethodField()
    cover_images = serializers.SerializerMethodField()

    class Meta:
        model = ProviderProfile
        fields = (
            "id",
            "provider_type",
            "provider_type_label",
            "display_name",
            "profile_image",
            "cover_image",
            "cover_gallery",
            "cover_images",
            "bio",
            "about_details",
            "years_experience",
            "whatsapp",
            "whatsapp_url",
            "website",
            "social_links",
            "languages",
            "country",
            "region",
            "city",
            "city_display",
            "location_label",
            "lat",
            "lng",
            "coverage_radius_km",
            "qualifications",
            "experiences",
            "content_sections",
            "seo_title",
            "seo_keywords",
            "seo_meta_description",
            "seo_slug",
            "accepts_urgent",
            "is_verified_blue",
            "is_verified_green",
            "excellence_badges",
            "rating_avg",
            "rating_count",
            "created_at",
            "primary_category_name",
            "primary_subcategory_name",
            "main_categories",
            "selected_subcategories",
            "subcategory_ids",
        )
        read_only_fields = (
            "id",
            "is_verified_blue",
            "is_verified_green",
            "rating_avg",
            "rating_count",
            "created_at",
        )

    def get_excellence_badges(self, obj):
        value = getattr(obj, "excellence_badges_cache", None)
        return value if isinstance(value, list) else []

    def validate_whatsapp(self, value):
        text = str(value or "").strip()
        if not text:
            return ""
        try:
            return require_phone_local05(normalize_phone_local05(text), allow_blank=True)
        except ValueError as exc:
            raise serializers.ValidationError(str(exc))

    def get_whatsapp_url(self, obj):
        return _build_whatsapp_url(getattr(obj, "whatsapp", ""))

    def validate_country(self, value):
        return _trim_text(value)

    def validate_region(self, value):
        return _trim_text(value)

    def validate_city(self, value):
        return _trim_text(value)

    def validate(self, attrs):
        attrs = super().validate(attrs)
        _normalize_provider_image_field(attrs, "profile_image", prefix="provider_profile_image")
        _normalize_provider_image_field(attrs, "cover_image", prefix="provider_cover_image")
        return _normalize_location_payload(attrs, instance=self.instance)

    def _provider_subcategory_rows(self, obj):
        rows = []
        relation_rows = getattr(obj, "_prefetched_objects_cache", {}).get("providercategory_set")
        if relation_rows is None:
            relation_rows = (
                obj.providercategory_set.select_related("subcategory", "subcategory__category")
                .order_by("subcategory__category__name", "subcategory__name", "id")
            )

        for relation in relation_rows:
            subcategory = getattr(relation, "subcategory", None)
            category = getattr(subcategory, "category", None) if subcategory else None
            if not subcategory or not category:
                continue
            rows.append(
                {
                    "id": subcategory.id,
                    "name": subcategory.name,
                    "category_id": category.id,
                    "category_name": category.name,
                    "accepts_urgent": bool(getattr(relation, "accepts_urgent", False)),
                    "requires_geo_scope": bool(getattr(relation, "requires_geo_scope", True)),
                }
            )
        return rows

    def get_primary_category_name(self, obj):
        rows = self._provider_subcategory_rows(obj)
        return rows[0]["category_name"] if rows else ""

    def get_primary_subcategory_name(self, obj):
        rows = self._provider_subcategory_rows(obj)
        return rows[0]["name"] if rows else ""

    def get_main_categories(self, obj):
        rows = self._provider_subcategory_rows(obj)
        return list(dict.fromkeys(row["category_name"] for row in rows if row["category_name"]))

    def get_selected_subcategories(self, obj):
        return self._provider_subcategory_rows(obj)

    def get_subcategory_ids(self, obj):
        return [row["id"] for row in self._provider_subcategory_rows(obj)]

    def get_city_display(self, obj):
        return format_city_display(getattr(obj, "city", ""), region=getattr(obj, "region", ""))

    def get_rating_avg(self, obj):
        return f"{provider_rating_values(obj)['rating_avg']:.2f}"

    def get_rating_count(self, obj):
        return provider_rating_values(obj)["rating_count"]

    def get_cover_gallery(self, obj):
        return _serialize_provider_cover_gallery(obj, serializer_context=self.context)

    def get_cover_images(self, obj):
        return [item.get("image_url", "") for item in self.get_cover_gallery(obj) if item.get("image_url")]

    def create(self, validated_data):
        profile = super().create(validated_data)
        if getattr(profile, "cover_image", None):
            profile.seed_cover_gallery_from_legacy_cover()
        return profile

    def update(self, instance, validated_data):
        cover_image_provided = "cover_image" in validated_data
        profile = super().update(instance, validated_data)
        if cover_image_provided and getattr(profile, "cover_image", None):
            primary = profile.cover_gallery.order_by("sort_order", "id").first()
            if primary is None:
                profile.seed_cover_gallery_from_legacy_cover()
            else:
                primary.image = profile.cover_image
                primary.sort_order = 0
                primary.save(update_fields=["image", "sort_order"])
        return profile

    def to_representation(self, instance):
        data = super().to_representation(instance)
        data["profile_image"] = _safe_file_url(getattr(instance, "profile_image", None))
        data["cover_image"] = _safe_file_url(getattr(instance, "cover_image", None))
        return data


class ProviderPublicSerializer(serializers.ModelSerializer):
    provider_type = serializers.CharField(read_only=True)
    provider_type_label = serializers.CharField(source="get_provider_type_display", read_only=True)
    followers_count = serializers.IntegerField(read_only=True)
    likes_count = serializers.IntegerField(read_only=True)
    completed_requests = serializers.IntegerField(read_only=True, required=False)
    following_count = serializers.SerializerMethodField()
    excellence_badges = serializers.SerializerMethodField()
    phone = serializers.CharField(source="user.phone", read_only=True)
    username = serializers.CharField(source="user.username", read_only=True)
    primary_category_name = serializers.SerializerMethodField()
    primary_subcategory_name = serializers.SerializerMethodField()
    main_categories = serializers.SerializerMethodField()
    selected_subcategories = serializers.SerializerMethodField()
    subcategory_ids = serializers.SerializerMethodField()
    whatsapp_url = serializers.SerializerMethodField()
    city_display = serializers.SerializerMethodField()
    rating_avg = serializers.SerializerMethodField()
    rating_count = serializers.SerializerMethodField()
    is_online = serializers.SerializerMethodField()
    last_seen = serializers.SerializerMethodField()
    cover_gallery = serializers.SerializerMethodField()
    cover_images = serializers.SerializerMethodField()

    class Meta:
        model = ProviderProfile
        fields = (
            "id",
            "provider_type",
            "provider_type_label",
            "display_name",
            "username",
            "profile_image",
            "cover_image",
            "cover_gallery",
            "cover_images",
            "bio",
            "about_details",
            "years_experience",
            "phone",
            "whatsapp",
            "whatsapp_url",
            "website",
            "social_links",
            "languages",
            "country",
            "country",
            "region",
            "city",
            "city_display",
            "lat",
            "lng",
            "coverage_radius_km",
            "seo_title",
            "seo_keywords",
            "seo_meta_description",
            "seo_slug",
            "accepts_urgent",
            "is_verified_blue",
            "is_verified_green",
            "excellence_badges",
            "qualifications",
            "experiences",
            "content_sections",
            "rating_avg",
            "rating_count",
            "is_online",
            "last_seen",
            "created_at",
            "followers_count",
            "likes_count",
            "following_count",
            "completed_requests",
            "primary_category_name",
            "primary_subcategory_name",
            "main_categories",
            "selected_subcategories",
            "subcategory_ids",
        )

    def get_following_count(self, obj):
        # Count unique providers this account follows across all account modes.
        try:
            return (
                obj.user.provider_follows
                .values("provider_id")
                .distinct()
                .count()
            )
        except Exception:
            return 0

    def get_excellence_badges(self, obj):
        value = getattr(obj, "excellence_badges_cache", None)
        return value if isinstance(value, list) else []

    def get_whatsapp_url(self, obj):
        return _build_whatsapp_url(getattr(obj, "whatsapp", ""))

    def _provider_subcategory_rows(self, obj):
        rows = []
        relation_rows = getattr(obj, "_prefetched_objects_cache", {}).get("providercategory_set")
        if relation_rows is None:
            relation_rows = (
                obj.providercategory_set.select_related("subcategory", "subcategory__category")
                .order_by("subcategory__category__name", "subcategory__name", "id")
            )

        for relation in relation_rows:
            subcategory = getattr(relation, "subcategory", None)
            category = getattr(subcategory, "category", None) if subcategory else None
            if not subcategory or not category:
                continue
            rows.append(
                {
                    "id": subcategory.id,
                    "name": subcategory.name,
                    "category_id": category.id,
                    "category_name": category.name,
                    "accepts_urgent": bool(getattr(relation, "accepts_urgent", False)),
                    "requires_geo_scope": bool(getattr(relation, "requires_geo_scope", True)),
                }
            )
        return rows

    def get_primary_category_name(self, obj):
        rows = self._provider_subcategory_rows(obj)
        return rows[0]["category_name"] if rows else ""

    def get_primary_subcategory_name(self, obj):
        rows = self._provider_subcategory_rows(obj)
        return rows[0]["name"] if rows else ""

    def get_main_categories(self, obj):
        rows = self._provider_subcategory_rows(obj)
        return list(dict.fromkeys(row["category_name"] for row in rows if row["category_name"]))

    def get_selected_subcategories(self, obj):
        return self._provider_subcategory_rows(obj)

    def get_subcategory_ids(self, obj):
        return [row["id"] for row in self._provider_subcategory_rows(obj)]

    def get_city_display(self, obj):
        return format_city_display(getattr(obj, "city", ""), region=getattr(obj, "region", ""))

    def get_rating_avg(self, obj):
        return f"{provider_rating_values(obj)['rating_avg']:.2f}"

    def get_rating_count(self, obj):
        return provider_rating_values(obj)["rating_count"]

    def get_is_online(self, obj):
        last = getattr(getattr(obj, "user", None), "last_seen", None)
        return _presence_is_online_value(last)

    def get_last_seen(self, obj):
        last = getattr(getattr(obj, "user", None), "last_seen", None)
        return last.isoformat() if last else None

    def get_cover_gallery(self, obj):
        return _serialize_provider_cover_gallery(obj, serializer_context=self.context)

    def get_cover_images(self, obj):
        return [item.get("image_url", "") for item in self.get_cover_gallery(obj) if item.get("image_url")]

    def to_representation(self, instance):
        data = super().to_representation(instance)
        data["profile_image"] = _safe_file_url(getattr(instance, "profile_image", None))
        data["cover_image"] = _safe_file_url(getattr(instance, "cover_image", None))
        return data


class ProviderPortfolioItemSerializer(serializers.ModelSerializer):
    provider_id = serializers.IntegerField(source="provider.id", read_only=True)
    provider_display_name = serializers.CharField(source="provider.display_name", read_only=True)
    provider_username = serializers.CharField(source="provider.user.username", read_only=True)
    provider_profile_image = serializers.SerializerMethodField()
    is_verified_blue = serializers.SerializerMethodField()
    is_verified_green = serializers.SerializerMethodField()
    provider_is_online = serializers.SerializerMethodField()
    file_url = serializers.SerializerMethodField()
    thumbnail_url = serializers.SerializerMethodField()
    likes_count = serializers.SerializerMethodField()
    saves_count = serializers.SerializerMethodField()
    comments_count = serializers.SerializerMethodField()
    is_liked = serializers.SerializerMethodField()
    is_saved = serializers.SerializerMethodField()

    class Meta:
        model = ProviderPortfolioItem
        fields = (
            "id",
            "provider_id",
            "provider_display_name",
            "provider_username",
            "provider_profile_image",
            "is_verified_blue",
            "is_verified_green",
            "provider_is_online",
            "file_type",
            "file_url",
            "thumbnail_url",
            "caption",
            "likes_count",
            "saves_count",
            "comments_count",
            "is_liked",
            "is_saved",
            "created_at",
        )

    def get_file_url(self, obj):
        return _safe_file_url(getattr(obj, "file", None))

    def get_provider_profile_image(self, obj):
        provider = getattr(obj, "provider", None)
        return _safe_file_url(getattr(provider, "profile_image", None))

    def get_is_verified_blue(self, obj):
        return bool(getattr(getattr(obj, "provider", None), "is_verified_blue", False))

    def get_is_verified_green(self, obj):
        return bool(getattr(getattr(obj, "provider", None), "is_verified_green", False))

    def get_provider_is_online(self, obj):
        last = getattr(getattr(getattr(obj, "provider", None), "user", None), "last_seen", None)
        return _presence_is_online_value(last)

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

    def get_comments_count(self, obj):
        try:
            annotated = getattr(obj, "comments_count", None)
            if annotated is not None:
                return int(annotated)
            return int(obj.comments.filter(is_approved=True).count())
        except Exception:
            return 0

    def get_is_liked(self, obj):
        annotated = getattr(obj, "_is_liked", None)
        if annotated is not None:
            return bool(annotated)
        request = self.context.get("request")
        if request and hasattr(request, "user") and request.user.is_authenticated:
            role = get_active_role(request, fallback="client")
            return obj.likes.filter(user=request.user, role_context=role).exists()
        return False

    def get_is_saved(self, obj):
        annotated = getattr(obj, "_is_saved", None)
        if annotated is not None:
            return bool(annotated)
        request = self.context.get("request")
        if request and hasattr(request, "user") and request.user.is_authenticated:
            role = get_active_role(request, fallback="client")
            return obj.saves.filter(user=request.user, role_context=role).exists()
        return False


class ProviderPortfolioItemCreateSerializer(serializers.ModelSerializer):
    file_type = serializers.ChoiceField(
        choices=ProviderPortfolioItem.FILE_TYPE_CHOICES,
        required=False,
        allow_blank=True,
    )

    def validate(self, attrs):
        attrs = super().validate(attrs)
        upload = attrs.get("file")
        media_type = _infer_upload_media_type(
            upload,
            fallback=str(attrs.get("file_type") or "").strip().lower(),
        )
        attrs["file_type"] = media_type
        attrs["file"] = _normalize_provider_media_upload(
            upload,
            media_type=media_type,
            image_prefix="provider_portfolio_image",
            video_prefix="provider_portfolio_video",
        )
        return attrs

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


class ProviderPortfolioItemUpdateSerializer(serializers.ModelSerializer):
    file_type = serializers.ChoiceField(
        choices=ProviderPortfolioItem.FILE_TYPE_CHOICES,
        required=False,
        allow_blank=True,
    )

    def validate(self, attrs):
        attrs = super().validate(attrs)
        upload = attrs.get("file")
        if upload is None:
            attrs.pop("file_type", None)
            return attrs
        media_type = _infer_upload_media_type(
            upload,
            fallback=str(attrs.get("file_type") or "").strip().lower(),
        )
        attrs["file_type"] = media_type
        attrs["file"] = _normalize_provider_media_upload(
            upload,
            media_type=media_type,
            image_prefix="provider_portfolio_image",
            video_prefix="provider_portfolio_video",
        )
        return attrs

    class Meta:
        model = ProviderPortfolioItem
        fields = (
            "caption",
            "file_type",
            "file",
        )


class ProviderSpotlightItemSerializer(serializers.ModelSerializer):
    provider_id = serializers.IntegerField(source="provider.id", read_only=True)
    provider_display_name = serializers.CharField(source="provider.display_name", read_only=True)
    provider_username = serializers.CharField(source="provider.user.username", read_only=True)
    provider_profile_image = serializers.SerializerMethodField()
    is_verified_blue = serializers.SerializerMethodField()
    is_verified_green = serializers.SerializerMethodField()
    provider_is_online = serializers.SerializerMethodField()
    file_url = serializers.SerializerMethodField()
    thumbnail_url = serializers.SerializerMethodField()
    likes_count = serializers.SerializerMethodField()
    saves_count = serializers.SerializerMethodField()
    comments_count = serializers.SerializerMethodField()
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
            "is_verified_blue",
            "is_verified_green",
            "provider_is_online",
            "file_type",
            "file_url",
            "thumbnail_url",
            "caption",
            "likes_count",
            "saves_count",
            "comments_count",
            "is_liked",
            "is_saved",
            "created_at",
        )

    def get_provider_profile_image(self, obj):
        return _safe_file_url(getattr(obj.provider, "profile_image", None))

    def get_is_verified_blue(self, obj):
        return bool(getattr(obj.provider, "is_verified_blue", False))

    def get_is_verified_green(self, obj):
        return bool(getattr(obj.provider, "is_verified_green", False))

    def get_provider_is_online(self, obj):
        last = getattr(getattr(getattr(obj, "provider", None), "user", None), "last_seen", None)
        return _presence_is_online_value(last)

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

    def get_comments_count(self, obj):
        try:
            annotated = getattr(obj, "comments_count", None)
            if annotated is not None:
                return int(annotated)
            return int(obj.comments.filter(is_approved=True).count())
        except Exception:
            return 0

    def get_is_liked(self, obj):
        # Prefer annotated value to avoid N+1 queries
        annotated = getattr(obj, "_is_liked", None)
        if annotated is not None:
            return bool(annotated)
        request = self.context.get("request")
        if request and hasattr(request, "user") and request.user.is_authenticated:
            role = get_active_role(request, fallback="client")
            return obj.likes.filter(user=request.user, role_context=role).exists()
        return False

    def get_is_saved(self, obj):
        annotated = getattr(obj, "_is_saved", None)
        if annotated is not None:
            return bool(annotated)
        request = self.context.get("request")
        if request and hasattr(request, "user") and request.user.is_authenticated:
            role = get_active_role(request, fallback="client")
            return obj.saves.filter(user=request.user, role_context=role).exists()
        return False


class BlockedProviderSerializer(serializers.ModelSerializer):
    provider_id = serializers.IntegerField(source="provider.id", read_only=True)
    display_name = serializers.CharField(source="provider.display_name", read_only=True)
    username = serializers.CharField(source="provider.user.username", read_only=True)
    profile_image = serializers.SerializerMethodField()
    is_verified_blue = serializers.SerializerMethodField()
    is_verified_green = serializers.SerializerMethodField()
    country = serializers.CharField(source="provider.country", read_only=True)
    city = serializers.CharField(source="provider.city", read_only=True)
    region = serializers.CharField(source="provider.region", read_only=True)
    city_display = serializers.SerializerMethodField()
    blocked_at = serializers.DateTimeField(source="created_at", read_only=True)

    class Meta:
        model = ProviderVisibilityBlock
        fields = (
            "provider_id",
            "display_name",
            "username",
            "profile_image",
            "is_verified_blue",
            "is_verified_green",
            "country",
            "city",
            "region",
            "city_display",
            "blocked_at",
        )

    def get_profile_image(self, obj):
        return _safe_file_url(getattr(getattr(obj, "provider", None), "profile_image", None))

    def get_is_verified_blue(self, obj):
        return bool(getattr(getattr(obj, "provider", None), "is_verified_blue", False))

    def get_is_verified_green(self, obj):
        return bool(getattr(getattr(obj, "provider", None), "is_verified_green", False))

    def get_city_display(self, obj):
        provider = getattr(obj, "provider", None)
        return format_city_display(getattr(provider, "city", ""), region=getattr(provider, "region", ""))


class SpotlightCommentSerializer(serializers.ModelSerializer):
    parent_id = serializers.IntegerField(source="parent.id", read_only=True)
    user_id = serializers.IntegerField(source="user.id", read_only=True)
    username = serializers.CharField(source="user.username", read_only=True)
    display_name = serializers.SerializerMethodField()
    profile_image = serializers.SerializerMethodField()
    is_verified_blue = serializers.SerializerMethodField()
    is_verified_green = serializers.SerializerMethodField()
    is_provider = serializers.SerializerMethodField()
    is_mine = serializers.SerializerMethodField()
    is_liked = serializers.SerializerMethodField()
    likes_count = serializers.SerializerMethodField()
    replies = serializers.SerializerMethodField()
    replies_count = serializers.SerializerMethodField()

    class Meta:
        model = ProviderContentComment
        fields = (
            "id",
            "parent_id",
            "user_id",
            "username",
            "display_name",
            "profile_image",
            "is_verified_blue",
            "is_verified_green",
            "is_provider",
            "is_mine",
            "is_liked",
            "likes_count",
            "body",
            "replies_count",
            "replies",
            "created_at",
        )
        read_only_fields = fields

    def get_display_name(self, obj):
        provider = self._provider_identity(obj)
        if provider and getattr(provider, "display_name", ""):
            return provider.display_name
        user = getattr(obj, "user", None)
        full_name = " ".join(
            part for part in [getattr(user, "first_name", ""), getattr(user, "last_name", "")] if str(part or "").strip()
        ).strip()
        return full_name or getattr(user, "username", "") or "مستخدم"

    def get_profile_image(self, obj):
        provider = self._provider_identity(obj)
        return _safe_file_url(getattr(provider, "profile_image", None))

    def get_is_verified_blue(self, obj):
        provider = self._provider_identity(obj)
        return bool(getattr(provider, "is_verified_blue", False))

    def get_is_verified_green(self, obj):
        provider = self._provider_identity(obj)
        return bool(getattr(provider, "is_verified_green", False))

    def get_is_provider(self, obj):
        return bool(self._provider_identity(obj))

    def get_is_mine(self, obj):
        request = self.context.get("request")
        user = getattr(request, "user", None)
        if not user or not getattr(user, "is_authenticated", False):
            return False
        return int(getattr(user, "id", 0) or 0) == int(getattr(obj, "user_id", 0) or 0)

    def get_is_liked(self, obj):
        annotated = getattr(obj, "is_liked", None)
        if annotated is not None:
            return bool(annotated)
        request = self.context.get("request")
        user = getattr(request, "user", None)
        if not user or not getattr(user, "is_authenticated", False):
            return False
        role = get_active_role(request)
        return ProviderContentCommentLike.objects.filter(
            user=user,
            comment=obj,
            role_context=role,
        ).exists()

    def get_likes_count(self, obj):
        annotated = getattr(obj, "likes_count", None)
        if annotated is not None:
            return int(annotated or 0)
        return int(obj.likes.count())

    def get_replies_count(self, obj):
        prefetched = getattr(obj, "prefetched_replies", None)
        if prefetched is not None:
            return len(prefetched)
        return int(obj.replies.filter(is_approved=True).count())

    def get_replies(self, obj):
        prefetched = getattr(obj, "prefetched_replies", None)
        if prefetched is None:
            prefetched = list(
                obj.replies.filter(is_approved=True)
                .select_related("user", "user__provider_profile")
                .order_by("created_at", "id")
            )
        serializer = SpotlightCommentSerializer(prefetched, many=True, context=self.context)
        return serializer.data

    @staticmethod
    def _provider_identity(obj):
        if str(getattr(obj, "role_context", "") or "").strip().lower() != RoleContext.PROVIDER:
            return None
        return getattr(getattr(obj, "user", None), "provider_profile", None)


class SpotlightCommentCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = ProviderContentComment
        fields = ("body", "parent")
        extra_kwargs = {
            "parent": {"required": False, "allow_null": True},
        }

    def validate_body(self, value):
        cleaned = " ".join(str(value or "").split()).strip()
        if not cleaned:
            raise serializers.ValidationError("نص التعليق مطلوب")
        if len(cleaned) > 1000:
            raise serializers.ValidationError("التعليق طويل جدًا")
        return cleaned

    def validate_parent(self, value):
        if value is None:
            return None
        if getattr(value, "parent_id", None):
            raise serializers.ValidationError("يمكن الرد على التعليق الأساسي فقط")
        if not getattr(value, "is_approved", False):
            raise serializers.ValidationError("لا يمكن الرد على هذا التعليق")
        return value


class BlockedSpotlightSerializer(serializers.ModelSerializer):
    spotlight_id = serializers.IntegerField(source="spotlight_item.id", read_only=True)
    provider_id = serializers.IntegerField(source="spotlight_item.provider.id", read_only=True)
    provider_display_name = serializers.CharField(source="spotlight_item.provider.display_name", read_only=True)
    provider_username = serializers.CharField(source="spotlight_item.provider.user.username", read_only=True)
    provider_profile_image = serializers.SerializerMethodField()
    is_verified_blue = serializers.SerializerMethodField()
    is_verified_green = serializers.SerializerMethodField()
    file_type = serializers.CharField(source="spotlight_item.file_type", read_only=True)
    file_url = serializers.SerializerMethodField()
    thumbnail_url = serializers.SerializerMethodField()
    caption = serializers.CharField(source="spotlight_item.caption", read_only=True)
    blocked_at = serializers.DateTimeField(source="created_at", read_only=True)

    class Meta:
        model = ProviderSpotlightVisibilityBlock
        fields = (
            "spotlight_id",
            "provider_id",
            "provider_display_name",
            "provider_username",
            "provider_profile_image",
            "is_verified_blue",
            "is_verified_green",
            "file_type",
            "file_url",
            "thumbnail_url",
            "caption",
            "blocked_at",
        )

    def get_provider_profile_image(self, obj):
        provider = getattr(getattr(obj, "spotlight_item", None), "provider", None)
        return _safe_file_url(getattr(provider, "profile_image", None))

    def get_is_verified_blue(self, obj):
        provider = getattr(getattr(obj, "spotlight_item", None), "provider", None)
        return bool(getattr(provider, "is_verified_blue", False))

    def get_is_verified_green(self, obj):
        provider = getattr(getattr(obj, "spotlight_item", None), "provider", None)
        return bool(getattr(provider, "is_verified_green", False))

    def get_file_url(self, obj):
        item = getattr(obj, "spotlight_item", None)
        return _safe_file_url(getattr(item, "file", None))

    def get_thumbnail_url(self, obj):
        item = getattr(obj, "spotlight_item", None)
        return _safe_file_url(getattr(item, "thumbnail", None))


class ProviderSpotlightItemCreateSerializer(serializers.ModelSerializer):
    file_type = serializers.ChoiceField(
        choices=ProviderSpotlightItem.FILE_TYPE_CHOICES,
        required=False,
        allow_blank=True,
    )

    def validate(self, attrs):
        attrs = super().validate(attrs)
        request = self.context.get("request")
        user = getattr(request, "user", None)
        if user is not None:
            from apps.subscriptions.services import user_has_active_subscription

            if not user_has_active_subscription(user):
                raise serializers.ValidationError(
                    {
                        "detail": "رفع الريلز والأضواء يتطلب اشتراكًا فعالًا في إحدى الباقات.",
                        "code": "subscription_required",
                    }
                )
        upload = attrs.get("file")
        file_type = (attrs.get("file_type") or "").strip().lower()

        if not file_type and upload is not None:
            content_type = str(getattr(upload, "content_type", "") or "").strip().lower()
            filename = str(getattr(upload, "name", "") or "").strip().lower()
            if content_type.startswith("video/") or filename.endswith((".mp4", ".mov", ".avi", ".webm", ".mkv")):
                file_type = "video"
            elif content_type.startswith("image/") or filename.endswith((".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp")):
                file_type = "image"

        if file_type not in {"image", "video"}:
            raise serializers.ValidationError({
                "file_type": "نوع الملف يجب أن يكون صورة أو فيديو.",
            })

        attrs["file_type"] = file_type
        attrs["file"] = _normalize_provider_media_upload(
            upload,
            media_type=file_type,
            image_prefix="provider_spotlight_image",
            video_prefix="provider_spotlight_video",
        )
        return attrs

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
    profile_image = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = (
            "id",
            "username",
            "display_name",
            "provider_id",
            "profile_image",
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

    def get_profile_image(self, obj: User) -> str:
        profile = getattr(obj, "provider_profile", None)
        provider_image = _safe_file_url(getattr(profile, "profile_image", None)) if profile is not None else ""
        if provider_image:
            return provider_image
        return _safe_file_url(getattr(obj, "profile_image", None))


class ProviderFollowerSerializer(serializers.ModelSerializer):
    id = serializers.IntegerField(source="user.id", read_only=True)
    username = serializers.CharField(source="user.username", read_only=True)
    display_name = serializers.SerializerMethodField()
    provider_id = serializers.SerializerMethodField()
    profile_image = serializers.SerializerMethodField()
    is_verified_blue = serializers.SerializerMethodField()
    is_verified_green = serializers.SerializerMethodField()
    follow_role_context = serializers.CharField(source="role_context", read_only=True)

    class Meta:
        model = ProviderFollow
        fields = (
            "id",
            "username",
            "display_name",
            "provider_id",
            "profile_image",
            "is_verified_blue",
            "is_verified_green",
            "follow_role_context",
            "created_at",
        )

    def get_display_name(self, obj: ProviderFollow) -> str:
        user = getattr(obj, "user", None)
        if user is None:
            return "مستخدم"
        if getattr(obj, "role_context", "") == "provider":
            profile = getattr(user, "provider_profile", None)
            provider_name = (getattr(profile, "display_name", "") or "").strip() if profile is not None else ""
            if provider_name:
                return provider_name
        first = (getattr(user, "first_name", "") or "").strip()
        last = (getattr(user, "last_name", "") or "").strip()
        if first or last:
            return (f"{first} {last}").strip()
        username = (getattr(user, "username", "") or "").strip()
        return username or "مستخدم"

    def get_provider_id(self, obj: ProviderFollow):
        if getattr(obj, "role_context", "") != "provider":
            return None
        user = getattr(obj, "user", None)
        profile = getattr(user, "provider_profile", None) if user is not None else None
        return profile.id if profile else None

    def get_profile_image(self, obj: ProviderFollow) -> str:
        user = getattr(obj, "user", None)
        if user is None:
            return ""
        profile = getattr(user, "provider_profile", None)
        provider_image = _safe_file_url(getattr(profile, "profile_image", None)) if profile is not None else ""
        if provider_image:
            return provider_image
        return _safe_file_url(getattr(user, "profile_image", None))

    def get_is_verified_blue(self, obj: ProviderFollow) -> bool:
        user = getattr(obj, "user", None)
        profile = getattr(user, "provider_profile", None) if user is not None else None
        return bool(getattr(profile, "is_verified_blue", False))

    def get_is_verified_green(self, obj: ProviderFollow) -> bool:
        user = getattr(obj, "user", None)
        profile = getattr(user, "provider_profile", None) if user is not None else None
        return bool(getattr(profile, "is_verified_green", False))


class MyProviderSubcategoriesSerializer(serializers.Serializer):
    subcategory_ids = serializers.ListField(
        child=serializers.IntegerField(min_value=1),
        allow_empty=True,
        required=False,
        default=list,
    )
    subcategory_settings = ProviderSubcategorySettingSerializer(many=True, required=False, default=list)

    def validate(self, attrs):
        raw_ids = list(attrs.get("subcategory_ids") or [])
        raw_settings = list(attrs.get("subcategory_settings") or [])

        ordered_ids = []
        settings_by_id = {}

        for sub_id in raw_ids:
            if sub_id in settings_by_id:
                continue
            ordered_ids.append(sub_id)
            settings_by_id[sub_id] = {
                "accepts_urgent": False,
            }

        for item in raw_settings:
            sub_id = item["subcategory_id"]
            if sub_id not in settings_by_id:
                ordered_ids.append(sub_id)
                settings_by_id[sub_id] = {
                    "accepts_urgent": False,
                }
            settings_by_id[sub_id] = {
                "accepts_urgent": bool(item.get("accepts_urgent", False)),
            }

        ids = ordered_ids
        if not ids:
            attrs["subcategory_ids"] = []
            attrs["subcategory_settings"] = []
            return attrs

        active_subcategories = {
            row.id: row for row in SubCategory.objects.filter(id__in=ids, is_active=True)
        }
        missing = [i for i in ids if i not in active_subcategories]
        if missing:
            raise serializers.ValidationError(f"تصنيفات فرعية غير صالحة: {missing}")

        attrs["subcategory_ids"] = ids
        normalized_settings = []
        for sub_id in ids:
            subcategory = active_subcategories[sub_id]
            accepts_urgent = bool((settings_by_id.get(sub_id) or {}).get("accepts_urgent", False))
            if accepts_urgent and not bool(getattr(subcategory, "allows_urgent_requests", False)):
                raise serializers.ValidationError(
                    {"subcategory_settings": f"التصنيف الفرعي {subcategory.name} لا يدعم الطلبات العاجلة."}
                )
            normalized_settings.append(
                {
                    "subcategory_id": sub_id,
                    "accepts_urgent": bool(
                        accepts_urgent and getattr(subcategory, "allows_urgent_requests", False)
                    ),
                    "requires_geo_scope": bool(getattr(subcategory, "requires_geo_scope", True)),
                }
            )

        attrs["subcategory_settings"] = normalized_settings
        return attrs


class SubCategoryWithCategorySerializer(serializers.ModelSerializer):
    category_id = serializers.IntegerField(read_only=True)
    category_name = serializers.CharField(source="category.name", read_only=True)

    class Meta:
        model = SubCategory
        fields = (
            "id",
            "name",
            "requires_geo_scope",
            "allows_urgent_requests",
            "category_id",
            "category_name",
        )


class ProviderServiceSerializer(serializers.ModelSerializer):
    provider_id = serializers.IntegerField(read_only=True)
    price_unit_label = serializers.CharField(source="get_price_unit_display", read_only=True)
    accepts_urgent = serializers.SerializerMethodField()
    requires_geo_scope = serializers.SerializerMethodField()
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
            "price_unit_label",
            "is_active",
            "accepts_urgent",
            "requires_geo_scope",
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

    def _input_accepts_urgent(self):
        if not hasattr(self, "initial_data") or not hasattr(self.initial_data, "get"):
            return serializers.empty
        if "accepts_urgent" not in self.initial_data:
            return serializers.empty
        return serializers.BooleanField(required=False).run_validation(self.initial_data.get("accepts_urgent"))

    def _accepts_urgent_map(self, provider_id):
        cache = self.context.setdefault("_provider_category_urgent_cache", {})
        if provider_id not in cache:
            cache[provider_id] = dict(
                ProviderCategory.objects.filter(provider_id=provider_id)
                .values_list("subcategory_id", "accepts_urgent")
            )
        return cache[provider_id]

    def _normalize_accepts_urgent(self, *, subcategory, accepts_urgent):
        normalized = False if accepts_urgent is serializers.empty else bool(accepts_urgent)
        if normalized and not bool(getattr(subcategory, "allows_urgent_requests", False)):
            raise serializers.ValidationError({"accepts_urgent": "هذا التصنيف الفرعي لا يدعم الطلبات العاجلة."})
        return bool(normalized and getattr(subcategory, "allows_urgent_requests", False))

    def _upsert_provider_category(self, provider, subcategory, accepts_urgent):
        relation, created = ProviderCategory.objects.get_or_create(
            provider=provider,
            subcategory=subcategory,
            defaults={
                "accepts_urgent": bool(accepts_urgent),
                "requires_geo_scope": bool(getattr(subcategory, "requires_geo_scope", True)),
            },
        )
        update_fields = []
        if not created and relation.accepts_urgent != bool(accepts_urgent):
            relation.accepts_urgent = bool(accepts_urgent)
            update_fields.append("accepts_urgent")
        if not created and relation.requires_geo_scope != bool(getattr(subcategory, "requires_geo_scope", True)):
            relation.requires_geo_scope = bool(getattr(subcategory, "requires_geo_scope", True))
            update_fields.append("requires_geo_scope")
        if update_fields:
            relation.save(update_fields=update_fields)
        cache = self.context.get("_provider_category_urgent_cache")
        if isinstance(cache, dict) and getattr(provider, "id", None) in cache:
            cache[provider.id][subcategory.id] = bool(accepts_urgent)
        sync_provider_accepts_urgent_flag(provider)

    def get_accepts_urgent(self, obj):
        provider_id = getattr(obj, "provider_id", None)
        subcategory_id = getattr(obj, "subcategory_id", None)
        if not provider_id or not subcategory_id:
            return False
        if not bool(getattr(getattr(obj, "subcategory", None), "allows_urgent_requests", False)):
            return False
        return bool(self._accepts_urgent_map(provider_id).get(subcategory_id, False))

    def get_requires_geo_scope(self, obj):
        return bool(getattr(getattr(obj, "subcategory", None), "requires_geo_scope", True))

    def create(self, validated_data):
        subcategory = validated_data.get("subcategory")
        accepts_urgent = self._normalize_accepts_urgent(
            subcategory=subcategory,
            accepts_urgent=self._input_accepts_urgent(),
        )
        service = super().create(validated_data)
        self._upsert_provider_category(service.provider, service.subcategory, accepts_urgent)
        return service

    def update(self, instance, validated_data):
        subcategory = validated_data.get("subcategory", getattr(instance, "subcategory", None))
        accepts_urgent = self._input_accepts_urgent()
        service = super().update(instance, validated_data)
        if accepts_urgent is serializers.empty:
            accepts_urgent = self.get_accepts_urgent(service)
        accepts_urgent = self._normalize_accepts_urgent(subcategory=subcategory, accepts_urgent=accepts_urgent)
        self._upsert_provider_category(service.provider, service.subcategory, accepts_urgent)
        return service


class ProviderServicePublicSerializer(serializers.ModelSerializer):
    price_unit_label = serializers.CharField(source="get_price_unit_display", read_only=True)
    requires_geo_scope = serializers.SerializerMethodField()
    subcategory = SubCategoryWithCategorySerializer(read_only=True)

    def get_requires_geo_scope(self, obj):
        return bool(getattr(getattr(obj, "subcategory", None), "requires_geo_scope", True))

    class Meta:
        model = ProviderService
        fields = (
            "id",
            "title",
            "description",
            "price_from",
            "price_to",
            "price_unit",
            "price_unit_label",
            "requires_geo_scope",
            "subcategory",
            "created_at",
            "updated_at",
        )
        read_only_fields = fields


class ProviderServicePublicDetailSerializer(ProviderServicePublicSerializer):
    provider_id = serializers.IntegerField(source="provider.id", read_only=True)
    provider_name = serializers.CharField(source="provider.display_name", read_only=True)
    provider_avatar = serializers.SerializerMethodField()
    provider_is_online = serializers.SerializerMethodField()
    category_name = serializers.CharField(source="subcategory.category.name", read_only=True)

    class Meta(ProviderServicePublicSerializer.Meta):
        fields = (
            "id",
            "provider_id",
            "provider_name",
            "provider_avatar",
            "provider_is_online",
            "title",
            "description",
            "price_from",
            "price_to",
            "price_unit",
            "price_unit_label",
            "requires_geo_scope",
            "category_name",
            "subcategory",
            "created_at",
            "updated_at",
        )
        read_only_fields = fields

    def get_provider_avatar(self, obj):
        return _safe_file_url(getattr(obj.provider, "profile_image", None))

    def get_provider_is_online(self, obj):
        last = getattr(getattr(getattr(obj, "provider", None), "user", None), "last_seen", None)
        return _presence_is_online_value(last)
