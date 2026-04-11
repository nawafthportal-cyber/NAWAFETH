from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import patch
from urllib.parse import urlsplit

from django.contrib.auth import get_user_model
from django.contrib.sessions.middleware import SessionMiddleware
from django.core.files.uploadedfile import SimpleUploadedFile
from django.db import OperationalError
from django.db.models import Q
from django.test import Client
from django.test import RequestFactory, SimpleTestCase, TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import UserRole
from apps.backoffice.models import AccessLevel, AccessPermission, Dashboard, UserAccessProfile
from apps.billing.models import Invoice, InvoiceStatus, PaymentAttempt
from apps.core.models import PlatformConfig
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.extras.models import ExtraPurchase, ExtraPurchaseStatus, ExtraType, ExtrasBundlePricingRule
from apps.extras.services import extras_bundle_invoice_for_request
from apps.extras_portal.models import ExtrasPortalSubscription, ExtrasPortalSubscriptionStatus
from apps.messaging.models import Message, Thread
from apps.promo.models import PromoAdType, PromoOpsStatus, PromoRequest, PromoRequestItem, PromoRequestStatus, PromoServiceType
from apps.providers.models import ProviderProfile, ProviderSpotlightItem
from apps.subscriptions.models import PlanPeriod, PlanTier, Subscription, SubscriptionInquiryProfile, SubscriptionPlan, SubscriptionStatus
from apps.support.models import SupportPriority, SupportTeam, SupportTicket, SupportTicketEntrypoint, SupportTicketStatus, SupportTicketType
from apps.unified_requests.models import UnifiedRequest, UnifiedRequestMetadata, UnifiedRequestType
from apps.verification.models import VerificationRequest

from .views import (
    PROMO_MODULE_SUBMIT_TOKENS_SESSION_KEY,
    _consume_single_use_submit_token,
    _issue_single_use_submit_token,
    _promo_quote_snapshot,
)
from .forms import AccessProfileForm


class DashboardNavAccessResilienceTests(SimpleTestCase):
    def setUp(self):
        self.factory = RequestFactory()

    def test_non_dashboard_paths_skip_nav_access_lookup(self):
        request = self.factory.get("/provider-dashboard/")
        request.user = SimpleNamespace(is_authenticated=True)

        with patch("apps.dashboard.context_processors.dashboard_allowed", side_effect=AssertionError("should not be called")):
            from .context_processors import dashboard_nav_access

            payload = dashboard_nav_access(request)

        self.assertEqual(payload, {"dashboard_nav_access": {}, "dashboard_main_nav_items": []})


class DashboardSingleUseSubmitTokenTests(TestCase):
    def setUp(self):
        self.factory = RequestFactory()
        self.session_middleware = SessionMiddleware(lambda request: None)

    def _build_request(self):
        request = self.factory.post("/dashboard/promo/modules/snapshots/")
        self.session_middleware.process_request(request)
        request.session.save()
        return request

    def test_cache_claim_rejects_token_already_claimed_by_parallel_submit(self):
        request = self._build_request()
        token = _issue_single_use_submit_token(request, PROMO_MODULE_SUBMIT_TOKENS_SESSION_KEY)

        with patch("apps.dashboard.views.cache.add", return_value=False):
            consumed = _consume_single_use_submit_token(
                request,
                PROMO_MODULE_SUBMIT_TOKENS_SESSION_KEY,
                token,
            )

        self.assertFalse(consumed)
        self.assertNotIn(token, request.session.get(PROMO_MODULE_SUBMIT_TOKENS_SESSION_KEY, []))

    def test_dashboard_paths_fall_back_when_database_is_unavailable(self):
        request = self.factory.get("/dashboard/verification/")
        request.user = SimpleNamespace(is_authenticated=True)

        with patch("apps.dashboard.context_processors.dashboard_allowed", side_effect=OperationalError("db down")):
            from .context_processors import dashboard_nav_access

            payload = dashboard_nav_access(request)

        self.assertEqual(payload, {"dashboard_nav_access": {}, "dashboard_main_nav_items": []})


