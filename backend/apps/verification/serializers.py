from __future__ import annotations

from rest_framework import serializers
from django.utils import timezone

from apps.features.support import support_priority
from apps.providers.eligibility import ProviderAccessError, ensure_provider_access
from apps.support.models import SupportTicket
from apps.support.models import SupportTicketType

from .models import (
    VerificationRequest, VerificationDocument,
    VerificationBadgeType,
    VerificationBlueProfile,
    VerificationBlueSubjectType,
    VerificationInquiryProfile,
    VerificationRequirement, VerificationRequirementAttachment,
)
from .services import REQUIREMENTS_CATALOG


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
    decision_status_label = serializers.SerializerMethodField()

    class Meta:
        model = VerificationRequirement
        fields = [
            "id",
            "badge_type",
            "code",
            "title",
            "is_approved",
            "decision_status_label",
            "decision_note",
            "evidence_expires_at",
            "decided_by",
            "decided_at",
            "attachments",
        ]

    def get_decision_status_label(self, obj: VerificationRequirement):
        if obj.is_approved is True:
            return "معتمد"
        if obj.is_approved is False:
            return "مرفوض"
        return "بانتظار المراجعة"


class VerificationDocumentSerializer(serializers.ModelSerializer):
    class Meta:
        model = VerificationDocument
        fields = [
            "id", "doc_type", "title", "file",
            "is_approved", "decision_note", "decided_by", "decided_at",
            "uploaded_by", "uploaded_at",
        ]
        read_only_fields = ["is_approved", "decision_note", "decided_by", "decided_at", "uploaded_by", "uploaded_at"]


class VerificationBlueProfileSerializer(serializers.ModelSerializer):
    subject_type_label = serializers.CharField(source="get_subject_type_display", read_only=True)
    official_number_label = serializers.SerializerMethodField()
    official_date_label = serializers.SerializerMethodField()
    verified_name_label = serializers.SerializerMethodField()

    class Meta:
        model = VerificationBlueProfile
        fields = [
            "subject_type",
            "subject_type_label",
            "official_number",
            "official_number_label",
            "official_date",
            "official_date_label",
            "verified_name",
            "verified_name_label",
            "is_name_approved",
            "verification_source",
            "verified_at",
            "updated_at",
        ]

    def get_official_number_label(self, obj: VerificationBlueProfile):
        if obj.subject_type == VerificationBlueSubjectType.BUSINESS:
            return "رقم السجل التجاري"
        return "رقم الهوية / الإقامة"

    def get_official_date_label(self, obj: VerificationBlueProfile):
        if obj.subject_type == VerificationBlueSubjectType.BUSINESS:
            return "تاريخه"
        return "تاريخ الميلاد"

    def get_verified_name_label(self, obj: VerificationBlueProfile):
        if obj.subject_type == VerificationBlueSubjectType.BUSINESS:
            return "اسم المنشأة"
        return "اسم العميل"


class VerificationBlueProfileInputSerializer(serializers.Serializer):
    subject_type = serializers.ChoiceField(choices=VerificationBlueSubjectType.choices)
    official_number = serializers.CharField(max_length=32)
    official_date = serializers.DateField(input_formats=["%Y-%m-%d", "%d/%m/%Y"])
    verified_name = serializers.CharField(max_length=180)
    is_name_approved = serializers.BooleanField()

    def validate_official_number(self, value):
        normalized = "".join(ch for ch in str(value or "").strip() if ch.isdigit())
        if len(normalized) < 6:
            raise serializers.ValidationError("رقم الإثبات غير صالح.")
        return normalized[:32]

    def validate_verified_name(self, value):
        normalized = str(value or "").strip()
        if not normalized:
            raise serializers.ValidationError("الاسم المسترجع مطلوب.")
        return normalized[:180]

    def validate(self, attrs):
        if not attrs.get("is_name_approved"):
            raise serializers.ValidationError("يجب اعتماد الاسم المسترجع قبل إرسال طلب الشارة الزرقاء.")
        return attrs


class VerificationBluePreviewSerializer(serializers.Serializer):
    subject_type = serializers.ChoiceField(choices=VerificationBlueSubjectType.choices)
    official_number = serializers.CharField(max_length=32)
    official_date = serializers.DateField(input_formats=["%Y-%m-%d", "%d/%m/%Y"])

    def validate_official_number(self, value):
        normalized = "".join(ch for ch in str(value or "").strip() if ch.isdigit())
        if len(normalized) < 6:
            raise serializers.ValidationError("رقم الإثبات غير صالح.")
        return normalized[:32]


