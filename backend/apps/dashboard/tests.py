from django.test import TestCase
from django.urls import reverse

from apps.accounts.models import User, UserRole
from apps.billing.models import Invoice, InvoiceStatus
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.extras_portal.models import ExtrasPortalSubscription
from apps.providers.models import ProviderProfile
from apps.unified_requests.models import UnifiedRequest, UnifiedRequestMetadata, UnifiedRequestStatus, UnifiedRequestType


class DashboardExtrasSpecialistTests(TestCase):
    def setUp(self):
        self.staff = User.objects.create_user(
            phone="0503200001",
            username="extras.staff",
            password="pass1234",
            role_state=UserRole.STAFF,
        )
        self.staff.is_staff = True
        self.staff.is_superuser = True
        self.staff.save(update_fields=["is_staff", "is_superuser"])

        self.provider_user = User.objects.create_user(
            phone="0503200002",
            username="extras.target.provider",
            role_state=UserRole.PROVIDER,
        )
        ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود صالح",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.non_provider_user = User.objects.create_user(
            phone="0503200003",
            username="extras.target.member",
            role_state=UserRole.CLIENT,
        )

        self.client.force_login(self.staff)
        session = self.client.session
        session[SESSION_OTP_VERIFIED_KEY] = True
        session.save()

    def test_specialist_search_excludes_non_provider_users(self):
        response = self.client.get(
            reverse("dashboard:extras_specialist_search_api"),
            {"q": "extras.target"},
        )

        self.assertEqual(response.status_code, 200)
        rows = response.json().get("rows", [])
        self.assertEqual([row.get("username") for row in rows], [self.provider_user.username])

    def test_closing_bundle_request_requires_valid_provider_target(self):
        request_obj = UnifiedRequest.objects.create(
            request_type=UnifiedRequestType.EXTRAS,
            status=UnifiedRequestStatus.IN_PROGRESS,
            priority="normal",
            requester=self.non_provider_user,
            assigned_user=self.staff,
            source_app="extras",
            source_model="ExtrasBundleRequest",
            source_object_id="bundle-dashboard-1",
            summary="طلب باقة",
        )
        invoice = Invoice.objects.create(
            user=self.non_provider_user,
            title="فاتورة باقة",
            description="فاتورة",
            currency="SAR",
            subtotal="100.00",
            vat_percent="15.00",
            reference_type="extras_bundle_request",
            reference_id=request_obj.code,
            status=InvoiceStatus.PAID,
            payment_confirmed=True,
        )
        UnifiedRequestMetadata.objects.update_or_create(
            request=request_obj,
            defaults={
                "payload": {
                    "invoice_id": invoice.id,
                    "bundle": {
                        "reports": {"options": ["platform_metrics"]},
                        "clients": {"options": []},
                        "finance": {"options": []},
                    },
                },
                "updated_by": self.staff,
            },
        )

        response = self.client.post(
            reverse("dashboard:extras_dashboard"),
            {
                "action": "save_extras_request",
                "request_id": str(request_obj.id),
                "assigned_to": str(self.staff.id),
                "status": "closed",
                "operator_comment": "",
                "invoice_title": "",
                "invoice_description": "",
            },
        )

        request_obj.refresh_from_db()

        self.assertEqual(response.status_code, 302)
        self.assertEqual(request_obj.status, UnifiedRequestStatus.IN_PROGRESS)
        self.assertEqual(ExtrasPortalSubscription.objects.count(), 0)