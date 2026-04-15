from datetime import timedelta
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from django.contrib.auth import get_user_model
from django.core.exceptions import PermissionDenied
from django.http import HttpResponse
from django.test import Client, RequestFactory, TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import UserRole
from apps.notifications.models import Notification
from apps.marketplace.models import RequestStatus, RequestType
from apps.marketplace.models import RequestStatusLog, ServiceRequest
from apps.marketplace.serializers import ServiceRequestListSerializer
from apps.marketplace.services.dispatch import dispatch_due_competitive_request_notifications, ensure_dispatch_windows_for_urgent_request
from apps.marketplace.services.actions import execute_action
from apps.marketplace.views import provider_requests
from apps.providers.models import Category, ProviderCategory, ProviderProfile, SaudiCity, SaudiRegion, SubCategory
from apps.subscriptions.models import PlanPeriod, PlanTier, Subscription, SubscriptionPlan, SubscriptionStatus


class _DummyServiceRequest:
    def __init__(self, *, status: str, client_id: int, provider_id=None, provider=None, request_type: str = RequestType.NORMAL):
        self.id = 501
        self.status = status
        self.client_id = client_id
        self.provider_id = provider_id
        self.provider = provider
        self.request_type = request_type

    def cancel(self, *, allowed_statuses=None):
        allowed_statuses = allowed_statuses or [RequestStatus.NEW, RequestStatus.IN_PROGRESS]
        if self.status not in allowed_statuses:
            raise ValueError("invalid status")
        self.status = RequestStatus.CANCELLED

    def accept(self, provider):
        self.provider = provider
        self.provider_id = getattr(provider, "id", None) or 1
        self.status = RequestStatus.IN_PROGRESS

    def start(self):
        self.status = RequestStatus.IN_PROGRESS

    def complete(self):
        self.status = RequestStatus.COMPLETED

    def reopen(self):
        self.status = RequestStatus.NEW
        self.provider = None
        self.provider_id = None


