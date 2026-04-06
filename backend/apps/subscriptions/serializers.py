from __future__ import annotations

from decimal import Decimal

from rest_framework import serializers

from apps.billing.models import Invoice

from .capabilities import plan_capabilities_for_plan
from .offers import subscription_offer_for_plan
from .tiering import canonical_tier_label
from .models import FeatureKey, SubscriptionPlan, Subscription


class PlanSerializer(serializers.ModelSerializer):
    feature_labels = serializers.SerializerMethodField()
    period_label = serializers.CharField(source="get_period_display", read_only=True)
    canonical_tier = serializers.SerializerMethodField()
    tier_label = serializers.SerializerMethodField()
    capabilities = serializers.SerializerMethodField()
    provider_offer = serializers.SerializerMethodField()

    def get_feature_labels(self, obj: SubscriptionPlan):
        from apps.verification.services import verification_price_amount, verification_pricing_for_plan

        labels = dict(FeatureKey.choices)
        raw = obj.feature_keys()
        out = []
        verification_keys = {"verify_blue", "verify_green"}
        if any(str(key or "").strip().lower() in verification_keys for key in raw):
            pricing = verification_pricing_for_plan(obj)
            blue_amount = verification_price_amount(pricing, "blue")
            green_amount = verification_price_amount(pricing, "green")
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

    def get_canonical_tier(self, obj: SubscriptionPlan) -> str:
        return obj.normalized_tier()

    def get_tier_label(self, obj: SubscriptionPlan) -> str:
        return canonical_tier_label(obj.normalized_tier())

    def get_capabilities(self, obj: SubscriptionPlan) -> dict:
        return plan_capabilities_for_plan(obj)

    def get_provider_offer(self, obj: SubscriptionPlan) -> dict:
        request = self.context.get("request")
        user = getattr(request, "user", None)
        return subscription_offer_for_plan(obj, user=user)

    class Meta:
        model = SubscriptionPlan
        fields = [
            "id",
            "code",
            "tier",
            "canonical_tier",
            "tier_label",
            "title",
            "description",
            "period",
            "period_label",
            "price",
            "features",
            "feature_labels",
            "capabilities",
            "provider_offer",
            "is_active",
        ]


class SubscriptionSerializer(serializers.ModelSerializer):
    plan = PlanSerializer(read_only=True)
    provider_status_code = serializers.SerializerMethodField()
    provider_status_label = serializers.SerializerMethodField()
    duration_label = serializers.SerializerMethodField()
    request_code = serializers.SerializerMethodField()
    invoice_summary = serializers.SerializerMethodField()

    def get_provider_status_code(self, obj: Subscription) -> str:
        return str(getattr(obj, "status", "") or "").strip().lower()

    def get_provider_status_label(self, obj: Subscription) -> str:
        if obj.status == "awaiting_review":
            return "بانتظار المراجعة"
        return obj.get_status_display()

    def get_duration_label(self, obj: Subscription) -> str:
        duration_count = max(1, int(getattr(obj, "duration_count", 1) or 1))
        period_label = getattr(getattr(obj, "plan", None), "get_period_display", lambda: "سنة")()
        return f"{duration_count} {period_label}"

    def get_request_code(self, obj: Subscription) -> str:
        from apps.unified_requests.models import UnifiedRequest

        request_row = UnifiedRequest.objects.filter(
            source_app="subscriptions",
            source_model="Subscription",
            source_object_id=str(obj.id),
        ).only("code").first()
        return str(getattr(request_row, "code", "") or f"SD{obj.id:06d}")

    def get_invoice_summary(self, obj: Subscription) -> dict | None:
        invoice = getattr(obj, "invoice", None)
        if not isinstance(invoice, Invoice):
            return None
        return {
            "id": invoice.id,
            "code": invoice.code,
            "status": invoice.status,
            "status_label": invoice.get_status_display(),
            "subtotal": str(invoice.subtotal),
            "vat": str(invoice.vat_amount),
            "total": str(invoice.total),
            "currency": invoice.currency,
            "payment_effective": invoice.is_payment_effective(),
        }

    class Meta:
        model = Subscription
        fields = [
            "id",
            "plan",
            "status",
            "provider_status_code",
            "provider_status_label",
            "duration_count",
            "duration_label",
            "request_code",
            "start_at",
            "end_at",
            "grace_end_at",
            "auto_renew",
            "invoice",
            "invoice_summary",
            "created_at",
        ]
