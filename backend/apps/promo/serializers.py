from __future__ import annotations

from rest_framework import serializers
from django.utils import timezone

from apps.providers.models import ProviderPortfolioItem
from apps.providers.serializers import ProviderPortfolioItemSerializer
from apps.subscriptions.capabilities import (
    promotional_chat_controls_enabled_for_user,
    promotional_notification_controls_enabled_for_user,
)

from .models import (
    HomeBanner,
    PromoAdType,
    PromoAsset,
    PromoFrequency,
    PromoMessageChannel,
    PromoOpsStatus,
    PromoPosition,
    PromoRequest,
    PromoRequestItem,
    PromoRequestStatus,
    PromoSearchScope,
    PromoServiceType,
)


class PromoHomeBannerAssetSerializer(serializers.ModelSerializer):
    provider_id = serializers.SerializerMethodField()
    provider_display_name = serializers.SerializerMethodField()
    provider_username = serializers.SerializerMethodField()
    file_type = serializers.SerializerMethodField()
    file = serializers.FileField(read_only=True)
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
            "file",
            "file_url",
            "caption",
            "redirect_url",
            "created_at",
        ]

    def _provider_profile(self, obj: PromoAsset):
        try:
            target_provider = getattr(getattr(obj, "item", None), "target_provider", None)
            if target_provider:
                return target_provider
            request_target = getattr(obj.request, "target_provider", None)
            if request_target:
                return request_target
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
        return str(getattr(requester, "username", "") or getattr(requester, "phone", "") or getattr(obj.request, "title", "إعلان"))

    def get_provider_username(self, obj: PromoAsset) -> str:
        pp = self._provider_profile(obj)
        user = getattr(pp, "user", None)
        if user and getattr(user, "username", None):
            return str(user.username)
        requester = getattr(obj.request, "requester", None)
        return str(getattr(requester, "username", "") or "")

    def get_file_type(self, obj: PromoAsset) -> str:
        return "video" if (getattr(obj, "asset_type", "") or "").lower().strip() == "video" else "image"

    def get_caption(self, obj: PromoAsset) -> str:
        title = (getattr(obj, "title", "") or "").strip()
        if title:
            return title
        item = getattr(obj, "item", None)
        if item and item.title:
            return item.title
        return str(getattr(obj.request, "title", "") or "")

    def get_redirect_url(self, obj: PromoAsset) -> str:
        item = getattr(obj, "item", None)
        if item and item.redirect_url:
            return str(item.redirect_url)
        return str(getattr(obj.request, "redirect_url", "") or "")


class PromoAssetSerializer(serializers.ModelSerializer):
    class Meta:
        model = PromoAsset
        fields = ["id", "request", "item", "asset_type", "title", "file", "uploaded_by", "uploaded_at"]
        read_only_fields = ["uploaded_by", "uploaded_at", "request"]


class PromoRequestItemCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = PromoRequestItem
        fields = [
            "id",
            "service_type",
            "title",
            "start_at",
            "end_at",
            "send_at",
            "frequency",
            "search_scope",
            "search_position",
            "target_category",
            "target_city",
            "target_provider",
            "target_portfolio_item",
            "redirect_url",
            "message_title",
            "message_body",
            "use_notification_channel",
            "use_chat_channel",
            "sponsor_name",
            "sponsor_url",
            "sponsorship_months",
            "attachment_specs",
            "operator_note",
            "sort_order",
        ]
        read_only_fields = ["id"]

    def validate(self, attrs):
        service_type = attrs.get("service_type")
        start_at = attrs.get("start_at")
        end_at = attrs.get("end_at")
        send_at = attrs.get("send_at")
        from .services import promo_min_campaign_hours, promo_min_campaign_message

        if service_type in {
            PromoServiceType.HOME_BANNER,
            PromoServiceType.FEATURED_SPECIALISTS,
            PromoServiceType.PORTFOLIO_SHOWCASE,
            PromoServiceType.SNAPSHOTS,
            PromoServiceType.SEARCH_RESULTS,
        }:
            if not start_at or not end_at:
                raise serializers.ValidationError("تاريخ البداية والنهاية مطلوبان لهذا البند.")
            if end_at <= start_at:
                raise serializers.ValidationError("تاريخ النهاية يجب أن يكون بعد البداية.")
            if start_at < timezone.now():
                raise serializers.ValidationError("لا يمكن بدء حملة بتاريخ ماض.")
            if (end_at - start_at).total_seconds() < promo_min_campaign_hours() * 60 * 60:
                raise serializers.ValidationError(promo_min_campaign_message())

        if service_type in {
            PromoServiceType.FEATURED_SPECIALISTS,
            PromoServiceType.PORTFOLIO_SHOWCASE,
            PromoServiceType.SNAPSHOTS,
        } and attrs.get("frequency") not in PromoFrequency.values:
            raise serializers.ValidationError("معدل الظهور غير صحيح.")

        if service_type == PromoServiceType.SEARCH_RESULTS:
            if attrs.get("search_scope") not in PromoSearchScope.values:
                raise serializers.ValidationError("قائمة الظهور مطلوبة.")
            if attrs.get("search_position") not in {
                PromoPosition.FIRST,
                PromoPosition.SECOND,
                PromoPosition.TOP5,
                PromoPosition.TOP10,
            }:
                raise serializers.ValidationError("ترتيب الظهور غير صحيح.")

        if service_type == PromoServiceType.PROMO_MESSAGES:
            if not send_at:
                raise serializers.ValidationError("وقت الإرسال مطلوب للرسائل الدعائية.")
            if send_at < timezone.now():
                raise serializers.ValidationError("لا يمكن جدولة رسالة دعائية في الماضي.")
            if not attrs.get("use_notification_channel") and not attrs.get("use_chat_channel"):
                raise serializers.ValidationError("اختر قناة إرسال واحدة على الأقل.")

        if service_type == PromoServiceType.SPONSORSHIP and int(attrs.get("sponsorship_months") or 0) <= 0:
            raise serializers.ValidationError("مدة الرعاية بالأشهر مطلوبة.")

        return attrs


