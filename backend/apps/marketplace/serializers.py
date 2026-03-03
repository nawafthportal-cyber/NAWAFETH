from rest_framework import serializers

from .models import Offer, RequestStatusLog, ServiceRequest, ServiceRequestAttachment
from apps.providers.models import ProviderCategory, ProviderProfile


class ServiceRequestCreateSerializer(serializers.ModelSerializer):
    city = serializers.CharField(required=False, allow_blank=True)
    dispatch_mode = serializers.ChoiceField(
        choices=("all", "nearest"),
        required=False,
        write_only=True,
    )
    provider = serializers.PrimaryKeyRelatedField(
        queryset=ProviderProfile.objects.all(),
        required=False,
        allow_null=True,
    )
    images = serializers.ListField(
        child=serializers.FileField(), required=False, write_only=True
    )
    videos = serializers.ListField(
        child=serializers.FileField(), required=False, write_only=True
    )
    files = serializers.ListField(
        child=serializers.FileField(), required=False, write_only=True
    )
    audio = serializers.FileField(required=False, write_only=True)
    quote_deadline = serializers.DateField(required=False, allow_null=True)

    class Meta:
        model = ServiceRequest
        fields = (
            "id",
            "provider",
            "subcategory",
            "title",
            "description",
            "request_type",
            "city",
            "dispatch_mode",
            "images",
            "videos",
            "files",
            "audio",
            "quote_deadline",
        )

    def validate_request_type(self, value):
        if value not in ("normal", "competitive", "urgent"):
            raise serializers.ValidationError("نوع الطلب غير صحيح")
        return value

    def validate(self, attrs):
        provider = attrs.get("provider")
        request_type = attrs.get("request_type")
        city = (attrs.get("city") or "").strip()
        dispatch_mode = (attrs.get("dispatch_mode") or "all").strip().lower()
        subcategory = attrs.get("subcategory")
        attrs["city"] = city

        # City rules:
        # - urgent + nearest: required
        # - urgent + all: optional
        # - normal/competitive: optional
        city_required = request_type == "urgent" and dispatch_mode == "nearest"
        if city_required and not city:
            raise serializers.ValidationError({"city": "المدينة مطلوبة"})

        # Competitive/Urgent requests are broadcast to matching providers.
        # They must NOT be targeted to a single provider.
        if request_type in ("competitive", "urgent") and provider is not None:
            raise serializers.ValidationError({
                "provider": "هذا النوع من الطلبات لا يدعم تحديد مزود خدمة."
            })

        if request_type == "normal" and provider is None:
            raise serializers.ValidationError({
                "provider": "طلب عادي يتطلب تحديد مزود خدمة"
            })

        if request_type == "normal" and provider is not None:
            # Ensure provider is eligible for this request (same city + same subcategory)
            if city and (getattr(provider, "city", None) or "").strip() and provider.city.strip() != city:
                raise serializers.ValidationError({
                    "city": "مدينة الطلب لا تطابق مدينة مزود الخدمة"
                })
            if subcategory is not None and not ProviderCategory.objects.filter(
                provider=provider, subcategory=subcategory
            ).exists():
                raise serializers.ValidationError({
                    "subcategory": "مزود الخدمة لا يدعم هذا التصنيف"
                })

        return attrs

    def create(self, validated_data):
        # Currently used as a routing hint for urgent requests.
        # Matching strategy is still controlled by server rules.
        validated_data.pop("dispatch_mode", None)

        images = validated_data.pop("images", [])
        videos = validated_data.pop("videos", [])
        files = validated_data.pop("files", [])
        audio = validated_data.pop("audio", None)

        request = super().create(validated_data)

        # Save attachments
        attachments = []
        for img in images:
            attachments.append(
                ServiceRequestAttachment(
                    request=request, file=img, file_type="image"
                )
            )
        for vid in videos:
            attachments.append(
                ServiceRequestAttachment(
                    request=request, file=vid, file_type="video"
                )
            )
        for f in files:
            attachments.append(
                ServiceRequestAttachment(
                    request=request, file=f, file_type="document"
                )
            )
        if audio:
            attachments.append(
                ServiceRequestAttachment(
                    request=request, file=audio, file_type="audio"
                )
            )

        if attachments:
            ServiceRequestAttachment.objects.bulk_create(attachments)

        return request


class UrgentRequestAcceptSerializer(serializers.Serializer):
    request_id = serializers.IntegerField()


