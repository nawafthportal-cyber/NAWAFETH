import re

from rest_framework import serializers

from .models import Notification, DeviceToken, NotificationPreference
from .services import notification_tier_to_canonical, normalize_notification_url


class NotificationSerializer(serializers.ModelSerializer):
    url = serializers.SerializerMethodField()

    def _verification_payment_url_from_notification(self, obj: Notification) -> str:
        title = str(getattr(obj, "title", "") or "").strip()
        if title != "استكمال رسوم التوثيق":
            return ""

        try:
            from apps.verification.models import VerificationRequest, VerificationStatus
        except Exception:
            return ""

        body = str(getattr(obj, "body", "") or "")
        code_match = re.search(r"AD\d{6}", body)
        request_qs = VerificationRequest.objects.select_related("invoice").filter(requester=obj.user)

        request_obj = None
        if code_match:
            request_obj = request_qs.filter(code=code_match.group(0)).order_by("-id").first()
        if request_obj is None:
            request_obj = request_qs.filter(status=VerificationStatus.PENDING_PAYMENT, invoice__isnull=False).order_by("-id").first()

        if request_obj is None or not getattr(request_obj, "invoice_id", None):
            return ""
        invoice = getattr(request_obj, "invoice", None)
        if invoice is not None and invoice.is_payment_effective():
            return ""

        return f"/verification/payment/?request_id={request_obj.id}&invoice_id={request_obj.invoice_id}"

    def get_url(self, obj: Notification) -> str:
        normalized = normalize_notification_url(obj.url)
        if normalized.startswith("/chat/"):
            verification_payment_url = self._verification_payment_url_from_notification(obj)
            if verification_payment_url:
                return verification_payment_url
        return normalized

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
