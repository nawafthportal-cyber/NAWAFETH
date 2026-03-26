from datetime import timedelta

from django.utils import timezone
from rest_framework import serializers

from apps.marketplace.models import ServiceRequest, RequestStatus

from .models import Review


class ReviewCreateSerializer(serializers.ModelSerializer):
    # NOTE: Rating is derived from the detailed criteria.
    # We accept an optional client-provided rating for backwards compatibility,
    # but we will compute/override it from criteria.
    rating = serializers.IntegerField(required=False, allow_null=True)

    response_speed = serializers.IntegerField(required=True)
    cost_value = serializers.IntegerField(required=True)
    quality = serializers.IntegerField(required=True)
    credibility = serializers.IntegerField(required=True)
    on_time = serializers.IntegerField(required=True)

    class Meta:
        model = Review
        fields = (
            "rating",
            "response_speed",
            "cost_value",
            "quality",
            "credibility",
            "on_time",
            "comment",
        )

    def _validate_criteria(self, attrs):
        keys = [
            "response_speed",
            "cost_value",
            "quality",
            "credibility",
            "on_time",
        ]
        present = {k: attrs.get(k, None) for k in keys}

        missing = [k for k, v in present.items() if v is None]
        if missing:
            raise serializers.ValidationError({"detail": "حقول التقييم التفصيلية مطلوبة"})

        for k, v in present.items():
            if v < 1 or v > 5:
                raise serializers.ValidationError({k: "يجب أن يكون بين 1 و 5"})

    def validate_comment(self, value):
        value = (value or "").strip()
        if len(value) > 500:
            raise serializers.ValidationError("التعليق طويل جدًا")
        return value

    def validate(self, attrs):
        request_obj: ServiceRequest = self.context["service_request"]
        user = self.context["user"]

        # فقط مالك الطلب
        if request_obj.client_id != user.id:
            raise serializers.ValidationError({"detail": "غير مصرح"})

        # السماح بالتقييم في الحالات التشغيلية المعتمدة:
        # - مكتمل
        # - ملغي
        # - تحت التنفيذ بعد تجاوز الموعد المتوقع + 48 ساعة
        status = request_obj.status
        if status == RequestStatus.COMPLETED:
            pass
        elif status == RequestStatus.CANCELLED:
            pass
        elif status == RequestStatus.IN_PROGRESS:
            deadline = getattr(request_obj, "expected_delivery_at", None)
            if not deadline or timezone.now() < (deadline + timedelta(hours=48)):
                raise serializers.ValidationError(
                    {"detail": "لا يمكن التقييم إلا بعد تجاوز موعد التسليم المتوقع بـ 48 ساعة"}
                )
        else:
            raise serializers.ValidationError({"detail": "لا يمكن التقييم في حالة الطلب الحالية"})

        # لازم يكون فيه مزود معيّن
        if not request_obj.provider_id:
            raise serializers.ValidationError({"detail": "لا يوجد مزود لتقييمه"})

        # منع التكرار (OneToOne سيمنع، لكن نرجع رسالة واضحة)
        if hasattr(request_obj, "review"):
            raise serializers.ValidationError({"detail": "تم تقييم هذا الطلب مسبقًا"})

        # التقييم يعتمد على المحاور فقط
        self._validate_criteria(attrs)

        keys = [
            "response_speed",
            "cost_value",
            "quality",
            "credibility",
            "on_time",
        ]
        avg = sum(int(attrs[k]) for k in keys) / len(keys)
        attrs["rating"] = max(1, min(5, round(avg)))

        return attrs


class ReviewListSerializer(serializers.ModelSerializer):
    request_id = serializers.IntegerField(read_only=True)
    client_id = serializers.IntegerField(read_only=True)
    client_phone = serializers.CharField(source="client.phone", read_only=True)
    client_name = serializers.SerializerMethodField()
    provider_reply_is_edited = serializers.SerializerMethodField()

    class Meta:
        model = Review
        fields = (
            "id",
            "request_id",
            "client_id",
            "rating",
            "response_speed",
            "cost_value",
            "quality",
            "credibility",
            "on_time",
            "comment",
            "provider_liked",
            "provider_liked_at",
            "provider_reply",
            "provider_reply_at",
            "provider_reply_edited_at",
            "provider_reply_is_edited",
            "client_name",
            "client_phone",
            "created_at",
        )

    def get_client_name(self, obj):
        first = (getattr(obj.client, "first_name", "") or "").strip()
        last = (getattr(obj.client, "last_name", "") or "").strip()
        full = f"{first} {last}".strip()
        if full:
            return full
        username = (getattr(obj.client, "username", "") or "").strip()
        if username:
            return username
        return "عميل"

    def get_provider_reply_is_edited(self, obj):
        return bool(getattr(obj, "provider_reply_edited_at", None))


class ProviderReviewReplySerializer(serializers.Serializer):
    provider_reply = serializers.CharField(required=True, allow_blank=False, max_length=500)

    def validate_provider_reply(self, value):
        value = (value or "").strip()
        if not value:
            raise serializers.ValidationError("الرد مطلوب")
        if len(value) > 500:
            raise serializers.ValidationError("الرد طويل جدًا")
        return value


class ProviderRatingSummarySerializer(serializers.Serializer):
    provider_id = serializers.IntegerField()
    rating_avg = serializers.DecimalField(max_digits=3, decimal_places=2)
    rating_count = serializers.IntegerField()
    distribution = serializers.DictField(child=serializers.IntegerField(), required=False)

    response_speed_avg = serializers.DecimalField(
        max_digits=3, decimal_places=2, allow_null=True, required=False
    )
    cost_value_avg = serializers.DecimalField(
        max_digits=3, decimal_places=2, allow_null=True, required=False
    )
    quality_avg = serializers.DecimalField(
        max_digits=3, decimal_places=2, allow_null=True, required=False
    )
    credibility_avg = serializers.DecimalField(
        max_digits=3, decimal_places=2, allow_null=True, required=False
    )
    on_time_avg = serializers.DecimalField(
        max_digits=3, decimal_places=2, allow_null=True, required=False
    )
