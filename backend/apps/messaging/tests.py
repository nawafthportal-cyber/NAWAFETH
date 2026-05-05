from django.test import TestCase
from django.urls import reverse

from apps.accounts.models import User, UserRole
from apps.extras_portal.models import PotentialClientSource, ProviderPotentialClient
from apps.marketplace.models import RequestStatus, RequestType, ServiceRequest
from apps.providers.models import Category, ProviderProfile, ProviderVisibilityBlock, SubCategory
from apps.subscriptions.models import Subscription, SubscriptionPlan, SubscriptionStatus

from .models import Thread, ThreadUserState


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


class DirectShareRecipientSearchTests(TestCase):
    def setUp(self):
        self.category = Category.objects.create(name="خدمات")
        self.subcategory = SubCategory.objects.create(category=self.category, name="استشارات")

        self.sender = User.objects.create_user(
            phone="0503800001",
            username="spotlight.sender",
            first_name="مرسل",
            role_state=UserRole.CLIENT,
        )
        self.provider_user = User.objects.create_user(
            phone="0503800002",
            username="spotlight.provider",
            first_name="واجهة",
            role_state=UserRole.PROVIDER,
        )
        self.provider_profile = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="واجهة مشاركة",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.client_recipient = User.objects.create_user(
            phone="0503800003",
            username="spotlight.client",
            first_name="مستلم",
            last_name="داخلي",
            role_state=UserRole.CLIENT,
        )
        self.staff_user = User.objects.create_user(
            phone="0503800004",
            username="spotlight.staff",
            first_name="مشرف",
            role_state=UserRole.CLIENT,
            is_staff=True,
        )
        self.client.force_login(self.sender)

    def test_recipient_search_returns_matching_users_and_excludes_self_and_staff(self):
        response = self.client.get(
            reverse("messaging:direct_share_recipient_search"),
            {"q": "مشاركة"},
        )

        self.assertEqual(response.status_code, 200)
        rows = response.json()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["id"], self.provider_user.id)
        self.assertEqual(rows[0]["provider_id"], self.provider_profile.id)
        self.assertEqual(rows[0]["name"], self.provider_profile.display_name)

        response = self.client.get(
            reverse("messaging:direct_share_recipient_search"),
            {"q": "spotlight"},
        )
        ids = {row["id"] for row in response.json()}
        self.assertIn(self.provider_user.id, ids)
        self.assertIn(self.client_recipient.id, ids)
        self.assertNotIn(self.sender.id, ids)
        self.assertNotIn(self.staff_user.id, ids)

    def test_direct_thread_can_be_created_by_recipient_user_id_and_reused(self):
        response = self.client.post(
            reverse("messaging:direct_thread_get_or_create"),
            data={"recipient_user_id": self.provider_user.id},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 200, response.json())
        thread_id = response.json()["id"]
        thread = Thread.objects.get(id=thread_id)
        self.assertTrue(thread.is_direct)
        self.assertEqual({thread.participant_1_id, thread.participant_2_id}, {self.sender.id, self.provider_user.id})

        second_response = self.client.post(
            reverse("messaging:direct_thread_get_or_create"),
            data={"recipient_user_id": self.provider_user.id},
            content_type="application/json",
        )

        self.assertEqual(second_response.status_code, 200, second_response.json())
        self.assertEqual(second_response.json()["id"], thread_id)
        self.assertEqual(Thread.objects.count(), 1)

    def test_recipient_search_excludes_blocked_provider_accounts(self):
        ProviderVisibilityBlock.objects.create(user=self.sender, provider=self.provider_profile)

        response = self.client.get(
            reverse("messaging:direct_share_recipient_search"),
            {"q": "spotlight"},
        )

        self.assertEqual(response.status_code, 200)
        ids = {row["id"] for row in response.json()}
        self.assertNotIn(self.provider_user.id, ids)
        self.assertIn(self.client_recipient.id, ids)

    def test_direct_thread_creation_rejects_blocked_provider(self):
        ProviderVisibilityBlock.objects.create(user=self.sender, provider=self.provider_profile)

        response = self.client.post(
            reverse("messaging:direct_thread_get_or_create"),
            data={"provider_id": self.provider_profile.id},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 404, response.json())