class PromoRequestItemDetailSerializer(serializers.ModelSerializer):
    assets = PromoAssetSerializer(many=True, read_only=True)
    service_type_label = serializers.CharField(source="get_service_type_display", read_only=True)
    frequency_label = serializers.CharField(source="get_frequency_display", read_only=True)
    search_scope_label = serializers.CharField(source="get_search_scope_display", read_only=True)
    search_position_label = serializers.CharField(source="get_search_position_display", read_only=True)

    class Meta:
        model = PromoRequestItem
        fields = [
            "id",
            "service_type",
            "service_type_label",
            "title",
            "start_at",
            "end_at",
            "send_at",
            "frequency",
            "frequency_label",
            "search_scope",
            "search_scope_label",
            "search_position",
            "search_position_label",
            "target_category",
            "target_city",
            "target_provider",
            "target_portfolio_item",
            "redirect_url",
            "message_title",
            "message_body",
            "use_notification_channel",
            "use_chat_channel",
            "message_sent_at",
            "message_recipients_count",
            "message_dispatch_error",
            "sponsor_name",
            "sponsor_url",
            "sponsorship_months",
            "attachment_specs",
            "operator_note",
            "subtotal",
            "duration_days",
            "pricing_rule_code",
            "sort_order",
            "assets",
        ]