class AdminControlAccessProfileSaveTests(TestCase):
    def setUp(self):
        self.staff_user = get_user_model().objects.create_user(
            phone="0500000300",
            password="secret123",
            username="adminctrl01",
            is_staff=True,
            is_active=True,
        )
        UserAccessProfile.objects.create(user=self.staff_user, level=AccessLevel.ADMIN)

        Dashboard.objects.update_or_create(
            code="support",
            defaults={"name_ar": "الدعم", "is_active": True, "sort_order": 1},
        )
        Dashboard.objects.update_or_create(
            code="promo",
            defaults={"name_ar": "الترويج", "is_active": True, "sort_order": 2},
        )
        AccessPermission.objects.update_or_create(
            code="support.manage",
            defaults={"name_ar": "إدارة الدعم", "dashboard_code": "support", "is_active": True, "sort_order": 1},
        )
        AccessPermission.objects.update_or_create(
            code="support.view",
            defaults={"name_ar": "عرض الدعم", "dashboard_code": "support", "is_active": True, "sort_order": 2},
        )
        AccessPermission.objects.update_or_create(
            code="promo.manage",
            defaults={"name_ar": "إدارة الترويج", "dashboard_code": "promo", "is_active": True, "sort_order": 3},
        )

        self.client.force_login(self.staff_user)
        session = self.client.session
        session[SESSION_OTP_VERIFIED_KEY] = True
        session.save()

    def test_save_user_persists_selected_permissions_subset_for_user_level(self):
        response = self.client.post(
            reverse("dashboard:admin_control_home"),
            {
                "action": "save_user",
                "username": "accessusr1",
                "mobile_number": "0500000301",
                "level": AccessLevel.USER,
                "dashboards": ["support"],
                "permissions": ["support.view"],
                "password": "secret1234",
            },
            follow=True,
        )

        self.assertEqual(response.status_code, 200)
        created_profile = UserAccessProfile.objects.select_related("user").get(user__phone="0500000301")
        self.assertEqual(created_profile.level, AccessLevel.USER)
        self.assertEqual(
            list(created_profile.allowed_dashboards.values_list("code", flat=True)),
            ["support"],
        )
        self.assertEqual(
            list(created_profile.granted_permissions.values_list("code", flat=True)),
            ["support.view"],
        )

    def test_save_user_rejects_permission_outside_selected_dashboard(self):
        response = self.client.post(
            reverse("dashboard:admin_control_home"),
            {
                "action": "save_user",
                "username": "accessusr2",
                "mobile_number": "0500000302",
                "level": AccessLevel.USER,
                "dashboards": ["support"],
                "permissions": ["promo.manage"],
                "password": "secret1234",
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertFalse(UserAccessProfile.objects.filter(user__phone="0500000302").exists())
        form = response.context["access_form"]
        self.assertIn("permissions", form.errors)
        self.assertIn("لا تنتمي إلى اللوحات المحددة", form.errors["permissions"][0])

    def test_save_user_rejects_invalid_mobile_for_new_profile(self):
        response = self.client.post(
            reverse("dashboard:admin_control_home"),
            {
                "action": "save_user",
                "username": "accessusr3",
                "mobile_number": "966500000303",
                "level": AccessLevel.USER,
                "dashboards": ["support"],
                "permissions": ["support.view"],
                "password": "secret1234",
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertFalse(UserAccessProfile.objects.filter(user__phone="966500000303").exists())
        form = response.context["access_form"]
        self.assertIn("mobile_number", form.errors)
        self.assertIn("10 خانات", form.errors["mobile_number"][0])


class AccessProfileFormCatalogBootstrapTests(TestCase):
    def test_form_bootstraps_dashboards_and_permissions_when_catalog_missing(self):
        Dashboard.objects.all().delete()
        AccessPermission.objects.all().delete()

        form = AccessProfileForm()

        self.assertGreater(len(form.fields["dashboards"].choices), 0)
        self.assertGreater(len(form.fields["permissions"].choices), 0)
        self.assertTrue(Dashboard.objects.filter(code="admin_control", is_active=True).exists())
        self.assertTrue(AccessPermission.objects.filter(code="admin_control.manage_access", is_active=True).exists())


class PromoDashboardDuplicateSaveTests(TestCase):
    def setUp(self):
        self.staff_user = get_user_model().objects.create_user(
            phone="0500000100",
            password="secret",
            is_staff=True,
        )
        UserAccessProfile.objects.create(user=self.staff_user, level=AccessLevel.ADMIN)

        self.requester = get_user_model().objects.create_user(phone="0500000101", password="secret")
        self.promo_request = PromoRequest.objects.create(
            requester=self.requester,
            title="طلب ترويج تجريبي",
            ad_type=PromoAdType.BANNER_HOME,
            start_at=timezone.now() + timezone.timedelta(days=1),
            end_at=timezone.now() + timezone.timedelta(days=5),
            status=PromoRequestStatus.NEW,
            ops_status=PromoOpsStatus.NEW,
        )

        self.client.force_login(self.staff_user)
        session = self.client.session
        session[SESSION_OTP_VERIFIED_KEY] = True
        session.save()

    def test_duplicate_save_post_is_ignored_after_first_submission(self):
        detail_url = reverse("dashboard:promo_request_detail", kwargs={"request_id": self.promo_request.id})
        response = self.client.get(detail_url)
        self.assertEqual(response.status_code, 200)

        form_token = response.context["promo_request_form_token"]
        payload = {
            "action": "save_request",
            "promo_request_id": str(self.promo_request.id),
            "promo_form_token": form_token,
            "assigned_to": "",
            "ops_status": PromoOpsStatus.NEW,
            "ops_note": "",
            "redirect_query": f"request={self.promo_request.id}",
        }

        first_response = self.client.post(detail_url, payload, follow=True)
        first_messages = [str(message) for message in first_response.context["messages"]]
        self.assertTrue(any("تم تحديث طلب الترويج" in message for message in first_messages))

        second_response = self.client.post(detail_url, payload, follow=True)
        second_messages = [str(message) for message in second_response.context["messages"]]
        self.assertTrue(any("تم تجاهل محاولة الحفظ المكررة" in message for message in second_messages))


@override_settings(
    STORAGES={
        "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
        "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"},
    }
)
class PromoModuleDuplicateSubmitTests(TestCase):
    def setUp(self):
        self.staff_user = get_user_model().objects.create_user(
            phone="0500000200",
            password="secret",
            is_staff=True,
        )
        UserAccessProfile.objects.create(user=self.staff_user, level=AccessLevel.ADMIN)

        self.requester = get_user_model().objects.create_user(
            phone="0500000201",
            password="secret",
            role_state="provider",
        )
        self.provider_profile = ProviderProfile.objects.create(
            user=self.requester,
            provider_type="individual",
            display_name="مختص تجريبي",
            bio="نبذة مختصرة",
        )
        self.spotlight_item = ProviderSpotlightItem.objects.create(
            provider=self.provider_profile,
            file_type="image",
            file=SimpleUploadedFile("spotlight.jpg", b"spotlight-image", content_type="image/jpeg"),
            caption="لمحة تجريبية",
        )
        self.promo_request = PromoRequest.objects.create(
            requester=self.requester,
            title="طلب ترويج مميز",
            ad_type=PromoAdType.FEATURED_TOP5,
            start_at=timezone.now() + timezone.timedelta(days=1),
            end_at=timezone.now() + timezone.timedelta(days=5),
            status=PromoRequestStatus.NEW,
            ops_status=PromoOpsStatus.NEW,
        )

        self.client.force_login(self.staff_user)
        session = self.client.session
        session[SESSION_OTP_VERIFIED_KEY] = True
        session.save()

    def test_duplicate_module_approve_creates_single_item(self):
        module_url = reverse("dashboard:promo_module", kwargs={"module_key": "featured_specialists"})
        response = self.client.get(f"{module_url}?request_id={self.promo_request.id}")
        self.assertEqual(response.status_code, 200)

        form_token = response.context["promo_module_form_token"]
        payload = {
            "workflow_action": "approve_item",
            "promo_module_form_token": form_token,
            "request_id": str(self.promo_request.id),
            "title": "تمييز مختص",
            "start_at": timezone.localtime(self.promo_request.start_at).strftime("%Y-%m-%dT%H:%M"),
            "end_at": timezone.localtime(self.promo_request.end_at).strftime("%Y-%m-%dT%H:%M"),
            "target_provider_id": str(self.provider_profile.id),
        }

        first_response = self.client.post(module_url, payload, follow=True)
        first_messages = [str(message) for message in first_response.context["messages"]]
        self.assertTrue(any("تم اعتماد" in message for message in first_messages))

        second_response = self.client.post(module_url, payload, follow=True)
        second_messages = [str(message) for message in second_response.context["messages"]]
        self.assertTrue(any("تم تجاهل محاولة" in message for message in second_messages))

        self.assertEqual(
            PromoRequestItem.objects.filter(
                request=self.promo_request,
                service_type="featured_specialists",
            ).count(),
            1,
        )

    def test_duplicate_snapshots_save_creates_single_item(self):
        module_url = reverse("dashboard:promo_module", kwargs={"module_key": "snapshots"})
        response = self.client.get(f"{module_url}?request_id={self.promo_request.id}")
        self.assertEqual(response.status_code, 200)

        form_token = response.context["promo_module_form_token"]
        payload = {
            "workflow_action": "approve_item",
            "promo_module_form_token": form_token,
            "request_id": str(self.promo_request.id),
            "title": "شريط اللمحات",
            "start_at": timezone.localtime(self.promo_request.start_at).strftime("%Y-%m-%dT%H:%M"),
            "end_at": timezone.localtime(self.promo_request.end_at).strftime("%Y-%m-%dT%H:%M"),
            "target_provider_id": str(self.provider_profile.id),
            "target_spotlight_item_id": str(self.spotlight_item.id),
        }

        first_response = self.client.post(module_url, payload, follow=True)
        first_messages = [str(message) for message in first_response.context["messages"]]
        self.assertTrue(any("تم اعتماد" in message for message in first_messages))

        second_response = self.client.post(module_url, payload, follow=True)
        second_messages = [str(message) for message in second_response.context["messages"]]
        self.assertTrue(any("تم تجاهل محاولة" in message for message in second_messages))

        created_items = PromoRequestItem.objects.filter(
            request=self.promo_request,
            service_type="snapshots",
        )
        self.assertEqual(created_items.count(), 1)
        self.assertEqual(created_items.first().target_spotlight_item_id, self.spotlight_item.id)


class PromoVatSnapshotTests(TestCase):
    def test_quote_snapshot_uses_platform_promo_vat_percent(self):
        config, _ = PlatformConfig.objects.get_or_create(pk=1)
        config.promo_vat_percent = Decimal("18.00")
        config.save()

        requester = get_user_model().objects.create_user(phone="0500000202", password="secret")
        promo_request = PromoRequest.objects.create(
            requester=requester,
            title="طلب ترويج ضريبة",
            ad_type=PromoAdType.BANNER_HOME,
            start_at=timezone.now() + timezone.timedelta(days=1),
            end_at=timezone.now() + timezone.timedelta(days=4),
            status=PromoRequestStatus.NEW,
            ops_status=PromoOpsStatus.NEW,
        )

        snapshot = _promo_quote_snapshot(promo_request)

        self.assertIsNotNone(snapshot)
        self.assertEqual(snapshot["vat_percent"], Decimal("18.00"))
        expected_vat = (snapshot["subtotal"] * Decimal("18.00") / Decimal("100")).quantize(Decimal("0.01"))
        self.assertEqual(snapshot["vat_amount"], expected_vat)
        self.assertEqual(snapshot["total"], (snapshot["subtotal"] + expected_vat).quantize(Decimal("0.01")))


class PromoDashboardStatusDisplayTests(TestCase):
    def setUp(self):
        self.staff_user = get_user_model().objects.create_user(
            phone="0500000250",
            password="secret",
            is_staff=True,
        )
        UserAccessProfile.objects.create(user=self.staff_user, level=AccessLevel.ADMIN)

        self.requester = get_user_model().objects.create_user(phone="0500000251", password="secret")
        self.invoice = Invoice.objects.create(
            user=self.requester,
            title="فاتورة ترويج",
            reference_type="promo_request",
            subtotal=Decimal("1000.00"),
            vat_percent=Decimal("15.00"),
        )
        self.promo_request = PromoRequest.objects.create(
            requester=self.requester,
            title="طلب ترويج مدفوع",
            ad_type=PromoAdType.FEATURED_TOP5,
            start_at=timezone.now() + timezone.timedelta(days=1),
            end_at=timezone.now() + timezone.timedelta(days=5),
            status=PromoRequestStatus.PENDING_PAYMENT,
            ops_status=PromoOpsStatus.NEW,
            invoice=self.invoice,
        )
        self.invoice.reference_id = self.promo_request.code
        self.invoice.mark_payment_confirmed(
            provider="mock",
            provider_reference="promo-dashboard-test",
            event_id=f"promo-dashboard-{self.promo_request.pk}",
            amount=Decimal("1150.00"),
            currency="SAR",
        )
        self.invoice.save()

        self.client.force_login(self.staff_user)
        session = self.client.session
        session[SESSION_OTP_VERIFIED_KEY] = True
        session.save()

    def test_paid_promo_request_shows_awaiting_review_in_dashboard_detail(self):
        response = self.client.get(reverse("dashboard:promo_request_detail", kwargs={"request_id": self.promo_request.id}))

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "حالة الطلب: بانتظار المراجعة")
        self.assertNotContains(response, "حالة الطلب: بانتظار الدفع")


class DashboardInlineDetailRenderingTests(TestCase):
    def setUp(self):
        self.staff_user = get_user_model().objects.create_user(
            phone="0500000255",
            password="secret",
            is_staff=True,
        )
        UserAccessProfile.objects.create(user=self.staff_user, level=AccessLevel.ADMIN)

        self.requester = get_user_model().objects.create_user(phone="0500000256", password="secret")
        self.support_team, _ = SupportTeam.objects.get_or_create(
            code="support",
            defaults={"name_ar": "الدعم والمساعدة", "is_active": True},
        )

        self.support_ticket = SupportTicket.objects.create(
            requester=self.requester,
            ticket_type=SupportTicketType.TECH,
            status=SupportTicketStatus.IN_PROGRESS,
            priority=SupportPriority.NORMAL,
            entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
            description="تذكرة دعم لاختبار العرض المضمن",
            assigned_team=self.support_team,
            assigned_to=self.staff_user,
            assigned_at=timezone.now(),
        )
        self.promo_request = PromoRequest.objects.create(
            requester=self.requester,
            assigned_to=self.staff_user,
            assigned_at=timezone.now(),
            title="طلب ترويج لاختبار العرض المضمن",
            ad_type=PromoAdType.BANNER_HOME,
            start_at=timezone.now() + timezone.timedelta(days=1),
            end_at=timezone.now() + timezone.timedelta(days=3),
            status=PromoRequestStatus.NEW,
            ops_status=PromoOpsStatus.NEW,
        )

        self.client.force_login(self.staff_user)
        session = self.client.session
        session[SESSION_OTP_VERIFIED_KEY] = True
        session.save()

    def test_support_dashboard_renders_selected_ticket_details_inline(self):
        response = self.client.get(f"{reverse('dashboard:support_dashboard')}?ticket={self.support_ticket.id}")

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, f'id="support-ticket-{self.support_ticket.id}"', html=False)
        self.assertContains(response, "dash-inline-detail-row", html=False)
        self.assertContains(response, f"تفاصيل الطلب: {self.support_ticket.code}")
        self.assertContains(response, "إغلاق العرض")

    def test_promo_dashboard_renders_selected_request_details_inline(self):
        response = self.client.get(f"{reverse('dashboard:promo_dashboard')}?request={self.promo_request.id}")

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, f'id="promo-request-{self.promo_request.id}"', html=False)
        self.assertContains(response, "dash-inline-detail-row", html=False)
        self.assertContains(response, f"تفاصيل طلب الترويج: {self.promo_request.code}")
        self.assertContains(response, "حالة التنفيذ")