class ProviderVisibilityMessagingTests(TestCase):
    def setUp(self):
        self.category = Category.objects.create(name="خدمات")
        self.subcategory = SubCategory.objects.create(category=self.category, name="استشارات")

        self.client_user = User.objects.create_user(
            phone="0503900001",
            username="blocked.client",
            first_name="عميل",
            role_state=UserRole.CLIENT,
        )
        self.provider_user = User.objects.create_user(
            phone="0503900002",
            username="blocked.provider",
            first_name="مزود",
            role_state=UserRole.PROVIDER,
        )
        self.provider = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود محظور",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.client.force_login(self.client_user)

        response = self.client.post(
            reverse("messaging:direct_thread_get_or_create"),
            data={"provider_id": self.provider.id},
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 200, response.json())
        self.thread_id = response.json()["id"]

        send_response = self.client.post(
            reverse("messaging:direct_message_send", kwargs={"thread_id": self.thread_id}),
            data={"body": "مرحبا"},
            content_type="application/json",
        )
        self.assertEqual(send_response.status_code, 201, send_response.json())

    def test_blocked_provider_hidden_from_direct_threads_list(self):
        ProviderVisibilityBlock.objects.create(user=self.client_user, provider=self.provider)

        response = self.client.get(reverse("messaging:direct_threads_list"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), [])

    def test_blocked_provider_direct_thread_messages_are_no_longer_accessible(self):
        ProviderVisibilityBlock.objects.create(user=self.client_user, provider=self.provider)

        response = self.client.get(
            reverse("messaging:direct_messages_list", kwargs={"thread_id": self.thread_id})
        )

        self.assertEqual(response.status_code, 403, response.content)

    def test_deleted_conversation_is_hidden_from_current_user_direct_threads_list(self):
        delete_response = self.client.post(
            reverse("messaging:thread_delete", kwargs={"thread_id": self.thread_id}),
            content_type="application/json",
        )

        self.assertEqual(delete_response.status_code, 200, delete_response.json())
        state = ThreadUserState.objects.get(thread_id=self.thread_id, user=self.client_user)
        self.assertTrue(state.is_deleted)

        response = self.client.get(reverse("messaging:direct_threads_list"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), [])

    def test_deleted_conversation_reappears_after_new_message(self):
        self.client.post(
            reverse("messaging:thread_delete", kwargs={"thread_id": self.thread_id}),
            content_type="application/json",
        )

        self.client.logout()
        self.client.force_login(self.provider_user)
        send_response = self.client.post(
            reverse("messaging:direct_message_send", kwargs={"thread_id": self.thread_id}) + "?mode=provider",
            data={"body": "رد جديد"},
            content_type="application/json",
        )
        self.assertEqual(send_response.status_code, 201, send_response.json())

        self.client.logout()
        self.client.force_login(self.client_user)
        response = self.client.get(reverse("messaging:direct_threads_list"))

        self.assertEqual(response.status_code, 200, response.json())
        self.assertEqual(len(response.json()), 1)
        state = ThreadUserState.objects.get(thread_id=self.thread_id, user=self.client_user)
        self.assertFalse(state.is_deleted)


class DirectThreadsClientClassificationTests(TestCase):
    def setUp(self):
        self.category = Category.objects.create(name="خدمات")
        self.subcategory = SubCategory.objects.create(category=self.category, name="استشارات")

        self.provider_user = User.objects.create_user(
            phone="0503901001",
            username="classification.provider",
            role_state=UserRole.PROVIDER,
        )
        self.provider = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود تصنيف",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.follower_user = User.objects.create_user(
            phone="0503901002",
            username="classification.follower",
            first_name="متابع",
            role_state=UserRole.CLIENT,
        )
        self.cancelled_client_user = User.objects.create_user(
            phone="0503901003",
            username="classification.cancelled",
            first_name="ملغي",
            role_state=UserRole.CLIENT,
        )
        ServiceRequest.objects.create(
            client=self.cancelled_client_user,
            provider=self.provider,
            subcategory=self.subcategory,
            title="طلب ملغي",
            description="يبقى عميلًا في التصنيف",
            request_type=RequestType.NORMAL,
            status=RequestStatus.CANCELLED,
            city="الرياض",
        )
        self.client.force_login(self.provider_user)

    def _open_provider_thread(self, recipient_user_id: int) -> int:
        response = self.client.post(
            reverse("messaging:direct_thread_get_or_create") + "?mode=provider",
            data={"recipient_user_id": recipient_user_id},
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 200, response.json())
        return response.json()["id"]

    def test_direct_threads_classify_clients_only_when_service_request_exists(self):
        self._open_provider_thread(self.follower_user.id)
        self._open_provider_thread(self.cancelled_client_user.id)

        response = self.client.get(reverse("messaging:direct_threads_list"), {"mode": "provider"})

        self.assertEqual(response.status_code, 200, response.json())
        rows_by_peer = {row["peer_id"]: row for row in response.json()}
        self.assertEqual(rows_by_peer[self.follower_user.id]["peer_kind"], "member")
        self.assertEqual(rows_by_peer[self.cancelled_client_user.id]["peer_kind"], "client")