class PromoRequestCreateSerializer(serializers.ModelSerializer):
    items = PromoRequestItemCreateSerializer(many=True, required=False)

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
            "target_provider",
            "target_portfolio_item",
            "message_title",
            "message_body",
            "redirect_url",
            "items",
        ]
        read_only_fields = ["id", "code"]
        extra_kwargs = {
            "title": {"required": False, "allow_blank": True},
            "ad_type": {"required": False},
            "start_at": {"required": False},
            "end_at": {"required": False},
        }

    def validate(self, attrs):
        request = self.context.get("request")
        user = getattr(request, "user", None)
        items = attrs.get("items") or []
        from .services import promo_min_campaign_hours, promo_min_campaign_message

        if items:
            has_notification = any(item.get("use_notification_channel") for item in items)
            has_chat = any(item.get("use_chat_channel") for item in items)
            if user is not None and user.is_authenticated:
                if has_notification and not promotional_notification_controls_enabled_for_user(user):
                    raise serializers.ValidationError("رسائل التنبيه الدعائية متاحة فقط ضمن الباقة الاحترافية.")
                if has_chat and not promotional_chat_controls_enabled_for_user(user):
                    raise serializers.ValidationError("رسائل المحادثات الدعائية متاحة فقط ضمن الباقة الاحترافية.")
            return attrs

        message_title = (attrs.get("message_title") or "").strip()
        message_body = (attrs.get("message_body") or "").strip()
        attrs["message_title"] = message_title
        attrs["message_body"] = message_body

        if user is not None and user.is_authenticated:
            if attrs.get("ad_type") == PromoAdType.PUSH_NOTIFICATION and not promotional_notification_controls_enabled_for_user(user):
                raise serializers.ValidationError("الإشعارات الدعائية متاحة فقط ضمن الباقة الاحترافية.")
            if (message_title or message_body) and not promotional_chat_controls_enabled_for_user(user):
                raise serializers.ValidationError("الرسائل الدعائية متاحة فقط ضمن الباقة الاحترافية.")

        start_at = attrs.get("start_at")
        end_at = attrs.get("end_at")
        if not start_at or not end_at:
            raise serializers.ValidationError("start_at و end_at مطلوبان.")
        if end_at <= start_at:
            raise serializers.ValidationError("تاريخ النهاية يجب أن يكون بعد البداية.")
        if start_at < timezone.now():
            raise serializers.ValidationError("لا يمكن بدء حملة بتاريخ ماضي.")
        if (end_at - start_at).total_seconds() < promo_min_campaign_hours() * 60 * 60:
            raise serializers.ValidationError(
                promo_min_campaign_message(prefix="الحد الأدنى لمدة الحملة الإعلانية هو")
            )
        if attrs.get("ad_type") not in PromoAdType.values:
            raise serializers.ValidationError("نوع الإعلان غير صحيح.")
        if attrs.get("frequency") not in PromoFrequency.values:
            raise serializers.ValidationError("معدل الظهور غير صحيح.")
        if attrs.get("position") not in PromoPosition.values:
            raise serializers.ValidationError("موقع الظهور غير صحيح.")
        return attrs

    def create(self, validated_data):
        request = self.context["request"]
        user = request.user
        items_data = validated_data.pop("items", [])
        from .services import _promo_request_summary, _sync_promo_to_unified

        if items_data:
            provider_profile = getattr(user, "provider_profile", None)
            normalized_items = []
            auto_targeted_service_types = {
                PromoServiceType.FEATURED_SPECIALISTS,
                PromoServiceType.PORTFOLIO_SHOWCASE,
                PromoServiceType.SNAPSHOTS,
                PromoServiceType.SEARCH_RESULTS,
            }
            for row in items_data:
                normalized = dict(row)
                if (
                    provider_profile is not None
                    and normalized.get("service_type") in auto_targeted_service_types
                    and not normalized.get("target_provider")
                ):
                    normalized["target_provider"] = provider_profile
                normalized_items.append(normalized)

            schedule_points = []
            for row in normalized_items:
                if row.get("start_at"):
                    schedule_points.append(("start", row["start_at"]))
                if row.get("end_at"):
                    schedule_points.append(("end", row["end_at"]))
                if row.get("send_at"):
                    schedule_points.append(("send", row["send_at"]))
            starts = [point for kind, point in schedule_points if kind == "start"]
            ends = [point for kind, point in schedule_points if kind == "end"]
            sends = [point for kind, point in schedule_points if kind == "send"]
            request_start = min(starts) if starts else (min(sends) if sends else timezone.now())
            request_end = max(ends) if ends else (max(sends) if sends else request_start)
            pr = PromoRequest.objects.create(
                requester=user,
                title=(validated_data.get("title") or "طلب ترويج متعدد الخدمات")[:160],
                ad_type=PromoAdType.BUNDLE,
                start_at=request_start,
                end_at=request_end,
                frequency=PromoFrequency.S60,
                position=PromoPosition.NORMAL,
                status=PromoRequestStatus.NEW,
                ops_status=PromoOpsStatus.NEW,
            )
            for row in normalized_items:
                PromoRequestItem.objects.create(request=pr, **row)
            pr.title = (_promo_request_summary(pr) or pr.title)[:160]
            pr.save(update_fields=["title", "updated_at"])
            _sync_promo_to_unified(pr=pr, changed_by=user)
            return pr

        pr = PromoRequest.objects.create(
            requester=user,
            status=PromoRequestStatus.NEW,
            ops_status=PromoOpsStatus.NEW,
            **validated_data,
        )
        _sync_promo_to_unified(pr=pr, changed_by=user)
        return pr


class PromoRequestDetailSerializer(serializers.ModelSerializer):
    assets = PromoAssetSerializer(many=True, read_only=True)
    items = PromoRequestItemDetailSerializer(many=True, read_only=True)
    invoice_total = serializers.SerializerMethodField()
    invoice_vat = serializers.SerializerMethodField()

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
            "target_provider",
            "target_portfolio_item",
            "message_title",
            "message_body",
            "redirect_url",
            "status",
            "ops_status",
            "subtotal",
            "total_days",
            "quote_note",
            "reject_reason",
            "invoice",
            "invoice_total",
            "invoice_vat",
            "reviewed_at",
            "activated_at",
            "ops_started_at",
            "ops_completed_at",
            "created_at",
            "updated_at",
            "items",
            "assets",
        ]

    def get_invoice_total(self, obj: PromoRequest):
        return getattr(getattr(obj, "invoice", None), "total", None)

    def get_invoice_vat(self, obj: PromoRequest):
        return getattr(getattr(obj, "invoice", None), "vat_amount", None)


