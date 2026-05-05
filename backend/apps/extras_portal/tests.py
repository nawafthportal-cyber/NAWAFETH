from datetime import timedelta

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.utils import timezone

from apps.accounts.models import User, UserRole
from apps.analytics.models import AnalyticsChannel, AnalyticsEvent, ProviderDailyStats
from apps.billing.models import Invoice, InvoiceStatus
from apps.marketplace.models import RequestStatus, RequestType, ServiceRequest
from apps.providers.models import (
    Category,
    ProviderContentShare,
    ProviderLike,
    ProviderPortfolioItem,
    ProviderPortfolioLike,
    ProviderProfile,
    ProviderSpotlightItem,
    ProviderSpotlightLike,
    SubCategory,
)
from apps.messaging.models import Message, Thread
from apps.unified_requests.models import UnifiedRequest, UnifiedRequestMetadata, UnifiedRequestStatus, UnifiedRequestType

from .views import _build_clients_dataset, _build_reports_dashboard_context, _latest_portal_section_context, _portal_shell_context, _report_option_card_catalog


class ReportsVisitMetricsTests(TestCase):
    def setUp(self):
        self.provider_user = User.objects.create_user(
            phone="0503000001",
            username="provider.reports",
            role_state=UserRole.PROVIDER,
        )
        self.provider = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود التقارير",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.category = Category.objects.create(name="التصميم")
        self.subcategory = SubCategory.objects.create(category=self.category, name="تصميم واجهات")

    def test_report_catalog_counts_profile_views_from_raw_events(self):
        now = timezone.now()
        start_at = now - timedelta(days=1)
        end_at = now + timedelta(minutes=1)

        ProviderDailyStats.objects.create(
            day=now.date(),
            provider=self.provider,
            profile_views=0,
        )
        AnalyticsEvent.objects.create(
            event_name="provider.profile_view",
            channel=AnalyticsChannel.MOBILE_WEB,
            source_app="mobile_web",
            object_type="ProviderProfile",
            object_id=str(self.provider.id),
            occurred_at=now - timedelta(hours=2),
        )
        AnalyticsEvent.objects.create(
            event_name="provider.profile_view",
            channel=AnalyticsChannel.FLUTTER,
            source_app="flutter",
            object_type="ProviderProfile",
            object_id=str(self.provider.id),
            occurred_at=now - timedelta(hours=1),
        )

        catalog = _report_option_card_catalog(self.provider, start_at=start_at, end_at=end_at)

        self.assertEqual(catalog["platform_visits"], 2)
        self.assertEqual(
            catalog["option_cards_by_key"]["platform_metrics"]["stats"][0],
            {"label": "زيارات منصتي", "value": "2"},
        )
        self.assertEqual(
            catalog["option_cards_by_key"]["platform_visits"]["stats"][0],
            {"label": "عدد الزيارات", "value": "2"},
        )

    def test_platform_metrics_matches_expected_indicator_set(self):
        now = timezone.now()
        start_at = now - timedelta(days=1)
        end_at = now + timedelta(minutes=1)

        liker_user = User.objects.create_user(
            phone="0503000011",
            username="provider.reports.liker",
            role_state=UserRole.CLIENT,
        )
        profile_liker_user = User.objects.create_user(
            phone="0503000014",
            username="provider.reports.profile.liker",
            role_state=UserRole.CLIENT,
        )
        spotlight_liker_user = User.objects.create_user(
            phone="0503000015",
            username="provider.reports.spotlight.liker",
            role_state=UserRole.CLIENT,
        )
        sharer_user = User.objects.create_user(
            phone="0503000012",
            username="provider.reports.sharer",
            role_state=UserRole.CLIENT,
        )
        client_user = User.objects.create_user(
            phone="0503000013",
            username="provider.reports.client",
            role_state=UserRole.CLIENT,
        )

        portfolio_item = ProviderPortfolioItem.objects.create(
            provider=self.provider,
            file_type="image",
            file=SimpleUploadedFile("portfolio.jpg", b"img", content_type="image/jpeg"),
        )
        ProviderPortfolioLike.objects.create(user=liker_user, item=portfolio_item)
        ProviderLike.objects.create(user=profile_liker_user, provider=self.provider)
        spotlight_item = ProviderSpotlightItem.objects.create(
            provider=self.provider,
            file_type="image",
            file=SimpleUploadedFile("spotlight.jpg", b"img", content_type="image/jpeg"),
        )
        ProviderSpotlightLike.objects.create(user=spotlight_liker_user, item=spotlight_item)
        ProviderContentShare.objects.create(provider=self.provider, user=sharer_user)
        AnalyticsEvent.objects.create(
            event_name="provider.profile_view",
            channel=AnalyticsChannel.MOBILE_WEB,
            source_app="mobile_web",
            object_type="ProviderProfile",
            object_id=str(self.provider.id),
            occurred_at=now - timedelta(hours=2),
        )

        for status in (
            RequestStatus.NEW,
            RequestStatus.PROVIDER_ACCEPTED,
            RequestStatus.AWAITING_CLIENT_APPROVAL,
            RequestStatus.IN_PROGRESS,
            RequestStatus.COMPLETED,
            RequestStatus.CANCELLED,
        ):
            ServiceRequest.objects.create(
                client=client_user,
                provider=self.provider,
                subcategory=self.subcategory,
                title=f"طلب {status}",
                description="تفاصيل",
                request_type=RequestType.NORMAL,
                status=status,
                city="الرياض",
            )

        catalog = _report_option_card_catalog(self.provider, start_at=start_at, end_at=end_at)

        # likes_count should include portfolio + profile + spotlight likes (3 total)
        self.assertEqual(catalog["likes_count"], 3)

        self.assertEqual(
            catalog["option_cards_by_key"]["platform_metrics"]["stats"],
            [
                {"label": "زيارات منصتي", "value": "1"},
                {"label": "عدد التفضيلات لمحتوى منصتي", "value": "3"},
                {"label": "عدد مرات مشاركة منصتي", "value": "1"},
                {"label": "عدد الطلبات الجديدة", "value": "3"},
                {"label": "عدد الطلبات تحت التنفيذ", "value": "1"},
                {"label": "عدد الطلبات المكتملة", "value": "1"},
                {"label": "عدد الطلبات الملغية", "value": "1"},
            ],
        )

        # content_favoriters distinct count should include all 3 unique users
        self.assertEqual(
            catalog["option_cards_by_key"]["content_favoriters"]["badge"],
            "3 عنصر",
        )

        dashboard_context = _build_reports_dashboard_context(self.provider)

        self.assertEqual(
            [(card["title"], str(card["value"])) for card in dashboard_context["overview_cards"]],
            [
                ("زيارات منصتي", "1"),
                ("عدد التفضيلات لمحتوى منصتي", "3"),
                ("عدد مرات مشاركة منصتي", "1"),
                ("عدد الطلبات الجديدة", "3"),
                ("عدد الطلبات تحت التنفيذ", "1"),
                ("عدد الطلبات المكتملة", "1"),
                ("عدد الطلبات الملغية", "1"),
            ],
        )

    def test_messages_count_excludes_system_and_provider_messages(self):
        """Messages metric should exclude system-generated and provider's own messages."""
        now = timezone.now()
        start_at = now - timedelta(days=1)
        end_at = now + timedelta(minutes=1)

        client_user = User.objects.create_user(
            phone="0503000020",
            username="msg.client",
            role_state=UserRole.CLIENT,
        )
        sr = ServiceRequest.objects.create(
            client=client_user,
            provider=self.provider,
            subcategory=self.subcategory,
            title="طلب رسائل",
            description="تفاصيل",
            request_type=RequestType.NORMAL,
            status=RequestStatus.IN_PROGRESS,
            city="الرياض",
        )
        thread = Thread.objects.create(request=sr)
        # Client message (should count)
        Message.objects.create(thread=thread, sender=client_user, body="رسالة عميل")
        # Provider's own message (should NOT count)
        Message.objects.create(thread=thread, sender=self.provider_user, body="رسالة المزود")
        # System message (should NOT count)
        Message.objects.create(thread=thread, sender=client_user, body="رسالة نظام", is_system_generated=True)

        catalog = _report_option_card_catalog(self.provider, start_at=start_at, end_at=end_at)

        self.assertEqual(catalog["messages_count"], 1)

    def test_service_requesters_stays_scoped_to_request_history_not_followers(self):
        now = timezone.now()
        start_at = now - timedelta(days=1)
        end_at = now + timedelta(minutes=1)

        requester_user = User.objects.create_user(
            phone="0503000021",
            username="report.requester",
            role_state=UserRole.CLIENT,
        )
        follower_only_user = User.objects.create_user(
            phone="0503000022",
            username="report.follower",
            role_state=UserRole.CLIENT,
        )

        ServiceRequest.objects.create(
            client=requester_user,
            provider=self.provider,
            subcategory=self.subcategory,
            title="طلب تقرير",
            description="تفاصيل",
            request_type=RequestType.NORMAL,
            status=RequestStatus.CANCELLED,
            city="الرياض",
        )
        from apps.providers.models import ProviderFollow

        ProviderFollow.objects.create(provider=self.provider, user=follower_only_user)

        catalog = _report_option_card_catalog(self.provider, start_at=start_at, end_at=end_at)

        requesters_entries = catalog["option_cards_by_key"]["service_requesters"]["entries"]
        followers_entries = catalog["option_cards_by_key"]["platform_followers"]["entries"]
        self.assertEqual(catalog["option_cards_by_key"]["service_requesters"]["badge"], "1 عنصر")
        self.assertEqual(catalog["option_cards_by_key"]["platform_followers"]["badge"], "1 عنصر")
        self.assertEqual(requesters_entries[0]["primary"], "@report.requester")
        self.assertEqual(followers_entries[0]["primary"], "@report.follower")


