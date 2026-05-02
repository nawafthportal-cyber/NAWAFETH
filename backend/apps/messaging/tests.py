from django.test import TestCase
from django.urls import reverse

from apps.accounts.models import User, UserRole
from apps.extras_portal.models import PotentialClientSource, ProviderPotentialClient
from apps.marketplace.models import RequestStatus, RequestType, ServiceRequest
from apps.providers.models import Category, ProviderProfile, SubCategory
from apps.subscriptions.models import Subscription, SubscriptionPlan, SubscriptionStatus


class DirectChatQuotaConsumptionTests(TestCase):
    def setUp(self):
        self.category = Category.objects.create(name="خدمات")
        self.subcategory = SubCategory.objects.create(category=self.category, name="استشارات")

        self.provider_user = User.objects.create_user(
            phone="0503600001",
            username="quota.provider",
            role_state=UserRole.PROVIDER,
        )
        self.provider = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود باقة",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.plan = SubscriptionPlan.objects.create(
            code="TEST-QUOTA-1",
            tier="basic",
            title="خطة اختبار",
            period="month",
            price="0.00",
            direct_chat_quota=1,
            is_active=True,
        )
        Subscription.objects.create(
            user=self.provider_user,
            plan=self.plan,
            status=SubscriptionStatus.ACTIVE,
        )

        self.client_one = User.objects.create_user(
            phone="0503600002",
            username="quota.client.one",
            role_state=UserRole.CLIENT,
        )
        self.client_two = User.objects.create_user(
            phone="0503600003",
            username="quota.client.two",
            role_state=UserRole.CLIENT,
        )
        self.client_three = User.objects.create_user(
            phone="0503600004",
            username="quota.client.three",
            role_state=UserRole.CLIENT,
        )
        self.request_one = ServiceRequest.objects.create(
            client=self.client_one,
            provider=self.provider,
            subcategory=self.subcategory,
            title="طلب أول",
            description="لاختبار المحادثة الأولى",
            request_type=RequestType.NORMAL,
            status=RequestStatus.NEW,
            city="الرياض",
        )
        self.request_two = ServiceRequest.objects.create(
            client=self.client_two,
            provider=self.provider,
            subcategory=self.subcategory,
            title="طلب ثان",
            description="لاختبار المحادثة الثانية",
            request_type=RequestType.NORMAL,
            status=RequestStatus.NEW,
            city="الرياض",
        )
        self.request_three = ServiceRequest.objects.create(
            client=self.client_three,
            provider=self.provider,
            subcategory=self.subcategory,
            title="طلب ثالث",
            description="لاختبار المحادثة الثالثة",
            request_type=RequestType.NORMAL,
            status=RequestStatus.NEW,
            city="الرياض",
        )
        self.client.force_login(self.provider_user)

    def _open_direct_thread(self, request_id: int | None = None, provider_id: int | None = None) -> int:
        payload = {}
        if request_id is not None:
            payload["request_id"] = request_id
        if provider_id is not None:
            payload["provider_id"] = provider_id
        response = self.client.post(
            reverse("messaging:direct_thread_get_or_create"),
            data=payload,
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 200, response.json())
        return response.json()["id"]

    def _send_direct_message(self, thread_id: int, body: str, *, mode: str | None = None):
        url = reverse("messaging:direct_message_send", kwargs={"thread_id": thread_id})
        if mode:
            url = f"{url}?mode={mode}"
        return self.client.post(
            url,
            data={"body": body},
            content_type="application/json",
        )

    def test_empty_direct_threads_do_not_consume_quota_until_first_message(self):
        first_thread_id = self._open_direct_thread(self.request_one.id)
        second_thread_id = self._open_direct_thread(self.request_two.id)

        first_send = self._send_direct_message(first_thread_id, "مرحبا")
        self.assertEqual(first_send.status_code, 201, first_send.json())

        second_send = self._send_direct_message(second_thread_id, "رسالة ثانية")
        self.assertEqual(second_send.status_code, 403, second_send.json())
        self.assertIn("الحد الأقصى", second_send.json()["error"])

    def test_client_initiated_thread_does_not_consume_provider_quota(self):
        self.client.logout()
        self.client.force_login(self.client_one)
        client_thread_id = self._open_direct_thread(provider_id=self.provider.id)
        first_client_send = self._send_direct_message(client_thread_id, "السلام عليكم")
        self.assertEqual(first_client_send.status_code, 201, first_client_send.json())

        self.client.logout()
        self.client.force_login(self.provider_user)
        provider_reply = self._send_direct_message(client_thread_id, "وعليكم السلام", mode="provider")
        self.assertEqual(provider_reply.status_code, 201, provider_reply.json())

        provider_thread_id = self._open_direct_thread(self.request_two.id)
        provider_send = self._send_direct_message(provider_thread_id, "مرحبا من المزود")
        self.assertEqual(provider_send.status_code, 201, provider_send.json())

        third_thread_id = self._open_direct_thread(self.request_three.id)
        blocked_send = self._send_direct_message(third_thread_id, "محاولة جديدة من المزود")
        self.assertEqual(blocked_send.status_code, 403, blocked_send.json())
        self.assertIn("الحد الأقصى", blocked_send.json()["error"])