def _user_handle(user_obj) -> str:
    if not user_obj:
        return "غير محدد"
    label = (getattr(user_obj, "username", "") or getattr(user_obj, "phone", "") or f"user-{user_obj.id}").strip()
    if label and not label.startswith("@"):
        label = f"@{label}"
    return label or "غير محدد"


def _verification_priority_number_for_user(user) -> int:
    priority_code = support_priority(user)
    mapping = {
        "low": 1,
        "normal": 2,
        "high": 3,
    }
    return int(mapping.get(priority_code, 2))


class VerificationRequestCreateSerializer(serializers.ModelSerializer):
    requirements = serializers.ListField(
        child=serializers.DictField(),
        required=False,
        allow_empty=True,
        write_only=True,
    )
    blue_profile = VerificationBlueProfileInputSerializer(required=False, write_only=True)

    class Meta:
        model = VerificationRequest
        fields = ["id", "code", "badge_type", "priority", "requirements", "blue_profile"]
        read_only_fields = ["id", "code", "priority"]

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
        seen = set()
        for raw in value:
            if not isinstance(raw, dict):
                raise serializers.ValidationError("كل عنصر في requirements يجب أن يكون كائن.")
            badge_type = (raw.get("badge_type") or "").strip()
            code = (raw.get("code") or "").strip().upper()
            if badge_type not in VerificationBadgeType.values:
                raise serializers.ValidationError("badge_type غير صحيح.")
            if not code:
                raise serializers.ValidationError("code مطلوب.")
            if code not in (REQUIREMENTS_CATALOG.get(badge_type) or {}):
                raise serializers.ValidationError("code غير صالح لنوع الشارة المحدد.")
            key = (badge_type, code)
            if key in seen:
                raise serializers.ValidationError("لا يمكن تكرار نفس بند التوثيق داخل الطلب الواحد.")
            seen.add(key)
            out.append({"badge_type": badge_type, "code": code})
        return out

    def validate(self, attrs):
        request = self.context.get("request")
        if request is not None:
            try:
                ensure_provider_access(request.user)
            except ProviderAccessError as exc:
                raise serializers.ValidationError({"detail": exc.detail, "code": exc.code})
        badge_type = attrs.get("badge_type")
        requirements = attrs.get("requirements") or []
        includes_blue = badge_type == VerificationBadgeType.BLUE or any(
            (item or {}).get("badge_type") == VerificationBadgeType.BLUE for item in requirements
        )
        blue_profile = attrs.get("blue_profile")
        if includes_blue and not blue_profile:
            raise serializers.ValidationError(
                {
                    "detail": "بيانات الشارة الزرقاء مطلوبة لأي طلب يتضمن بنود الشارة الزرقاء.",
                    "blue_profile": "بيانات الشارة الزرقاء مطلوبة لأي طلب يتضمن بنود الشارة الزرقاء.",
                    "code": "verification_blue_profile_required",
                }
            )
        if blue_profile:
            if not includes_blue:
                raise serializers.ValidationError(
                    {
                        "detail": "بيانات الشارة الزرقاء مرتبطة فقط بطلبات الشارة الزرقاء.",
                        "blue_profile": "بيانات الشارة الزرقاء مرتبطة فقط بطلبات الشارة الزرقاء.",
                        "code": "verification_blue_profile_unexpected",
                    }
                )
        return attrs

    def create(self, validated_data):
        user = self.context["request"].user
        from .services import (
            _sync_verification_to_unified,
            resolve_requirement_def,
            verification_request_blocking_open_request_for_badge,
        )

        requirements = validated_data.pop("requirements", []) or []
        blue_profile_data = validated_data.pop("blue_profile", None)
        validated_data.pop("priority", None)

        badge_type = validated_data.get("badge_type")

        # Legacy flow: badge_type only -> create a single default requirement.
        if not requirements:
            if badge_type not in VerificationBadgeType.values:
                raise serializers.ValidationError(
                    {
                        "detail": "نوع الشارة مطلوب أو قم بإرسال بنود التوثيق المطلوبة.",
                        "code": "verification_badge_type_required",
                    }
                )
            requirements = [{"badge_type": badge_type, "code": "B1" if badge_type == "blue" else "G1"}]

        # Prevent multiple active/pending requests for the same badge type.
        # (Mixed requests are also blocked if they include a badge type that already has a pending request.)
        for bt in {r["badge_type"] for r in requirements}:
            existing_request = verification_request_blocking_open_request_for_badge(user, bt)
            if existing_request is not None:
                raise serializers.ValidationError(
                    {
                        "detail": "يوجد طلب توثيق قائم لنفس نوع الشارة. أكمل الطلب الحالي قبل إنشاء طلب جديد.",
                        "code": "verification_request_exists",
                        "existing_request": {
                            "id": existing_request.id,
                            "code": existing_request.code,
                            "status": existing_request.status,
                            "status_label": existing_request.get_status_display(),
                            "badge_type": bt,
                        },
                    }
                )

        # For backward compatibility, store badge_type if request is single-type; otherwise keep it null.
        badge_types = {r["badge_type"] for r in requirements}
        if len(badge_types) == 1:
            validated_data["badge_type"] = next(iter(badge_types))
        else:
            validated_data["badge_type"] = None

        validated_data["priority"] = _verification_priority_number_for_user(user)
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

        if blue_profile_data:
            VerificationBlueProfile.objects.create(
                request=vr,
                subject_type=blue_profile_data["subject_type"],
                official_number=blue_profile_data["official_number"],
                official_date=blue_profile_data["official_date"],
                verified_name=blue_profile_data["verified_name"],
                is_name_approved=blue_profile_data["is_name_approved"],
                verification_source="elm",
                verified_at=timezone.now(),
            )

        _sync_verification_to_unified(vr=vr, changed_by=user)
        return vr


