from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import OTP, User, UserRole
from apps.analytics.models import AnalyticsEvent
from apps.billing.models import Invoice, InvoiceStatus, PaymentAttempt, PaymentAttemptStatus, PaymentProvider
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.dashboard.views import EXTRAS_REPORT_OPTIONS, _collect_reports, _extras_report_option_groups
from apps.extras.services import extras_bundle_payload_for_request
from apps.extras.option_catalog import EXTRAS_REPORT_OPTIONS as CATALOG_EXTRAS_REPORT_OPTIONS
from apps.extras_portal.models import ExtrasPortalSubscription
from apps.marketplace.models import RequestStatus, RequestType, ServiceRequest
from apps.messaging.models import Thread
from apps.notifications.models import DeviceToken
from apps.providers.models import (
    Category,
    ProviderContentComment,
    ProviderContentCommentLike,
    ProviderContentShare,
    ProviderFollow,
    ProviderPortfolioItem,
    ProviderPortfolioLike,
    ProviderProfile,
    ProviderService,
    ProviderSpotlightItem,
    ProviderSpotlightLike,
    SubCategory,
)
from apps.reviews.models import Review
from apps.subscriptions.models import PlanTier, Subscription, SubscriptionPlan, SubscriptionStatus
from apps.support.models import SupportTicket, SupportTicketType
from apps.unified_requests.models import UnifiedRequest, UnifiedRequestMetadata, UnifiedRequestStatus, UnifiedRequestType
from apps.verification.models import VerificationBadgeType, VerificationRequest


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

    def test_dashboard_created_report_request_persists_bundle_period(self):
        start_at = timezone.now().replace(second=0, microsecond=0)
        end_at = start_at + timezone.timedelta(days=14)
        current_timezone = timezone.get_current_timezone()
        expected_start_at = timezone.make_aware(start_at.replace(tzinfo=None), current_timezone)
        expected_end_at = timezone.make_aware(end_at.replace(tzinfo=None), current_timezone)

        save_response = self.client.post(
            reverse("dashboard:extras_dashboard"),
            {
                "action": "save_extras_bundle_reports",
                "specialist_identifier": self.provider_user.username,
                "reports_options": ["platform_metrics", "platform_visits"],
                "reports_start_at": start_at.strftime("%Y-%m-%dT%H:%M"),
                "reports_end_at": end_at.strftime("%Y-%m-%dT%H:%M"),
            },
        )
        self.assertEqual(save_response.status_code, 302)

        submit_response = self.client.post(
            reverse("dashboard:extras_dashboard"),
            {
                "action": "submit_extras_bundle_request",
                "specialist_identifier": self.provider_user.username,
            },
        )
        self.assertEqual(submit_response.status_code, 302)

        request_obj = UnifiedRequest.objects.filter(
            request_type=UnifiedRequestType.EXTRAS,
            source_app="dashboard",
            source_model="ExtrasServiceRequest",
            requester=self.provider_user,
        ).latest("id")

        payload = request_obj.metadata_record.payload
        bundle = payload.get("bundle") if isinstance(payload.get("bundle"), dict) else {}
        reports = bundle.get("reports") if isinstance(bundle.get("reports"), dict) else {}

        self.assertEqual(reports.get("options"), ["platform_metrics", "platform_visits"])
        self.assertEqual(reports.get("start_at"), expected_start_at.isoformat())
        self.assertEqual(reports.get("end_at"), expected_end_at.isoformat())
        self.assertEqual(
            extras_bundle_payload_for_request(request_obj).get("reports", {}).get("start_at"),
            expected_start_at.isoformat(),
        )


class DashboardExtrasCatalogParityTests(TestCase):
    def test_dashboard_report_options_match_provider_request_catalog(self):
        self.assertEqual(EXTRAS_REPORT_OPTIONS, CATALOG_EXTRAS_REPORT_OPTIONS)

    def test_dashboard_report_groups_include_every_catalog_option(self):
        grouped_keys = [
            option["key"]
            for group in _extras_report_option_groups()
            for option in group["options"]
        ]
        catalog_keys = [key for key, _label in CATALOG_EXTRAS_REPORT_OPTIONS]

        self.assertEqual(grouped_keys, catalog_keys)
        self.assertIn("service_orders_detail", grouped_keys)