class ExtrasDashboardTests(TestCase):
    def setUp(self):
        self.staff_user = get_user_model().objects.create_user(
            phone="0500000280",
            password="secret",
            is_staff=True,
        )
        UserAccessProfile.objects.create(user=self.staff_user, level=AccessLevel.ADMIN)

        self.requester = get_user_model().objects.create_user(
            phone="0500000281",
            username="extras_provider",
            password="secret",
        )
        self.requester_provider_profile = ProviderProfile.objects.create(
            user=self.requester,
            provider_type="individual",
            display_name="مزود خدمات إضافية",
            bio="نبذة اختبارية",
            years_experience=5,
        )
        self.specialist = get_user_model().objects.create_user(
            phone="0500000282",
            username="extras_specialist",
            password="secret",
            role_state=UserRole.CLIENT,
        )
        self.request_owner = get_user_model().objects.create_user(
            phone="0500000283",
            username="extras_request_owner",
            password="secret",
            role_state=UserRole.CLIENT,
        )
        self.pro_plan = SubscriptionPlan.objects.create(
            code="extras_pro_month",
            tier=PlanTier.PRO,
            title="الباقة الاحترافية",
            period=PlanPeriod.MONTH,
            price="299.00",
        )
        Subscription.objects.create(
            user=self.requester,
            plan=self.pro_plan,
            status=SubscriptionStatus.ACTIVE,
            start_at=timezone.now() - timezone.timedelta(days=2),
            end_at=timezone.now() + timezone.timedelta(days=28),
        )
        self.extras_team, _ = SupportTeam.objects.get_or_create(
            code="extras",
            defaults={
                "name_ar": "فريق إدارة الخدمات الإضافية",
                "is_active": True,
            },
        )

        self.extras_inquiry = SupportTicket.objects.create(
            requester=self.requester,
            ticket_type=SupportTicketType.EXTRAS,
            status=SupportTicketStatus.NEW,
            priority=SupportPriority.NORMAL,
            entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
            description="استفسار حول تفعيل خدمة إضافية",
            assigned_team=self.extras_team,
            assigned_to=self.staff_user,
            assigned_at=timezone.now(),
        )

        self.invoice = Invoice.objects.create(
            user=self.requester,
            title="فاتورة خدمة إضافية",
            reference_type="extra_purchase",
            reference_id="1",
            subtotal=Decimal("100.00"),
            vat_percent=Decimal("15.00"),
            status=InvoiceStatus.PENDING,
        )
        self.extra_purchase = ExtraPurchase.objects.create(
            user=self.requester,
            sku="tickets_100",
            title="تذكرة خدمات إضافية",
            extra_type=ExtraType.CREDIT_BASED,
            subtotal=Decimal("100.00"),
            currency="SAR",
            status=ExtraPurchaseStatus.PENDING_PAYMENT,
            invoice=self.invoice,
            credits_total=100,
            credits_used=0,
        )
        self.extra_request = UnifiedRequest.objects.create(
            request_type=UnifiedRequestType.EXTRAS,
            status="new",
            priority="normal",
            requester=self.requester,
            assigned_team_code="extras",
            assigned_team_name="فريق إدارة الخدمات الإضافية",
            source_app="extras",
            source_model="ExtraPurchase",
            source_object_id=str(self.extra_purchase.id),
            summary=self.extra_purchase.title,
        )

        self.client.force_login(self.staff_user)
        session = self.client.session
        session[SESSION_OTP_VERIFIED_KEY] = True
        session.save()

    def _create_bundle_request(self, *, requester_user=None, specialist_user=None):
        requester_user = requester_user or self.requester
        specialist_user = specialist_user or self.specialist
        request_obj = UnifiedRequest.objects.create(
            request_type=UnifiedRequestType.EXTRAS,
            status="new",
            priority="normal",
            requester=requester_user,
            assigned_team_code="extras",
            assigned_team_name="فريق إدارة الخدمات الإضافية",
            assigned_user=self.staff_user,
            source_app="extras",
            source_model="ExtrasBundleRequest",
            source_object_id=f"bundle-{UnifiedRequest.objects.count() + 1}",
            summary="طلب خدمات إضافية - التقارير / إدارة العملاء",
        )
        UnifiedRequestMetadata.objects.create(
            request=request_obj,
            payload={
                "specialist_identifier": specialist_user.username or specialist_user.phone,
                "specialist_label": specialist_user.username or specialist_user.phone,
                "bundle": {
                    "reports": {
                        "enabled": True,
                        "options": ["platform_metrics"],
                        "start_at": "2026-04-01",
                        "end_at": "2026-04-10",
                    },
                    "clients": {
                        "enabled": True,
                        "options": ["platform_clients_list"],
                        "subscription_years": 2,
                        "bulk_message_count": 500,
                    },
                    "finance": {
                        "enabled": False,
                        "options": [],
                        "subscription_years": 1,
                    },
                    "summary_sections": [
                        {"key": "reports", "title": "التقارير", "items": ["مؤشرات المنصة"]},
                        {"key": "clients", "title": "إدارة العملاء", "items": ["قوائم عملاء منصتي"]},
                        {"key": "finance", "title": "الإدارة المالية", "items": []},
                    ],
                    "notes": "يرجى البدء فور اعتماد السداد.",
                }
            },
        )
        return request_obj

    def _create_bundle_pricing_rules(self):
        ExtrasBundlePricingRule.objects.create(
            section_key="reports",
            option_key="platform_metrics",
            fee=Decimal("75.00"),
            currency="SAR",
            is_active=True,
            sort_order=1,
        )

    def _reload_request_with_metadata(self, request_obj):
        return UnifiedRequest.objects.select_related("metadata_record", "requester", "assigned_user").get(pk=request_obj.pk)

    def _bundle_system_thread_for(self, recipient):
        return (
            Thread.objects.filter(
                is_direct=True,
                is_system_thread=True,
                system_thread_key="extras_bundle",
            )
            .filter(
                Q(participant_1=self.staff_user, participant_2=recipient)
                | Q(participant_1=recipient, participant_2=self.staff_user)
            )
            .order_by("-id")
            .first()
        )
        ExtrasBundlePricingRule.objects.create(
            section_key="clients",
            option_key="platform_clients_list",
            fee=Decimal("120.00"),
            currency="SAR",
            apply_year_multiplier=True,
            is_active=True,
            sort_order=1,
        )

    def test_extras_dashboard_renders_selected_inquiry_details_inline(self):
        response = self.client.get(f"{reverse('dashboard:extras_dashboard')}?inquiry={self.extras_inquiry.id}")

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, f'id="extras-inquiry-{self.extras_inquiry.id}"', html=False)
        self.assertContains(response, "dash-inline-detail-row", html=False)
        self.assertContains(response, f"تفاصيل الاستفسار: {self.extras_inquiry.code}")

    def test_extras_dashboard_sidebar_shows_extras_submenu_items(self):
        response = self.client.get(reverse("dashboard:extras_dashboard"))

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "التقارير")
        self.assertContains(response, "إدارة العملاء")
        self.assertContains(response, "الإدارة المالية")
        self.assertContains(response, "بيانات مشتركي الخدمات الإضافية")

    def test_extras_dashboard_reports_section_renders_management_page(self):
        response = self.client.get(f"{reverse('dashboard:extras_dashboard')}?section=reports")

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "لوحة التحكم للتقارير")
        self.assertContains(response, "بداية التقرير")
        self.assertContains(response, "نهاية التقرير")
        self.assertContains(response, "تفعيل خيارات الإحصاءات والتقارير المطلوبة")
        self.assertNotContains(response, "قائمة استفسارات الخدمات الإضافية")

    def test_extras_dashboard_reports_section_can_save_report_options(self):
        specialist_identifier = self.requester.username or self.requester.phone or ""

        response = self.client.post(
            reverse("dashboard:extras_dashboard"),
            {
                "action": "save_extras_bundle_reports",
                "redirect_section": "reports",
                "specialist_identifier": specialist_identifier,
                "reports_options": ["platform_metrics", "platform_visits"],
                "reports_start_at": "2026-10-25T19:40",
                "reports_end_at": "2026-10-26T19:40",
            },
        )

        self.assertEqual(response.status_code, 302)
        self.assertIn("section=reports", response["Location"])
        session_payload = self.client.session.get("dashboard_extras_bundle_draft", {})
        self.assertEqual(session_payload.get("specialist_identifier"), specialist_identifier)
        self.assertEqual(session_payload.get("reports", {}).get("options"), ["platform_metrics", "platform_visits"])
        self.assertTrue(session_payload.get("reports", {}).get("start_at"))
        self.assertTrue(session_payload.get("reports", {}).get("end_at"))

    def test_extras_dashboard_clients_section_renders_management_page(self):
        response = self.client.get(f"{reverse('dashboard:extras_dashboard')}?section=clients")

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "بيانات اعتماد الخدمة")
        self.assertContains(response, "الخدمات المطلوبة")
        self.assertContains(response, "اعتماد")
        self.assertContains(response, "إلغاء")

    def test_extras_dashboard_finance_section_renders_management_page(self):
        response = self.client.get(f"{reverse('dashboard:extras_dashboard')}?section=finance")

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "الإدارة المالية")
        self.assertContains(response, "مدة الاشتراك (بالسنوات)")
        self.assertContains(response, "IBAN")
        self.assertContains(response, "خيارات باقة الخدمات المالية المعتمدة")

    def test_extras_dashboard_finance_section_can_save_finance_options(self):
        specialist_identifier = self.requester.username or self.requester.phone or ""

        response = self.client.post(
            reverse("dashboard:extras_dashboard"),
            {
                "action": "save_extras_bundle_finance",
                "redirect_section": "finance",
                "specialist_identifier": specialist_identifier,
                "finance_subscription_years": "1",
                "finance_qr_first_name": "أحمد",
                "finance_qr_last_name": "محمد",
                "finance_iban": "sa03 8000 0000 6080 1016 7519",
                "finance_options": ["bank_qr_registration", "electronic_payments"],
            },
        )

        self.assertEqual(response.status_code, 302)
        self.assertIn("section=finance", response["Location"])
        session_payload = self.client.session.get("dashboard_extras_bundle_draft", {})
        finance_payload = session_payload.get("finance", {})
        self.assertEqual(finance_payload.get("subscription_years"), 1)
        self.assertEqual(finance_payload.get("qr_first_name"), "أحمد")
        self.assertEqual(finance_payload.get("qr_last_name"), "محمد")
        self.assertEqual(finance_payload.get("iban"), "SA0380000000608010167519")
        self.assertEqual(finance_payload.get("options"), ["bank_qr_registration", "electronic_payments"])

    def test_extras_dashboard_subscribers_section_renders_management_page(self):
        response = self.client.get(f"{reverse('dashboard:extras_dashboard')}?section=subscribers")

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "بيانات مشتركي الخدمات الإضافية")
        self.assertContains(response, "ابحث باسم العميل أو رقم الطلب أو اسم الخدمة")
        self.assertNotContains(response, "تم فصل هذه الصفحة عن الصفحة الرئيسية")
        self.assertNotContains(response, self.extra_purchase.title)

    def test_extras_dashboard_subscribers_section_uses_portal_subscription_rows_from_latest_closed_bundle_request(self):
        bundle_request = self._create_bundle_request()
        self._create_bundle_pricing_rules()

        self.client.post(
            reverse("dashboard:extras_dashboard"),
            {
                "action": "issue_extras_invoice",
                "request_id": str(bundle_request.id),
                "redirect_query": f"section=overview&request={bundle_request.id}",
                "status": "in_progress",
                "assigned_to": str(self.staff_user.id),
                "operator_comment": "إصدار فاتورة الطلب.",
                "invoice_line_title[]": ["تقارير إحصائية", "إدارة عملاء"],
                "invoice_line_amount[]": ["500.00", "300.00"],
            },
        )

        bundle_request = self._reload_request_with_metadata(bundle_request)
        invoice = Invoice.objects.get(id=bundle_request.metadata_record.payload.get("invoice_id"))
        invoice.mark_payment_confirmed(
            provider="mock",
            provider_reference=f"extras-bundle-{invoice.id}",
            event_id=f"extras-bundle-paid-{invoice.id}",
            amount=invoice.total,
            currency=invoice.currency,
        )
        invoice.save(
            update_fields=[
                "status",
                "paid_at",
                "cancelled_at",
                "payment_confirmed",
                "payment_confirmed_at",
                "payment_provider",
                "payment_reference",
                "payment_event_id",
                "payment_amount",
                "payment_currency",
                "updated_at",
            ]
        )

        self.client.post(
            reverse("dashboard:extras_dashboard"),
            {
                "action": "save_extras_request",
                "request_id": str(bundle_request.id),
                "redirect_query": f"section=overview&request={bundle_request.id}",
                "status": "closed",
                "assigned_to": str(self.staff_user.id),
                "operator_comment": "تم اكتمال التفعيل.",
            },
        )

        response = self.client.get(f"{reverse('dashboard:extras_dashboard')}?section=subscribers")

        self.assertEqual(response.status_code, 200)
        rows = response.context["extras_subscribers_rows"]
        self.assertEqual(len(rows), 2)
        self.assertEqual({row["service_key"] for row in rows}, {"reports", "clients"})
        self.assertEqual(response.context["subscribers_summary"]["active"], 2)
        self.assertContains(response, bundle_request.code)
        self.assertContains(response, "التقارير")
        self.assertContains(response, "إدارة العملاء")
        self.assertContains(response, "مدفوع ومعتمد")
        self.assertNotContains(response, self.extra_purchase.title)

        selected_reports_row = next(row for row in rows if row["service_key"] == "reports")
        detail_response = self.client.get(
            f"{reverse('dashboard:extras_dashboard')}?section=subscribers&subscriber={selected_reports_row['id']}"
        )

        self.assertEqual(detail_response.status_code, 200)
        self.assertContains(detail_response, f"تفاصيل الاشتراك: {bundle_request.code}")
        self.assertContains(detail_response, "مؤشرات المنصة")
        self.assertContains(detail_response, "تمت عملية السداد بنجاح")
        self.assertContains(detail_response, "إجراءات التجديد والحذف ستُربط")

    def test_extras_dashboard_uses_client_package_for_priority_number_and_color(self):
        response = self.client.get(reverse("dashboard:extras_dashboard"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.context["extras_inquiries"][0]["priority_number"], 3)
        self.assertEqual(response.context["extras_inquiries"][0]["priority_class"], "priority-3")
        self.assertEqual(response.context["extras_requests"][0]["priority_number"], 3)
        self.assertEqual(response.context["extras_requests"][0]["priority_class"], "priority-3")

    def test_extras_dashboard_can_save_request_details(self):
        response = self.client.post(
            reverse("dashboard:extras_dashboard"),
            {
                "action": "save_extras_request",
                "request_id": str(self.extra_request.id),
                "redirect_query": f"request={self.extra_request.id}",
                "status": "in_progress",
                "assigned_to": str(self.staff_user.id),
                "operator_comment": "تمت مراجعة الطلب والبدء في التنفيذ",
            },
        )

        self.assertEqual(response.status_code, 302)
        self.assertIn("#extrasRequests", response["Location"])

        self.extra_request.refresh_from_db()
        self.assertEqual(self.extra_request.status, "in_progress")
        self.assertEqual(self.extra_request.assigned_user_id, self.staff_user.id)
        self.assertEqual(self.extra_request.assigned_team_code, "extras")
        self.assertTrue(hasattr(self.extra_request, "metadata_record"))
        self.assertEqual(
            self.extra_request.metadata_record.payload.get("operator_comment"),
            "تمت مراجعة الطلب والبدء في التنفيذ",
        )

    def test_extras_dashboard_save_request_does_not_issue_invoice_even_if_line_items_present(self):
        bundle_request = self._create_bundle_request()

        response = self.client.post(
            reverse("dashboard:extras_dashboard"),
            {
                "action": "save_extras_request",
                "request_id": str(bundle_request.id),
                "redirect_query": f"section=overview&request={bundle_request.id}",
                "status": "in_progress",
                "assigned_to": str(self.staff_user.id),
                "operator_comment": "بدء المعالجة والتسعير لاحقًا.",
                "invoice_line_title[]": ["تقارير شهرية"],
                "invoice_line_amount[]": ["500.00"],
            },
        )

        self.assertEqual(response.status_code, 302)
        bundle_request = self._reload_request_with_metadata(bundle_request)
        self.assertEqual(bundle_request.status, "in_progress")
        self.assertEqual(bundle_request.assigned_user_id, self.staff_user.id)
        self.assertFalse(bundle_request.metadata_record.payload.get("invoice_id"))
        self.assertIsNone(extras_bundle_invoice_for_request(bundle_request))

    def test_extras_dashboard_issue_invoice_action_saves_request_and_renders_invoice_details(self):
        bundle_request = self._create_bundle_request()

        response = self.client.post(
            reverse("dashboard:extras_dashboard"),
            {
                "action": "issue_extras_invoice",
                "request_id": str(bundle_request.id),
                "redirect_query": f"section=overview&request={bundle_request.id}",
                "status": "in_progress",
                "assigned_to": str(self.staff_user.id),
                "operator_comment": "إصدار فاتورة يدوية للطلب.",
                "invoice_title": "عرض سعر باقة التقارير وإدارة العملاء",
                "invoice_description": "يشمل إعداد لوحة التقارير وتجهيز قاعدة العملاء مع متابعة التنفيذ.",
                "invoice_line_title[]": ["تقارير شهرية", "إدارة قاعدة العملاء"],
                "invoice_line_amount[]": ["500.00", "300.00"],
            },
        )

        self.assertEqual(response.status_code, 302)
        self.assertIn("#extrasRequests", response["Location"])

        bundle_request = self._reload_request_with_metadata(bundle_request)
        self.assertEqual(bundle_request.status, "in_progress")
        self.assertEqual(bundle_request.assigned_user_id, self.staff_user.id)
        self.assertEqual(
            bundle_request.metadata_record.payload.get("operator_comment"),
            "إصدار فاتورة يدوية للطلب.",
        )

        invoice = Invoice.objects.get(id=bundle_request.metadata_record.payload.get("invoice_id"))
        self.assertEqual(invoice.lines.count(), 2)
        self.assertEqual(invoice.title, "عرض سعر باقة التقارير وإدارة العملاء")
        self.assertEqual(invoice.description, "يشمل إعداد لوحة التقارير وتجهيز قاعدة العملاء مع متابعة التنفيذ.")
        self.assertTrue(PaymentAttempt.objects.filter(invoice=invoice).exists())

        detail_response = self.client.get(
            f"{reverse('dashboard:extras_dashboard')}?section=overview&request={bundle_request.id}"
        )

        self.assertEqual(detail_response.status_code, 200)
        self.assertContains(detail_response, "تفاصيل الفاتورة")
        self.assertContains(detail_response, invoice.code)
        self.assertContains(detail_response, "عرض سعر باقة التقارير وإدارة العملاء")
        self.assertContains(detail_response, "يشمل إعداد لوحة التقارير وتجهيز قاعدة العملاء مع متابعة التنفيذ.")
        self.assertContains(detail_response, "تقارير شهرية")
        self.assertContains(detail_response, "إدارة قاعدة العملاء")
        self.assertContains(detail_response, "800.00 SAR")
        self.assertContains(detail_response, "120.00 SAR")
        self.assertContains(detail_response, "920.00 SAR")

    def test_extras_dashboard_new_request_status_choices_exclude_direct_completion(self):
        response = self.client.get(
            f"{reverse('dashboard:extras_dashboard')}?section=overview&request={self.extra_request.id}"
        )

        self.assertEqual(response.status_code, 200)
        form = response.context["selected_request_form"]
        self.assertEqual(
            [choice[0] for choice in form.fields["status"].choices],
            ["new", "in_progress"],
        )
        self.assertContains(response, "المتاح الآن: إبقاء الطلب جديدًا أو نقله إلى تحت المعالجة فقط.")

    def test_extras_dashboard_in_progress_request_status_choices_exclude_reverting_to_new(self):
        self.extra_request.status = "in_progress"
        self.extra_request.assigned_user = self.staff_user
        self.extra_request.save(update_fields=["status", "assigned_user", "assigned_at", "updated_at"])

        response = self.client.get(
            f"{reverse('dashboard:extras_dashboard')}?section=overview&request={self.extra_request.id}"
        )

        self.assertEqual(response.status_code, 200)
        form = response.context["selected_request_form"]
        self.assertEqual(
            [choice[0] for choice in form.fields["status"].choices],
            ["in_progress", "closed"],
        )
        self.assertContains(response, "المتاح الآن: إبقاء الطلب تحت المعالجة أو نقله إلى مكتمل فقط.")

    def test_extras_dashboard_blocks_direct_close_from_new_request(self):
        response = self.client.post(
            reverse("dashboard:extras_dashboard"),
            {
                "action": "save_extras_request",
                "request_id": str(self.extra_request.id),
                "redirect_query": f"section=overview&request={self.extra_request.id}",
                "status": "closed",
                "assigned_to": str(self.staff_user.id),
                "operator_comment": "محاولة إغلاق مباشرة.",
            },
            follow=True,
        )

        self.extra_request.refresh_from_db()
        self.assertEqual(self.extra_request.status, "new")
        self.assertContains(response, "المتاح الآن: إبقاء الطلب جديدًا أو نقله إلى تحت المعالجة فقط.")

    def test_extras_bundle_flow_creates_new_request_in_new_status(self):
        specialist_identifier = self.requester.username or self.requester.phone or ""

        save_reports_response = self.client.post(
            reverse("dashboard:extras_dashboard"),
            {
                "action": "save_extras_bundle_reports",
                "specialist_identifier": specialist_identifier,
                "reports_options": ["platform_metrics", "platform_visits"],
                "continue_to_summary": "1",
            },
        )
        self.assertEqual(save_reports_response.status_code, 302)
        self.assertIn("section=request_summary", save_reports_response["Location"])

        submit_response = self.client.post(
            reverse("dashboard:extras_dashboard"),
            {
                "action": "submit_extras_bundle_request",
                "specialist_identifier": specialist_identifier,
            },
        )
        self.assertEqual(submit_response.status_code, 302)
        self.assertIn("section=request_created", submit_response["Location"])

        created_request = (
            UnifiedRequest.objects.filter(
                request_type=UnifiedRequestType.EXTRAS,
                source_app="dashboard",
                source_model="ExtrasServiceRequest",
            )
            .order_by("-id")
            .first()
        )
        self.assertIsNotNone(created_request)
        self.assertEqual(created_request.status, "new")
        self.assertEqual(created_request.requester_id, self.requester.id)
        self.assertEqual(created_request.assigned_user_id, self.staff_user.id)
        self.assertTrue(hasattr(created_request, "metadata_record"))
        self.assertIn("platform_metrics", created_request.metadata_record.payload.get("reports", {}).get("options", []))

        requests_page = self.client.get(reverse('dashboard:extras_dashboard'))
        self.assertEqual(requests_page.status_code, 200)
        self.assertContains(requests_page, created_request.code)
        self.assertContains(requests_page, "جديد")

    def test_extras_dashboard_renders_bundle_request_details_with_durations_inline(self):
        bundle_request = self._create_bundle_request()

        response = self.client.get(
            f"{reverse('dashboard:extras_dashboard')}?section=overview&request={bundle_request.id}"
        )

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, f'id="extras-request-{bundle_request.id}"', html=False)
        self.assertContains(response, "البنود والخدمات المختارة")
        self.assertContains(response, "مؤشرات المنصة")
        self.assertContains(response, "من 01/04/2026 إلى 10/04/2026")
        self.assertContains(response, "قوائم عملاء منصتي")
        self.assertContains(response, "2 سنة")

    def test_extras_dashboard_issue_invoice_creates_bundle_invoice_and_sends_payment_message(self):
        bundle_request = self._create_bundle_request()

        response = self.client.post(
            reverse("dashboard:extras_dashboard"),
            {
                "action": "issue_extras_invoice",
                "request_id": str(bundle_request.id),
                "redirect_query": f"section=overview&request={bundle_request.id}",
                "status": "in_progress",
                "assigned_to": str(self.staff_user.id),
                "operator_comment": "تمت مراجعة الطلب وإصدار الفاتورة.",
                "invoice_line_title[]": ["تقارير إحصائية", "إدارة عملاء"],
                "invoice_line_amount[]": ["500.00", "300.00"],
            },
        )

        self.assertEqual(response.status_code, 302)
        bundle_request = self._reload_request_with_metadata(bundle_request)
        self.assertEqual(bundle_request.status, "in_progress")
        self.assertTrue(hasattr(bundle_request, "metadata_record"))
        invoice_id = bundle_request.metadata_record.payload.get("invoice_id")
        self.assertTrue(invoice_id)
        invoice = Invoice.objects.get(id=invoice_id)
        self.assertEqual(invoice.reference_type, "extras_bundle_request")
        self.assertEqual(invoice.lines.count(), 2)
        self.assertTrue(PaymentAttempt.objects.filter(invoice=invoice).exists())

        requester_thread = self._bundle_system_thread_for(self.requester)
        self.assertIsNotNone(requester_thread)
        self.assertEqual(requester_thread.participant_mode_for_user(self.requester), Thread.ContextMode.PROVIDER)
        self.assertTrue(
            Message.objects.filter(
                thread=requester_thread,
                body__icontains="رابط الدفع المباشر",
            ).filter(body__icontains=bundle_request.code).exists()
        )

        specialist_thread = self._bundle_system_thread_for(self.specialist)
        self.assertIsNotNone(specialist_thread)
        self.assertEqual(specialist_thread.participant_mode_for_user(self.specialist), Thread.ContextMode.CLIENT)
        self.assertTrue(
            Message.objects.filter(
                thread=specialist_thread,
                body__icontains="رابط الدفع المباشر",
            ).filter(body__icontains=bundle_request.code).exists()
        )

    def test_extras_dashboard_prevents_closing_bundle_request_before_payment(self):
        bundle_request = self._create_bundle_request()

        self.client.post(
            reverse("dashboard:extras_dashboard"),
            {
                "action": "issue_extras_invoice",
                "request_id": str(bundle_request.id),
                "redirect_query": f"section=overview&request={bundle_request.id}",
                "status": "in_progress",
                "assigned_to": str(self.staff_user.id),
                "operator_comment": "تمت المراجعة.",
                "invoice_line_title[]": ["تقارير إحصائية"],
                "invoice_line_amount[]": ["500.00"],
            },
        )

        close_response = self.client.post(
            reverse("dashboard:extras_dashboard"),
            {
                "action": "save_extras_request",
                "request_id": str(bundle_request.id),
                "redirect_query": f"section=overview&request={bundle_request.id}",
                "status": "closed",
                "assigned_to": str(self.staff_user.id),
                "operator_comment": "محاولة إغلاق قبل الدفع.",
            },
            follow=True,
        )

        bundle_request.refresh_from_db()
        self.assertEqual(bundle_request.status, "in_progress")
        self.assertContains(close_response, "لا يمكن تحويل الطلب إلى مكتمل قبل اعتماد السداد فعليًا")

    def test_extras_dashboard_uses_requester_as_invoice_owner_when_request_owner_differs(self):
        bundle_request = self._create_bundle_request(
            requester_user=self.request_owner,
            specialist_user=self.requester,
        )

        response = self.client.post(
            reverse("dashboard:extras_dashboard"),
            {
                "action": "issue_extras_invoice",
                "request_id": str(bundle_request.id),
                "redirect_query": f"section=overview&request={bundle_request.id}",
                "status": "in_progress",
                "assigned_to": str(self.staff_user.id),
                "operator_comment": "تمت مراجعة الطلب وإصدار الفاتورة.",
                "invoice_line_title[]": ["تقارير إحصائية", "إدارة عملاء"],
                "invoice_line_amount[]": ["500.00", "300.00"],
            },
        )

        self.assertEqual(response.status_code, 302)
        bundle_request = self._reload_request_with_metadata(bundle_request)
        invoice = Invoice.objects.get(id=bundle_request.metadata_record.payload.get("invoice_id"))
        self.assertEqual(invoice.user_id, self.request_owner.id)

        payment_attempt = PaymentAttempt.objects.filter(invoice=invoice).order_by("-created_at").first()
        self.assertIsNotNone(payment_attempt)

        self.client.force_login(self.request_owner)
        checkout_response = self.client.get(urlsplit(payment_attempt.checkout_url).path)
        self.assertEqual(checkout_response.status_code, 302)
        self.assertIn("payment=success", checkout_response["Location"])

    def test_extras_dashboard_assignee_can_close_bundle_request_after_payment_and_send_activation_message(self):
        bundle_request = self._create_bundle_request()

        self.client.post(
            reverse("dashboard:extras_dashboard"),
            {
                "action": "issue_extras_invoice",
                "request_id": str(bundle_request.id),
                "redirect_query": f"section=overview&request={bundle_request.id}",
                "status": "in_progress",
                "assigned_to": str(self.staff_user.id),
                "operator_comment": "إصدار فاتورة الطلب.",
                "invoice_line_title[]": ["تقارير إحصائية", "إدارة عملاء"],
                "invoice_line_amount[]": ["500.00", "300.00"],
            },
        )

        bundle_request = self._reload_request_with_metadata(bundle_request)
        invoice = Invoice.objects.get(id=bundle_request.metadata_record.payload.get("invoice_id"))
        invoice.mark_payment_confirmed(
            provider="mock",
            provider_reference=f"extras-bundle-{invoice.id}",
            event_id=f"extras-bundle-paid-{invoice.id}",
            amount=invoice.total,
            currency=invoice.currency,
        )
        invoice.save(
            update_fields=[
                "status",
                "paid_at",
                "cancelled_at",
                "payment_confirmed",
                "payment_confirmed_at",
                "payment_provider",
                "payment_reference",
                "payment_event_id",
                "payment_amount",
                "payment_currency",
                "updated_at",
            ]
        )

        response = self.client.post(
            reverse("dashboard:extras_dashboard"),
            {
                "action": "save_extras_request",
                "request_id": str(bundle_request.id),
                "redirect_query": f"section=overview&request={bundle_request.id}",
                "status": "closed",
                "assigned_to": str(self.staff_user.id),
                "operator_comment": "تم اكتمال التفعيل.",
            },
        )

        self.assertEqual(response.status_code, 302)
        bundle_request.refresh_from_db()
        self.assertEqual(bundle_request.status, "closed")
        portal_subscription = ExtrasPortalSubscription.objects.filter(provider=self.requester_provider_profile).first()
        self.assertIsNotNone(portal_subscription)
        self.assertEqual(portal_subscription.status, ExtrasPortalSubscriptionStatus.ACTIVE)
        self.assertIn("التقارير", portal_subscription.plan_title)

        requester_thread = self._bundle_system_thread_for(self.requester)
        self.assertIsNotNone(requester_thread)
        self.assertEqual(requester_thread.participant_mode_for_user(self.requester), Thread.ContextMode.PROVIDER)
        self.assertTrue(
            Message.objects.filter(
                thread=requester_thread,
                body__icontains="اكتملت عملية تفعيل الخدمات الإضافية المطلوبة بنجاح",
            )
            .filter(body__icontains="مؤشرات المنصة")
            .filter(body__icontains="2 سنة")
            .filter(body__icontains=reverse("extras_portal:reports"))
            .exists()
        )

        specialist_thread = self._bundle_system_thread_for(self.specialist)
        self.assertIsNotNone(specialist_thread)
        self.assertEqual(specialist_thread.participant_mode_for_user(self.specialist), Thread.ContextMode.CLIENT)
        self.assertTrue(
            Message.objects.filter(
                thread=specialist_thread,
                body__icontains="اكتملت عملية تفعيل الخدمات الإضافية المطلوبة بنجاح",
            )
            .filter(body__icontains="مؤشرات المنصة")
            .filter(body__icontains=bundle_request.code)
            .exists()
        )


