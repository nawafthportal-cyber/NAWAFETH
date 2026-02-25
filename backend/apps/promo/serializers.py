from __future__ import annotations

from rest_framework import serializers
from django.utils import timezone

from .models import (
    PromoRequest, PromoAsset,
    PromoRequestStatus,
    PromoAdType, PromoFrequency, PromoPosition,
)


class PromoHomeBannerAssetSerializer(serializers.ModelSerializer):
    """Public-facing banner asset payload.

    Matches the mobile app's `ProviderPortfolioItem` JSON shape to reuse
    existing UI widgets safely (no provider portfolio leakage).
    """

    provider_id = serializers.SerializerMethodField()
    provider_display_name = serializers.SerializerMethodField()
    provider_username = serializers.SerializerMethodField()
    file_type = serializers.SerializerMethodField()
    file_url = serializers.FileField(source="file", read_only=True)
    caption = serializers.SerializerMethodField()
    redirect_url = serializers.SerializerMethodField()
    created_at = serializers.DateTimeField(source="uploaded_at", read_only=True)

    class Meta:
        model = PromoAsset
        fields = [
            "id",
            "provider_id",
            "provider_display_name",
            "provider_username",
            "file_type",
            "file_url",
            "caption",
            "redirect_url",
            "created_at",
        ]

    def _provider_profile(self, obj: PromoAsset):
        try:
            return obj.request.requester.provider_profile
        except Exception:
            return None

    def get_provider_id(self, obj: PromoAsset) -> int:
        pp = self._provider_profile(obj)
        return int(pp.id) if pp else 0

    def get_provider_display_name(self, obj: PromoAsset) -> str:
        pp = self._provider_profile(obj)
        if pp and getattr(pp, "display_name", None):
            return str(pp.display_name)

        requester = getattr(obj.request, "requester", None)
        username = getattr(requester, "username", None)
        if username:
            return str(username)

        phone = getattr(requester, "phone", None)
        if phone:
            return str(phone)

        return str(getattr(obj.request, "title", "إعلان"))

    def get_provider_username(self, obj: PromoAsset) -> str:
        requester = getattr(obj.request, "requester", None)
        return str(getattr(requester, "username", "") or "")

    def get_file_type(self, obj: PromoAsset) -> str:
        # Mobile expects: image | video
        t = (getattr(obj, "asset_type", "") or "").lower().strip()
        return "video" if t == "video" else "image"

    def get_caption(self, obj: PromoAsset) -> str:
        title = (getattr(obj, "title", "") or "").strip()
        if title:
            return title
        return str(getattr(obj.request, "title", "") or "")

    def get_redirect_url(self, obj: PromoAsset) -> str:
        return str(getattr(obj.request, "redirect_url", "") or "")


class PromoAssetSerializer(serializers.ModelSerializer):
    class Meta:
        model = PromoAsset
        fields = ["id", "asset_type", "title", "file", "uploaded_by", "uploaded_at"]
        read_only_fields = ["uploaded_by", "uploaded_at"]


class PromoRequestCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = PromoRequest
        fields = [
            "id", "code",
            "title", "ad_type",
            "start_at", "end_at",
            "frequency", "position",
            "target_category", "target_city",
            "target_provider", "target_portfolio_item",
            "message_title", "message_body",
            "redirect_url",
        ]
        read_only_fields = ["id", "code"]

    def validate(self, attrs):
        from apps.features.checks import has_feature

        request = self.context.get("request")
        user = getattr(request, "user", None)
        if user is not None and user.is_authenticated:
            if not has_feature(user, "promo_ads"):
                raise serializers.ValidationError("ميزة الإعلانات (Promo) غير متاحة في باقتك الحالية.")

        start_at = attrs.get("start_at")
        end_at = attrs.get("end_at")

        if not start_at or not end_at:
            raise serializers.ValidationError("start_at و end_at مطلوبان.")

        if end_at <= start_at:
            raise serializers.ValidationError("تاريخ النهاية يجب أن يكون بعد البداية.")

        if start_at < timezone.now():
            raise serializers.ValidationError("لا يمكن بدء حملة بتاريخ ماضي.")

        if (end_at - start_at).total_seconds() < 24 * 60 * 60:
            raise serializers.ValidationError("الحد الأدنى لمدة الحملة الإعلانية هو 24 ساعة.")

        ad_type = attrs.get("ad_type")
        if ad_type not in PromoAdType.values:
            raise serializers.ValidationError("نوع الإعلان غير صحيح.")

        frequency = attrs.get("frequency")
        if frequency not in PromoFrequency.values:
            raise serializers.ValidationError("معدل الظهور غير صحيح.")

        position = attrs.get("position")
        if position not in PromoPosition.values:
            raise serializers.ValidationError("موقع الظهور غير صحيح.")

        return attrs

    def create(self, validated_data):
        request = self.context["request"]
        user = request.user
        from .services import _sync_promo_to_unified
        pr = PromoRequest.objects.create(
            requester=user,
            status=PromoRequestStatus.NEW,
            **validated_data,
        )
        _sync_promo_to_unified(pr=pr, changed_by=user)

        # Audit
        try:
            from apps.audit.services import log_action
            from apps.audit.models import AuditAction

            log_action(
                actor=user,
                action=AuditAction.PROMO_REQUEST_CREATED,
                reference_type="promo_request",
                reference_id=pr.code,
                request=request,
            )
        except Exception:
            pass

        return pr


class PromoRequestDetailSerializer(serializers.ModelSerializer):
    assets = PromoAssetSerializer(many=True, read_only=True)

    class Meta:
        model = PromoRequest
        fields = [
            "id", "code",
            "title", "ad_type",
            "start_at", "end_at",
            "frequency", "position",
            "target_category", "target_city",
            "target_provider", "target_portfolio_item",
            "message_title", "message_body",
            "redirect_url",
            "status",
            "subtotal", "total_days",
            "quote_note", "reject_reason",
            "invoice",
            "reviewed_at", "activated_at",
            "created_at", "updated_at",
            "assets",
        ]


class PromoActivePlacementSerializer(serializers.ModelSerializer):
    """Public-facing active promo placement payload.

    Used by the mobile app to render various promo placements.
    """

    assets = PromoHomeBannerAssetSerializer(many=True, read_only=True)

    target_provider_id = serializers.IntegerField(source="target_provider.id", read_only=True)
    target_provider_display_name = serializers.CharField(source="target_provider.display_name", read_only=True)
    target_provider_profile_image = serializers.FileField(source="target_provider.profile_image", read_only=True)
    target_provider_city = serializers.CharField(source="target_provider.city", read_only=True)
    target_provider_type = serializers.CharField(source="target_provider.provider_type", read_only=True)

    target_portfolio_item_id = serializers.IntegerField(source="target_portfolio_item.id", read_only=True)
    target_portfolio_item_file = serializers.FileField(source="target_portfolio_item.file", read_only=True)
    target_portfolio_item_file_type = serializers.CharField(source="target_portfolio_item.file_type", read_only=True)

    class Meta:
        model = PromoRequest
        fields = [
            "id",
            "code",
            "title",
            "ad_type",
            "start_at",
            "end_at",
            "frequency",
            "position",
            "target_category",
            "target_city",
            "redirect_url",
            "message_title",
            "message_body",
            "target_provider_id",
            "target_provider_display_name",
            "target_provider_profile_image",
            "target_provider_city",
            "target_provider_type",
            "target_portfolio_item_id",
            "target_portfolio_item_file",
            "target_portfolio_item_file_type",
            "assets",
        ]


class PromoQuoteSerializer(serializers.Serializer):
    """
    للموظف: يضيف ملاحظة أو يستخدم التسعير التلقائي فقط
    """
    quote_note = serializers.CharField(required=False, allow_blank=True, max_length=300)


class PromoRejectSerializer(serializers.Serializer):
    reject_reason = serializers.CharField(required=True, max_length=300)