class MarketplaceActionLoggingTests(TestCase):
    def _mock_locked_request(self, *, select_for_update_mock, sr):
        query = MagicMock()
        query.select_related.return_value = query
        query.get.return_value = sr
        select_for_update_mock.return_value = query

    @patch("apps.marketplace.services.actions.RequestStatusLog.objects.create")
    @patch("apps.marketplace.services.actions.ServiceRequest.objects.select_for_update")
    def test_cancel_creates_status_log(self, select_for_update_mock, status_log_create_mock):
        sr = _DummyServiceRequest(status=RequestStatus.NEW, client_id=77, provider_id=None, provider=None)
        self._mock_locked_request(select_for_update_mock=select_for_update_mock, sr=sr)

        user = SimpleNamespace(id=77, is_staff=False)
        result = execute_action(user=user, request_id=sr.id, action="cancel")

        self.assertTrue(result.ok)
        self.assertEqual(result.new_status, RequestStatus.CANCELLED)
        status_log_create_mock.assert_called_once()
        kwargs = status_log_create_mock.call_args.kwargs
        self.assertEqual(kwargs["from_status"], RequestStatus.NEW)
        self.assertEqual(kwargs["to_status"], RequestStatus.CANCELLED)
        self.assertEqual(kwargs["note"], "إلغاء الطلب من العميل")

    @patch("apps.marketplace.services.actions.RequestStatusLog.objects.create")
    @patch("apps.marketplace.services.actions.ServiceRequest.objects.select_for_update")
    def test_client_can_cancel_accepted_urgent_request_while_new(self, select_for_update_mock, status_log_create_mock):
        provider = SimpleNamespace(id=99, user_id=55)
        sr = _DummyServiceRequest(
            status=RequestStatus.NEW,
            client_id=77,
            provider_id=provider.id,
            provider=provider,
            request_type=RequestType.URGENT,
        )
        self._mock_locked_request(select_for_update_mock=select_for_update_mock, sr=sr)

        user = SimpleNamespace(id=77, is_staff=False)
        result = execute_action(
            user=user,
            request_id=sr.id,
            action="cancel",
            note="تم الإلغاء من العميل",
        )

        self.assertTrue(result.ok)
        self.assertEqual(result.new_status, RequestStatus.CANCELLED)
        status_log_create_mock.assert_called_once()
        kwargs = status_log_create_mock.call_args.kwargs
        self.assertEqual(kwargs["from_status"], RequestStatus.NEW)
        self.assertEqual(kwargs["to_status"], RequestStatus.CANCELLED)
        self.assertEqual(kwargs["note"], "تم الإلغاء من العميل")

    @patch("apps.marketplace.services.actions.ServiceRequest.objects.select_for_update")
    def test_client_cannot_cancel_assigned_non_urgent_request(self, select_for_update_mock):
        provider = SimpleNamespace(id=88, user_id=66)
        sr = _DummyServiceRequest(
            status=RequestStatus.NEW,
            client_id=77,
            provider_id=provider.id,
            provider=provider,
            request_type=RequestType.NORMAL,
        )
        self._mock_locked_request(select_for_update_mock=select_for_update_mock, sr=sr)

        user = SimpleNamespace(id=77, is_staff=False)
        with self.assertRaises(PermissionDenied):
            execute_action(user=user, request_id=sr.id, action="cancel")

    @patch("apps.marketplace.services.actions.RequestStatusLog.objects.create")
    @patch("apps.marketplace.services.actions.ServiceRequest.objects.select_for_update")
    def test_accept_creates_status_log(self, select_for_update_mock, status_log_create_mock):
        sr = _DummyServiceRequest(status=RequestStatus.NEW, client_id=11, provider_id=None, provider=None)
        self._mock_locked_request(select_for_update_mock=select_for_update_mock, sr=sr)

        user = SimpleNamespace(id=88, is_staff=False)
        provider_profile = SimpleNamespace(id=314, user_id=88)
        result = execute_action(
            user=user,
            request_id=sr.id,
            action="accept",
            provider_profile=provider_profile,
        )

        self.assertTrue(result.ok)
        self.assertEqual(result.new_status, RequestStatus.IN_PROGRESS)
        status_log_create_mock.assert_called_once()
        kwargs = status_log_create_mock.call_args.kwargs
        self.assertEqual(kwargs["from_status"], RequestStatus.NEW)
        self.assertEqual(kwargs["to_status"], RequestStatus.IN_PROGRESS)
        self.assertEqual(kwargs["note"], "قبول الطلب وبدء التنفيذ من مزود الخدمة")

    @patch("apps.marketplace.services.actions.RequestStatusLog.objects.create")
    @patch("apps.marketplace.services.actions.ServiceRequest.objects.select_for_update")
    def test_start_creates_status_log(self, select_for_update_mock, status_log_create_mock):
        provider = SimpleNamespace(id=909, user_id=42)
        sr = _DummyServiceRequest(
            status=RequestStatus.NEW,
            client_id=3,
            provider_id=provider.id,
            provider=provider,
        )
        self._mock_locked_request(select_for_update_mock=select_for_update_mock, sr=sr)

        user = SimpleNamespace(id=42, is_staff=False)
        result = execute_action(user=user, request_id=sr.id, action="start")

        self.assertTrue(result.ok)
        self.assertEqual(result.new_status, RequestStatus.IN_PROGRESS)
        status_log_create_mock.assert_called_once()
        kwargs = status_log_create_mock.call_args.kwargs
        self.assertEqual(kwargs["from_status"], RequestStatus.NEW)
        self.assertEqual(kwargs["to_status"], RequestStatus.IN_PROGRESS)
        self.assertEqual(kwargs["note"], "بدء التنفيذ")

    @patch("apps.marketplace.services.actions.RequestStatusLog.objects.create")
    @patch("apps.marketplace.services.actions.ServiceRequest.objects.select_for_update")
    def test_complete_creates_status_log(self, select_for_update_mock, status_log_create_mock):
        provider = SimpleNamespace(id=454, user_id=66)
        sr = _DummyServiceRequest(
            status=RequestStatus.IN_PROGRESS,
            client_id=12,
            provider_id=provider.id,
            provider=provider,
        )
        self._mock_locked_request(select_for_update_mock=select_for_update_mock, sr=sr)

        user = SimpleNamespace(id=66, is_staff=False)
        result = execute_action(user=user, request_id=sr.id, action="complete")

        self.assertTrue(result.ok)
        self.assertEqual(result.new_status, RequestStatus.COMPLETED)
        status_log_create_mock.assert_called_once()
        kwargs = status_log_create_mock.call_args.kwargs
        self.assertEqual(kwargs["from_status"], RequestStatus.IN_PROGRESS)
        self.assertEqual(kwargs["to_status"], RequestStatus.COMPLETED)
        self.assertIn("يرجى مراجعة الطلب وتقييم الخدمة", kwargs["note"])


