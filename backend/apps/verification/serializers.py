from __future__ import annotations

from rest_framework import serializers

from .models import (
    VerificationRequest, VerificationDocument,
    VerificationStatus, VerificationBadgeType,
    VerificationRequirement, VerificationRequirementAttachment,
)


class VerificationRequirementAttachmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = VerificationRequirementAttachment
        fields = [
            "id",
            "file",
            "uploaded_by",
            "uploaded_at",
        ]
        read_only_fields = ["uploaded_by", "uploaded_at"]


class VerificationRequirementSerializer(serializers.ModelSerializer):
    attachments = VerificationRequirementAttachmentSerializer(many=True, read_only=True)

    class Meta:
        model = VerificationRequirement
        fields = [
            "id",
            "badge_type",
            "code",
            "title",
            "is_approved",
            "decision_note",
            "decided_by",
            "decided_at",
            "attachments",
        ]


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
    requirements = serializers.ListField(
        child=serializers.DictField(),
        required=False,
        allow_empty=True,
        write_only=True,
    )

    class Meta:
        model = VerificationRequest
        fields = ["id", "code", "badge_type", "priority", "requirements"]
        read_only_fields = ["id", "code"]

    def validate_badge_type(self, v):
        if v in (None, ""):
            return None
        if v not in VerificationBadgeType.values:
            raise serializers.ValidationError("نوع الشارة غير صحيح.")
        return v

    def validate_requirements(self, value):
        # requirements is optional; when provided it must be a list of objects.
        if value in (None, ""):
            return []
        if not isinstance(value, list):
            raise serializers.ValidationError("requirements يجب أن تكون قائمة.")
        out = []
        for raw in value:
            if not isinstance(raw, dict):
                raise serializers.ValidationError("كل عنصر في requirements يجب أن يكون كائن.")
            badge_type = (raw.get("badge_type") or "").strip()
            code = (raw.get("code") or "").strip()
            if badge_type not in VerificationBadgeType.values:
                raise serializers.ValidationError("badge_type غير صحيح.")
            if not code:
                raise serializers.ValidationError("code مطلوب.")
            out.append({"badge_type": badge_type, "code": code})
        return out

    def create(self, validated_data):
        user = self.context["request"].user
        from .services import _sync_verification_to_unified
        from .services import resolve_requirement_def

        requirements = validated_data.pop("requirements", []) or []

        badge_type = validated_data.get("badge_type")

        # Legacy flow: badge_type only -> create a single default requirement.
        if not requirements:
            if badge_type not in VerificationBadgeType.values:
                raise serializers.ValidationError("badge_type مطلوب أو قم بإرسال requirements.")
            requirements = [{"badge_type": badge_type, "code": "B1" if badge_type == "blue" else "G1"}]

        # Prevent multiple active/pending requests for the same badge type.
        # (Mixed requests are also blocked if they include a badge type that already has a pending request.)
        for bt in {r["badge_type"] for r in requirements}:
            exists = VerificationRequest.objects.filter(
                requester=user,
                badge_type=bt,
                status__in=[
                    VerificationStatus.NEW,
                    VerificationStatus.IN_REVIEW,
                    VerificationStatus.PENDING_PAYMENT,
                    VerificationStatus.ACTIVE,
                ],
            ).exists()
            if exists:
                raise serializers.ValidationError("يوجد طلب توثيق قائم لنفس نوع الشارة.")

        # For backward compatibility, store badge_type if request is single-type; otherwise keep it null.
        badge_types = {r["badge_type"] for r in requirements}
        if len(badge_types) == 1:
            validated_data["badge_type"] = next(iter(badge_types))
        else:
            validated_data["badge_type"] = None

        vr = VerificationRequest.objects.create(requester=user, **validated_data)
        # Create requirements.
        for idx, r in enumerate(requirements):
            definition = resolve_requirement_def(r["badge_type"], r["code"])
            VerificationRequirement.objects.create(
                request=vr,
                badge_type=r["badge_type"],
                code=definition["code"],
                title=definition["title"],
                sort_order=idx,
            )

        _sync_verification_to_unified(vr=vr, changed_by=user)
        return vr


class VerificationRequestDetailSerializer(serializers.ModelSerializer):
    documents = VerificationDocumentSerializer(many=True, read_only=True)
    requirements = VerificationRequirementSerializer(many=True, read_only=True)

    invoice_summary = serializers.SerializerMethodField()

    class Meta:
        model = VerificationRequest
        fields = [
            "id", "code",
            "badge_type",
            "priority",
            "status",
            "admin_note", "reject_reason",
            "invoice",
            "invoice_summary",
            "requested_at", "reviewed_at", "approved_at",
            "activated_at", "expires_at",
            "documents",
            "requirements",
        ]

    def get_invoice_summary(self, obj: VerificationRequest):
        inv = getattr(obj, "invoice", None)
        if not inv:
            return None
        lines = []
        if hasattr(inv, "lines"):
            cached_lines = getattr(inv, "_prefetched_objects_cache", {}).get("lines")
            iterable = cached_lines if cached_lines is not None else inv.lines.all().order_by("sort_order", "id")
            for li in iterable:
                lines.append(
                    {
                        "id": li.id,
                        "item_code": li.item_code,
                        "title": li.title,
                        "amount": str(li.amount),
                    }
                )
        return {
            "id": inv.id,
            "code": inv.code,
            "status": inv.status,
            "currency": inv.currency,
            "subtotal": str(inv.subtotal),
            "vat_percent": str(inv.vat_percent),
            "vat_amount": str(inv.vat_amount),
            "total": str(inv.total),
            "lines": lines,
        }


class VerificationDocDecisionSerializer(serializers.Serializer):
    is_approved = serializers.BooleanField(required=True)
    decision_note = serializers.CharField(required=False, allow_blank=True, max_length=300)


class VerificationRequirementDecisionSerializer(serializers.Serializer):
    is_approved = serializers.BooleanField(required=True)
    decision_note = serializers.CharField(required=False, allow_blank=True, max_length=300)