class PotentialClientTagSyncTests(TestCase):
    def setUp(self):
        self.category = Category.objects.create(name="خدمات")
        self.subcategory = SubCategory.objects.create(category=self.category, name="استشارات")

        self.provider_user = User.objects.create_user(
            phone="0503700001",
            username="lead.provider",
            role_state=UserRole.PROVIDER,
        )
        self.provider = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود متابعة",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.client_user = User.objects.create_user(
            phone="0503700002",
            username="lead.client",
            role_state=UserRole.CLIENT,
        )
        self.request = ServiceRequest.objects.create(
            client=self.client_user,
            provider=self.provider,
            subcategory=self.subcategory,
            title="طلب متابعة",
            description="مسار عميل محتمل",
            request_type=RequestType.NORMAL,
            status=RequestStatus.NEW,
            city="الرياض",
        )
        self.client.force_login(self.provider_user)

    def _open_direct_thread(self) -> int:
        response = self.client.post(
            reverse("messaging:direct_thread_get_or_create"),
            data={"request_id": self.request.id},
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 200, response.json())
        return response.json()["id"]

    def test_favoriting_thread_creates_system_potential_client(self):
        thread_id = self._open_direct_thread()

        response = self.client.post(
            reverse("messaging:thread_favorite", kwargs={"thread_id": thread_id}),
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 200, response.json())
        self.assertTrue(
            ProviderPotentialClient.objects.filter(
                provider=self.provider,
                user=self.client_user,
                source=PotentialClientSource.SYSTEM,
            ).exists()
        )

    def test_unfavoriting_thread_removes_system_potential_client(self):
        thread_id = self._open_direct_thread()
        ProviderPotentialClient.objects.create(
            provider=self.provider,
            user=self.client_user,
            source=PotentialClientSource.SYSTEM,
        )

        response = self.client.post(
            reverse("messaging:thread_favorite", kwargs={"thread_id": thread_id}),
            data={"action": "remove"},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 200, response.json())
        self.assertFalse(
            ProviderPotentialClient.objects.filter(
                provider=self.provider,
                user=self.client_user,
            ).exists()
        )

    def test_unfavoriting_thread_preserves_manual_potential_client(self):
        thread_id = self._open_direct_thread()
        ProviderPotentialClient.objects.create(
            provider=self.provider,
            user=self.client_user,
            source=PotentialClientSource.MANUAL,
        )

        response = self.client.post(
            reverse("messaging:thread_favorite", kwargs={"thread_id": thread_id}),
            data={"action": "remove"},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 200, response.json())
        manual_row = ProviderPotentialClient.objects.get(
            provider=self.provider,
            user=self.client_user,
        )
        self.assertEqual(manual_row.source, PotentialClientSource.MANUAL)

    def test_favorite_label_alone_no_longer_creates_potential_client(self):
        thread_id = self._open_direct_thread()

        response = self.client.post(
            reverse("messaging:thread_favorite_label", kwargs={"thread_id": thread_id}),
            data={"label": "potential_client"},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 200, response.json())
        self.assertFalse(
            ProviderPotentialClient.objects.filter(
                provider=self.provider,
                user=self.client_user,
            ).exists()
        )