class AdminControlReportsCollectionTests(TestCase):
    def _metric_cell(self, report: dict, section_title: str, metric_label: str):
        for section in report.get("metric_sections", []):
            if section.get("title") != section_title:
                continue
            for row in section.get("rows", []):
                for cell in row:
                    if cell.get("label") == metric_label:
                        return cell
        self.fail(f"Metric not found: {section_title} / {metric_label}")

    def _metric_value(self, report: dict, section_title: str, metric_label: str):
        return self._metric_cell(report, section_title, metric_label).get("value")

    def test_collect_reports_interaction_metrics_match_current_dashboard_contract(self):
        today = timezone.localdate()

        client_user = User.objects.create_user(
            phone="0503390001",
            username="client.report.interaction",
            role_state=UserRole.CLIENT,
        )
        provider_user = User.objects.create_user(
            phone="0503390002",
            username="provider.report.interaction",
            role_state=UserRole.PROVIDER,
        )

        provider = ProviderProfile.objects.create(
            user=provider_user,
            provider_type="individual",
            display_name="مزود تفاعل",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
        )
        category = Category.objects.create(name="التصميم")
        subcategory = SubCategory.objects.create(category=category, name="تصميم المحتوى")

        request_new = ServiceRequest.objects.create(
            client=client_user,
            subcategory=subcategory,
            title="طلب تفاعل جديد",
            description="-",
            request_type=RequestType.NORMAL,
            status=RequestStatus.NEW,
            city="الرياض",
        )
        request_completed = ServiceRequest.objects.create(
            client=client_user,
            provider=provider,
            subcategory=subcategory,
            title="طلب تفاعل مكتمل",
            description="-",
            request_type=RequestType.NORMAL,
            status=RequestStatus.COMPLETED,
            city="الرياض",
        )

        Thread.objects.create(request=request_new)
        Review.objects.create(request=request_completed, provider=provider, client=client_user, rating=5, comment="ممتاز")

        portfolio_item = ProviderPortfolioItem.objects.create(
            provider=provider,
            file_type="image",
            file=SimpleUploadedFile("interaction-portfolio.jpg", b"portfolio", content_type="image/jpeg"),
            caption="مشروع",
        )
        spotlight_item = ProviderSpotlightItem.objects.create(
            provider=provider,
            file_type="image",
            file=SimpleUploadedFile("interaction-spotlight.jpg", b"spotlight", content_type="image/jpeg"),
            caption="لمحة",
        )
        ProviderPortfolioLike.objects.create(user=client_user, item=portfolio_item)
        ProviderSpotlightLike.objects.create(user=client_user, item=spotlight_item)
        comment = ProviderContentComment.objects.create(
            provider=provider,
            user=client_user,
            portfolio_item=portfolio_item,
            body="تعليق على المشروع",
        )
        ProviderContentCommentLike.objects.create(user=provider_user, comment=comment)

        SupportTicket.objects.create(requester=client_user, ticket_type=SupportTicketType.SUGGEST, description="اقتراح")

        report = _collect_reports(today, today)

        self.assertEqual(self._metric_value(report, "إحصاءات التفاعل", "عدد المحادثات"), 1)
        self.assertEqual(self._metric_value(report, "إحصاءات التفاعل", "عدد التعليقات"), 1)
        self.assertEqual(self._metric_value(report, "إحصاءات التفاعل", "عدد عمليات التقييم"), 1)
        self.assertEqual(self._metric_value(report, "إحصاءات التفاعل", "عدد عمليات الإعجاب بالمحتوى"), 3)
        self.assertEqual(self._metric_value(report, "إحصاءات التفاعل", "عدد مواد المحتوى المرفوع"), 1)
        self.assertEqual(self._metric_value(report, "إحصاءات التفاعل", "عدد التلميحات المرفوعة"), 1)
        self.assertEqual(self._metric_value(report, "إحصاءات التفاعل", "عدد طلبات الدعم والمساعدة الكل"), 1)
        self.assertEqual(self._metric_value(report, "إحصاءات التفاعل", "عدد طلبات الدعم والمساعدة (اقتراح)"), 1)
        self.assertFalse(self._metric_cell(report, "إحصاءات التفاعل", "عدد عمليات التوصية بالمنصة").get("available", True))
        self.assertFalse(self._metric_cell(report, "إحصاءات التفاعل", "عدد عمليات التوصية بالمختصين").get("available", True))
        self.assertIn("قريبًا", self._metric_cell(report, "إحصاءات التفاعل", "عدد عمليات التوصية بالمنصة").get("note", ""))

    def test_collect_reports_matches_extended_dashboard_metrics(self):
        today = timezone.localdate()
        now = timezone.now()

        client_user = User.objects.create_user(
            phone="0503300001",
            username="client.report.user",
            role_state=UserRole.CLIENT,
            terms_accepted_at=now,
        )
        guest_user = User.objects.create_user(phone="0503300002", role_state=UserRole.VISITOR)
        phone_only_user = User.objects.create_user(phone="0503300003", role_state=UserRole.PHONE_ONLY)
        provider_user = User.objects.create_user(
            phone="0503300004",
            username="provider.report.user",
            role_state=UserRole.PROVIDER,
        )
        staff_user = User.objects.create_user(
            phone="0503300005",
            username="staff.report.user",
            role_state=UserRole.STAFF,
        )
        staff_user.is_staff = True
        staff_user.save(update_fields=["is_staff"])

        provider = ProviderProfile.objects.create(
            user=provider_user,
            provider_type="individual",
            display_name="مزود تقارير",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
        )
        category = Category.objects.create(name="التسويق")
        subcategory = SubCategory.objects.create(category=category, name="إدارة الحملات")

        request_new = ServiceRequest.objects.create(
            client=client_user,
            subcategory=subcategory,
            title="طلب جديد",
            description="-",
            request_type=RequestType.NORMAL,
            status=RequestStatus.NEW,
            city="الرياض",
        )
        ServiceRequest.objects.create(
            client=client_user,
            provider=provider,
            subcategory=subcategory,
            title="طلب بانتظار التنفيذ",
            description="-",
            request_type=RequestType.NORMAL,
            status=RequestStatus.PROVIDER_ACCEPTED,
            city="الرياض",
        )
        ServiceRequest.objects.create(
            client=client_user,
            provider=provider,
            subcategory=subcategory,
            title="طلب قيد التنفيذ",
            description="-",
            request_type=RequestType.NORMAL,
            status=RequestStatus.IN_PROGRESS,
            city="الرياض",
        )
        request_completed = ServiceRequest.objects.create(
            client=client_user,
            provider=provider,
            subcategory=subcategory,
            title="طلب مكتمل",
            description="-",
            request_type=RequestType.NORMAL,
            status=RequestStatus.COMPLETED,
            city="الرياض",
        )
        ServiceRequest.objects.create(
            client=client_user,
            provider=provider,
            subcategory=subcategory,
            title="طلب ملغي",
            description="-",
            request_type=RequestType.NORMAL,
            status=RequestStatus.CANCELLED,
            city="الرياض",
        )

        Thread.objects.create(request=request_new)
        Review.objects.create(request=request_completed, provider=provider, client=client_user, rating=5, comment="ممتاز")

        portfolio_item = ProviderPortfolioItem.objects.create(
            provider=provider,
            file_type="image",
            file=SimpleUploadedFile("portfolio.jpg", b"portfolio", content_type="image/jpeg"),
            caption="معرض",
        )
        spotlight_item = ProviderSpotlightItem.objects.create(
            provider=provider,
            file_type="image",
            file=SimpleUploadedFile("spotlight.jpg", b"spotlight", content_type="image/jpeg"),
            caption="أضواء",
        )
        ProviderService.objects.create(provider=provider, subcategory=subcategory, title="خدمة نشطة", description="-", is_active=True)
        ProviderContentShare.objects.create(provider=provider, user=client_user, content_type="profile", content_id=provider.id, channel="copy_link")
        ProviderFollow.objects.create(user=client_user, provider=provider)
        ProviderPortfolioLike.objects.create(user=client_user, item=portfolio_item)
        ProviderSpotlightLike.objects.create(user=client_user, item=spotlight_item)
        comment = ProviderContentComment.objects.create(provider=provider, user=client_user, portfolio_item=portfolio_item, body="رائع")
        ProviderContentCommentLike.objects.create(user=provider_user, comment=comment)

        SupportTicket.objects.create(requester=client_user, ticket_type=SupportTicketType.SUGGEST, description="اقتراح")
        SupportTicket.objects.create(requester=client_user, ticket_type=SupportTicketType.VERIFY, description="توثيق")
        SupportTicket.objects.create(requester=client_user, ticket_type=SupportTicketType.COMPLAINT, description="شكوى")

        DeviceToken.objects.create(user=client_user, token="ios-token", platform="ios")
        DeviceToken.objects.create(user=client_user, token="android-token", platform="android")

        AnalyticsEvent.objects.create(
            event_name="search.result_click",
            session_id="session-a",
            occurred_at=now,
        )
        AnalyticsEvent.objects.create(
            event_name="search.direct_request_click",
            session_id="session-a",
            occurred_at=now + timezone.timedelta(minutes=10),
        )
        AnalyticsEvent.objects.create(
            event_name="provider.profile_view",
            session_id="session-b",
            occurred_at=now,
        )

        OTP.objects.create(phone=client_user.phone, code="1234", expires_at=now + timezone.timedelta(minutes=5))

        basic_plan = SubscriptionPlan.objects.create(code="basic-month", title="أساسية", tier=PlanTier.BASIC)
        riyadi_plan = SubscriptionPlan.objects.create(code="riyadi-month", title="ريادية", tier=PlanTier.RIYADI)
        pro_plan = SubscriptionPlan.objects.create(code="pro-month", title="احترافية", tier=PlanTier.PRO)
        Subscription.objects.create(user=provider_user, plan=basic_plan, status=SubscriptionStatus.ACTIVE)
        Subscription.objects.create(user=client_user, plan=riyadi_plan, status=SubscriptionStatus.ACTIVE)
        Subscription.objects.create(user=staff_user, plan=pro_plan, status=SubscriptionStatus.ACTIVE)

        VerificationRequest.objects.create(requester=client_user, badge_type=VerificationBadgeType.BLUE)
        VerificationRequest.objects.create(requester=provider_user, badge_type=VerificationBadgeType.GREEN)

        invoice = Invoice.objects.create(
            user=client_user,
            title="فاتورة اشتراك",
            description="-",
            currency="SAR",
            subtotal="100.00",
            reference_type="extras",
            reference_id="extras-report-1",
            status=InvoiceStatus.PAID,
            paid_at=now,
            payment_confirmed=True,
        )
        PaymentAttempt.objects.create(
            invoice=invoice,
            provider=PaymentProvider.MOCK,
            status=PaymentAttemptStatus.FAILED,
            amount="100.00",
            currency="SAR",
        )

        report = _collect_reports(today, today)

        self.assertEqual(self._metric_value(report, "إحصاءات المستخدمين", "عدد تحميلات التطبيق IOS"), 1)
        self.assertEqual(self._metric_value(report, "إحصاءات المستخدمين", "عدد تحميلات التطبيق Android"), 1)
        self.assertEqual(self._metric_value(report, "إحصاءات المستخدمين", "عدد المستخدمين الكلي (رقم جوال فقط)"), 1)
        self.assertEqual(self._metric_value(report, "إحصاءات المستخدمين", "عدد المستخدمين كمزود خدمة"), 1)
        self.assertEqual(self._metric_value(report, "إحصاءات الطلبات", "عدد الطلبات الجديدة"), 2)
        self.assertEqual(self._metric_value(report, "إحصاءات التفاعل", "عدد المحادثات"), 1)
        self.assertEqual(self._metric_value(report, "إحصاءات التفاعل", "عدد التعليقات"), 1)
        self.assertEqual(self._metric_value(report, "إحصاءات التفاعل", "عدد عمليات الإعجاب بالمحتوى"), 3)
        self.assertEqual(self._metric_value(report, "إحصاءات التفاعل", "عدد مواد المحتوى المرفوع"), 1)
        self.assertEqual(self._metric_value(report, "إحصاءات التفاعل", "عدد التلميحات المرفوعة"), 1)
        self.assertEqual(self._metric_value(report, "إحصاءات التفاعل", "عدد طلبات الدعم والمساعدة (اقتراح)"), 1)
        self.assertFalse(self._metric_cell(report, "إحصاءات التفاعل", "عدد عمليات التوصية بالمنصة").get("available", True))
        self.assertFalse(self._metric_cell(report, "إحصاءات التفاعل", "عدد عمليات التوصية بالمختصين").get("available", True))
        self.assertEqual(self._metric_value(report, "إحصاءات الدعم", "عدد طلبات الدعم والمساعدة (توثيق)"), 1)
        self.assertEqual(self._metric_value(report, "إحصاءات البحث", "عدد عمليات البحث الكلية"), 2)
        self.assertEqual(self._metric_value(report, "إحصاءات البحث", "عدد عمليات طلبات العروض"), 1)
        self.assertEqual(self._metric_value(report, "إحصاءات الخدمات المدفوعة", "عدد المشتركين في الخدمة الأساسية"), 1)
        self.assertEqual(self._metric_value(report, "إحصاءات الخدمات المدفوعة", "عدد عمليات توثيق الشارة الزرقاء"), 1)
        self.assertEqual(self._metric_value(report, "إحصاءات الدفع الإلكتروني", "عدد عمليات الدفع الفاشلة"), 1)
        self.assertEqual(self._metric_value(report, "إحصاءات الزوار", "عدد زوار التطبيق"), 2)
        self.assertEqual(self._metric_value(report, "إحصاءات الزوار", "متوسط عدد المستخدمين خلال يوم واحد"), 2.0)
        self.assertEqual(self._metric_value(report, "إحصاءات الزوار", "متوسط مدة تواجد الزائر في التطبيق"), 5.0)


