from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from apps.billing.models import Invoice, InvoiceStatus
from apps.notifications.models import Notification
from apps.core.models import PlatformConfig
from apps.providers.models import ProviderProfile
from apps.subscriptions.configuration import canonical_subscription_plan_for_tier
from apps.subscriptions.tiering import CanonicalPlanTier

from .models import VerificationBadgeType, VerificationRequest, VerificationRequirement, VerificationStatus
from .services import (
    _locked_verification_request_queryset,
    revoke_after_payment_reversal,
    verification_billing_policy,
    verification_invoice_preview_for_request,
)


class VerificationVatPricingTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(phone="0500000500", password="secret")

        config, _ = PlatformConfig.objects.get_or_create(pk=1)
        config.vat_percent = Decimal("12.50")
        config.save()

        basic_plan = canonical_subscription_plan_for_tier(CanonicalPlanTier.BASIC)
        basic_plan.verification_blue_fee = Decimal("100.00")
        basic_plan.verification_green_fee = Decimal("200.00")
        basic_plan.save(update_fields=["verification_blue_fee", "verification_green_fee"])

    def test_verification_invoice_preview_uses_platform_vat(self):
        request = VerificationRequest.objects.create(requester=self.user)
        VerificationRequirement.objects.create(
            request=request,
            badge_type=VerificationBadgeType.BLUE,
            code="B1",
            title="توثيق الهوية",
            is_approved=True,
            sort_order=0,
        )
        VerificationRequirement.objects.create(
            request=request,
            badge_type=VerificationBadgeType.GREEN,
            code="G1",
            title="توثيق الاعتماد المهني",
            is_approved=True,
            sort_order=1,
        )

        billing_policy = verification_billing_policy()
        preview = verification_invoice_preview_for_request(vr=request)

        self.assertEqual(billing_policy["additional_vat_percent"], "12.50")
        self.assertFalse(billing_policy["tax_included"])
        self.assertEqual(preview["additional_vat_percent"], "12.50")
        self.assertEqual(preview["subtotal"], Decimal("300.00"))
        self.assertEqual(preview["vat_amount"], Decimal("37.50"))
        self.assertEqual(preview["total"], Decimal("337.50"))

    def test_locked_verification_query_avoids_nullable_invoice_join(self):
        request = VerificationRequest.objects.create(requester=self.user)

        sql = str(_locked_verification_request_queryset().filter(pk=request.pk).query).upper()

        self.assertNotIn("LEFT OUTER JOIN", sql)
        self.assertNotIn(Invoice._meta.db_table.upper(), sql)


class VerificationSubscriptionRequirementTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(phone="0500000501", password="secret")
        ProviderProfile.objects.create(
            user=self.user,
            provider_type="individual",
            display_name="مزود بلا اشتراك",
            bio="نبذة مختصرة",
        )
        self.api_client = APIClient()
        self.api_client.force_authenticate(user=self.user)

    def test_create_verification_request_requires_active_subscription(self):
        response = self.api_client.post(
            "/api/verification/requests/create/",
            {"badge_type": VerificationBadgeType.BLUE},
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["code"][0], "verification_subscription_required")
        self.assertEqual(VerificationRequest.objects.filter(requester=self.user).count(), 0)


class VerificationPaymentReversalNotificationTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(phone="0500000502", password="secret")
        ProviderProfile.objects.create(
            user=self.user,
            provider_type="individual",
            display_name="مزود توثيق",
            bio="نبذة مختصرة",
        )
        self.invoice = Invoice.objects.create(
            user=self.user,
            title="فاتورة توثيق",
            subtotal="100.00",
            vat_percent="15.00",
            reference_type="verify_request",
            reference_id="ADTEST",
            status=InvoiceStatus.PENDING,
        )
        self.request = VerificationRequest.objects.create(
            requester=self.user,
            status=VerificationStatus.ACTIVE,
            invoice=self.invoice,
            activated_at=timezone.now() - timezone.timedelta(days=10),
            expires_at=timezone.now() + timezone.timedelta(days=355),
        )

    def test_revoke_after_payment_reversal_notifies_requester(self):
        revoke_after_payment_reversal(vr=self.request)
        self.request.refresh_from_db()

        self.assertEqual(self.request.status, VerificationStatus.PENDING_PAYMENT)
        self.assertIsNone(self.request.activated_at)
        self.assertIsNone(self.request.expires_at)

        notification = Notification.objects.filter(user=self.user).order_by("-id").first()
        self.assertIsNotNone(notification)
        self.assertIn("تراجع الدفع", notification.title)
        self.assertIn("بانتظار الدفع", notification.body)
