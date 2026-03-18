from __future__ import annotations

from datetime import timedelta

from django.utils import timezone
from rest_framework import serializers

from .models import AnalyticsChannel, AnalyticsEvent
from .tracking import analytics_event_names


class AnalyticsEventIngestSerializer(serializers.Serializer):
    event_name = serializers.ChoiceField(choices=sorted(analytics_event_names()))
    channel = serializers.ChoiceField(choices=AnalyticsChannel.choices, required=False, default=AnalyticsChannel.MOBILE_WEB)
    surface = serializers.CharField(max_length=120, required=False, allow_blank=True)
    source_app = serializers.CharField(max_length=50, required=False, allow_blank=True)
    object_type = serializers.CharField(max_length=80, required=False, allow_blank=True)
    object_id = serializers.CharField(max_length=50, required=False, allow_blank=True)
    session_id = serializers.CharField(max_length=64, required=False, allow_blank=True)
    dedupe_key = serializers.CharField(max_length=160, required=False, allow_blank=True)
    occurred_at = serializers.DateTimeField(required=False)
    version = serializers.IntegerField(required=False, min_value=1, default=1)
    payload = serializers.JSONField(required=False)

    def validate_occurred_at(self, value):
        if value > timezone.now() + timedelta(minutes=5):
            raise serializers.ValidationError("occurred_at لا يمكن أن يكون في المستقبل البعيد.")
        return value


class AnalyticsEventSerializer(serializers.ModelSerializer):
    actor_phone = serializers.CharField(source="actor.phone", read_only=True)

    class Meta:
        model = AnalyticsEvent
        fields = [
            "id",
            "event_name",
            "channel",
            "surface",
            "source_app",
            "object_type",
            "object_id",
            "actor",
            "actor_phone",
            "session_id",
            "dedupe_key",
            "version",
            "occurred_at",
            "payload",
            "created_at",
        ]
