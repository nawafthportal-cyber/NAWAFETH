from __future__ import annotations

from rest_framework import serializers

from .models import (
    ModerationActionLog,
    ModerationCase,
    ModerationDecision,
    ModerationDecisionCode,
    ModerationSeverity,
    ModerationStatus,
)


class ModerationCaseCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = ModerationCase
        fields = [
            "source_app",
            "source_model",
            "source_object_id",
            "source_label",
            "reported_user",
            "category",
            "reason",
            "details",
            "summary",
            "severity",
            "snapshot",
            "meta",
        ]

    def validate_reason(self, value):
        value = (value or "").strip()
        if not value:
            raise serializers.ValidationError("reason مطلوب")
        return value[:120]

    def validate_severity(self, value):
        if value not in {choice[0] for choice in ModerationSeverity.choices}:
            raise serializers.ValidationError("severity غير صالحة")
        return value


class ModerationActionLogSerializer(serializers.ModelSerializer):
    created_by_phone = serializers.CharField(source="created_by.phone", read_only=True)

    class Meta:
        model = ModerationActionLog
        fields = [
            "id",
            "action_type",
            "from_status",
            "to_status",
            "note",
            "payload",
            "created_by",
            "created_by_phone",
            "created_at",
        ]


class ModerationDecisionSerializer(serializers.ModelSerializer):
    applied_by_phone = serializers.CharField(source="applied_by.phone", read_only=True)

    class Meta:
        model = ModerationDecision
        fields = [
            "id",
            "decision_code",
            "note",
            "outcome",
            "is_final",
            "applied_by",
            "applied_by_phone",
            "applied_at",
            "created_at",
        ]


class ModerationCaseListSerializer(serializers.ModelSerializer):
    reporter_phone = serializers.CharField(source="reporter.phone", read_only=True)
    reported_user_phone = serializers.CharField(source="reported_user.phone", read_only=True)
    assigned_to_phone = serializers.CharField(source="assigned_to.phone", read_only=True)

    class Meta:
        model = ModerationCase
        fields = [
            "id",
            "code",
            "status",
            "severity",
            "source_app",
            "source_model",
            "source_object_id",
            "source_label",
            "category",
            "reason",
            "summary",
            "reporter",
            "reporter_phone",
            "reported_user",
            "reported_user_phone",
            "assigned_team_code",
            "assigned_team_name",
            "assigned_to",
            "assigned_to_phone",
            "sla_due_at",
            "created_at",
            "updated_at",
        ]


class ModerationCaseDetailSerializer(ModerationCaseListSerializer):
    action_logs = ModerationActionLogSerializer(many=True, read_only=True)
    decisions = ModerationDecisionSerializer(many=True, read_only=True)

    class Meta(ModerationCaseListSerializer.Meta):
        fields = ModerationCaseListSerializer.Meta.fields + [
            "details",
            "snapshot",
            "meta",
            "linked_support_ticket_id",
            "linked_support_ticket_code",
            "closed_at",
            "action_logs",
            "decisions",
        ]


class ModerationCaseAssignSerializer(serializers.Serializer):
    assigned_team_code = serializers.CharField(max_length=50, required=False, allow_blank=True)
    assigned_team_name = serializers.CharField(max_length=120, required=False, allow_blank=True)
    assigned_to = serializers.IntegerField(required=False, allow_null=True)
    note = serializers.CharField(max_length=500, required=False, allow_blank=True)


class ModerationCaseStatusSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=ModerationStatus.choices)
    note = serializers.CharField(max_length=500, required=False, allow_blank=True)


class ModerationCaseDecisionWriteSerializer(serializers.Serializer):
    decision_code = serializers.ChoiceField(choices=ModerationDecisionCode.choices)
    note = serializers.CharField(max_length=500, required=False, allow_blank=True)
    is_final = serializers.BooleanField(required=False, default=True)
    outcome = serializers.JSONField(required=False)