class VerificationRequestDetailSerializer(serializers.ModelSerializer):
    documents = VerificationDocumentSerializer(many=True, read_only=True)
    requirements = VerificationRequirementSerializer(many=True, read_only=True)
    blue_profile = VerificationBlueProfileSerializer(read_only=True)
    status_label = serializers.CharField(source="get_status_display", read_only=True)

    invoice_summary = serializers.SerializerMethodField()
    requester_id = serializers.IntegerField(source="requester.id", read_only=True)
    requester_name = serializers.SerializerMethodField()
    assigned_to_id = serializers.IntegerField(source="assigned_to.id", read_only=True)
    assigned_to_name = serializers.SerializerMethodField()
    badge_types = serializers.SerializerMethodField()
    badge_type_labels = serializers.SerializerMethodField()
    linked_inquiries = serializers.SerializerMethodField()

    class Meta:
        model = VerificationRequest
        fields = [
            "id", "code",
            "requester_id",
            "requester_name",
            "badge_type",
            "badge_types",
            "badge_type_labels",
            "priority",
            "status",
            "status_label",
            "admin_note", "reject_reason",
            "assigned_to_id",
            "assigned_to_name",
            "assigned_at",
            "invoice",
            "invoice_summary",
            "requested_at", "reviewed_at", "approved_at",
            "activated_at", "expires_at",
            "linked_inquiries",
            "blue_profile",
            "documents",
            "requirements",
        ]

    def get_requester_name(self, obj: VerificationRequest):
        return _user_handle(getattr(obj, "requester", None))

    def get_assigned_to_name(self, obj: VerificationRequest):
        assigned_to = getattr(obj, "assigned_to", None)
        return _user_handle(assigned_to) if assigned_to else "غير مكلف"

    def get_badge_types(self, obj: VerificationRequest):
        if obj.badge_type:
            return [obj.badge_type]
        values: list[str] = []
        seen: set[str] = set()
        for requirement in obj.requirements.all():
            badge_type = str(requirement.badge_type or "").strip()
            if badge_type and badge_type not in seen:
                seen.add(badge_type)
                values.append(badge_type)
        return values

    def get_badge_type_labels(self, obj: VerificationRequest):
        labels = dict(VerificationBadgeType.choices)
        return [labels.get(item, item) for item in self.get_badge_types(obj)]

    def get_linked_inquiries(self, obj: VerificationRequest):
        rows = []
        for profile in getattr(obj, "linked_inquiries", []).all() if hasattr(obj, "linked_inquiries") else []:
            ticket = getattr(profile, "ticket", None)
            if ticket is None:
                continue
            rows.append(
                {
                    "ticket_id": ticket.id,
                    "ticket_code": ticket.code or f"HD{ticket.id:06d}",
                }
            )
        return rows

    def get_invoice_summary(self, obj: VerificationRequest):
        inv = getattr(obj, "invoice", None)
        if not inv:
            return None
        from .services import verification_billing_policy

        pricing_policy = verification_billing_policy()
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
            "billing_cycle": pricing_policy["billing_cycle"],
            "billing_cycle_label": pricing_policy["billing_cycle_label"],
            "tax_policy": pricing_policy["tax_policy"],
            "tax_policy_label": pricing_policy["tax_policy_label"],
            "tax_included": pricing_policy["tax_included"],
            "additional_vat_percent": pricing_policy["additional_vat_percent"],
            "price_note": pricing_policy["price_note"],
            "subtotal": str(inv.subtotal),
            "vat_percent": str(inv.vat_percent),
            "vat_amount": str(inv.vat_amount),
            "total": str(inv.total),
            "lines": lines,
        }


