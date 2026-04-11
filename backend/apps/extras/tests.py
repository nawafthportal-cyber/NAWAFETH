from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import Client, TestCase
from django.urls import reverse
from apps.billing.models import Invoice, InvoiceStatus
from apps.billing.services import init_payment
from apps.extras.services import (
    EXTRAS_BUNDLE_INVOICE_REFERENCE_TYPE,
    extras_bundle_payment_access_url,
)
from apps.unified_requests.models import UnifiedRequest, UnifiedRequestMetadata, UnifiedRequestType


class ExtrasBundlePaymentLinkViewTests(TestCase):
    def setUp(self):
        user_model = get_user_model()
        self.owner = user_model.objects.create_user(
            phone="0500000810",
            username="extras_owner",
            password="secret",
        )
        self.staff_user = user_model.objects.create_user(
            phone="0500000811",
            username="extras_staff",
            password="secret",
            is_staff=True,
        )
        self.request_obj = UnifiedRequest.objects.create(
            request_type=UnifiedRequestType.EXTRAS,
            status="in_progress",
            priority="normal",
            requester=self.owner,
            assigned_team_code="extras",
            assigned_team_name="فريق إدارة الخدمات الإضافية",
            assigned_user=self.staff_user,
            source_app="extras",
            source_model="ExtrasBundleRequest",
            source_object_id="bundle-payment-link-test",
            summary="طلب خدمات إضافية",
        )
        UnifiedRequestMetadata.objects.create(
            request=self.request_obj,
            payload={
                "bundle": {
                    "reports": {"enabled": True, "options": ["platform_metrics"], "start_at": "", "end_at": ""},
                    "clients": {"enabled": False, "options": [], "subscription_years": 1},
                    "finance": {"enabled": False, "options": [], "subscription_years": 1},
                }
            },
        )
        self.invoice = Invoice.objects.create(
            user=self.owner,
            title="فاتورة طلب خدمات إضافية",
            reference_type=EXTRAS_BUNDLE_INVOICE_REFERENCE_TYPE,
            reference_id=self.request_obj.code,
            currency="SAR",
            subtotal=Decimal("100.00"),
            vat_percent=Decimal("15.00"),
            status=InvoiceStatus.PENDING,
        )
        self.attempt = init_payment(
            invoice=self.invoice,
            provider="mock",
            by_user=self.staff_user,
            idempotency_key="extras-bundle-payment-link-view-test",
        )
        self.client = Client()

    def test_bundle_payment_link_redirects_owner_to_additional_services_payment_page(self):
        self.client.force_login(self.owner)

        response = self.client.get(
            reverse("extras:bundle_payment_link", kwargs={"attempt_id": self.attempt.id})
        )

        self.assertEqual(response.status_code, 302)
        self.assertIn("/additional-services/payment/", response["Location"])
        self.assertIn(f"request_id={self.request_obj.id}", response["Location"])
        self.assertIn(f"invoice_id={self.invoice.id}", response["Location"])

    def test_bundle_payment_link_redirects_staff_to_request_detail(self):
        self.client.force_login(self.staff_user)

        response = self.client.get(
            reverse("extras:bundle_payment_link", kwargs={"attempt_id": self.attempt.id})
        )

        self.assertEqual(response.status_code, 302)
        self.assertIn("/dashboard/extras/", response["Location"])
        self.assertIn(f"request={self.request_obj.id}", response["Location"])

    def test_bundle_payment_link_allows_unauthenticated_mobile_web_flow(self):
        response = self.client.get(
            reverse("extras:bundle_payment_link", kwargs={"attempt_id": self.attempt.id})
        )

        self.assertEqual(response.status_code, 302)
        self.assertIn("/additional-services/payment/", response["Location"])

    def test_bundle_payment_link_restores_requester_ownership_for_existing_wrong_invoice_owner(self):
        other_user = get_user_model().objects.create_user(
            phone="0500000812",
            username="extras_other",
            password="secret",
        )
        self.invoice.user = other_user
        self.invoice.save(update_fields=["user", "updated_at"])

        self.client.force_login(self.owner)

        response = self.client.get(
            reverse("extras:bundle_payment_link", kwargs={"attempt_id": self.attempt.id})
        )

        self.invoice.refresh_from_db()
        self.assertEqual(response.status_code, 302)
        self.assertIn("/additional-services/payment/", response["Location"])
        self.assertEqual(self.invoice.user_id, self.owner.id)

    def test_bundle_payment_access_url_points_to_additional_services_payment_page(self):
        payment_url = extras_bundle_payment_access_url(
            request_obj=self.request_obj,
            invoice=self.invoice,
            checkout_url=self.attempt.checkout_url,
        )

        self.assertIn("/additional-services/payment/", payment_url)
        self.assertIn(f"request_id={self.request_obj.id}", payment_url)
        self.assertIn(f"invoice_id={self.invoice.id}", payment_url)
