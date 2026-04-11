from rest_framework import serializers

from .models import Offer, RequestStatusLog, ServiceRequest, ServiceRequestAttachment
from apps.providers.models import ProviderCategory, ProviderProfile, SubCategory
from apps.uploads.media_optimizer import optimize_upload_for_storage
from apps.uploads.validators import (
    ALL_SAFE_EXTENSIONS,
    ALL_SAFE_MIME_TYPES,
    AUDIO_EXTENSIONS,
    AUDIO_MIME_TYPES,
    DOCUMENT_EXTENSIONS,
    DOCUMENT_MIME_TYPES,
    IMAGE_EXTENSIONS,
    IMAGE_MIME_TYPES,
    VIDEO_EXTENSIONS,
    VIDEO_MIME_TYPES,
    validate_secure_upload,
)


class ServiceRequestCreateSerializer(serializers.ModelSerializer):
    subcategory = serializers.PrimaryKeyRelatedField(
        queryset=SubCategory.objects.filter(is_active=True),
        required=False,
    )
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
    subcategory_ids = serializers.ListField(
        child=serializers.IntegerField(min_value=1),
        required=False,
        write_only=True,
    )

    class Meta:
        model = ServiceRequest
        fields = (
            "id",
            "provider",
            "subcategory",
            "subcategory_ids",
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
        subcategory_ids = list(attrs.get("subcategory_ids") or [])
        attrs["city"] = city

        if subcategory is not None and subcategory.id not in subcategory_ids:
            subcategory_ids = [subcategory.id, *subcategory_ids]

        if not subcategory_ids and subcategory is not None:
            subcategory_ids = [subcategory.id]

        normalized_ids: list[int] = []
        for sub_id in subcategory_ids:
            if sub_id not in normalized_ids:
                normalized_ids.append(sub_id)

        if not normalized_ids:
            raise serializers.ValidationError({"subcategory": "الرجاء اختيار تصنيف فرعي واحد على الأقل"})

        active_subcategories = {
            row.id: row
            for row in SubCategory.objects.filter(id__in=normalized_ids, is_active=True)
        }
        invalid_ids = [sub_id for sub_id in normalized_ids if sub_id not in active_subcategories]
        if invalid_ids:
            raise serializers.ValidationError({"subcategory_ids": "توجد تصنيفات فرعية غير صالحة"})

        primary_subcategory = active_subcategories[normalized_ids[0]]
        attrs["subcategory"] = primary_subcategory
        attrs["_selected_subcategory_ids"] = normalized_ids

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
            if not ProviderCategory.objects.filter(
                provider=provider,
                subcategory_id__in=normalized_ids,
            ).exists():
                raise serializers.ValidationError({
                    "subcategory_ids": "مزود الخدمة لا يدعم أيًا من التصنيفات المختارة"
                })

        optimized_images = []
        for image in attrs.get("images") or []:
            validate_secure_upload(
                image,
                allowed_extensions=IMAGE_EXTENSIONS,
                allowed_mime_types=IMAGE_MIME_TYPES,
                max_size_mb=20,
                rename=True,
                rename_prefix="marketplace_image",
            )
            optimized_images.append(optimize_upload_for_storage(image, declared_type="image"))

        optimized_videos = []
        for video in attrs.get("videos") or []:
            validate_secure_upload(
                video,
                allowed_extensions=VIDEO_EXTENSIONS,
                allowed_mime_types=VIDEO_MIME_TYPES,
                max_size_mb=50,
                rename=True,
                rename_prefix="marketplace_video",
            )
            optimized_videos.append(optimize_upload_for_storage(video, declared_type="video"))

        for doc in attrs.get("files") or []:
            validate_secure_upload(
                doc,
                allowed_extensions=DOCUMENT_EXTENSIONS,
                allowed_mime_types=DOCUMENT_MIME_TYPES,
                max_size_mb=25,
                rename=True,
                rename_prefix="marketplace_file",
            )
        audio = attrs.get("audio")
        if audio is not None:
            validate_secure_upload(
                audio,
                allowed_extensions=AUDIO_EXTENSIONS,
                allowed_mime_types=AUDIO_MIME_TYPES,
                max_size_mb=20,
                rename=True,
                rename_prefix="marketplace_audio",
            )

        attrs["images"] = optimized_images
        attrs["videos"] = optimized_videos
        return attrs

    def create(self, validated_data):
        images = validated_data.pop("images", [])
        videos = validated_data.pop("videos", [])
        files = validated_data.pop("files", [])
        audio = validated_data.pop("audio", None)
        validated_data.pop("subcategory_ids", None)
        selected_subcategory_ids = list(validated_data.pop("_selected_subcategory_ids", []))

        request = super().create(validated_data)
        if selected_subcategory_ids:
            request.subcategories.set(selected_subcategory_ids)

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

        try:
            from apps.analytics.tracking import safe_track_event

            safe_track_event(
                event_name="marketplace.request_created",
                channel="server",
                surface="marketplace.service_request_create",
                source_app="marketplace",
                object_type="ServiceRequest",
                object_id=str(request.id),
                actor=getattr(request, "client", None),
                dedupe_key=f"marketplace.request_created:{request.id}",
                payload={
                    "request_type": request.request_type,
                    "provider_id": getattr(request, "provider_id", None),
                    "subcategory_id": getattr(request, "subcategory_id", None),
                    "city": request.city or "",
                },
            )
        except Exception:
            pass

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
    subcategory_ids = serializers.SerializerMethodField()
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

    def get_subcategory_ids(self, obj):
        try:
            return obj.selected_subcategory_ids()
        except Exception:
            if getattr(obj, "subcategory_id", None):
                return [obj.subcategory_id]
            return []

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
            "subcategory_ids",
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

        optimized_attachments = []
        for attachment in attrs.get("attachments") or []:
            validate_secure_upload(
                attachment,
                allowed_extensions=ALL_SAFE_EXTENSIONS,
                allowed_mime_types=ALL_SAFE_MIME_TYPES,
                max_size_mb=50,
                rename=True,
                rename_prefix="marketplace_complete",
            )
            optimized_attachments.append(optimize_upload_for_storage(attachment))
        attrs["attachments"] = optimized_attachments
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
