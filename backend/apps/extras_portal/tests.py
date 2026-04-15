from datetime import datetime, timedelta
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone

from apps.analytics.models import ProviderDailyStats
from apps.billing.models import Invoice
from apps.extras_portal.auth import SESSION_PORTAL_OTP_VERIFIED_KEY
from apps.extras_portal.models import (
    ExtrasPortalScheduledMessage,
    ExtrasPortalScheduledMessageRecipient,
    ExtrasPortalSubscription,
    ExtrasPortalSubscriptionStatus,
    ScheduledMessageStatus,
)
from apps.extras_portal.services import process_due_scheduled_messages
from apps.marketplace.models import RequestStatus, RequestType, ServiceRequest
from apps.messaging.models import Message
from apps.notifications.models import Notification
from apps.providers.models import (
    Category,
    ProviderFollow,
    ProviderPortfolioItem,
    ProviderPortfolioLike,
    ProviderProfile,
    SubCategory,
)
from apps.reviews.models import Review
from apps.subscriptions.models import PlanPeriod, PlanTier, Subscription, SubscriptionPlan, SubscriptionStatus
from apps.unified_requests.models import UnifiedRequest, UnifiedRequestMetadata, UnifiedRequestType


@override_settings(
    STORAGES={
        "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
        "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"},
    }
)
class ExtrasPortalReportsViewTests(TestCase):
    def setUp(self):
        user_model = get_user_model()
        self.provider_user = user_model.objects.create_user(
            phone="0500000910",
            username="portal_provider",
            password="secret",
        )
        self.provider_profile = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مختص بوابة التقارير",
            bio="ملف اختباري",
            years_experience=6,
        )
        self.client_a = user_model.objects.create_user(
            phone="0500000911",
            username="client_alpha",
            password="secret",
        )
        self.client_b = user_model.objects.create_user(
            phone="0500000912",
            username="client_beta",
            password="secret",
        )

        self.category = Category.objects.create(name="تصميم", is_active=True)
        self.subcategory = SubCategory.objects.create(category=self.category, name="هوية بصرية", is_active=True)

        self.request_completed = ServiceRequest.objects.create(
            client=self.client_a,
            provider=self.provider_profile,
            subcategory=self.subcategory,
            title="طلب مكتمل",
            description="وصف",
            request_type=RequestType.COMPETITIVE,
            status=RequestStatus.COMPLETED,
            city="جدة",
            received_amount=Decimal("450.00"),
        )
        self.request_in_progress = ServiceRequest.objects.create(
            client=self.client_b,
            provider=self.provider_profile,
            subcategory=self.subcategory,
            title="طلب تحت التنفيذ",
            description="وصف",
            request_type=RequestType.COMPETITIVE,
            status=RequestStatus.IN_PROGRESS,
            city="جدة",
            received_amount=Decimal("150.00"),
        )
        self.request_outside_window = ServiceRequest.objects.create(
            client=self.client_b,
            provider=self.provider_profile,
            subcategory=self.subcategory,
            title="طلب خارج الفترة",
            description="وصف",
            request_type=RequestType.COMPETITIVE,
            status=RequestStatus.NEW,
            city="جدة",
        )

        inside_start = timezone.make_aware(datetime(2026, 4, 2, 12, 0))
        inside_end = timezone.make_aware(datetime(2026, 4, 8, 14, 0))
        outside_date = timezone.make_aware(datetime(2026, 3, 20, 10, 0))
        ServiceRequest.objects.filter(id=self.request_completed.id).update(created_at=inside_start)
        ServiceRequest.objects.filter(id=self.request_in_progress.id).update(created_at=inside_end)
        ServiceRequest.objects.filter(id=self.request_outside_window.id).update(created_at=outside_date)

        self.portfolio_item = ProviderPortfolioItem.objects.create(
            provider=self.provider_profile,
            file_type="image",
            file=SimpleUploadedFile("portfolio.jpg", b"fake-image", content_type="image/jpeg"),
            caption="عنصر معرض",
        )
        self.like = ProviderPortfolioLike.objects.create(user=self.client_a, item=self.portfolio_item)
        ProviderPortfolioLike.objects.filter(id=self.like.id).update(created_at=inside_start)

        self.follow = ProviderFollow.objects.create(user=self.client_b, provider=self.provider_profile)
        ProviderFollow.objects.filter(id=self.follow.id).update(created_at=inside_end)

        self.review = Review.objects.create(
            request=self.request_completed,
            provider=self.provider_profile,
            client=self.client_a,
            rating=5,
            comment="خدمة ممتازة",
        )
        Review.objects.filter(id=self.review.id).update(created_at=inside_end)

        ProviderDailyStats.objects.create(
            provider=self.provider_profile,
            day=datetime(2026, 4, 3).date(),
            profile_views=11,
            requests_received=1,
            requests_completed=1,
        )
        ProviderDailyStats.objects.create(
            provider=self.provider_profile,
            day=datetime(2026, 4, 7).date(),
            profile_views=7,
            requests_received=1,
            requests_accepted=1,
        )
        ProviderDailyStats.objects.create(
            provider=self.provider_profile,
            day=datetime(2026, 3, 21).date(),
            profile_views=99,
        )

        self.bundle_request = UnifiedRequest.objects.create(
            request_type=UnifiedRequestType.EXTRAS,
            status="closed",
            priority="normal",
            requester=self.provider_user,
            assigned_team_code="extras",
            assigned_team_name="فريق إدارة الخدمات الإضافية",
            source_app="extras",
            source_model="ExtrasBundleRequest",
            source_object_id="bundle-portal-1",
            summary="طلب تقارير مفعّل",
        )
        self.invoice = Invoice.objects.create(
            user=self.provider_user,
            title="فاتورة طلب تقارير",
            reference_type="extras_bundle_request",
            reference_id=self.bundle_request.code,
            currency="SAR",
            subtotal=Decimal("200.00"),
            vat_percent=Decimal("15.00"),
            status="pending",
        )
        self.invoice.mark_payment_confirmed(
            provider="mock",
            provider_reference="portal-report-payment",
            event_id="portal-report-payment-1",
            amount=self.invoice.total,
            currency=self.invoice.currency,
            when=timezone.make_aware(datetime(2026, 4, 10, 19, 40)),
        )
        self.invoice.save(
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

        metadata, _ = UnifiedRequestMetadata.objects.get_or_create(request=self.bundle_request)
        metadata.payload = {
            "invoice_id": self.invoice.id,
            "operator_comment": "رسالة من النظام توضح آخر عملية سداد رسوم ناجحة للعميل.",
            "bundle": {
                "reports": {
                    "enabled": True,
                    "options": [
                        "platform_metrics",
                        "platform_visits",
                        "orders_breakdown",
                        "service_requesters",
                        "content_favoriters",
                        "platform_followers",
                        "positive_reviewers",
                    ],
                    "start_at": "2026-04-01",
                    "end_at": "2026-04-10",
                },
                "clients": {"enabled": False, "options": [], "subscription_years": 1},
                "finance": {"enabled": False, "options": [], "subscription_years": 1},
            },
        }
        metadata.save(update_fields=["payload"])
        ExtrasPortalSubscription.objects.create(
            provider=self.provider_profile,
            status=ExtrasPortalSubscriptionStatus.ACTIVE,
            plan_title="التقارير",
            started_at=timezone.make_aware(datetime(2026, 4, 10, 19, 40)),
            ends_at=timezone.make_aware(datetime(2027, 4, 10, 19, 40)),
        )

        self.client.force_login(self.provider_user)
        session = self.client.session
        session[SESSION_PORTAL_OTP_VERIFIED_KEY] = True
        session.save()

    def test_portal_reports_renders_latest_paid_bundle_request_with_windowed_data(self):
        response = self.client.get(reverse("extras_portal:reports"))

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "لوحة التقارير المرتبطة بطلب الخدمات الإضافية")
        self.assertContains(response, "تمت عملية سداد الرسوم بنجاح بتاريخ 10/04/2026 - 19:40")
        self.assertContains(response, "01/04/2026")
        self.assertContains(response, "10/04/2026")
        self.assertContains(response, "@portal_provider")
        self.assertContains(response, "رسالة من النظام توضح آخر عملية سداد رسوم ناجحة للعميل.")

        context = response.context
        self.assertEqual(context["selected_option_count"], 7)
        self.assertEqual(context["overview_cards"][0]["value"], 2)
        self.assertEqual(context["overview_cards"][1]["value"], 1)
        self.assertEqual(context["overview_cards"][2]["value"], 18)

        cards = [
            card
            for group in context["report_option_groups"]
            for card in group["cards"]
        ]
        cards_by_key = {card["key"]: card for card in cards}
        self.assertEqual(cards_by_key["service_requesters"]["entries"][0]["primary"], "@client_alpha")
        self.assertEqual(cards_by_key["content_favoriters"]["entries"][0]["primary"], "@client_alpha")
        self.assertEqual(cards_by_key["platform_followers"]["entries"][0]["primary"], "@client_beta")
        self.assertEqual(cards_by_key["positive_reviewers"]["entries"][0]["primary"], "@client_alpha")
        self.assertEqual(len(context["portal_nav_items"]), 1)
        self.assertEqual(context["portal_nav_items"][0]["key"], "reports")
        self.assertTrue(context["portal_nav_items"][0]["active"])

    def test_portal_reports_renders_newly_implemented_options_as_working_cards(self):
        metadata = self.bundle_request.metadata_record
        payload = metadata.payload
        payload["bundle"]["reports"]["options"] = [
            "platform_metrics",
            "platform_shares",
            "content_commenters",
            "potential_clients",
            "content_sharers",
        ]
        metadata.payload = payload
        metadata.save(update_fields=["payload"])

        response = self.client.get(reverse("extras_portal:reports"))

        self.assertEqual(response.status_code, 200)
        context = response.context
        self.assertEqual(context["selected_option_count"], 5)

        rows_by_key = {row["key"]: row for row in context["selected_option_rows"]}
        self.assertEqual(rows_by_key["platform_metrics"]["status"], "جاهز للعرض")
        self.assertEqual(rows_by_key["platform_shares"]["status"], "جاهز للعرض")
        self.assertEqual(rows_by_key["content_commenters"]["status"], "جاهز للعرض")
        self.assertEqual(rows_by_key["potential_clients"]["status"], "جاهز للعرض")
        self.assertEqual(rows_by_key["content_sharers"]["status"], "جاهز للعرض")
        self.assertTrue(rows_by_key["platform_metrics"]["can_export"])
        self.assertTrue(rows_by_key["platform_shares"]["can_export"])
        self.assertTrue(rows_by_key["content_commenters"]["can_export"])

        cards = [
            card
            for group in context["report_option_groups"]
            for card in group["cards"]
        ]
        cards_by_key = {card["key"]: card for card in cards}
        self.assertEqual(cards_by_key["platform_metrics"]["kind"], "stats")
        self.assertEqual(cards_by_key["platform_shares"]["kind"], "stats")
        self.assertEqual(cards_by_key["content_commenters"]["kind"], "list")
        self.assertEqual(cards_by_key["potential_clients"]["kind"], "list")
        self.assertEqual(cards_by_key["content_sharers"]["kind"], "list")

    def test_portal_home_redirects_to_first_enabled_section(self):
        response = self.client.get(reverse("extras_portal:home"))

        self.assertEqual(response.status_code, 302)
        self.assertEqual(response.url, reverse("extras_portal:reports"))

    def test_portal_clients_redirects_when_section_not_enabled(self):
        response = self.client.get(reverse("extras_portal:clients"))

        self.assertEqual(response.status_code, 302)
        self.assertEqual(response.url, reverse("extras_portal:reports"))

    def test_portal_finance_redirects_when_section_not_enabled(self):
        response = self.client.get(reverse("extras_portal:finance"))

        self.assertEqual(response.status_code, 302)
        self.assertEqual(response.url, reverse("extras_portal:reports"))