@override_settings(
    STORAGES={
        "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
        "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"},
    }
)
class VerificationDashboardStatusDisplayTests(TestCase):
    def setUp(self):
        self.staff_user = get_user_model().objects.create_user(
            phone="0500000260",
            password="secret",
            is_staff=True,
        )
        UserAccessProfile.objects.create(user=self.staff_user, level=AccessLevel.ADMIN)

        self.requester = get_user_model().objects.create_user(phone="0500000261", password="secret")
        self.pro_plan = SubscriptionPlan.objects.create(
            code="verify_pro_month",
            tier=PlanTier.PRO,
            title="الباقة الاحترافية",
            period=PlanPeriod.MONTH,
            price="399.00",
        )
        Subscription.objects.create(
            user=self.requester,
            plan=self.pro_plan,
            status=SubscriptionStatus.ACTIVE,
            start_at=timezone.now() - timezone.timedelta(days=1),
            end_at=timezone.now() + timezone.timedelta(days=29),
        )
        self.support_team = SupportTeam.objects.create(code="verify", name_ar="فريق التوثيق", is_active=True)
        self.invoice = Invoice.objects.create(
            user=self.requester,
            title="فاتورة توثيق",
            reference_type="verify_request",
            subtotal=Decimal("100.00"),
            vat_percent=Decimal("15.00"),
        )
        self.verification_request = VerificationRequest.objects.create(
            requester=self.requester,
            assigned_to=self.staff_user,
            assigned_at=timezone.now(),
            status="pending_payment",
            invoice=self.invoice,
        )
        self.invoice.reference_id = self.verification_request.code
        self.invoice.mark_payment_confirmed(
            provider="mock",
            provider_reference="verification-dashboard-test",
            event_id=f"verification-dashboard-{self.verification_request.pk}",
            amount=Decimal("115.00"),
            currency="SAR",
        )
        self.invoice.save()

        self.client.force_login(self.staff_user)
        session = self.client.session
        session[SESSION_OTP_VERIFIED_KEY] = True
        session.save()

    def test_paid_verification_request_does_not_render_pending_payment_label(self):
        response = self.client.get(
            f"{reverse('dashboard:verification_dashboard')}?request={self.verification_request.id}&request_stage=review"
        )

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "الحالة الحالية: مكتمل")
        self.assertNotContains(response, "الحالة الحالية: بانتظار الدفع")

    def test_verification_dashboard_renders_selected_request_details_inline(self):
        response = self.client.get(
            f"{reverse('dashboard:verification_dashboard')}?request={self.verification_request.id}&request_stage=review"
        )

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, f'id="verification-request-{self.verification_request.id}"', html=False)
        self.assertContains(response, "dash-inline-detail-row", html=False)
        self.assertContains(response, self.verification_request.code)
        self.assertContains(response, "مراجعة بنود طلب التوثيق")

    def test_verification_dashboard_uses_client_package_for_priority_number_and_color(self):
        response = self.client.get(reverse("dashboard:verification_dashboard"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.context["verification_requests"][0]["priority_number"], 3)
        self.assertEqual(response.context["verification_requests"][0]["priority_class"], "priority-3")


@override_settings(
    STORAGES={
        "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
        "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"},
    }
)
class SubscriptionPaymentAwaitingReviewFlowTests(TestCase):
    def setUp(self):
        self.staff_user = get_user_model().objects.create_user(
            phone="0500000600",
            password="secret",
            is_staff=True,
        )
        UserAccessProfile.objects.create(user=self.staff_user, level=AccessLevel.ADMIN)

        self.requester = get_user_model().objects.create_user(
            phone="0500000601",
            password="secret",
            role_state="provider",
        )
        ProviderProfile.objects.create(
            user=self.requester,
            provider_type="individual",
            display_name="مزود تدفق الدفع",
            bio="نبذة مختصرة",
        )
        Subscription.objects.filter(user=self.requester, status=SubscriptionStatus.ACTIVE).delete()

        self.plan = SubscriptionPlan.objects.create(
            code="pro_payment_flow",
            tier=PlanTier.PRO,
            title="الباقة الاحترافية",
            period=PlanPeriod.MONTH,
            price="299.00",
        )

        self.provider_page_client = Client()
        self.provider_page_client.force_login(self.requester)

        self.provider_api_client = APIClient()
        self.provider_api_client.force_authenticate(user=self.requester)

        self.dashboard_client = Client()
        self.dashboard_client.force_login(self.staff_user)
        session = self.dashboard_client.session
        session[SESSION_OTP_VERIFIED_KEY] = True
        session.save()

    def test_provider_checkout_payment_moves_request_to_dashboard_awaiting_review(self):
        plans_response = self.provider_api_client.get("/api/subscriptions/plans/")
        self.assertEqual(plans_response.status_code, 200)

        summary_route_response = self.provider_page_client.get(f"/plans/summary/?plan_id={self.plan.id}")
        self.assertEqual(summary_route_response.status_code, 200)

        subscribe_response = self.provider_api_client.post(
            f"/api/subscriptions/subscribe/{self.plan.id}/",
            {"duration_count": 1},
            format="json",
        )
        self.assertEqual(subscribe_response.status_code, 201)

        payload = subscribe_response.json()
        subscription_id = int(payload["id"])
        invoice_id = int(payload["invoice_summary"]["id"])
        request_code = str(payload["request_code"])

        payment_page_response = self.provider_page_client.get(f"/plans/payment/?subscription_id={subscription_id}")
        self.assertEqual(payment_page_response.status_code, 200)

        init_response = self.provider_api_client.post(
            f"/api/billing/invoices/{invoice_id}/init-payment/",
            {
                "provider": "mock",
                "idempotency_key": f"subscription-flow-{subscription_id}-{invoice_id}",
                "payment_method": "mada",
            },
            format="json",
        )
        self.assertEqual(init_response.status_code, 200)

        complete_response = self.provider_api_client.post(
            f"/api/billing/invoices/{invoice_id}/complete-mock-payment/",
            {
                "idempotency_key": f"subscription-flow-{subscription_id}-{invoice_id}",
                "payment_method": "mada",
            },
            format="json",
        )
        self.assertEqual(complete_response.status_code, 200)

        subscription = Subscription.objects.select_related("invoice").get(pk=subscription_id)
        self.assertEqual(subscription.status, SubscriptionStatus.AWAITING_REVIEW)
        self.assertTrue(subscription.invoice.is_payment_effective())
        subscription_request = UnifiedRequest.objects.get(
            request_type=UnifiedRequestType.SUBSCRIPTION,
            source_app="subscriptions",
            source_model="Subscription",
            source_object_id=str(subscription_id),
        )
        self.assertEqual(subscription_request.status, "new")

        my_subscriptions_response = self.provider_api_client.get("/api/subscriptions/my/")
        self.assertEqual(my_subscriptions_response.status_code, 200)
        my_subscription = next(row for row in my_subscriptions_response.json() if int(row["id"]) == subscription_id)
        self.assertEqual(my_subscription["provider_status_code"], SubscriptionStatus.AWAITING_REVIEW)
        self.assertEqual(my_subscription["invoice_summary"]["status"], InvoiceStatus.PAID)

        dashboard_response = self.dashboard_client.get(reverse("dashboard:subscription_dashboard"))
        self.assertEqual(dashboard_response.status_code, 200)
        self.assertContains(dashboard_response, request_code)
        self.assertContains(dashboard_response, "جديد")


