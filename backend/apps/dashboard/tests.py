from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import Client
from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from apps.backoffice.models import AccessLevel, UserAccessProfile
from apps.billing.models import Invoice, InvoiceStatus
from apps.core.models import PlatformConfig
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.messaging.models import Message
from apps.promo.models import PromoAdType, PromoOpsStatus, PromoRequest, PromoRequestItem, PromoRequestStatus
from apps.providers.models import ProviderProfile
from apps.subscriptions.models import PlanPeriod, PlanTier, Subscription, SubscriptionInquiryProfile, SubscriptionPlan, SubscriptionStatus
from apps.support.models import SupportPriority, SupportTeam, SupportTicket, SupportTicketEntrypoint, SupportTicketStatus, SupportTicketType
from apps.unified_requests.models import UnifiedRequest, UnifiedRequestType
from apps.verification.models import VerificationRequest

from .views import _promo_quote_snapshot


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
        self.assertTrue(any("تم تجاهل محاولة الاعتماد المكررة" in message for message in second_messages))

        self.assertEqual(
            PromoRequestItem.objects.filter(
                request=self.promo_request,
                service_type="featured_specialists",
            ).count(),
            1,
        )


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

        my_subscriptions_response = self.provider_api_client.get("/api/subscriptions/my/")
        self.assertEqual(my_subscriptions_response.status_code, 200)
        my_subscription = next(row for row in my_subscriptions_response.json() if int(row["id"]) == subscription_id)
        self.assertEqual(my_subscription["provider_status_code"], SubscriptionStatus.AWAITING_REVIEW)
        self.assertEqual(my_subscription["invoice_summary"]["status"], InvoiceStatus.PAID)

        dashboard_response = self.dashboard_client.get(reverse("dashboard:subscription_dashboard"))
        self.assertEqual(dashboard_response.status_code, 200)
        self.assertContains(dashboard_response, request_code)
        self.assertContains(dashboard_response, "بانتظار المراجعة")


class SubscriptionDashboardTests(TestCase):
    def setUp(self):
        self.staff_user = get_user_model().objects.create_user(
            phone="0500000300",
            password="secret",
            is_staff=True,
        )
        UserAccessProfile.objects.create(user=self.staff_user, level=AccessLevel.ADMIN)

        self.requester = get_user_model().objects.create_user(phone="0500000301", password="secret")
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

    def test_subscription_dashboard_accounts_tab_renders_subscriber_accounts(self):
        response = self.client.get(f"{reverse('dashboard:subscription_dashboard')}?tab=subscriber_accounts")

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "بيانات حسابات المشتركين")
        self.assertContains(response, self.plan.title)
        self.assertNotContains(response, "قائمة طلبات الاشتراكات")

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

    def test_subscription_dashboard_can_save_inquiry_details(self):
        response = self.client.post(
            reverse("dashboard:subscription_dashboard"),
            {
                "action": "save_subscription_inquiry",
                "ticket_id": str(self.subscription_inquiry.id),
                "redirect_query": "inquiry_q=test",
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
        self.assertEqual(self.subscription_inquiry.assigned_team_id, self.support_team.id)
        self.assertEqual(self.subscription_inquiry.assigned_to_id, self.staff_user.id)
        self.assertEqual(profile.operator_comment, "تمت مراجعة الاستفسار وتحويله للمعالجة.")
        self.assertContains(response, "تفاصيل الاستفسار")

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