@override_settings(
    STORAGES={
        "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
        "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"},
    }
)
class ExtrasPortalMultiRequestSectionsTests(TestCase):
    def setUp(self):
        user_model = get_user_model()
        self.provider_user = user_model.objects.create_user(
            phone="0500000920",
            username="portal_provider_multi",
            password="secret",
        )
        self.provider_profile = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مختص بوابة متعددة",
            bio="ملف اختباري",
            years_experience=4,
        )
        self.client.force_login(self.provider_user)
        session = self.client.session
        session[SESSION_PORTAL_OTP_VERIFIED_KEY] = True
        session.save()

        self.reports_bundle_request = self._create_closed_bundle_request(
            source_object_id="bundle-portal-reports",
            invoice_id=9201,
            bundle={
                "reports": {
                    "enabled": True,
                    "options": ["platform_metrics", "platform_visits"],
                    "start_at": "2026-04-01",
                    "end_at": "2026-04-10",
                },
                "clients": {"enabled": False, "options": [], "subscription_years": 1},
                "finance": {"enabled": False, "options": [], "subscription_years": 1},
            },
            paid_at=timezone.make_aware(datetime(2026, 4, 10, 19, 40)),
        )
        self.clients_bundle_request = self._create_closed_bundle_request(
            source_object_id="bundle-portal-clients",
            invoice_id=9202,
            bundle={
                "reports": {"enabled": False, "options": []},
                "clients": {
                    "enabled": True,
                    "options": ["platform_clients_list", "bulk_messages"],
                    "subscription_years": 2,
                    "bulk_message_count": 500,
                },
                "finance": {"enabled": False, "options": [], "subscription_years": 1},
            },
            paid_at=timezone.make_aware(datetime(2026, 4, 12, 19, 40)),
        )
        self.finance_bundle_request = self._create_closed_bundle_request(
            source_object_id="bundle-portal-finance",
            invoice_id=9203,
            bundle={
                "reports": {"enabled": False, "options": []},
                "clients": {"enabled": False, "options": [], "subscription_years": 1},
                "finance": {
                    "enabled": True,
                    "options": ["bank_qr_registration", "financial_statement"],
                    "subscription_years": 1,
                    "qr_first_name": "أحمد",
                    "qr_last_name": "محمد",
                    "iban": "SA0380000000608010167519",
                },
            },
            paid_at=timezone.make_aware(datetime(2026, 4, 13, 19, 40)),
        )

        ExtrasPortalSubscription.objects.create(
            provider=self.provider_profile,
            status=ExtrasPortalSubscriptionStatus.ACTIVE,
            plan_title="التقارير / إدارة العملاء / الإدارة المالية",
            started_at=timezone.make_aware(datetime(2026, 4, 10, 19, 40)),
            ends_at=timezone.make_aware(datetime(2028, 4, 12, 19, 40)),
        )

    def _create_closed_bundle_request(self, *, source_object_id: str, invoice_id: int, bundle: dict, paid_at):
        request_obj = UnifiedRequest.objects.create(
            request_type=UnifiedRequestType.EXTRAS,
            status="closed",
            priority="normal",
            requester=self.provider_user,
            assigned_team_code="extras",
            assigned_team_name="فريق إدارة الخدمات الإضافية",
            source_app="extras",
            source_model="ExtrasBundleRequest",
            source_object_id=source_object_id,
            summary=f"طلب {source_object_id}",
            updated_at=paid_at,
        )
        invoice = Invoice.objects.create(
            id=invoice_id,
            code=f"IVT{invoice_id}",
            user=self.provider_user,
            title=f"فاتورة {source_object_id}",
            reference_type="extras_bundle_request",
            reference_id=request_obj.code,
            currency="SAR",
            subtotal=Decimal("200.00"),
            vat_percent=Decimal("15.00"),
            status="pending",
        )
        invoice.mark_payment_confirmed(
            provider="mock",
            provider_reference=f"portal-multi-payment-{invoice_id}",
            event_id=f"portal-multi-payment-{invoice_id}",
            amount=invoice.total,
            currency=invoice.currency,
            when=paid_at,
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
        metadata, _ = UnifiedRequestMetadata.objects.get_or_create(request=request_obj)
        metadata.payload = {
            "invoice_id": invoice.id,
            "bundle": bundle,
        }
        metadata.save(update_fields=["payload"])
        return request_obj

    def test_portal_navigation_unions_enabled_sections_across_closed_requests(self):
        response = self.client.get(reverse("extras_portal:home"))

        self.assertEqual(response.status_code, 302)
        self.assertEqual(response.url, reverse("extras_portal:reports"))

        reports_response = self.client.get(reverse("extras_portal:reports"))
        self.assertEqual(reports_response.status_code, 200)
        nav_keys = [item["key"] for item in reports_response.context["portal_nav_items"]]
        self.assertEqual(nav_keys, ["reports", "clients", "finance"])

        clients_response = self.client.get(reverse("extras_portal:clients"))
        self.assertEqual(clients_response.status_code, 200)
        self.assertContains(clients_response, "إدارة العملاء")

        finance_response = self.client.get(reverse("extras_portal:finance"))
        self.assertEqual(finance_response.status_code, 200)
        self.assertContains(finance_response, "كشف الحساب")

    def test_clients_page_shows_clients_request_details_from_active_bundle(self):
        response = self.client.get(reverse("extras_portal:clients"))

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, self.clients_bundle_request.code)
        self.assertContains(response, "قوائم عملاء منصتي")
        self.assertContains(response, "إرسال الرسائل الجماعية لعملائي")
        self.assertContains(response, "2 سنة")
        self.assertContains(response, "500 رسالة")
        self.assertTrue(response.context["clients_supports_bulk_messages"])
        self.assertEqual(response.context["bulk_message_limit"], 500)
        self.assertEqual(response.context["clients_subscription_years"], 2)

    def test_finance_page_shows_finance_request_details_and_request_fallback_values(self):
        response = self.client.get(reverse("extras_portal:finance"))

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, self.finance_bundle_request.code)
        self.assertContains(response, "خدمة تسجيل الحساب البنكي للمختص (QR)")
        self.assertContains(response, "كشف حساب شامل")
        self.assertContains(response, "أحمد محمد")
        self.assertContains(response, "SA0380000000608010167519")
        self.assertTrue(response.context["supports_bank_qr_registration"])
        self.assertTrue(response.context["supports_financial_statement"])
        self.assertEqual(response.context["requested_account_name"], "أحمد محمد")
        self.assertEqual(response.context["requested_iban"], "SA0380000000608010167519")
        self.assertEqual(response.context["form"]["account_name"].value(), "أحمد محمد")
        self.assertEqual(response.context["form"]["iban"].value(), "SA0380000000608010167519")

    def test_clients_page_renders_new_features_when_enabled(self):
        metadata = self.clients_bundle_request.metadata_record
        payload = metadata.payload
        payload["bundle"]["clients"]["options"] = [
            "platform_clients_list",
            "bulk_messages",
            "all_followers",
            "potential_clients_contact",
            "loyalty_program",
            "loyalty_points",
        ]
        metadata.payload = payload
        metadata.save(update_fields=["payload"])

        ProviderFollow.objects.create(
            user=get_user_model().objects.create_user(phone="0500000930", username="follower_one", password="secret"),
            provider=self.provider_profile,
        )

        response = self.client.get(reverse("extras_portal:clients"))

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.context["clients_supports_all_followers"])
        self.assertTrue(response.context["clients_supports_potential"])
        self.assertTrue(response.context["clients_supports_loyalty"])
        self.assertTrue(response.context["clients_supports_points"])
        self.assertEqual(response.context["followers_total_count"], 1)
        self.assertIsNotNone(response.context["loyalty_program"])
        self.assertTrue(response.context["loyalty_program"].is_active)
        self.assertContains(response, "قائمة متابعي المختص")
        self.assertContains(response, "العملاء المحتملون")
        self.assertContains(response, "برنامج الولاء")
        self.assertContains(response, "نظام نقاط العملاء")

    def test_reports_page_shows_all_paid_report_requests_and_items(self):
        latest_report_request = self._create_closed_bundle_request(
            source_object_id="bundle-portal-reports-latest",
            invoice_id=9204,
            bundle={
                "reports": {
                    "enabled": True,
                    "options": ["orders_breakdown", "service_requesters"],
                    "start_at": "2026-04-11",
                    "end_at": "2026-04-15",
                },
                "clients": {"enabled": False, "options": [], "subscription_years": 1},
                "finance": {"enabled": False, "options": [], "subscription_years": 1},
            },
            paid_at=timezone.make_aware(datetime(2026, 4, 14, 19, 40)),
        )

        response = self.client.get(reverse("extras_portal:reports"))

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, self.reports_bundle_request.code)
        self.assertContains(response, latest_report_request.code)
        self.assertEqual(response.context["report_request_count"], 2)
        self.assertEqual(response.context["selected_option_count"], 4)
        self.assertEqual(
            [row["request_code"] for row in response.context["selected_option_rows"]],
            [latest_report_request.code, latest_report_request.code, self.reports_bundle_request.code, self.reports_bundle_request.code],
        )
        self.assertEqual(response.context["request_code"], latest_report_request.code)
        self.assertEqual(
            [row["request_code"] for row in response.context["report_request_summaries"]],
            [latest_report_request.code, self.reports_bundle_request.code],
        )

    def test_reports_page_ignores_newer_unpaid_report_request(self):
        unpaid_request = UnifiedRequest.objects.create(
            request_type=UnifiedRequestType.EXTRAS,
            status="closed",
            priority="normal",
            requester=self.provider_user,
            assigned_team_code="extras",
            assigned_team_name="فريق إدارة الخدمات الإضافية",
            source_app="extras",
            source_model="ExtrasBundleRequest",
            source_object_id="bundle-portal-reports-unpaid",
            summary="طلب تقارير غير مدفوع",
            updated_at=timezone.make_aware(datetime(2026, 4, 15, 19, 40)),
        )
        metadata, _ = UnifiedRequestMetadata.objects.get_or_create(request=unpaid_request)
        metadata.payload = {
            "bundle": {
                "reports": {
                    "enabled": True,
                    "options": ["orders_breakdown"],
                    "start_at": "2026-04-12",
                    "end_at": "2026-04-15",
                },
                "clients": {"enabled": False, "options": [], "subscription_years": 1},
                "finance": {"enabled": False, "options": [], "subscription_years": 1},
            },
        }
        metadata.save(update_fields=["payload"])

        response = self.client.get(reverse("extras_portal:reports"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.context["request_code"], self.reports_bundle_request.code)
        self.assertEqual(response.context["report_request_count"], 1)
        self.assertNotContains(response, unpaid_request.code)


class ScheduledMessageReminderNotificationTests(TestCase):
    def setUp(self):
        user_model = get_user_model()
        self.provider_user = user_model.objects.create_user(
            phone="0500001990",
            username="portal_scheduler_provider",
            password="secret",
        )
        self.provider_profile = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود رسائل مجدولة",
            bio="نبذة",
            years_experience=3,
        )
        self.client_user = user_model.objects.create_user(
            phone="0500001991",
            username="portal_scheduler_client",
            password="secret",
        )
        plan = SubscriptionPlan.objects.create(
            code="portal-scheduled-basic",
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
        ExtrasPortalSubscription.objects.create(
            provider=self.provider_profile,
            status=ExtrasPortalSubscriptionStatus.ACTIVE,
            plan_title="إدارة العملاء",
            started_at=timezone.now() - timedelta(days=1),
            ends_at=timezone.now() + timedelta(days=30),
        )

    def test_due_scheduled_message_creates_provider_notification(self):
        scheduled = ExtrasPortalScheduledMessage.objects.create(
            provider=self.provider_profile,
            body="رسالة متابعة مجدولة",
            send_at=timezone.now() - timedelta(minutes=5),
            status=ScheduledMessageStatus.PENDING,
            created_by=self.provider_user,
        )
        ExtrasPortalScheduledMessageRecipient.objects.create(
            scheduled_message=scheduled,
            user=self.client_user,
        )

        with self.captureOnCommitCallbacks(execute=True):
            result = process_due_scheduled_messages(now=timezone.now())

        scheduled.refresh_from_db()
        self.assertEqual(result["sent"], 1)
        self.assertEqual(scheduled.status, ScheduledMessageStatus.SENT)
        self.assertEqual(Message.objects.filter(sender=self.provider_user).count(), 1)
        notification = Notification.objects.get(user=self.provider_user)
        self.assertIn("التذكير المجدول", notification.title)
        self.assertEqual(notification.audience_mode, Notification.AudienceMode.PROVIDER)

    def test_due_scheduled_message_without_recipients_is_cancelled_without_notification(self):
        scheduled = ExtrasPortalScheduledMessage.objects.create(
            provider=self.provider_profile,
            body="رسالة بلا مستقبلين",
            send_at=timezone.now() - timedelta(minutes=5),
            status=ScheduledMessageStatus.PENDING,
            created_by=self.provider_user,
        )

        with self.captureOnCommitCallbacks(execute=True):
            result = process_due_scheduled_messages(now=timezone.now())

        scheduled.refresh_from_db()
        self.assertEqual(result["cancelled"], 1)
        self.assertEqual(scheduled.status, ScheduledMessageStatus.CANCELLED)
        self.assertFalse(Notification.objects.filter(user=self.provider_user).exists())