class SubscriptionDashboardTests(TestCase):
    def setUp(self):
        self.staff_user = get_user_model().objects.create_user(
            phone="0500000300",
            password="secret",
            is_staff=True,
        )
        UserAccessProfile.objects.create(user=self.staff_user, level=AccessLevel.ADMIN)

        self.requester = get_user_model().objects.create_user(phone="0500000301", password="secret", role_state="provider")
        ProviderProfile.objects.create(
            user=self.requester,
            provider_type="individual",
            display_name="مزود اشتراك تجريبي",
            bio="نبذة مختصرة",
        )
        self.plan = SubscriptionPlan.objects.create(
            code="riyadi_month",
            tier=PlanTier.RIYADI,
            title="الباقة الريادية",
            period=PlanPeriod.MONTH,
            price="199.00",
        )
        self.pro_plan = SubscriptionPlan.objects.create(
            code="pro_year",
            tier=PlanTier.PRO,
            title="الباقة الاحترافية",
            period=PlanPeriod.YEAR,
            price="999.00",
        )
        self.support_team = SupportTeam.objects.create(code="subs", name_ar="فريق إدارة الاشتراكات", is_active=True)
        self.subscription = Subscription.objects.create(
            user=self.requester,
            plan=self.plan,
            status=SubscriptionStatus.ACTIVE,
            start_at=timezone.now() - timezone.timedelta(days=3),
            end_at=timezone.now() + timezone.timedelta(days=27),
        )
        self.subscription_request = UnifiedRequest.objects.create(
            request_type=UnifiedRequestType.SUBSCRIPTION,
            requester=self.requester,
            status="in_progress",
            priority="leading",
            assigned_user=self.staff_user,
            assigned_team_code="subs",
            assigned_team_name="فريق إدارة الترقية والاشتراكات",
            source_app="subscriptions",
            source_model="Subscription",
            source_object_id=str(self.subscription.id),
            summary="اشتراك الباقة الريادية",
            assigned_at=timezone.now() - timezone.timedelta(days=1),
        )
        self.subscription_inquiry = SupportTicket.objects.create(
            requester=self.requester,
            ticket_type=SupportTicketType.SUBS,
            status=SupportTicketStatus.RETURNED,
            priority=SupportPriority.NORMAL,
            entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
            description="استفسار حول تفعيل الاشتراك",
            assigned_team=self.support_team,
            assigned_to=self.staff_user,
            assigned_at=timezone.now() - timezone.timedelta(hours=3),
        )

        self.client.force_login(self.staff_user)
        session = self.client.session
        session[SESSION_OTP_VERIFIED_KEY] = True
        session.save()

    def test_subscription_dashboard_renders_all_three_data_sources(self):
        response = self.client.get(reverse("dashboard:subscription_dashboard"))

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "قائمة استفسارات الاشتراكات")
        self.assertContains(response, self.subscription_inquiry.code)
        self.assertContains(response, self.subscription_request.code)
        self.assertContains(response, "تفعيل الاشتراكات")
        self.assertContains(response, "بيانات حسابات المشتركين")

    def test_subscription_dashboard_uses_subscription_package_for_priority_number_and_color(self):
        response = self.client.get(reverse("dashboard:subscription_dashboard"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.context["subscription_inquiries"][0]["priority_number"], 2)
        self.assertEqual(response.context["subscription_inquiries"][0]["priority_class"], "priority-2")
        self.assertEqual(response.context["subscription_requests"][0]["priority_number"], 2)
        self.assertEqual(response.context["subscription_requests"][0]["priority_class"], "priority-2")

    def test_subscription_dashboard_accounts_tab_renders_subscriber_accounts(self):
        response = self.client.get(f"{reverse('dashboard:subscription_dashboard')}?tab=subscriber_accounts")

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "بيانات حسابات المشتركين")
        self.assertContains(response, self.plan.title)
        self.assertNotContains(response, "قائمة طلبات الاشتراكات")

    def test_subscription_dashboard_accounts_tab_toggles_selected_account_details(self):
        base_url = f"{reverse('dashboard:subscription_dashboard')}?tab=subscriber_accounts"

        collapsed_response = self.client.get(base_url)
        self.assertEqual(collapsed_response.status_code, 200)
        self.assertNotContains(collapsed_response, "اسم مزود الخدمة")

        expanded_response = self.client.get(f"{base_url}&account={self.subscription.id}")
        self.assertEqual(expanded_response.status_code, 200)
        self.assertContains(expanded_response, "اسم مزود الخدمة")
        self.assertContains(expanded_response, "مزود اشتراك تجريبي")
        self.assertContains(expanded_response, "تجديد الباقة")
        self.assertContains(expanded_response, "حذف الباقة")

    def test_subscription_dashboard_accounts_tab_shows_fallback_end_date_and_payment_details(self):
        self.subscription.end_at = None
        self.subscription.grace_end_at = None
        self.subscription.invoice = None
        self.subscription.save(update_fields=["end_at", "grace_end_at", "invoice", "updated_at"])

        fallback_invoice = Invoice.objects.create(
            user=self.requester,
            title="فاتورة اشتراك سابقة",
            subtotal="199.00",
            vat_percent="0.00",
            reference_type="subscription",
            reference_id="99999",
            status=InvoiceStatus.PAID,
            payment_confirmed=True,
            payment_confirmed_at=timezone.now(),
        )

        response = self.client.get(
            f"{reverse('dashboard:subscription_dashboard')}?tab=subscriber_accounts&account={self.subscription.id}"
        )

        expected_end_at = timezone.localtime(self.subscription.calc_end_date(self.subscription.start_at)).strftime("%d/%m/%Y - %H:%M")
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, expected_end_at)
        self.assertContains(response, "تمت عملية السداد بنجاح")
        self.assertContains(response, str(fallback_invoice.total))
        self.assertContains(response, "SAR")

    def test_subscription_dashboard_can_start_subscription_renewal_from_account_details(self):
        response = self.client.post(
            reverse("dashboard:subscription_dashboard"),
            {
                "action": "renew_subscription_account",
                "subscription_id": str(self.subscription.id),
                "redirect_query": f"tab=subscriber_accounts&account={self.subscription.id}",
            },
            follow=False,
        )

        self.assertEqual(response.status_code, 302)
        self.assertIn("#subscriptionRequests", response["Location"])

        renewal_sub = (
            Subscription.objects.filter(
                user=self.requester,
                plan=self.plan,
                status=SubscriptionStatus.PENDING_PAYMENT,
            )
            .exclude(pk=self.subscription.id)
            .order_by("-id")
            .first()
        )
        self.assertIsNotNone(renewal_sub)

        renewal_request = UnifiedRequest.objects.filter(
            request_type=UnifiedRequestType.SUBSCRIPTION,
            source_app="subscriptions",
            source_model="Subscription",
            source_object_id=str(renewal_sub.id),
        ).first()
        self.assertIsNotNone(renewal_request)
        self.assertIn(f"request={renewal_request.id}", response["Location"])

    def test_subscription_dashboard_can_delete_pending_subscription_from_account_details(self):
        pending_sub = Subscription.objects.create(
            user=self.requester,
            plan=self.plan,
            status=SubscriptionStatus.PENDING_PAYMENT,
        )
        invoice = Invoice.objects.create(
            user=self.requester,
            title="فاتورة اشتراك معلقة",
            subtotal="199.00",
            vat_percent="0.00",
            reference_type="subscription",
            reference_id=str(pending_sub.id),
            status=InvoiceStatus.DRAFT,
        )
        pending_sub.invoice = invoice
        pending_sub.save(update_fields=["invoice", "updated_at"])
        pending_request = UnifiedRequest.objects.create(
            request_type=UnifiedRequestType.SUBSCRIPTION,
            requester=self.requester,
            status="new",
            priority="normal",
            source_app="subscriptions",
            source_model="Subscription",
            source_object_id=str(pending_sub.id),
            summary="طلب اشتراك معلق",
        )

        response = self.client.post(
            reverse("dashboard:subscription_dashboard"),
            {
                "action": "delete_subscription_account",
                "subscription_id": str(pending_sub.id),
                "redirect_query": f"tab=subscriber_accounts&account={pending_sub.id}",
            },
            follow=False,
        )

        self.assertEqual(response.status_code, 302)
        self.assertFalse(Subscription.objects.filter(pk=pending_sub.id).exists())
        self.assertFalse(Invoice.objects.filter(pk=invoice.id).exists())
        self.assertFalse(UnifiedRequest.objects.filter(pk=pending_request.id).exists())

    def test_subscription_dashboard_blocks_deleting_active_subscription_from_account_details(self):
        response = self.client.post(
            reverse("dashboard:subscription_dashboard"),
            {
                "action": "delete_subscription_account",
                "subscription_id": str(self.subscription.id),
                "redirect_query": f"tab=subscriber_accounts&account={self.subscription.id}",
            },
            follow=True,
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(Subscription.objects.filter(pk=self.subscription.id).exists())
        self.assertContains(response, "لا يمكن حذف اشتراك نشط أو ضمن فترة السماح")

    def test_subscription_dashboard_can_activate_paid_subscription_after_review(self):
        invoice = Invoice.objects.create(
            user=self.requester,
            title="فاتورة اشتراك",
            subtotal="199.00",
            vat_percent="15.00",
            reference_type="subscription",
            reference_id=str(self.subscription.id),
            status=InvoiceStatus.PAID,
            payment_confirmed=True,
            payment_confirmed_at=timezone.now(),
        )
        self.subscription.invoice = invoice
        self.subscription.status = SubscriptionStatus.AWAITING_REVIEW
        self.subscription.save(update_fields=["invoice", "status", "updated_at"])

        response = self.client.post(
            reverse("dashboard:subscription_dashboard"),
            {
                "action": "activate_subscription_request",
                "subscription_id": str(self.subscription.id),
                "redirect_query": "",
            },
            follow=True,
        )

        self.assertEqual(response.status_code, 200)
        self.subscription.refresh_from_db()
        self.subscription_request.refresh_from_db()
        self.assertEqual(self.subscription.status, SubscriptionStatus.ACTIVE)
        self.assertEqual(self.subscription_request.status, "closed")

    def test_subscription_dashboard_blocks_direct_activation_for_new_request(self):
        invoice = Invoice.objects.create(
            user=self.requester,
            title="فاتورة اشتراك",
            subtotal="199.00",
            vat_percent="15.00",
            reference_type="subscription",
            reference_id=str(self.subscription.id),
            status=InvoiceStatus.PAID,
            payment_confirmed=True,
            payment_confirmed_at=timezone.now(),
        )
        self.subscription.invoice = invoice
        self.subscription.status = SubscriptionStatus.AWAITING_REVIEW
        self.subscription.save(update_fields=["invoice", "status", "updated_at"])
        self.subscription_request.status = "new"
        self.subscription_request.save(update_fields=["status", "updated_at"])

        response = self.client.post(
            reverse("dashboard:subscription_dashboard"),
            {
                "action": "activate_subscription_request",
                "subscription_id": str(self.subscription.id),
                "redirect_query": "",
            },
            follow=True,
        )

        self.assertEqual(response.status_code, 200)
        self.subscription.refresh_from_db()
        self.subscription_request.refresh_from_db()
        self.assertEqual(self.subscription.status, SubscriptionStatus.AWAITING_REVIEW)
        self.assertEqual(self.subscription_request.status, "new")
        self.assertContains(response, "يجب نقل طلب الاشتراك أولًا إلى تحت المعالجة")

    def test_subscription_dashboard_can_save_inquiry_details(self):
        response = self.client.post(
            reverse("dashboard:subscription_dashboard"),
            {
                "action": "save_subscription_inquiry",
                "ticket_id": str(self.subscription_inquiry.id),
                "redirect_query": f"inquiry={self.subscription_inquiry.id}",
                "status": SupportTicketStatus.IN_PROGRESS,
                "assigned_to": str(self.staff_user.id),
                "description": "تفاصيل محدثة لطلب الاشتراك",
                "operator_comment": "تمت مراجعة الاستفسار وتحويله للمعالجة.",
            },
            follow=True,
        )

        self.assertEqual(response.status_code, 200)
        self.subscription_inquiry.refresh_from_db()
        profile = SubscriptionInquiryProfile.objects.get(ticket=self.subscription_inquiry)

        self.assertEqual(self.subscription_inquiry.status, SupportTicketStatus.IN_PROGRESS)
        self.assertEqual(self.subscription_inquiry.description, "تفاصيل محدثة لطلب الاشتراك")
        self.assertIsNotNone(self.subscription_inquiry.assigned_team_id)
        self.assertEqual(self.subscription_inquiry.assigned_to_id, self.staff_user.id)
        self.assertEqual(profile.operator_comment, "تمت مراجعة الاستفسار وتحويله للمعالجة.")
        self.assertContains(response, "تفاصيل الاستفسار")

    def test_subscription_dashboard_blocks_closing_paid_request_before_in_progress(self):
        invoice = Invoice.objects.create(
            user=self.requester,
            title="فاتورة اشتراك",
            subtotal="999.00",
            vat_percent="0.00",
            reference_type="subscription",
            reference_id=str(self.subscription.id),
            status=InvoiceStatus.PAID,
            payment_confirmed=True,
            payment_confirmed_at=timezone.now(),
        )
        self.subscription.invoice = invoice
        self.subscription.status = SubscriptionStatus.AWAITING_REVIEW
        self.subscription.save(update_fields=["invoice", "status", "updated_at"])
        self.subscription_request.status = "new"
        self.subscription_request.save(update_fields=["status", "updated_at"])

        response = self.client.post(
            reverse("dashboard:subscription_dashboard"),
            {
                "action": "save_subscription_request",
                "request_id": str(self.subscription_request.id),
                "redirect_query": f"request={self.subscription_request.id}",
                "status": "closed",
                "assigned_to": str(self.staff_user.id),
                "plan_id": str(self.plan.id),
                "duration_count": 1,
            },
            follow=True,
        )

        self.assertEqual(response.status_code, 200)
        self.subscription.refresh_from_db()
        self.subscription_request.refresh_from_db()
        self.assertEqual(self.subscription.status, SubscriptionStatus.AWAITING_REVIEW)
        self.assertEqual(self.subscription_request.status, "new")
        self.assertContains(response, "يجب نقل طلب الاشتراك أولًا إلى تحت المعالجة")

    def test_subscription_dashboard_renders_selected_request_details_inline(self):
        response = self.client.get(
            f"{reverse('dashboard:subscription_dashboard')}?request={self.subscription_request.id}"
        )

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, f'id="subscription-request-{self.subscription_request.id}"', html=False)
        self.assertContains(response, "dash-inline-detail-row", html=False)
        self.assertContains(response, f"تفاصيل الطلب: {self.subscription_request.code}")
        self.assertNotContains(response, 'id="subscriptionRequestDetails"', html=False)

    def test_subscription_dashboard_save_request_details_activates_and_redirects_to_accounts(self):
        invoice = Invoice.objects.create(
            user=self.requester,
            title="فاتورة اشتراك",
            subtotal="999.00",
            vat_percent="0.00",
            reference_type="subscription",
            reference_id=str(self.subscription.id),
            status=InvoiceStatus.PAID,
            payment_confirmed=True,
            payment_confirmed_at=timezone.now(),
        )
        self.subscription.invoice = invoice
        self.subscription.status = SubscriptionStatus.AWAITING_REVIEW
        self.subscription.save(update_fields=["invoice", "status", "updated_at"])

        response = self.client.post(
            reverse("dashboard:subscription_dashboard"),
            {
                "action": "save_subscription_request",
                "request_id": str(self.subscription_request.id),
                "redirect_query": f"request={self.subscription_request.id}",
                "status": "closed",
                "assigned_to": str(self.staff_user.id),
                "plan_id": str(self.pro_plan.id),
                "duration_count": 5,
            },
            follow=False,
        )

        self.assertEqual(response.status_code, 302)
        self.assertIn("#subscriberAccounts", response["Location"])
        self.assertIn("tab=subscriber_accounts", response["Location"])
        self.assertIn(f"account={self.subscription.id}", response["Location"])

        self.subscription.refresh_from_db()
        self.subscription_request.refresh_from_db()

        self.assertEqual(self.subscription.status, SubscriptionStatus.ACTIVE)
        self.assertEqual(self.subscription.plan_id, self.pro_plan.id)
        self.assertEqual(self.subscription.duration_count, 5)
        self.assertEqual(self.subscription_request.status, "closed")
        self.assertTrue(
            Message.objects.filter(
                thread__system_thread_key="subscriptions",
                sender=self.staff_user,
                sender_team_name="فريق إدارة الاشتراكات",
                thread__participant_2=self.requester,
            ).exists()
        )


