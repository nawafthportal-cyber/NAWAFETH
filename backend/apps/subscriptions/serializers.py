from __future__ import annotations

from decimal import Decimal

from rest_framework import serializers
from .models import FeatureKey, SubscriptionPlan, Subscription


class PlanSerializer(serializers.ModelSerializer):
    feature_labels = serializers.SerializerMethodField()
    period_label = serializers.CharField(source="get_period_display", read_only=True)

    def get_feature_labels(self, obj: SubscriptionPlan):
        from apps.verification.services import verification_pricing_for_plan

        labels = dict(FeatureKey.choices)
        raw = obj.features or []
        out = []
        verification_keys = {"verify_blue", "verify_green"}
        if any(str(key or "").strip().lower() in verification_keys for key in raw):
            pricing = verification_pricing_for_plan(obj)
            blue_amount = ((pricing.get("prices") or {}).get("blue") or {}).get("amount", "100.00")
            green_amount = ((pricing.get("prices") or {}).get("green") or {}).get("amount", "100.00")
            if blue_amount == green_amount:
                if Decimal(str(blue_amount)) <= Decimal("0.00"):
                    out.append("التوثيق مجاني لجميع الشارات ضمن هذه الباقة")
                else:
                    out.append(f"رسوم التوثيق {blue_amount} ر.س لكل شارة عند الاعتماد")
            else:
                out.append(f"رسوم التوثيق الأزرق {blue_amount} ر.س والأخضر {green_amount} ر.س")

        for key in raw:
            normalized = str(key or "").strip()
            if not normalized:
                continue
            if normalized.lower() in verification_keys:
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