class PromoActivePlacementSerializer(serializers.Serializer):
    id = serializers.IntegerField(read_only=True)
    request_id = serializers.IntegerField(read_only=True)
    item_id = serializers.IntegerField(read_only=True, allow_null=True)
    code = serializers.CharField(read_only=True, allow_blank=True)
    title = serializers.CharField(read_only=True, allow_blank=True)
    ad_type = serializers.CharField(read_only=True, allow_blank=True)
    service_type = serializers.CharField(read_only=True, allow_blank=True)
    start_at = serializers.DateTimeField(read_only=True, allow_null=True)
    end_at = serializers.DateTimeField(read_only=True, allow_null=True)
    send_at = serializers.DateTimeField(read_only=True, allow_null=True)
    frequency = serializers.CharField(read_only=True, allow_blank=True)
    position = serializers.CharField(read_only=True, allow_blank=True)
    search_scope = serializers.CharField(read_only=True, allow_blank=True)
    search_position = serializers.CharField(read_only=True, allow_blank=True)
    target_category = serializers.CharField(read_only=True, allow_blank=True)
    target_city = serializers.CharField(read_only=True, allow_blank=True)
    redirect_url = serializers.CharField(read_only=True, allow_blank=True)
    message_title = serializers.CharField(read_only=True, allow_blank=True)
    message_body = serializers.CharField(read_only=True, allow_blank=True)
    sponsor_name = serializers.CharField(read_only=True, allow_blank=True)
    sponsor_url = serializers.CharField(read_only=True, allow_blank=True)
    sponsorship_months = serializers.IntegerField(read_only=True)
    attachment_specs = serializers.CharField(read_only=True, allow_blank=True)
    assets = PromoHomeBannerAssetSerializer(many=True, read_only=True)
    target_provider_id = serializers.IntegerField(source="target_provider.id", read_only=True)
    target_provider_display_name = serializers.CharField(source="target_provider.display_name", read_only=True)
    target_provider_profile_image = serializers.FileField(source="target_provider.profile_image", read_only=True)
    target_provider_city = serializers.CharField(source="target_provider.city", read_only=True)
    target_provider_type = serializers.CharField(source="target_provider.provider_type", read_only=True)
    target_portfolio_item_id = serializers.IntegerField(source="target_portfolio_item.id", read_only=True)
    target_portfolio_item_file = serializers.FileField(source="target_portfolio_item.file", read_only=True)
    target_portfolio_item_file_type = serializers.CharField(source="target_portfolio_item.file_type", read_only=True)
    portfolio_item = serializers.SerializerMethodField()

    def get_portfolio_item(self, obj):
        if not isinstance(obj, dict):
            return None
        target_item = obj.get("target_portfolio_item")
        if target_item is None and obj.get("service_type") == PromoServiceType.PORTFOLIO_SHOWCASE:
            target_provider = obj.get("target_provider")
            if target_provider is not None:
                target_item = (
                    ProviderPortfolioItem.objects.select_related("provider", "provider__user")
                    .filter(provider=target_provider)
                    .order_by("-created_at", "-id")
                    .first()
                )
        if target_item is None:
            return None
        return ProviderPortfolioItemSerializer(target_item, context=self.context).data

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if data.get("item_id") in ("", None):
            data["item_id"] = None
        return data


class PromoQuoteSerializer(serializers.Serializer):
    quote_note = serializers.CharField(required=False, allow_blank=True, max_length=300)


class PromoRejectSerializer(serializers.Serializer):
    reject_reason = serializers.CharField(required=True, max_length=300)


class HomeBannerSerializer(serializers.ModelSerializer):
    media_url = serializers.FileField(source="media_file", read_only=True)
    provider_id = serializers.SerializerMethodField()
    provider_display_name = serializers.SerializerMethodField()

    class Meta:
        model = HomeBanner
        fields = [
            "id",
            "title",
            "media_type",
            "media_url",
            "link_url",
            "provider_id",
            "provider_display_name",
            "display_order",
        ]

    def get_provider_id(self, obj) -> int:
        return int(obj.provider_id) if obj.provider_id else 0

    def get_provider_display_name(self, obj) -> str:
        if obj.provider and getattr(obj.provider, "display_name", None):
            return str(obj.provider.display_name)
        return ""
