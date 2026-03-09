from __future__ import annotations

from decimal import Decimal
from django.conf import settings
from rest_framework import serializers

from .models import Invoice, PaymentAttempt, InvoiceStatus, PaymentProvider, money_round


class InvoiceCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = Invoice
        fields = [
            "id", "code",
            "title", "description", "currency",
            "subtotal", "vat_percent",
            "reference_type", "reference_id",
            "status",
        ]
        read_only_fields = ["id", "code", "status"]

    def validate_subtotal(self, v):
        v = money_round(Decimal(v))
        if v <= 0:
            raise serializers.ValidationError("المبلغ يجب أن يكون أكبر من صفر.")
        return v

    def create(self, validated_data):
        user = self.context["request"].user
        from apps.core.models import PlatformConfig
        vat = PlatformConfig.load().vat_percent
        invoice = Invoice.objects.create(
            user=user,
            vat_percent=Decimal(str(vat)),
            status=InvoiceStatus.DRAFT,
            **validated_data,
        )
        invoice.mark_pending()
        invoice.save(update_fields=["status", "subtotal", "vat_percent", "vat_amount", "total", "updated_at"])
        return invoice


class InvoiceDetailSerializer(serializers.ModelSerializer):
    class Meta:
        model = Invoice
        fields = [
            "id", "code",
            "title", "description",
            "currency",
            "subtotal", "vat_percent", "vat_amount", "total",
            "status",
            "reference_type", "reference_id",
            "paid_at",
            "created_at", "updated_at",
        ]


class InitPaymentSerializer(serializers.Serializer):
    provider = serializers.ChoiceField(choices=PaymentProvider.choices, default=PaymentProvider.MOCK)
    idempotency_key = serializers.CharField(required=False, allow_blank=True, max_length=80)

    def validate(self, attrs):
        # لا يوجد تحقق إضافي الآن
        return attrs


class PaymentAttemptSerializer(serializers.ModelSerializer):
    class Meta:
        model = PaymentAttempt
        fields = [
            "id", "provider", "status",
            "amount", "currency",
            "checkout_url", "provider_reference",
            "created_at",
        ]
