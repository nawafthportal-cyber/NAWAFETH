from __future__ import annotations

from rest_framework import serializers
from .models import ExtraPurchase
from .option_catalog import (
    EXTRAS_CLIENT_OPTIONS,
    EXTRAS_FINANCE_OPTIONS,
    EXTRAS_REPORT_OPTIONS,
    normalize_option_keys,
)


class ExtraCatalogItemSerializer(serializers.Serializer):
    sku = serializers.CharField()
    title = serializers.CharField()
    price = serializers.DecimalField(max_digits=12, decimal_places=2)


class ExtraPurchaseSerializer(serializers.ModelSerializer):
    class Meta:
        model = ExtraPurchase
        fields = [
            "id", "sku", "title",
            "extra_type", "subtotal", "currency",
            "status",
            "start_at", "end_at",
            "credits_total", "credits_used",
            "invoice",
            "created_at",
        ]


class ExtrasReportsSelectionSerializer(serializers.Serializer):
    enabled = serializers.BooleanField(required=False, default=False)
    options = serializers.ListField(
        child=serializers.CharField(),
        required=False,
        default=list,
    )
    start_at = serializers.DateField(required=False, allow_null=True)
    end_at = serializers.DateField(required=False, allow_null=True)

    def validate(self, attrs):
        attrs = dict(attrs)
        attrs["options"] = normalize_option_keys(list(attrs.get("options", [])), EXTRAS_REPORT_OPTIONS)
        enabled = bool(attrs.get("enabled", False))
        if attrs["options"] and not enabled:
            enabled = True
        if enabled and not attrs["options"]:
            raise serializers.ValidationError({"options": "اختر خياراً واحداً على الأقل للتقارير."})

        start_at = attrs.get("start_at")
        end_at = attrs.get("end_at")
        if start_at and end_at and start_at > end_at:
            raise serializers.ValidationError({"end_at": "تاريخ نهاية التقرير يجب أن يكون بعد تاريخ البداية."})
        attrs["enabled"] = enabled
        if not enabled:
            attrs["start_at"] = None
            attrs["end_at"] = None
        return attrs


class ExtrasClientsSelectionSerializer(serializers.Serializer):
    enabled = serializers.BooleanField(required=False, default=False)
    options = serializers.ListField(
        child=serializers.CharField(),
        required=False,
        default=list,
    )
    subscription_years = serializers.IntegerField(required=False, default=1, min_value=1, max_value=5)
    bulk_message_count = serializers.IntegerField(required=False, default=0, min_value=0, max_value=200000)

    def validate(self, attrs):
        attrs = dict(attrs)
        attrs["options"] = normalize_option_keys(list(attrs.get("options", [])), EXTRAS_CLIENT_OPTIONS)
        enabled = bool(attrs.get("enabled", False))
        if attrs["options"] and not enabled:
            enabled = True
        if enabled and not attrs["options"]:
            raise serializers.ValidationError({"options": "اختر خياراً واحداً على الأقل لإدارة العملاء."})
        attrs["enabled"] = enabled
        if not enabled:
            attrs["subscription_years"] = 1
            attrs["bulk_message_count"] = 0
        return attrs


class ExtrasFinanceSelectionSerializer(serializers.Serializer):
    enabled = serializers.BooleanField(required=False, default=False)
    options = serializers.ListField(
        child=serializers.CharField(),
        required=False,
        default=list,
    )
    subscription_years = serializers.IntegerField(required=False, default=1, min_value=1, max_value=5)
    qr_first_name = serializers.CharField(required=False, allow_blank=True, max_length=50)
    qr_last_name = serializers.CharField(required=False, allow_blank=True, max_length=50)
    iban = serializers.CharField(required=False, allow_blank=True, max_length=34)

    def validate(self, attrs):
        attrs = dict(attrs)
        attrs["options"] = normalize_option_keys(list(attrs.get("options", [])), EXTRAS_FINANCE_OPTIONS)
        enabled = bool(attrs.get("enabled", False))
        if attrs["options"] and not enabled:
            enabled = True
        if enabled and not attrs["options"]:
            raise serializers.ValidationError({"options": "اختر خياراً واحداً على الأقل للإدارة المالية."})
        attrs["enabled"] = enabled
        if not enabled:
            attrs["subscription_years"] = 1
            attrs["qr_first_name"] = ""
            attrs["qr_last_name"] = ""
            attrs["iban"] = ""
        else:
            attrs["qr_first_name"] = str(attrs.get("qr_first_name") or "").strip()
            attrs["qr_last_name"] = str(attrs.get("qr_last_name") or "").strip()
            attrs["iban"] = str(attrs.get("iban") or "").strip().replace(" ", "").upper()
        return attrs


class ExtrasBundleRequestInputSerializer(serializers.Serializer):
    reports = ExtrasReportsSelectionSerializer(required=False, default=dict)
    clients = ExtrasClientsSelectionSerializer(required=False, default=dict)
    finance = ExtrasFinanceSelectionSerializer(required=False, default=dict)
    notes = serializers.CharField(required=False, allow_blank=True, max_length=1000)

    def validate(self, attrs):
        attrs = dict(attrs)
        reports = attrs.get("reports") or {}
        clients = attrs.get("clients") or {}
        finance = attrs.get("finance") or {}

        any_enabled = bool(reports.get("enabled") or clients.get("enabled") or finance.get("enabled"))
        if not any_enabled:
            raise serializers.ValidationError("اختر على الأقل قسماً واحداً من الخدمات الإضافية.")
        attrs["reports"] = reports
        attrs["clients"] = clients
        attrs["finance"] = finance
        attrs["notes"] = str(attrs.get("notes") or "").strip()
        return attrs
