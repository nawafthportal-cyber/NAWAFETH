from rest_framework import serializers

from .models import Message, Thread, ThreadUserState


class ThreadSerializer(serializers.ModelSerializer):
    class Meta:
        model = Thread
        fields = ("id", "request", "is_direct", "context_mode", "created_at")
        read_only_fields = ("id", "created_at")


class DirectThreadSerializer(serializers.ModelSerializer):
    participant_1_id = serializers.IntegerField(source="participant_1.id", read_only=True)
    participant_2_id = serializers.IntegerField(source="participant_2.id", read_only=True)

    class Meta:
        model = Thread
        fields = ("id", "is_direct", "context_mode", "participant_1_id", "participant_2_id", "created_at")
        read_only_fields = ("id", "created_at")


class MessageCreateSerializer(serializers.ModelSerializer):
    body = serializers.CharField(required=False, allow_blank=True)
    attachment = serializers.FileField(required=False, allow_null=True)

    class Meta:
        model = Message
        fields = ("id", "body", "attachment", "attachment_type", "attachment_name")
        read_only_fields = ("id",)

    def validate_body(self, value):
        value = (value or "").strip()
        if len(value) > 2000:
            raise serializers.ValidationError("نص الرسالة طويل جدًا")
        return value

    def validate(self, attrs):
        body = (attrs.get("body") or "").strip()
        attachment = attrs.get("attachment")
        if not body and not attachment:
            raise serializers.ValidationError("نص الرسالة أو المرفق مطلوب")
        attrs["body"] = body
        return attrs


class MessageListSerializer(serializers.ModelSerializer):
    sender_phone = serializers.CharField(source="sender.phone", read_only=True)
    sender_name = serializers.SerializerMethodField()
    receiver_name = serializers.SerializerMethodField()
    read_by_ids = serializers.SerializerMethodField()
    attachment_url = serializers.FileField(source="attachment", read_only=True)

    class Meta:
        model = Message
        fields = (
            "id",
            "sender",
            "sender_phone",
            "sender_name",
            "receiver_name",
            "body",
            "attachment_url",
            "attachment_type",
            "attachment_name",
            "created_at",
            "read_by_ids",
        )

    def get_read_by_ids(self, obj):
        try:
            return list(obj.reads.values_list("user_id", flat=True))
        except Exception:
            return []

    def _display_name_for_user(self, user):
        if not user:
            return ""
        first = (getattr(user, "first_name", "") or "").strip()
        last = (getattr(user, "last_name", "") or "").strip()
        full = ("%s %s" % (first, last)).strip()
        if full:
            return full
        username = (getattr(user, "username", "") or "").strip()
        if username:
            return username
        return getattr(user, "phone", "") or str(user)

    def get_sender_name(self, obj):
        return self._display_name_for_user(getattr(obj, "sender", None))

    def get_receiver_name(self, obj):
        try:
            thread = getattr(obj, "thread", None)
            if not thread or not thread.is_direct:
                return ""
            sender = getattr(obj, "sender", None)
            if sender and sender.id == thread.participant_1_id:
                peer = thread.participant_2
            else:
                peer = thread.participant_1
            return self._display_name_for_user(peer)
        except Exception:
            return ""


class ThreadUserStateSerializer(serializers.ModelSerializer):
    class Meta:
        model = ThreadUserState
        fields = (
            "thread",
            "is_favorite",
            "favorite_label",
            "client_label",
            "is_archived",
            "is_blocked",
            "blocked_at",
            "archived_at",
        )
        read_only_fields = fields
