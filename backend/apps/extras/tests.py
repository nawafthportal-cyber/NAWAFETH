from decimal import Decimal
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.db import connection
from django.test import Client, TestCase
from django.test.utils import CaptureQueriesContext
from django.urls import reverse
from rest_framework.test import APIRequestFactory, force_authenticate

from apps.accounts.models import UserRole
from apps.billing.models import Invoice, InvoiceLineItem, InvoiceStatus
from apps.billing.services import init_payment
from apps.extras.views import MyExtrasBundleRequestsView
from apps.extras.services import (
    EXTRAS_BUNDLE_INVOICE_REFERENCE_TYPE,
    extras_bundle_payment_access_url,
    notify_bundle_completed,
)
from apps.providers.models import ProviderProfile
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


class MyExtrasBundleRequestsViewTests(TestCase):
    def setUp(self):
        user_model = get_user_model()
        self.user = user_model.objects.create_user(
            phone="0500000910",
            username="extras_bundle_history_owner",
            password="secret",
        )

        self.requests = []
        for index in range(3):
            request_obj = UnifiedRequest.objects.create(
                request_type=UnifiedRequestType.EXTRAS,
                status="in_progress",
                priority="normal",
                requester=self.user,
                assigned_team_code="extras",
                assigned_team_name="فريق إدارة الخدمات الإضافية",
                source_app="extras",
                source_model="ExtrasBundleRequest",
                source_object_id=f"bundle-history-{index}",
                summary=f"طلب خدمات إضافية {index}",
            )
            invoice = Invoice.objects.create(
                user=self.user,
                title=f"فاتورة {index}",
                reference_type=EXTRAS_BUNDLE_INVOICE_REFERENCE_TYPE,
                reference_id=request_obj.code,
                currency="SAR",
                subtotal=Decimal("100.00"),
                vat_percent=Decimal("15.00"),
                status=InvoiceStatus.PENDING,
            )
            InvoiceLineItem.objects.create(invoice=invoice, title=f"line-{index}-1", amount=Decimal("50.00"), sort_order=1)
            InvoiceLineItem.objects.create(invoice=invoice, title=f"line-{index}-2", amount=Decimal("50.00"), sort_order=2)
            UnifiedRequestMetadata.objects.update_or_create(
                request=request_obj,
                defaults={
                    "payload": {
                        "invoice_id": invoice.id,
                        "bundle": {
                            "summary_sections": [
                                {
                                    "key": "reports",
                                    "title": "التقارير",
                                    "items": [f"خيار {index}"],
                                }
                            ],
                            "notes": f"ملاحظة {index}",
                        },
                    }
                },
            )
            self.requests.append((request_obj, invoice))

    def test_bundle_requests_view_batches_invoice_queries(self):
        factory = APIRequestFactory()
        request = factory.get(reverse("extras:bundle_request_my"))
        force_authenticate(request, user=self.user)

        with CaptureQueriesContext(connection) as context:
            response = MyExtrasBundleRequestsView.as_view()(request)
            response.render()

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data["results"]), 3)
        self.assertEqual(len(context.captured_queries), 3)

    def test_bundle_requests_view_returns_prefetched_invoice_lines(self):
        factory = APIRequestFactory()
        request = factory.get(reverse("extras:bundle_request_my"))
        force_authenticate(request, user=self.user)

        response = MyExtrasBundleRequestsView.as_view()(request)
        response.render()

        first_result = response.data["results"][0]
        self.assertEqual(len(first_result["invoice_summary"]["lines"]), 2)


class ExtrasBundleNotificationRoutingTests(TestCase):
    def setUp(self):
        user_model = get_user_model()
        self.provider_user = user_model.objects.create_user(
            phone="0500000920",
            username="extras_provider",
            password="secret",
            role_state=UserRole.PROVIDER,
        )
        ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود خدمات إضافية",
            bio="نبذة",
        )
        self.staff_user = user_model.objects.create_user(
            phone="0500000921",
            username="extras_operator",
            password="secret",
            is_staff=True,
        )
        self.request_obj = UnifiedRequest.objects.create(
            request_type=UnifiedRequestType.EXTRAS,
            status="completed",
            priority="normal",
            requester=self.provider_user,
            assigned_team_code="extras",
            assigned_team_name="فريق إدارة الخدمات الإضافية",
            assigned_user=self.staff_user,
            source_app="extras",
            source_model="ExtrasBundleRequest",
            source_object_id="bundle-notification-routing",
            summary="طلب خدمات إضافية مكتمل",
        )
        UnifiedRequestMetadata.objects.create(
            request=self.request_obj,
            payload={
                "bundle": {
                    "reports": {"options": ["platform_metrics"], "start_at": "", "end_at": ""},
                    "clients": {"options": ["scheduled_messages"], "subscription_years": 1},
                    "finance": {"options": ["invoice_exports"], "subscription_years": 1},
                }
            },
        )

    @patch("apps.extras.services._send_bundle_system_message", return_value=None)
    @patch("apps.notifications.services.create_notification")
    def test_bundle_completed_routes_notifications_to_section_specific_pref_keys(self, create_notification_mock, _send_message_mock):
        notify_bundle_completed(request_obj=self.request_obj, actor=self.staff_user)

        pref_keys = [call.kwargs.get("pref_key") for call in create_notification_mock.call_args_list]
        self.assertEqual(pref_keys, [
            "report_completed",
            "customer_service_package_completed",
            "finance_package_completed",
        ])
