from datetime import timedelta
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import Client, TestCase
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import UserRole
from apps.notifications.models import Notification
from apps.providers.models import ProviderProfile
from apps.subscriptions.models import PlanPeriod, PlanTier, Subscription, SubscriptionPlan, SubscriptionStatus

from .models import Invoice, InvoiceStatus, PaymentAttempt, PaymentProvider
from .services import init_payment


class PaymentNotificationSignalTests(TestCase):
    def setUp(self):
        user_model = get_user_model()
        self.provider_user = user_model.objects.create_user(
            phone="0500001760",
            password="secret",
            role_state=UserRole.PROVIDER,
        )
        ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود دفعات",
            bio="نبذة",
            city="الرياض",
        )
        plan = SubscriptionPlan.objects.create(
            code="payment-notify-basic",
            tier=PlanTier.BASIC,
            title="أساسية",
            period=PlanPeriod.MONTH,
            price="0.00",
            notifications_enabled=True,
            is_active=True,
        )
        Subscription.objects.create(
            user=self.provider_user,
            plan=plan,
            status=SubscriptionStatus.ACTIVE,
            start_at=timezone.now() - timedelta(days=1),
            end_at=timezone.now() + timedelta(days=30),
        )

    def test_effective_payment_creates_provider_notification_once(self):
        invoice = Invoice.objects.create(
            user=self.provider_user,
            title="فاتورة ترويج",
            reference_type="promo_request",
            reference_id="123",
            subtotal=Decimal("100.00"),
            vat_percent=Decimal("15.00"),
            status="pending",
        )

        invoice.mark_payment_confirmed(
            provider="mock",
            provider_reference="PAY-123",
            event_id="EV-123",
            amount=invoice.total,
            currency="SAR",
        )
        invoice.save()
        invoice.save(update_fields=["updated_at"])

        notifications = Notification.objects.filter(user=self.provider_user)
        self.assertEqual(notifications.count(), 1)
        notification = notifications.first()
        self.assertIsNotNone(notification)
        self.assertEqual(notification.audience_mode, Notification.AudienceMode.PROVIDER)
        self.assertIn("عملية سداد جديدة", notification.title)
        self.assertIn("فاتورة ترويج", notification.body)


class MockCheckoutViewTests(TestCase):
    def setUp(self):
        user_model = get_user_model()
        self.owner = user_model.objects.create_user(
            phone="0500000710",
            username="checkout_owner",
            password="secret",
        )
        self.other_user = user_model.objects.create_user(
            phone="0500000711",
            username="checkout_other",
            password="secret",
        )
        self.invoice = Invoice.objects.create(
            user=self.owner,
            title="فاتورة اختبار checkout",
            reference_type="extras_bundle_request",
            reference_id="P-CHECKOUT-1",
            currency="SAR",
            subtotal="100.00",
            vat_percent="15.00",
            status=InvoiceStatus.PENDING,
        )
        self.attempt = init_payment(
            invoice=self.invoice,
            provider=PaymentProvider.MOCK,
            by_user=self.owner,
            idempotency_key="billing-mock-checkout-test",
        )
        self.client = Client()

    def test_mock_checkout_allows_non_owner(self):
        self.client.force_login(self.other_user)

        response = self.client.get(
            reverse("billing:mock_checkout", kwargs={"provider": "mock", "attempt_id": self.attempt.id})
        )

        self.assertEqual(response.status_code, 302)
        self.assertIn("payment=success", response["Location"])

    def test_mock_checkout_allows_anonymous_user(self):
        response = self.client.get(
            reverse("billing:mock_checkout", kwargs={"provider": "mock", "attempt_id": self.attempt.id})
        )

        self.assertEqual(response.status_code, 302)
        self.assertIn("payment=success", response["Location"])

    def test_mock_checkout_allows_invoice_owner(self):
        self.client.force_login(self.owner)

        response = self.client.get(
            reverse("billing:mock_checkout", kwargs={"provider": "mock", "attempt_id": self.attempt.id})
        )

        self.assertEqual(response.status_code, 302)
        self.assertIn("payment=success", response["Location"])