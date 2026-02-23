from __future__ import annotations

from rest_framework import serializers

from .models import (
    SupportTicket, SupportAttachment, SupportComment,
    SupportTeam, SupportTicketStatus, SupportStatusLog
)


class SupportTeamSerializer(serializers.ModelSerializer):
    class Meta:
        model = SupportTeam
        fields = ["id", "code", "name_ar", "is_active", "sort_order"]


class SupportAttachmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = SupportAttachment
        fields = ["id", "file", "created_at", "uploaded_by"]


class SupportCommentSerializer(serializers.ModelSerializer):
    created_by_name = serializers.SerializerMethodField()

    class Meta:
        model = SupportComment
        fields = ["id", "text", "is_internal", "created_at", "created_by", "created_by_name"]
        read_only_fields = ["created_by", "created_at", "created_by_name"]

    def get_created_by_name(self, obj):
        u = obj.created_by
        if not u:
            return None
        return getattr(u, "name", None) or getattr(u, "phone", None) or str(u.pk)


class SupportStatusLogSerializer(serializers.ModelSerializer):
    class Meta:
        model = SupportStatusLog
        fields = ["id", "from_status", "to_status", "changed_by", "note", "created_at"]


class SupportTicketCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = SupportTicket
        fields = [
            "id",
            "code",
            "ticket_type",
            "description",
            "priority",
            "reported_kind",
            "reported_object_id",
            "reported_user",
        ]
        read_only_fields = ["id", "code"]

    def validate_description(self, value):
        value = (value or "").strip()
        if not value:
            raise serializers.ValidationError("الوصف مطلوب.")
        if len(value) > 300:
            raise serializers.ValidationError("الوصف يجب ألا يتجاوز 300 حرف.")
        return value

    def create(self, validated_data):
        user = self.context["request"].user
        from apps.features.support import support_priority
        from .services import _sync_ticket_to_unified

        # أولوية التذكرة حسب ميزة Priority Support
        validated_data.pop("priority", None)
        reported_kind = (validated_data.get("reported_kind") or "").strip()[:30]
        reported_object_id = (validated_data.get("reported_object_id") or "").strip()[:50]
        validated_data["reported_kind"] = reported_kind
        validated_data["reported_object_id"] = reported_object_id
        ticket = SupportTicket.objects.create(
            requester=user,
            priority=support_priority(user),
            **validated_data,
        )
        _sync_ticket_to_unified(ticket=ticket, changed_by=user)
        return ticket


class SupportTicketDetailSerializer(serializers.ModelSerializer):
    requester_name = serializers.SerializerMethodField()
    assigned_to_name = serializers.SerializerMethodField()
    assigned_team_obj = SupportTeamSerializer(source="assigned_team", read_only=True)

    attachments = SupportAttachmentSerializer(many=True, read_only=True)
    comments = SupportCommentSerializer(many=True, read_only=True)
    status_logs = SupportStatusLogSerializer(many=True, read_only=True)

    class Meta:
        model = SupportTicket
        fields = [
            "id", "code",
            "requester", "requester_name",
            "ticket_type", "status", "priority",
            "description",
            "reported_kind", "reported_object_id", "reported_user",
            "assigned_team", "assigned_team_obj",
            "assigned_to", "assigned_to_name",
            "assigned_at", "returned_at", "closed_at",
            "created_at", "updated_at",
            "attachments", "comments", "status_logs",
        ]

    def get_requester_name(self, obj):
        u = obj.requester
        return getattr(u, "name", None) or getattr(u, "phone", None) or str(u.pk)

    def get_assigned_to_name(self, obj):
        u = obj.assigned_to
        if not u:
            return None
        return getattr(u, "name", None) or getattr(u, "phone", None) or str(u.pk)


class SupportTicketUpdateSerializer(serializers.ModelSerializer):
    """
    تحديثات التشغيل: status / assignment
    """
    class Meta:
        model = SupportTicket
        fields = ["status", "assigned_team", "assigned_to"]

    def validate_status(self, value):
        if value not in SupportTicketStatus.values:
            raise serializers.ValidationError("حالة غير صحيحة.")
        return value
