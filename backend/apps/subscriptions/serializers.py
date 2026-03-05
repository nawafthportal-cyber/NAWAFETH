from __future__ import annotations

from rest_framework import serializers
from .models import FeatureKey, SubscriptionPlan, Subscription


class PlanSerializer(serializers.ModelSerializer):
    feature_labels = serializers.SerializerMethodField()
    period_label = serializers.CharField(source="get_period_display", read_only=True)

    def get_feature_labels(self, obj: SubscriptionPlan):
        labels = dict(FeatureKey.choices)
        raw = obj.features or []
        out = []
        for key in raw:
            normalized = str(key or "").strip()
            if not normalized:
                continue
            out.append(labels.get(normalized, normalized.replace("_", " ")))
        return out

    class Meta:
        model = SubscriptionPlan
        fields = [
            "id",
            "code",
            "tier",
            "title",
            "description",
            "period",
            "period_label",
            "price",
            "features",
            "feature_labels",
            "is_active",
        ]


class SubscriptionSerializer(serializers.ModelSerializer):
    plan = PlanSerializer(read_only=True)

    class Meta:
        model = Subscription
        fields = ["id", "plan", "status", "start_at", "end_at", "grace_end_at", "auto_renew", "invoice", "created_at"]