class VerificationInquiryProfileSerializer(serializers.ModelSerializer):
    ticket_id = serializers.IntegerField(source="ticket.id", read_only=True)
    ticket_code = serializers.SerializerMethodField()
    linked_request_id = serializers.IntegerField(source="linked_request.id", read_only=True)
    linked_request_code = serializers.SerializerMethodField()

    class Meta:
        model = VerificationInquiryProfile
        fields = [
            "ticket_id",
            "ticket_code",
            "linked_request_id",
            "linked_request_code",
            "detailed_request_url",
            "operator_comment",
            "updated_at",
        ]

    def get_ticket_code(self, obj: VerificationInquiryProfile):
        ticket = getattr(obj, "ticket", None)
        if ticket is None:
            return ""
        return ticket.code or f"HD{ticket.id:06d}"

    def get_linked_request_code(self, obj: VerificationInquiryProfile):
        linked_request = getattr(obj, "linked_request", None)
        if linked_request is None:
            return ""
        return linked_request.code or f"AD{linked_request.id:06d}"


class BackofficeVerificationInquirySerializer(serializers.ModelSerializer):
    requester_name = serializers.SerializerMethodField()
    priority_number = serializers.SerializerMethodField()
    team_name = serializers.SerializerMethodField()
    assigned_to_name = serializers.SerializerMethodField()
    linked_request_id = serializers.SerializerMethodField()
    linked_request_code = serializers.SerializerMethodField()
    detailed_request_url = serializers.SerializerMethodField()
    operator_comment = serializers.SerializerMethodField()

    class Meta:
        model = SupportTicket
        fields = [
            "id",
            "code",
            "requester_name",
            "ticket_type",
            "priority",
            "priority_number",
            "status",
            "description",
            "created_at",
            "assigned_at",
            "team_name",
            "assigned_to",
            "assigned_to_name",
            "linked_request_id",
            "linked_request_code",
            "detailed_request_url",
            "operator_comment",
        ]

    def get_requester_name(self, obj: SupportTicket):
        return _user_handle(getattr(obj, "requester", None))

    def get_priority_number(self, obj: SupportTicket):
        mapping = {"low": 1, "normal": 2, "high": 3}
        return int(mapping.get(obj.priority, 1))

    def get_team_name(self, obj: SupportTicket):
        if obj.assigned_team:
            return obj.assigned_team.name_ar
        if obj.ticket_type == SupportTicketType.VERIFY:
            return "فريق التوثيق"
        return "غير محدد"

    def get_assigned_to_name(self, obj: SupportTicket):
        assigned_to = getattr(obj, "assigned_to", None)
        return _user_handle(assigned_to) if assigned_to else "غير مكلف"

    def _profile(self, obj: SupportTicket):
        return getattr(obj, "verification_profile", None)

    def get_linked_request_id(self, obj: SupportTicket):
        profile = self._profile(obj)
        return getattr(profile, "linked_request_id", None)

    def get_linked_request_code(self, obj: SupportTicket):
        profile = self._profile(obj)
        linked_request = getattr(profile, "linked_request", None)
        if linked_request is None:
            return ""
        return linked_request.code or f"AD{linked_request.id:06d}"

    def get_detailed_request_url(self, obj: SupportTicket):
        profile = self._profile(obj)
        return getattr(profile, "detailed_request_url", "") if profile else ""

    def get_operator_comment(self, obj: SupportTicket):
        profile = self._profile(obj)
        return getattr(profile, "operator_comment", "") if profile else ""


class VerifiedAccountRowSerializer(serializers.Serializer):
    badge_id = serializers.IntegerField()
    user_id = serializers.IntegerField()
    requester_name = serializers.CharField()
    verified_name = serializers.CharField()
    request_id = serializers.IntegerField()
    request_code = serializers.CharField(allow_blank=True)
    verification_code = serializers.CharField()
    verification_title = serializers.CharField(allow_blank=True)
    badge_type = serializers.CharField()
    badge_type_label = serializers.CharField()
    activated_at = serializers.DateTimeField(allow_null=True)
    expires_at = serializers.DateTimeField(allow_null=True)


class VerificationDocDecisionSerializer(serializers.Serializer):
    is_approved = serializers.BooleanField(required=True)
    decision_note = serializers.CharField(required=False, allow_blank=True, max_length=300)


class VerificationRequirementDecisionSerializer(serializers.Serializer):
    is_approved = serializers.BooleanField(required=True)
    decision_note = serializers.CharField(required=False, allow_blank=True, max_length=300)
    evidence_expires_at = serializers.DateTimeField(required=False, allow_null=True)