class ServiceRequestListSerializer(serializers.ModelSerializer):
    client_id = serializers.IntegerField(source="client.id", read_only=True)
    subcategory_name = serializers.CharField(source="subcategory.name", read_only=True)
    category_name = serializers.CharField(source="subcategory.category.name", read_only=True)
    client_phone = serializers.CharField(source="client.phone", read_only=True)
    client_name = serializers.SerializerMethodField()
    provider_name = serializers.CharField(source="provider.display_name", read_only=True)
    provider_phone = serializers.CharField(source="provider.user.phone", read_only=True)
    status_group = serializers.SerializerMethodField()
    status_label = serializers.SerializerMethodField()
    review_id = serializers.SerializerMethodField()
    review_rating = serializers.SerializerMethodField()
    review_response_speed = serializers.SerializerMethodField()
    review_cost_value = serializers.SerializerMethodField()
    review_quality = serializers.SerializerMethodField()
    review_credibility = serializers.SerializerMethodField()
    review_on_time = serializers.SerializerMethodField()
    review_comment = serializers.SerializerMethodField()

    def _status_group_value(self, raw: str) -> str:
        s = (raw or "").strip().lower()
        if s == "new":
            return "new"
        if s == "in_progress":
            return "in_progress"
        if s == "completed":
            return "completed"
        if s in ("cancelled", "canceled"):
            return "cancelled"
        return "new"

    def get_status_group(self, obj):
        return self._status_group_value(getattr(obj, "status", ""))

    def get_status_label(self, obj):
        group = self.get_status_group(obj)
        return {
            "new": "جديد",
            "in_progress": "تحت التنفيذ",
            "completed": "مكتمل",
            "cancelled": "ملغي",
        }.get(group, "جديد")

    def get_client_name(self, obj):
        first = (getattr(obj.client, "first_name", "") or "").strip()
        last = (getattr(obj.client, "last_name", "") or "").strip()
        name = f"{first} {last}".strip()
        return name or "-"

    def _review_attr(self, obj, attr):
        try:
            review = getattr(obj, "review", None)
        except Exception:
            review = None
        if not review:
            return None
        return getattr(review, attr, None)

    def get_review_id(self, obj):
        return self._review_attr(obj, "id")

    def get_review_rating(self, obj):
        return self._review_attr(obj, "rating")

    def get_review_response_speed(self, obj):
        return self._review_attr(obj, "response_speed")

    def get_review_cost_value(self, obj):
        return self._review_attr(obj, "cost_value")

    def get_review_quality(self, obj):
        return self._review_attr(obj, "quality")

    def get_review_credibility(self, obj):
        return self._review_attr(obj, "credibility")

    def get_review_on_time(self, obj):
        return self._review_attr(obj, "on_time")

    def get_review_comment(self, obj):
        return self._review_attr(obj, "comment")

    class Meta:
        model = ServiceRequest
        fields = (
            "id",
            "client_id",
            "title",
            "description",
            "request_type",
            "status",
            "status_group",
            "status_label",
            "city",
            "created_at",
            "provider",
            "provider_name",
            "provider_phone",
            "quote_deadline",
            "expected_delivery_at",
            "estimated_service_amount",
            "received_amount",
            "remaining_amount",
            "delivered_at",
            "actual_service_amount",
            "canceled_at",
            "cancel_reason",
            "provider_inputs_approved",
            "provider_inputs_decided_at",
            "provider_inputs_decision_note",
            "review_id",
            "review_rating",
            "review_response_speed",
            "review_cost_value",
            "review_quality",
            "review_credibility",
            "review_on_time",
            "review_comment",
            "subcategory",
            "subcategory_name",
            "category_name",
            "client_name",
            "client_phone",
        )


class OfferCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = Offer
        fields = ("id", "price", "duration_days", "note")


class OfferListSerializer(serializers.ModelSerializer):
    provider_name = serializers.CharField(source="provider.display_name", read_only=True)

    class Meta:
        model = Offer
        fields = (
            "id",
            "provider",
            "provider_name",
            "price",
            "duration_days",
            "note",
            "status",
            "created_at",
        )


class RequestActionSerializer(serializers.Serializer):
    note = serializers.CharField(max_length=255, required=False, allow_blank=True)


class ClientRequestUpdateSerializer(serializers.Serializer):
    title = serializers.CharField(max_length=50, required=False, allow_blank=False)
    description = serializers.CharField(max_length=500, required=False, allow_blank=False)

    def validate(self, attrs):
        if "title" not in attrs and "description" not in attrs:
            raise serializers.ValidationError("لا توجد حقول للتحديث")
        return attrs


class RequestStartSerializer(RequestActionSerializer):
    expected_delivery_at = serializers.DateTimeField(required=True)
    estimated_service_amount = serializers.DecimalField(max_digits=12, decimal_places=2, required=True)
    received_amount = serializers.DecimalField(max_digits=12, decimal_places=2, required=True)

    def validate(self, attrs):
        estimated = attrs.get("estimated_service_amount")
        received = attrs.get("received_amount")
        if estimated is not None and estimated < 0:
            raise serializers.ValidationError({"estimated_service_amount": "القيمة يجب أن تكون موجبة"})
        if received is not None and received < 0:
            raise serializers.ValidationError({"received_amount": "القيمة يجب أن تكون موجبة"})
        if estimated is not None and received is not None and received > estimated:
            raise serializers.ValidationError({"received_amount": "المبلغ المستلم لا يمكن أن يكون أكبر من القيمة المقدرة"})
        if estimated is not None and received is not None:
            attrs["remaining_amount"] = estimated - received
        return attrs