# ---------------------------------------------------------------------------
# Regression tests: promo status-guard protection against double-creation
# ---------------------------------------------------------------------------

@override_settings(
    STORAGES={
        "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
        "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"},
    }
)
class PromoModuleTerminalStatusGuardTests(TestCase):
    """Verify that the promo_module view rejects item creation on terminal-state requests."""

    def setUp(self):
        self.staff_user = get_user_model().objects.create_user(
            phone="0500000300", password="secret", is_staff=True,
        )
        UserAccessProfile.objects.create(user=self.staff_user, level=AccessLevel.ADMIN)

        self.requester = get_user_model().objects.create_user(
            phone="0500000301", password="secret", role_state="provider",
        )
        self.provider_profile = ProviderProfile.objects.create(
            user=self.requester,
            provider_type="individual",
            display_name="مختص حماية",
            bio="نبذة",
        )
        self.spotlight_item = ProviderSpotlightItem.objects.create(
            provider=self.provider_profile,
            file_type="image",
            file=SimpleUploadedFile("guard.jpg", b"img", content_type="image/jpeg"),
            caption="لمحة",
        )

        self.client.force_login(self.staff_user)
        session = self.client.session
        session[SESSION_OTP_VERIFIED_KEY] = True
        session.save()

    def _make_request(self, status, ops_status=PromoOpsStatus.NEW):
        return PromoRequest.objects.create(
            requester=self.requester,
            title="طلب حماية",
            ad_type=PromoAdType.FEATURED_TOP5,
            start_at=timezone.now() + timezone.timedelta(days=1),
            end_at=timezone.now() + timezone.timedelta(days=5),
            status=status,
            ops_status=ops_status,
        )

    def _post_approve(self, promo_request, module_key="featured_specialists"):
        module_url = reverse("dashboard:promo_module", kwargs={"module_key": module_key})
        response = self.client.get(f"{module_url}?request_id={promo_request.id}")
        form_token = response.context.get("promo_module_form_token", "")
        payload = {
            "workflow_action": "approve_item",
            "promo_module_form_token": form_token,
            "request_id": str(promo_request.id),
            "title": "بند جديد",
            "start_at": timezone.localtime(promo_request.start_at).strftime("%Y-%m-%dT%H:%M"),
            "end_at": timezone.localtime(promo_request.end_at).strftime("%Y-%m-%dT%H:%M"),
            "target_provider_id": str(self.provider_profile.id),
        }
        return self.client.post(module_url, payload, follow=True)

    def test_module_rejects_item_creation_on_active_request(self):
        pr = self._make_request(PromoRequestStatus.ACTIVE)
        self._post_approve(pr)
        self.assertEqual(PromoRequestItem.objects.filter(request=pr).count(), 0)

    def test_module_rejects_item_creation_on_completed_request(self):
        pr = self._make_request(PromoRequestStatus.COMPLETED)
        self._post_approve(pr)
        self.assertEqual(PromoRequestItem.objects.filter(request=pr).count(), 0)

    def test_module_rejects_item_creation_on_expired_request(self):
        pr = self._make_request(PromoRequestStatus.EXPIRED)
        self._post_approve(pr)
        self.assertEqual(PromoRequestItem.objects.filter(request=pr).count(), 0)

    def test_module_rejects_item_creation_on_cancelled_request(self):
        pr = self._make_request(PromoRequestStatus.CANCELLED)
        self._post_approve(pr)
        self.assertEqual(PromoRequestItem.objects.filter(request=pr).count(), 0)

    def test_module_rejects_item_creation_on_rejected_request(self):
        pr = self._make_request(PromoRequestStatus.REJECTED)
        self._post_approve(pr)
        self.assertEqual(PromoRequestItem.objects.filter(request=pr).count(), 0)

    def test_module_rejects_item_creation_when_ops_in_progress(self):
        pr = self._make_request(PromoRequestStatus.NEW, ops_status=PromoOpsStatus.IN_PROGRESS)
        self._post_approve(pr)
        self.assertEqual(PromoRequestItem.objects.filter(request=pr).count(), 0)

    def test_module_rejects_item_creation_when_ops_completed(self):
        pr = self._make_request(PromoRequestStatus.NEW, ops_status=PromoOpsStatus.COMPLETED)
        self._post_approve(pr)
        self.assertEqual(PromoRequestItem.objects.filter(request=pr).count(), 0)

    def test_module_allows_item_creation_on_new_request(self):
        pr = self._make_request(PromoRequestStatus.NEW)
        self._post_approve(pr)
        self.assertEqual(PromoRequestItem.objects.filter(request=pr).count(), 1)

    def test_candidate_queryset_excludes_terminal_requests(self):
        from apps.dashboard.views import _promo_module_request_candidates_queryset

        new_pr = self._make_request(PromoRequestStatus.NEW)
        active_pr = self._make_request(PromoRequestStatus.ACTIVE)
        completed_pr = self._make_request(PromoRequestStatus.COMPLETED)

        # Attach items so the filter query can match
        for pr in [new_pr, active_pr, completed_pr]:
            PromoRequestItem.objects.create(
                request=pr,
                service_type=PromoServiceType.FEATURED_SPECIALISTS,
                title="بند",
                start_at=pr.start_at,
                end_at=pr.end_at,
            )

        base_qs = PromoRequest.objects.all()
        candidates = _promo_module_request_candidates_queryset(
            base_qs, service_type=PromoServiceType.FEATURED_SPECIALISTS,
        )
        candidate_ids = set(candidates.values_list("id", flat=True))
        self.assertIn(new_pr.id, candidate_ids)
        self.assertNotIn(active_pr.id, candidate_ids)
        self.assertNotIn(completed_pr.id, candidate_ids)


