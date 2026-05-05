from rest_framework import serializers

from .models import Message, Thread, ThreadUserState
from .display import display_name_for_user
from apps.uploads.media_optimizer import optimize_upload_for_storage
from apps.uploads.validators import (
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
        attachment_type = (attrs.get("attachment_type") or "").strip().lower()
        if not body and not attachment:
            raise serializers.ValidationError("نص الرسالة أو المرفق مطلوب")

        if attachment is not None:
            if attachment_type == "image":
                validate_secure_upload(
                    attachment,
                    allowed_extensions=IMAGE_EXTENSIONS,
                    allowed_mime_types=IMAGE_MIME_TYPES,
                    max_size_mb=20,
                    rename=True,
                    rename_prefix="msg_image",
                )
            elif attachment_type == "video":
                validate_secure_upload(
                    attachment,
                    allowed_extensions=VIDEO_EXTENSIONS,
                    allowed_mime_types=VIDEO_MIME_TYPES,
                    max_size_mb=50,
                    rename=True,
                    rename_prefix="msg_video",
                )
            elif attachment_type == "audio":
                validate_secure_upload(
                    attachment,
                    allowed_extensions=AUDIO_EXTENSIONS,
                    allowed_mime_types=AUDIO_MIME_TYPES,
                    max_size_mb=20,
                    rename=True,
                    rename_prefix="msg_audio",
                )
            else:
                validate_secure_upload(
                    attachment,
                    allowed_extensions=DOCUMENT_EXTENSIONS | AUDIO_EXTENSIONS,
                    allowed_mime_types=DOCUMENT_MIME_TYPES | AUDIO_MIME_TYPES,
                    max_size_mb=25,
                    rename=True,
                    rename_prefix="msg_file",
                )
            attachment = optimize_upload_for_storage(attachment, declared_type=attachment_type)
            attrs["attachment"] = attachment
            attrs["attachment_name"] = (attrs.get("attachment_name") or attachment.name or "")[:255]
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
            "is_system_generated",
            "sender_team_name",
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
        return display_name_for_user(user)

    def get_sender_name(self, obj):
        return display_name_for_user(
            getattr(obj, "sender", None),
            message_body=getattr(obj, "body", ""),
            sender_team_name=getattr(obj, "sender_team_name", ""),
        )

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
            return display_name_for_user(peer, sender_team_name=getattr(thread, "system_sender_label", ""))
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
            "is_deleted",
            "blocked_at",
            "archived_at",
            "deleted_at",
        )
        read_only_fields = fields