class ProviderInputsDecisionSerializer(RequestActionSerializer):
    approved = serializers.BooleanField(required=True)

    def validate(self, attrs):
        approved = attrs.get("approved")
        note = (attrs.get("note") or "").strip()
        if approved is False and not note:
            raise serializers.ValidationError({"note": "سبب الرفض مطلوب"})
        return attrs


class RequestCompleteSerializer(RequestActionSerializer):
    delivered_at = serializers.DateTimeField(required=True)
    actual_service_amount = serializers.DecimalField(max_digits=12, decimal_places=2, required=True)
    attachments = serializers.ListField(
        child=serializers.FileField(),
        required=False,
        write_only=True,
    )

    def validate(self, attrs):
        amount = attrs.get("actual_service_amount")
        if amount is not None and amount < 0:
            raise serializers.ValidationError({"actual_service_amount": "القيمة يجب أن تكون موجبة"})
        return attrs


class ProviderRejectSerializer(RequestActionSerializer):
    canceled_at = serializers.DateTimeField(required=True)
    cancel_reason = serializers.CharField(max_length=255, required=True, allow_blank=False)

class ProviderProgressUpdateSerializer(RequestActionSerializer):
    expected_delivery_at = serializers.DateTimeField(required=False)
    estimated_service_amount = serializers.DecimalField(
        max_digits=12,
        decimal_places=2,
        required=False,
    )
    received_amount = serializers.DecimalField(
        max_digits=12,
        decimal_places=2,
        required=False,
    )

    def validate(self, attrs):
        note = (attrs.get("note") or "").strip()
        has_expected = "expected_delivery_at" in attrs
        has_estimated = "estimated_service_amount" in attrs
        has_received = "received_amount" in attrs

        if has_estimated != has_received:
            raise serializers.ValidationError(
                {
                    "received_amount": "يلزم إرسال القيمة المقدرة والمبلغ المستلم معًا",
                }
            )

        if has_estimated:
            estimated = attrs.get("estimated_service_amount")
            received = attrs.get("received_amount")
            if estimated is not None and estimated < 0:
                raise serializers.ValidationError(
                    {"estimated_service_amount": "القيمة يجب أن تكون موجبة"}
                )
            if received is not None and received < 0:
                raise serializers.ValidationError(
                    {"received_amount": "القيمة يجب أن تكون موجبة"}
                )
            if (
                estimated is not None
                and received is not None
                and received > estimated
            ):
                raise serializers.ValidationError(
                    {
                        "received_amount": "المبلغ المستلم لا يمكن أن يكون أكبر من القيمة المقدرة",
                    }
                )
            attrs["remaining_amount"] = estimated - received

        if not note and not has_expected and not has_estimated:
            raise serializers.ValidationError(
                {"note": "أدخل ملاحظة أو حدّث بيانات التنفيذ"}
            )
        return attrs


class ServiceRequestAttachmentSerializer(serializers.ModelSerializer):
    file_url = serializers.SerializerMethodField()

    class Meta:
        model = ServiceRequestAttachment
        fields = ("id", "file_type", "file_url", "created_at")

    def get_file_url(self, obj):
        request = self.context.get("request")
        try:
            url = obj.file.url
        except Exception:
            return ""
        if request:
            return request.build_absolute_uri(url)
        return url


class RequestStatusLogSerializer(serializers.ModelSerializer):
    actor_name = serializers.SerializerMethodField()

    class Meta:
        model = RequestStatusLog
        fields = ("id", "from_status", "to_status", "note", "created_at", "actor_name")

    def get_actor_name(self, obj):
        actor = getattr(obj, "actor", None)
        if not actor:
            return "-"
        full = f"{(getattr(actor, 'first_name', '') or '').strip()} {(getattr(actor, 'last_name', '') or '').strip()}".strip()
        if full:
            return full
        username = (getattr(actor, "username", "") or "").strip()
        if username:
            return username
        phone = (getattr(actor, "phone", "") or "").strip()
        return phone or "-"


class ProviderRequestDetailSerializer(ServiceRequestListSerializer):
    attachments = ServiceRequestAttachmentSerializer(many=True, read_only=True)
    status_logs = RequestStatusLogSerializer(many=True, read_only=True)

    class Meta(ServiceRequestListSerializer.Meta):
        fields = ServiceRequestListSerializer.Meta.fields + (
            "attachments",
            "status_logs",
        )
