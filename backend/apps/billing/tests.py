from decimal import Decimal

from django.test import TestCase, override_settings
from django.urls import reverse

from apps.accounts.models import User, UserRole
from apps.billing.models import Invoice, PaymentProvider
from apps.billing.services import init_payment


@override_settings(BILLING_WEBHOOK_SECRETS={PaymentProvider.MOCK: "test-secret"})
class MockCheckoutReturnTests(TestCase):
    def test_checkout_allows_app_payment_return_deep_link(self):
        user = User.objects.create(
            phone="0500000090",
            username="billing.return",
            role_state=UserRole.CLIENT,
        )
        invoice = Invoice.objects.create(
            user=user,
            title="فاتورة اختبار",
            subtotal=Decimal("100.00"),
            reference_type="promo_request",
            reference_id="77",
        )
        attempt = init_payment(
            invoice=invoice,
            provider=PaymentProvider.MOCK,
            by_user=user,
            idempotency_key="checkout-return-test",
        )

        next_url = "nawafeth://payment-return?request_code=PR000077"
        response = self.client.get(
            reverse(
                "billing:mock_checkout",
                kwargs={"provider": PaymentProvider.MOCK, "attempt_id": attempt.id},
            ),
            {"next": next_url},
        )

        self.assertEqual(response.status_code, 302)
        self.assertTrue(response["Location"].startswith(next_url))
        self.assertIn("payment=success", response["Location"])
        self.assertIn("invoice=", response["Location"])