class PromoDashboardSaveTerminalGuardTests(TestCase):
    """Verify that the promo_dashboard save_request blocks saves on terminal-state requests."""

    def setUp(self):
        self.staff_user = get_user_model().objects.create_user(
            phone="0500000310", password="secret", is_staff=True,
        )
        UserAccessProfile.objects.create(user=self.staff_user, level=AccessLevel.ADMIN)

        self.requester = get_user_model().objects.create_user(phone="0500000311", password="secret")

        self.client.force_login(self.staff_user)
        session = self.client.session
        session[SESSION_OTP_VERIFIED_KEY] = True
        session.save()

    def _make_request(self, status, ops_status=PromoOpsStatus.NEW):
        return PromoRequest.objects.create(
            requester=self.requester,
            title="طلب حماية حفظ",
            ad_type=PromoAdType.BANNER_HOME,
            start_at=timezone.now() + timezone.timedelta(days=1),
            end_at=timezone.now() + timezone.timedelta(days=5),
            status=status,
            ops_status=ops_status,
        )

    def _post_save(self, promo_request):
        detail_url = reverse("dashboard:promo_request_detail", kwargs={"request_id": promo_request.id})
        response = self.client.get(detail_url)
        form_token = response.context.get("promo_request_form_token", "")
        payload = {
            "action": "save_request",
            "promo_request_id": str(promo_request.id),
            "promo_form_token": form_token,
            "assigned_to": "",
            "ops_status": promo_request.ops_status,
            "ops_note": "",
            "redirect_query": f"request={promo_request.id}",
        }
        return self.client.post(detail_url, payload, follow=True)

    def test_save_blocked_on_active_request(self):
        pr = self._make_request(PromoRequestStatus.ACTIVE)
        resp = self._post_save(pr)
        msgs = [str(m) for m in resp.context["messages"]]
        # Blocked either by token guard (no token issued) or status guard
        self.assertFalse(any("تم تحديث طلب الترويج" in m for m in msgs))

    def test_save_blocked_on_completed_request(self):
        pr = self._make_request(PromoRequestStatus.COMPLETED)
        resp = self._post_save(pr)
        msgs = [str(m) for m in resp.context["messages"]]
        self.assertFalse(any("تم تحديث طلب الترويج" in m for m in msgs))

    def test_save_blocked_on_ops_completed(self):
        pr = self._make_request(PromoRequestStatus.NEW, ops_status=PromoOpsStatus.COMPLETED)
        resp = self._post_save(pr)
        msgs = [str(m) for m in resp.context["messages"]]
        self.assertFalse(any("تم تحديث طلب الترويج" in m for m in msgs))

    def test_save_allowed_on_new_request(self):
        pr = self._make_request(PromoRequestStatus.NEW)
        resp = self._post_save(pr)
        msgs = [str(m) for m in resp.context["messages"]]
        self.assertTrue(any("تم تحديث طلب الترويج" in m for m in msgs))

    def test_form_token_not_issued_for_terminal_request(self):
        pr = self._make_request(PromoRequestStatus.COMPLETED)
        detail_url = reverse("dashboard:promo_request_detail", kwargs={"request_id": pr.id})
        response = self.client.get(detail_url)
        self.assertEqual(response.context.get("promo_request_form_token"), "")
        self.assertFalse(response.context.get("selected_request_can_save"))