class MarketplaceStatusLabelTests(TestCase):
    def test_urgent_assigned_new_request_has_accepted_status_label(self):
        serializer = ServiceRequestListSerializer()
        obj = SimpleNamespace(
            status=RequestStatus.NEW,
            request_type=RequestType.URGENT,
            provider_id=123,
            provider=SimpleNamespace(id=123),
        )

        self.assertEqual(serializer.get_status_label(obj), "تم قبول الطلب")

    def test_city_display_is_exposed_for_requests(self):
        region, _ = SaudiRegion.objects.update_or_create(
            name_ar="منطقة الرياض",
            defaults={"sort_order": 1, "is_active": True},
        )
        SaudiCity.objects.update_or_create(
            region=region,
            name_ar="الخرج",
            defaults={"sort_order": 1, "is_active": True},
        )

        serializer = ServiceRequestListSerializer()
        obj = SimpleNamespace(city="الخرج")

        self.assertEqual(serializer.get_city_display(obj), "الرياض - الخرج")


class MarketplaceLegacyHtmlFlowTests(TestCase):
    def setUp(self):
        user_model = get_user_model()

        self.client_user = user_model.objects.create_user(phone="0500001700", password="secret")
        self.client_user.role_state = UserRole.CLIENT
        self.client_user.save(update_fields=["role_state"])

        self.provider_user = user_model.objects.create_user(phone="0500001701", password="secret")
        self.provider_user.role_state = UserRole.PROVIDER
        self.provider_user.save(update_fields=["role_state"])

        self.category = Category.objects.create(name="تصميم")
        self.subcategory = SubCategory.objects.create(category=self.category, name="هوية بصرية")

        self.provider_profile = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود HTML",
            bio="نبذة",
            city="الرياض",
            accepts_urgent=True,
        )
        ProviderCategory.objects.create(
            provider=self.provider_profile,
            subcategory=self.subcategory,
            accepts_urgent=True,
        )

        self.basic_plan = SubscriptionPlan.objects.create(
            code="marketplace_basic_html",
            tier=PlanTier.BASIC,
            title="أساسية HTML",
            period=PlanPeriod.MONTH,
            price="0.00",
        )
        self.pro_plan = SubscriptionPlan.objects.create(
            code="marketplace_pro_html",
            tier=PlanTier.PRO,
            title="احترافية HTML",
            period=PlanPeriod.MONTH,
            price="299.00",
        )

        self.browser = Client()
        self.factory = RequestFactory()
        self.api_client = APIClient()

    def _activate_subscription(self, plan: SubscriptionPlan) -> Subscription:
        return Subscription.objects.create(
            user=self.provider_user,
            plan=plan,
            status=SubscriptionStatus.ACTIVE,
            start_at=timezone.now() - timedelta(days=1),
            end_at=timezone.now() + timedelta(days=30),
        )

    def _create_request(self, *, request_type: str, title: str, quote_deadline=None) -> ServiceRequest:
        request_obj = ServiceRequest.objects.create(
            client=self.client_user,
            subcategory=self.subcategory,
            title=title,
            description="تفاصيل الطلب",
            request_type=request_type,
            status=RequestStatus.NEW,
            city="الرياض",
            is_urgent=request_type == RequestType.URGENT,
            quote_deadline=quote_deadline,
        )
        request_obj.subcategories.add(self.subcategory)
        return request_obj

    def _available_page_titles(self) -> list[str]:
        request = self.factory.get(reverse("marketplace:provider_requests_page"), {"tab": "available"})
        request.user = self.provider_user

        with patch("apps.marketplace.views.render") as render_mock:
            render_mock.side_effect = lambda _request, _template, context: HttpResponse(
                "\n".join(obj.title for obj in context["page_obj"].object_list)
            )
            response = provider_requests(request)

        self.assertEqual(response.status_code, 200)
        body = response.content.decode("utf-8")
        return [line for line in body.splitlines() if line.strip()]

    def test_available_page_hides_broadcast_requests_without_active_subscription(self):
        urgent_request = self._create_request(request_type=RequestType.URGENT, title="طلب عاجل مخفي")
        competitive_request = self._create_request(
            request_type=RequestType.COMPETITIVE,
            title="طلب تنافسي مخفي",
            quote_deadline=timezone.localdate() + timedelta(days=2),
        )

        titles = self._available_page_titles()

        self.assertNotIn(urgent_request.title, titles)
        self.assertNotIn(competitive_request.title, titles)

    def test_available_page_respects_subscription_delay_windows(self):
        self._activate_subscription(self.basic_plan)

        urgent_ready = self._create_request(request_type=RequestType.URGENT, title="عاجل متاح")
        urgent_waiting = self._create_request(request_type=RequestType.URGENT, title="عاجل غير متاح")
        ensure_dispatch_windows_for_urgent_request(urgent_ready, now=timezone.now() - timedelta(hours=80))
        ensure_dispatch_windows_for_urgent_request(urgent_waiting, now=timezone.now())

        competitive_ready = self._create_request(
            request_type=RequestType.COMPETITIVE,
            title="تنافسي متاح",
            quote_deadline=timezone.localdate() + timedelta(days=2),
        )
        competitive_waiting = self._create_request(
            request_type=RequestType.COMPETITIVE,
            title="تنافسي غير متاح",
            quote_deadline=timezone.localdate() + timedelta(days=2),
        )
        ServiceRequest.objects.filter(id=competitive_ready.id).update(
            created_at=timezone.now() - timedelta(hours=80)
        )

        titles = self._available_page_titles()

        self.assertIn(urgent_ready.title, titles)
        self.assertIn(competitive_ready.title, titles)
        self.assertNotIn(urgent_waiting.title, titles)
        self.assertNotIn(competitive_waiting.title, titles)

    def test_legacy_html_accept_keeps_urgent_request_new_until_client_approval(self):
        self._activate_subscription(self.pro_plan)
        urgent_request = self._create_request(request_type=RequestType.URGENT, title="عاجل عبر HTML")

        self.browser.force_login(self.provider_user)
        response = self.browser.post(
            reverse("marketplace:request_action", args=[urgent_request.id]),
            {"action": "accept"},
        )

        self.assertEqual(response.status_code, 302)
        urgent_request.refresh_from_db()
        self.assertEqual(urgent_request.provider_id, self.provider_profile.id)
        self.assertEqual(urgent_request.status, RequestStatus.NEW)
        self.assertIsNone(urgent_request.provider_inputs_approved)
        self.assertTrue(
            RequestStatusLog.objects.filter(
                request=urgent_request,
                note__icontains="تم قبول الطلب العاجل",
            ).exists()
        )

    def test_legacy_html_accept_rejects_competitive_request(self):
        self._activate_subscription(self.pro_plan)
        competitive_request = self._create_request(
            request_type=RequestType.COMPETITIVE,
            title="تنافسي عبر HTML",
            quote_deadline=timezone.localdate() + timedelta(days=2),
        )

        self.browser.force_login(self.provider_user)
        response = self.browser.post(
            reverse("marketplace:request_action", args=[competitive_request.id]),
            {"action": "accept"},
        )

        self.assertEqual(response.status_code, 302)
        competitive_request.refresh_from_db()
        self.assertIsNone(competitive_request.provider_id)
        self.assertEqual(competitive_request.status, RequestStatus.NEW)
        self.assertFalse(RequestStatusLog.objects.filter(request=competitive_request).exists())

    def test_competitive_request_creation_rejects_past_quote_deadline(self):
        self.api_client.force_authenticate(user=self.client_user)

        response = self.api_client.post(
            reverse("marketplace:request_create"),
            {
                "subcategory": self.subcategory.id,
                "subcategory_ids": [self.subcategory.id],
                "title": "طلب عرض أسعار",
                "description": "أحتاج عرض سعر",
                "request_type": RequestType.COMPETITIVE,
                "quote_deadline": (timezone.localdate() - timedelta(days=1)).isoformat(),
            },
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("quote_deadline", response.json())

    def test_create_offer_rejects_request_after_quote_deadline(self):
        self._activate_subscription(self.pro_plan)
        competitive_request = self._create_request(
            request_type=RequestType.COMPETITIVE,
            title="تنافسي منتهي المهلة",
            quote_deadline=timezone.localdate() - timedelta(days=1),
        )

        self.api_client.force_authenticate(user=self.provider_user)
        response = self.api_client.post(
            reverse("marketplace:offer_create", args=[competitive_request.id]),
            {
                "price": "500.00",
                "duration_days": 5,
                "note": "عرض بعد انتهاء المهلة",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["detail"], "انتهت مهلة استقبال عروض الأسعار لهذا الطلب")


class CompetitiveRequestNotificationDispatchTests(TestCase):
    def setUp(self):
        user_model = get_user_model()
        self.client_user = user_model.objects.create_user(
            phone="0500001750",
            password="secret",
            role_state=UserRole.CLIENT,
        )
        self.provider_user = user_model.objects.create_user(
            phone="0500001751",
            password="secret",
            role_state=UserRole.PROVIDER,
        )
        self.category = Category.objects.create(name="برمجة")
        self.subcategory = SubCategory.objects.create(category=self.category, name="تطبيقات")
        self.provider_profile = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود تنافسي",
            bio="نبذة",
            city="الرياض",
        )
        ProviderCategory.objects.create(provider=self.provider_profile, subcategory=self.subcategory)
        self.api_client = APIClient()
        self.api_client.force_authenticate(user=self.client_user)

    def _activate_subscription(self, *, code: str, tier: str, title: str) -> None:
        plan = SubscriptionPlan.objects.create(
            code=code,
            tier=tier,
            title=title,
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

    def test_competitive_request_creation_notifies_provider_when_access_is_immediate(self):
        self._activate_subscription(code="marketplace_pro_competitive_notify", tier=PlanTier.PRO, title="احترافية")

        response = self.api_client.post(
            reverse("marketplace:request_create"),
            {
                "subcategory": self.subcategory.id,
                "subcategory_ids": [self.subcategory.id],
                "title": "طلب تنافسي فوري",
                "description": "تفاصيل الطلب",
                "request_type": RequestType.COMPETITIVE,
                "city": "الرياض",
                "quote_deadline": (timezone.localdate() + timedelta(days=2)).isoformat(),
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        notification = Notification.objects.filter(user=self.provider_user).order_by("-id").first()
        self.assertIsNotNone(notification)
        self.assertEqual(notification.audience_mode, Notification.AudienceMode.PROVIDER)
        self.assertIn("طلب عرض خدمة تنافسية", notification.title)

    def test_competitive_request_notification_waits_until_provider_delay_window(self):
        self._activate_subscription(code="marketplace_riyadi_competitive_notify", tier=PlanTier.RIYADI, title="ريادية")
        request_obj = ServiceRequest.objects.create(
            client=self.client_user,
            subcategory=self.subcategory,
            title="طلب تنافسي مؤجل",
            description="تفاصيل الطلب",
            request_type=RequestType.COMPETITIVE,
            status=RequestStatus.NEW,
            city="الرياض",
            quote_deadline=timezone.localdate() + timedelta(days=3),
        )
        request_obj.subcategories.add(self.subcategory)

        first_run = dispatch_due_competitive_request_notifications(now=timezone.now(), limit=50)
        self.assertEqual(first_run["sent"], 0)

        ServiceRequest.objects.filter(id=request_obj.id).update(created_at=timezone.now() - timedelta(hours=30))
        second_run = dispatch_due_competitive_request_notifications(now=timezone.now(), limit=50)

        self.assertEqual(second_run["sent"], 1)
        notification = Notification.objects.filter(user=self.provider_user).order_by("-id").first()
        self.assertIsNotNone(notification)
        self.assertIn("طلب تنافسي", notification.body)
