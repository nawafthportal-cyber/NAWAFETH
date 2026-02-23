from __future__ import annotations

from django.conf import settings
from rest_framework import serializers

from .models import (
    VerificationRequest, VerificationDocument,
    VerificationStatus, VerificationBadgeType
)


class VerificationDocumentSerializer(serializers.ModelSerializer):
    class Meta:
        model = VerificationDocument
        fields = [
            "id", "doc_type", "title", "file",
            "is_approved", "decision_note", "decided_by", "decided_at",
            "uploaded_by", "uploaded_at",
        ]
        read_only_fields = ["is_approved", "decision_note", "decided_by", "decided_at", "uploaded_by", "uploaded_at"]


class VerificationRequestCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = VerificationRequest
        fields = ["id", "code", "badge_type"]
        read_only_fields = ["id", "code"]

    def validate_badge_type(self, v):
        if v not in VerificationBadgeType.values:
            raise serializers.ValidationError("نوع الشارة غير صحيح.")
        return v

    def create(self, validated_data):
        user = self.context["request"].user
        from .services import _sync_verification_to_unified

        from apps.features.checks import has_feature

        # قفل حسب الباقة/الميزات
        if validated_data["badge_type"] == VerificationBadgeType.BLUE:
            if not has_feature(user, "verify_blue"):
                raise serializers.ValidationError("توثيق الشارة الزرقاء غير متاح في باقتك الحالية.")
        else:
            if not has_feature(user, "verify_green"):
                raise serializers.ValidationError("توثيق الشارة الخضراء غير متاح في باقتك الحالية.")

        # منع إنشاء طلب جديد إذا لديه طلب pending/active لنفس الشارة
        exists = VerificationRequest.objects.filter(
            requester=user,
            badge_type=validated_data["badge_type"],
            status__in=[VerificationStatus.NEW, VerificationStatus.IN_REVIEW, VerificationStatus.PENDING_PAYMENT, VerificationStatus.ACTIVE],
        ).exists()
        if exists:
            raise serializers.ValidationError("يوجد طلب توثيق قائم لنفس نوع الشارة.")

        vr = VerificationRequest.objects.create(requester=user, **validated_data)
        _sync_verification_to_unified(vr=vr, changed_by=user)
        return vr


class VerificationRequestDetailSerializer(serializers.ModelSerializer):
    documents = VerificationDocumentSerializer(many=True, read_only=True)

    class Meta:
        model = VerificationRequest
        fields = [
            "id", "code",
            "badge_type",
            "status",
            "admin_note", "reject_reason",
            "invoice",
            "requested_at", "reviewed_at", "approved_at",
            "activated_at", "expires_at",
            "documents",
        ]


class VerificationDocDecisionSerializer(serializers.Serializer):
    is_approved = serializers.BooleanField(required=True)
    decision_note = serializers.CharField(required=False, allow_blank=True, max_length=300)
