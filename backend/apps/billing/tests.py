from django.contrib.auth import get_user_model
from django.test import Client, TestCase
from django.urls import reverse

from apps.billing.models import Invoice, InvoiceStatus, PaymentAttempt, PaymentProvider
from apps.billing.services import init_payment


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