class DashboardContentCategoriesTests(TestCase):
    def setUp(self):
        self.staff = User.objects.create_user(
            phone="0503201001",
            username="content.categories.staff",
            password="pass1234",
            role_state=UserRole.STAFF,
        )
        self.staff.is_staff = True
        self.staff.is_superuser = True
        self.staff.save(update_fields=["is_staff", "is_superuser"])
        self.category = Category.objects.create(name="الخدمات المنزلية")

        self.client.force_login(self.staff)
        session = self.client.session
        session[SESSION_OTP_VERIFIED_KEY] = True
        session.save()

    def test_content_categories_page_loads(self):
        response = self.client.get(reverse("dashboard:content_categories"))

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "إدارة التصنيفات")

    def test_content_categories_can_create_subcategory_policy(self):
        response = self.client.post(
            reverse("dashboard:content_categories"),
            {
                "action": "save_subcategory",
                "category": str(self.category.id),
                "name": "سباكة",
                "requires_geo_scope": "on",
                "allows_urgent_requests": "on",
                "is_active": "on",
            },
        )

        self.assertEqual(response.status_code, 302)
        subcategory = SubCategory.objects.get(category=self.category, name="سباكة")
        self.assertTrue(subcategory.requires_geo_scope)
        self.assertTrue(subcategory.allows_urgent_requests)
        self.assertTrue(subcategory.is_active)
