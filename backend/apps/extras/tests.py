from datetime import timedelta

from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole
from apps.billing.models import Invoice, InvoiceStatus
from apps.extras_portal.models import LoyaltyMembership, LoyaltyProgram
from apps.providers.models import ProviderProfile
from apps.unified_requests.models import UnifiedRequest, UnifiedRequestMetadata, UnifiedRequestStatus, UnifiedRequestType

from .option_catalog import EXTRAS_CLIENT_OPTIONS
from .serializers import ExtrasBundleRequestInputSerializer
from .services import activate_bundle_portal_subscription_for_request, extras_bundle_invoice_for_request


class ExtrasBundleRequestValidationTests(TestCase):
    def test_reports_require_both_start_and_end_dates(self):
        serializer = ExtrasBundleRequestInputSerializer(
            data={
                "reports": {
                    "enabled": True,
                    "options": ["platform_metrics"],
                    "start_at": "2026-04-01",
                }
            }
        )

        self.assertFalse(serializer.is_valid())
        self.assertIn("end_at", serializer.errors["reports"])

    def test_reports_accept_specific_date_range(self):
        serializer = ExtrasBundleRequestInputSerializer(
            data={
                "reports": {
                    "enabled": True,
                    "options": ["platform_metrics"],
                    "start_at": "2026-04-01",
                    "end_at": "2026-04-30",
                }
            }
        )

        self.assertTrue(serializer.is_valid(), serializer.errors)

    def test_unimplemented_finance_options_are_rejected(self):
        serializer = ExtrasBundleRequestInputSerializer(
            data={
                "finance": {
                    "enabled": True,
                    "options": ["electronic_payments"],
                    "subscription_years": 1,
                }
            }
        )

        self.assertFalse(serializer.is_valid())
        self.assertIn("options", serializer.errors["finance"])

    def test_loyalty_points_is_merged_into_loyalty_program(self):
        self.assertIn(("loyalty_program", "برنامج الولاء ونقاط العملاء"), EXTRAS_CLIENT_OPTIONS)
        self.assertNotIn("loyalty_points", [key for key, _label in EXTRAS_CLIENT_OPTIONS])

        serializer = ExtrasBundleRequestInputSerializer(
            data={
                "clients": {
                    "enabled": True,
                    "options": ["loyalty_points"],
                    "subscription_years": 1,
                }
            }
        )

        self.assertTrue(serializer.is_valid(), serializer.errors)
        self.assertEqual(serializer.validated_data["clients"]["options"], ["loyalty_program"])