class ClientsDatasetClassificationTests(TestCase):
    def setUp(self):
        self.provider_user = User.objects.create_user(
            phone="0503000101",
            username="provider.clients.dataset",
            role_state=UserRole.PROVIDER,
        )
        self.provider = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود العملاء",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.category = Category.objects.create(name="الخدمات")
        self.subcategory = SubCategory.objects.create(category=self.category, name="استشارة")

    def test_historical_clients_dataset_uses_service_requests_only(self):
        requester_user = User.objects.create_user(
            phone="0503000102",
            username="dataset.requester",
            role_state=UserRole.CLIENT,
        )
        follower_only_user = User.objects.create_user(
            phone="0503000103",
            username="dataset.follower",
            role_state=UserRole.CLIENT,
        )

        ServiceRequest.objects.create(
            client=requester_user,
            provider=self.provider,
            subcategory=self.subcategory,
            title="طلب تاريخي",
            description="تفاصيل",
            request_type=RequestType.NORMAL,
            status=RequestStatus.CANCELLED,
            city="الرياض",
        )
        from apps.providers.models import ProviderFollow

        ProviderFollow.objects.create(provider=self.provider, user=follower_only_user)

        dataset = _build_clients_dataset(
            self.provider,
            {
                "section_payload": {"subscription_years": 1},
                "option_keys": ["historical_clients"],
                "effective_at": timezone.now() - timedelta(days=30),
            },
        )

        usernames = {row["user"].username for row in dataset["enriched_clients"]}
        self.assertEqual(usernames, {"dataset.requester"})


