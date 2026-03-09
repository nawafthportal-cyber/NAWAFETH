from rest_framework import serializers

from .models import Notification, DeviceToken, NotificationPreference
from .services import notification_tier_to_canonical


class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = (
            "id",
            "title",
            "body",
            "kind",
            "url",
            "audience_mode",
            "is_read",
            "is_pinned",
            "is_follow_up",
            "is_urgent",
            "created_at",
        )


class DeviceTokenSerializer(serializers.ModelSerializer):
    class Meta:
        model = DeviceToken
        fields = ("token", "platform")


class NotificationPreferenceSerializer(serializers.ModelSerializer):
    canonical_tier = serializers.SerializerMethodField()
    audience_mode = serializers.CharField(read_only=True)

    def get_canonical_tier(self, obj: NotificationPreference) -> str:
        return notification_tier_to_canonical(obj.tier)

    class Meta:
        model = NotificationPreference
        fields = ("key", "enabled", "tier", "canonical_tier", "audience_mode", "updated_at")