class ExtrasLoyaltyWalletTests(TestCase):
    def test_client_wallet_api_returns_membership_levels_and_rewards(self):
        client_user = User.objects.create_user(
            phone="0503100101",
            username="wallet.client",
            role_state=UserRole.CLIENT,
        )
        provider_user = User.objects.create_user(
            phone="0503100102",
            username="wallet.provider",
            role_state=UserRole.PROVIDER,
        )
        provider = ProviderProfile.objects.create(
            user=provider_user,
            provider_type="individual",
            display_name="مزود الولاء",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        program = LoyaltyProgram.objects.create(
            provider=provider,
            name="برنامج عملاء النخبة",
            points_per_completed_request=10,
            is_active=True,
        )
        LoyaltyMembership.objects.create(
            program=program,
            user=client_user,
            points_balance=140,
            total_earned=160,
            total_redeemed=20,
        )

        api = APIClient()
        api.force_authenticate(user=client_user)
        response = api.get(reverse("extras:loyalty_my"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["summary"]["total_balance"], 140)
        self.assertEqual(response.data["summary"]["best_level"]["label"], "فضي")
        self.assertEqual(response.data["memberships"][0]["provider_name"], "مزود الولاء")
        self.assertTrue(response.data["memberships"][0]["rewards"][0]["available"])
        self.assertEqual(response.data["memberships"][0]["level"]["next_label"], "ذهبي")


class ExtrasBundleInvoiceResolutionTests(TestCase):
    def test_prefers_paid_reference_invoice_over_stale_metadata_invoice(self):
        provider_user = User.objects.create_user(
            phone="0503100001",
            username="extras.invoice.provider",
            role_state=UserRole.PROVIDER,
        )
        ProviderProfile.objects.create(
            user=provider_user,
            provider_type="individual",
            display_name="مزود فواتير",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        request_obj = UnifiedRequest.objects.create(
            request_type=UnifiedRequestType.EXTRAS,
            status=UnifiedRequestStatus.IN_PROGRESS,
            priority="normal",
            requester=provider_user,
            source_app="extras",
            source_model="ExtrasBundleRequest",
            source_object_id="bundle-invoice-1",
            summary="طلب باقة",
        )
        stale_invoice = Invoice.objects.create(
            user=provider_user,
            title="فاتورة قديمة",
            description="فاتورة",
            currency="SAR",
            subtotal="100.00",
            vat_percent="15.00",
            reference_type="extras_bundle_request",
            reference_id=request_obj.code,
            status=InvoiceStatus.PENDING,
        )
        paid_invoice = Invoice.objects.create(
            user=provider_user,
            title="فاتورة مدفوعة",
            description="فاتورة",
            currency="SAR",
            subtotal="100.00",
            vat_percent="15.00",
            reference_type="extras_bundle_request",
            reference_id=request_obj.code,
            status=InvoiceStatus.PAID,
            payment_confirmed=True,
            payment_confirmed_at=timezone.now(),
        )
        UnifiedRequestMetadata.objects.update_or_create(
            request=request_obj,
            defaults={
                "payload": {
                    "invoice_id": stale_invoice.id,
                    "bundle": {
                        "reports": {"options": ["platform_metrics"]},
                        "clients": {"options": []},
                        "finance": {"options": []},
                    },
                },
                "updated_by": provider_user,
            },
        )

        resolved_invoice = extras_bundle_invoice_for_request(request_obj)

        self.assertEqual(getattr(resolved_invoice, "id", None), paid_invoice.id)


class ExtrasBundleActivationTests(TestCase):
    def test_activate_portal_subscription_targets_specialist_provider(self):
        requester = User.objects.create_user(
            phone="0503100002",
            username="extras.requester",
            role_state=UserRole.CLIENT,
        )
        provider_user = User.objects.create_user(
            phone="0503100003",
            username="extras.specialist",
            role_state=UserRole.PROVIDER,
        )
        provider = ProviderProfile.objects.create(
            user=provider_user,
            provider_type="individual",
            display_name="مزود التفعيل",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        request_obj = UnifiedRequest.objects.create(
            request_type=UnifiedRequestType.EXTRAS,
            status=UnifiedRequestStatus.CLOSED,
            priority="normal",
            requester=requester,
            source_app="extras",
            source_model="ExtrasBundleRequest",
            source_object_id="bundle-activation-1",
            summary="طلب باقة",
        )
        paid_at = timezone.now() - timedelta(hours=2)
        invoice = Invoice.objects.create(
            user=requester,
            title="فاتورة باقة",
            description="فاتورة",
            currency="SAR",
            subtotal="100.00",
            vat_percent="15.00",
            reference_type="extras_bundle_request",
            reference_id=request_obj.code,
            status=InvoiceStatus.PAID,
            payment_confirmed=True,
            payment_confirmed_at=paid_at,
        )
        UnifiedRequestMetadata.objects.update_or_create(
            request=request_obj,
            defaults={
                "payload": {
                    "invoice_id": invoice.id,
                    "specialist_identifier": provider_user.username,
                    "bundle": {
                        "reports": {
                            "options": ["platform_metrics"],
                            "start_at": (paid_at - timedelta(days=1)).isoformat(),
                            "end_at": (paid_at + timedelta(days=30)).isoformat(),
                        },
                        "clients": {"options": []},
                        "finance": {"options": []},
                    },
                },
                "updated_by": requester,
            },
        )

        subscription = activate_bundle_portal_subscription_for_request(request_obj=request_obj)

        self.assertIsNotNone(subscription)
        self.assertEqual(getattr(subscription, "provider_id", None), provider.id)
        self.assertEqual(getattr(subscription, "started_at", None), paid_at)