class ReportsBundleContextSelectionTests(TestCase):
    def setUp(self):
        self.provider_user = User.objects.create_user(
            phone="0503000002",
            username="provider.bundle",
            role_state=UserRole.PROVIDER,
        )
        self.provider = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود الباقات",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.category = Category.objects.create(name="فئة التقارير")
        self.subcategory = SubCategory.objects.create(category=self.category, name="تقارير")

    def _create_paid_report_request(self, *, start_at, end_at, payment_confirmed_at):
        request_obj = UnifiedRequest.objects.create(
            request_type=UnifiedRequestType.EXTRAS,
            status=UnifiedRequestStatus.CLOSED,
            priority="normal",
            requester=self.provider_user,
            source_app="extras",
            source_model="ExtrasBundleRequest",
            source_object_id=f"bundle-{timezone.now().timestamp()}",
            summary="طلب تقارير",
        )
        UnifiedRequestMetadata.objects.create(
            request=request_obj,
            payload={
                "bundle": {
                    "reports": {
                        "options": ["platform_metrics", "platform_visits"],
                        "start_at": start_at.isoformat(),
                        "end_at": end_at.isoformat(),
                    },
                    "clients": {"options": []},
                    "finance": {"options": []},
                }
            },
            updated_by=self.provider_user,
        )
        invoice = Invoice.objects.create(
            user=self.provider_user,
            title="فاتورة تقارير",
            description="فاتورة",
            currency="SAR",
            subtotal="100.00",
            vat_percent="15.00",
            reference_type="extras_bundle_request",
            reference_id=request_obj.code,
            status=InvoiceStatus.PAID,
            payment_confirmed=True,
            payment_confirmed_at=payment_confirmed_at,
        )
        return request_obj, invoice

    def test_latest_portal_section_context_ignores_expired_report_bundle(self):
        now = timezone.now()
        self._create_paid_report_request(
            start_at=now - timedelta(days=500),
            end_at=now - timedelta(days=420),
            payment_confirmed_at=now - timedelta(days=500),
        )
        active_request, _ = self._create_paid_report_request(
            start_at=now - timedelta(days=30),
            end_at=now + timedelta(days=30),
            payment_confirmed_at=now - timedelta(days=2),
        )

        section_context = _latest_portal_section_context(self.provider, "reports")

        self.assertEqual(getattr(section_context.get("request_obj"), "id", None), active_request.id)
        self.assertEqual(section_context.get("option_keys"), ["platform_metrics", "platform_visits"])

    def test_latest_portal_section_context_prefers_latest_paid_bundle_not_latest_updated_at(self):
        now = timezone.now()
        older_paid_request, _ = self._create_paid_report_request(
            start_at=now - timedelta(days=90),
            end_at=now + timedelta(days=60),
            payment_confirmed_at=now - timedelta(days=20),
        )
        latest_paid_request, _ = self._create_paid_report_request(
            start_at=now - timedelta(days=10),
            end_at=now + timedelta(days=50),
            payment_confirmed_at=now - timedelta(days=1),
        )

        UnifiedRequest.objects.filter(id=older_paid_request.id).update(updated_at=now + timedelta(days=2))

        section_context = _latest_portal_section_context(self.provider, "reports")

        self.assertEqual(getattr(section_context.get("request_obj"), "id", None), latest_paid_request.id)

    def test_portal_shell_context_unions_sections_across_paid_bundles(self):
        now = timezone.now()
        self._create_paid_report_request(
            start_at=now - timedelta(days=14),
            end_at=now + timedelta(days=14),
            payment_confirmed_at=now - timedelta(days=3),
        )

        clients_request = UnifiedRequest.objects.create(
            request_type=UnifiedRequestType.EXTRAS,
            status=UnifiedRequestStatus.CLOSED,
            priority="normal",
            requester=self.provider_user,
            source_app="extras",
            source_model="ExtrasBundleRequest",
            source_object_id=f"bundle-clients-{timezone.now().timestamp()}",
            summary="طلب عملاء",
        )
        UnifiedRequestMetadata.objects.create(
            request=clients_request,
            payload={
                "bundle": {
                    "reports": {"options": []},
                    "clients": {"options": ["lead_generation"], "subscription_years": 1},
                    "finance": {"options": []},
                }
            },
            updated_by=self.provider_user,
        )
        Invoice.objects.create(
            user=self.provider_user,
            title="فاتورة عملاء",
            description="فاتورة",
            currency="SAR",
            subtotal="100.00",
            vat_percent="15.00",
            reference_type="extras_bundle_request",
            reference_id=clients_request.code,
            status=InvoiceStatus.PAID,
            payment_confirmed=True,
            payment_confirmed_at=now - timedelta(days=1),
        )

        shell_context = _portal_shell_context(self.provider, active_section="reports")

        self.assertEqual(
            [item["key"] for item in shell_context.get("portal_nav_items", [])],
            ["reports", "clients"],
        )

    def test_reports_dashboard_context_uses_dashboard_bundle_period(self):
        now = timezone.now().replace(second=0, microsecond=0)
        start_at = now - timedelta(days=3)
        end_at = now + timedelta(days=3)
        payment_confirmed_at = now - timedelta(hours=2)

        request_obj = UnifiedRequest.objects.create(
            request_type=UnifiedRequestType.EXTRAS,
            status=UnifiedRequestStatus.CLOSED,
            priority="normal",
            requester=self.provider_user,
            source_app="dashboard",
            source_model="ExtrasServiceRequest",
            source_object_id=f"dashboard-bundle-{timezone.now().timestamp()}",
            summary="طلب تقارير من لوحة الإدارة",
        )
        UnifiedRequestMetadata.objects.create(
            request=request_obj,
            payload={
                "flow_type": "extras_bundle_wizard",
                "specialist_identifier": self.provider_user.username,
                "specialist_label": self.provider.display_name,
                "reports": {
                    "options": ["platform_metrics", "service_orders_detail"],
                    "start_at": start_at.isoformat(),
                    "end_at": end_at.isoformat(),
                },
                "clients": {"options": []},
                "finance": {"options": []},
                "summary_sections": [],
                "bundle": {
                    "reports": {
                        "options": ["platform_metrics", "service_orders_detail"],
                        "start_at": start_at.isoformat(),
                        "end_at": end_at.isoformat(),
                    },
                    "clients": {"options": []},
                    "finance": {"options": []},
                    "summary_sections": [],
                },
            },
            updated_by=self.provider_user,
        )
        Invoice.objects.create(
            user=self.provider_user,
            title="فاتورة تقارير الداشبورد",
            description="فاتورة",
            currency="SAR",
            subtotal="100.00",
            vat_percent="15.00",
            reference_type="extras_bundle_request",
            reference_id=request_obj.code,
            status=InvoiceStatus.PAID,
            payment_confirmed=True,
            payment_confirmed_at=payment_confirmed_at,
        )

        inside_request = ServiceRequest.objects.create(
            client=User.objects.create_user(
                phone="0503000111",
                username="bundle.window.inside",
                role_state=UserRole.CLIENT,
            ),
            provider=self.provider,
            subcategory=self.subcategory,
            title="طلب داخل الفترة",
            description="تفاصيل",
            request_type=RequestType.NORMAL,
            status=RequestStatus.NEW,
            city="الرياض",
        )
        outside_request = ServiceRequest.objects.create(
            client=User.objects.create_user(
                phone="0503000112",
                username="bundle.window.outside",
                role_state=UserRole.CLIENT,
            ),
            provider=self.provider,
            subcategory=self.subcategory,
            title="طلب خارج الفترة",
            description="تفاصيل",
            request_type=RequestType.NORMAL,
            status=RequestStatus.NEW,
            city="الرياض",
        )
        ServiceRequest.objects.filter(id=inside_request.id).update(created_at=start_at + timedelta(hours=1))
        ServiceRequest.objects.filter(id=outside_request.id).update(created_at=start_at - timedelta(days=10))

        dashboard_context = _build_reports_dashboard_context(self.provider)

        self.assertEqual(dashboard_context.get("request_code"), request_obj.code)
        self.assertEqual(
            dashboard_context.get("bundle_context", {}).get("start_label"),
            timezone.localtime(start_at).strftime("%d/%m/%Y - %H:%M"),
        )
        self.assertEqual(
            dashboard_context.get("bundle_context", {}).get("end_label"),
            timezone.localtime(end_at).strftime("%d/%m/%Y - %H:%M"),
        )
        self.assertEqual(dashboard_context.get("report_request_count"), 1)
        self.assertEqual(dashboard_context.get("totals", {}).get("new_requests"), 1)
        self.assertEqual(
            dashboard_context.get("report_request_groups", [])[0]["option_groups"][0]["cards"][0]["stats"][3],
            {"label": "عدد الطلبات الجديدة", "value": "1"},
        )
