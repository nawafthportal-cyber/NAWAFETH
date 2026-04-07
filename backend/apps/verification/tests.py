from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase

from apps.billing.models import Invoice
from apps.core.models import PlatformConfig
from apps.subscriptions.configuration import canonical_subscription_plan_for_tier
from apps.subscriptions.tiering import CanonicalPlanTier

from .models import VerificationBadgeType, VerificationRequest, VerificationRequirement
from .services import _locked_verification_request_queryset, verification_billing_policy, verification_invoice_preview_for_request


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