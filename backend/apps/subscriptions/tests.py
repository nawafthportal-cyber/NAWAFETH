from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from apps.billing.models import Invoice, InvoiceStatus
from apps.core.models import PlatformConfig
from apps.providers.models import ProviderProfile
from apps.unified_requests.models import UnifiedRequest

from .models import PlanPeriod, PlanTier, Subscription, SubscriptionPlan, SubscriptionStatus
from .services import _locked_subscription_queryset, activate_subscription_after_payment, start_subscription_checkout


class SubscriptionPaymentReviewWorkflowTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(phone="0500000400", password="secret")
        self.plan = SubscriptionPlan.objects.create(
            code="pro_monthly_review",
            tier=PlanTier.PRO,
            title="الباقة الاحترافية",
            period=PlanPeriod.MONTH,
            price="299.00",
        )
        self.subscription = Subscription.objects.create(
            user=self.user,
            plan=self.plan,
            status=SubscriptionStatus.PENDING_PAYMENT,
        )
        self.invoice = Invoice.objects.create(
            user=self.user,
            title="فاتورة اشتراك",
            subtotal="299.00",
            vat_percent="15.00",
            reference_type="subscription",
            reference_id=str(self.subscription.id),
            status=InvoiceStatus.PENDING,
        )
        self.subscription.invoice = self.invoice
        self.subscription.save(update_fields=["invoice", "updated_at"])

    def test_paid_subscription_moves_to_awaiting_review_not_active(self):
        self.invoice.mark_payment_confirmed(
            provider="mock",
            provider_reference="pay-1",
            event_id="evt-1",
            amount=self.invoice.total,
            currency="SAR",
            when=timezone.now(),
        )
        self.invoice.save(update_fields=[
            "status",
            "paid_at",
            "payment_confirmed",
            "payment_confirmed_at",
            "payment_provider",
            "payment_reference",
            "payment_event_id",
            "payment_amount",
            "payment_currency",
            "updated_at",
        ])

        self.subscription.refresh_from_db()
        request_row = UnifiedRequest.objects.get(
            source_app="subscriptions",
            source_model="Subscription",
            source_object_id=str(self.subscription.id),
        )

        self.assertEqual(self.subscription.status, SubscriptionStatus.AWAITING_REVIEW)
        self.assertIsNone(self.subscription.start_at)
        self.assertEqual(request_row.status, "in_progress")

    def test_manual_activation_after_review_activates_and_closes_request(self):
        self.invoice.mark_payment_confirmed(
            provider="mock",
            provider_reference="pay-2",
            event_id="evt-2",
            amount=self.invoice.total,
            currency="SAR",
            when=timezone.now(),
        )
        self.invoice.save(update_fields=[
            "status",
            "paid_at",
            "payment_confirmed",
            "payment_confirmed_at",
            "payment_provider",
            "payment_reference",
            "payment_event_id",
            "payment_amount",
            "payment_currency",
            "updated_at",
        ])

        activate_subscription_after_payment(sub=self.subscription, changed_by=self.user, assigned_user=self.user)

        self.subscription.refresh_from_db()
        request_row = UnifiedRequest.objects.get(
            source_app="subscriptions",
            source_model="Subscription",
            source_object_id=str(self.subscription.id),
        )

        self.assertEqual(self.subscription.status, SubscriptionStatus.ACTIVE)
        self.assertIsNotNone(self.subscription.start_at)
        self.assertEqual(request_row.status, "closed")
        self.assertEqual(request_row.assigned_user_id, self.user.id)

    def test_payment_reversal_from_awaiting_review_returns_to_pending_payment(self):
        self.invoice.mark_payment_confirmed(
            provider="mock",
            provider_reference="pay-3",
            event_id="evt-3",
            amount=self.invoice.total,
            currency="SAR",
            when=timezone.now(),
        )
        self.invoice.save(update_fields=[
            "status",
            "paid_at",
            "payment_confirmed",
            "payment_confirmed_at",
            "payment_provider",
            "payment_reference",
            "payment_event_id",
            "payment_amount",
            "payment_currency",
            "updated_at",
        ])

        self.invoice.status = InvoiceStatus.REFUNDED
        self.invoice.clear_payment_confirmation()
        self.invoice.save(update_fields=[
            "status",
            "payment_confirmed",
            "payment_confirmed_at",
            "payment_provider",
            "payment_reference",
            "payment_event_id",
            "payment_amount",
            "payment_currency",
            "updated_at",
        ])

        self.subscription.refresh_from_db()
        request_row = UnifiedRequest.objects.get(
            source_app="subscriptions",
            source_model="Subscription",
            source_object_id=str(self.subscription.id),
        )

        self.assertEqual(self.subscription.status, SubscriptionStatus.PENDING_PAYMENT)
        self.assertEqual(request_row.status, "new")

    def test_locked_subscription_query_avoids_nullable_invoice_join(self):
        sql = str(_locked_subscription_queryset().filter(pk=self.subscription.pk).query).upper()

        self.assertNotIn("JOIN", sql)


class SubscriptionEntitlementApiRecoveryTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(phone="0500000410", password="secret")
        ProviderProfile.objects.create(
            user=self.user,
            provider_type="individual",
            display_name="مزود تجريبي",
            bio="نبذة مختصرة",
        )
        Subscription.objects.filter(user=self.user).delete()
        self.api_client = APIClient()
        self.api_client.force_authenticate(user=self.user)

    def test_my_subscriptions_api_recreates_basic_entitlement(self):
        response = self.api_client.get("/api/subscriptions/my/")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(Subscription.objects.filter(user=self.user, status=SubscriptionStatus.ACTIVE).count(), 1)
        self.assertEqual(len(response.json()), 1)
        self.assertEqual(response.json()[0]["plan"]["canonical_tier"], PlanTier.BASIC)

    def test_plans_api_recreates_basic_entitlement_before_offer_render(self):
        response = self.api_client.get("/api/subscriptions/plans/")

        self.assertEqual(response.status_code, 200)
        current = Subscription.objects.filter(user=self.user, status=SubscriptionStatus.ACTIVE).first()
        self.assertIsNotNone(current)
        plans = response.json()
        basic_plan = next((plan for plan in plans if plan["canonical_tier"] == PlanTier.BASIC), None)
        self.assertIsNotNone(basic_plan)
        self.assertEqual(basic_plan["provider_offer"]["cta"]["state"], "current")


class SubscriptionCheckoutDurationTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(phone="0500000420", password="secret")
        config, _ = PlatformConfig.objects.get_or_create(pk=1)
        config.vat_percent = Decimal("17.50")
        config.save()
        ProviderProfile.objects.create(
            user=self.user,
            provider_type="individual",
            display_name="مزود مدة",
            bio="نبذة مختصرة",
        )
        Subscription.objects.filter(user=self.user, status=SubscriptionStatus.ACTIVE).delete()
        self.plan = SubscriptionPlan.objects.create(
            code="riyadi_yearly_duration",
            tier=PlanTier.RIYADI,
            title="الريادية",
            period=PlanPeriod.YEAR,
            price="199.00",
        )
        self.api_client = APIClient()
        self.api_client.force_authenticate(user=self.user)

    def test_checkout_duration_multiplies_invoice_amount_and_activation_window(self):
        subscription = start_subscription_checkout(user=self.user, plan=self.plan, duration_count=2)

        self.assertEqual(subscription.duration_count, 2)
        self.assertEqual(subscription.invoice.subtotal, Decimal("398.00"))
        self.assertEqual(subscription.invoice.vat_percent, Decimal("17.50"))
        self.assertEqual(subscription.invoice.vat_amount, Decimal("69.65"))
        self.assertEqual(subscription.invoice.total, Decimal("467.65"))

        invoice = subscription.invoice
        invoice.mark_payment_confirmed(
            provider="mock",
            provider_reference="pay-duration-1",
            event_id="evt-duration-1",
            amount=invoice.total,
            currency="SAR",
            when=timezone.now(),
        )
        invoice.save(update_fields=[
            "status",
            "paid_at",
            "payment_confirmed",
            "payment_confirmed_at",
            "payment_provider",
            "payment_reference",
            "payment_event_id",
            "payment_amount",
            "payment_currency",
            "updated_at",
        ])

        subscription.refresh_from_db()
        self.assertEqual(subscription.status, SubscriptionStatus.AWAITING_REVIEW)

        activate_subscription_after_payment(sub=subscription, changed_by=self.user, assigned_user=self.user)
        subscription.refresh_from_db()

        config = PlatformConfig.load()
        self.assertEqual(
            (subscription.end_at - subscription.start_at).days,
            int(config.subscription_yearly_duration_days or 365) * 2,
        )

    def test_subscribe_api_returns_request_code_invoice_summary_and_duration(self):
        response = self.api_client.post(
            f"/api/subscriptions/subscribe/{self.plan.id}/",
            {"duration_count": 3},
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        payload = response.json()
        self.assertEqual(payload["duration_count"], 3)
        self.assertTrue(str(payload["request_code"]).startswith("SD"))
        self.assertEqual(payload["invoice_summary"]["subtotal"], "597.00")
        self.assertEqual(payload["invoice_summary"]["vat"], "104.48")
        self.assertEqual(payload["invoice_summary"]["total"], "701.48")

    def test_cancel_pending_checkout_removes_subscription_invoice_and_request(self):
        subscribe_response = self.api_client.post(
            f"/api/subscriptions/subscribe/{self.plan.id}/",
            {"duration_count": 1},
            format="json",
        )

        self.assertEqual(subscribe_response.status_code, 201)
        payload = subscribe_response.json()
        subscription_id = int(payload["id"])
        invoice_id = int(payload["invoice_summary"]["id"])

        cancel_response = self.api_client.post(f"/api/subscriptions/cancel/{subscription_id}/", {}, format="json")

        self.assertEqual(cancel_response.status_code, 200)
        self.assertEqual(cancel_response.json()["redirect_url"], f"/plans/summary/?plan_id={self.plan.id}")
        self.assertFalse(Subscription.objects.filter(pk=subscription_id).exists())
        self.assertFalse(Invoice.objects.filter(pk=invoice_id).exists())
        self.assertFalse(
            UnifiedRequest.objects.filter(
                source_app="subscriptions",
                source_model="Subscription",
                source_object_id=str(subscription_id),
            ).exists()
        )

        my_response = self.api_client.get("/api/subscriptions/my/")
        self.assertEqual(my_response.status_code, 200)
        self.assertFalse(any(int(row["id"]) == subscription_id for row in my_response.json()))