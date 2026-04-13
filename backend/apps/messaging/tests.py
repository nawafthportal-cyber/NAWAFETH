from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.test import APIClient

from apps.messaging.models import Thread, create_system_message
from apps.notifications.models import Notification
from apps.providers.models import ProviderProfile, SaudiCity, SaudiRegion


class DirectThreadRoleIsolationTests(TestCase):
    def setUp(self):
        user_model = get_user_model()
        self.sender = user_model.objects.create_user(
            phone="0501000001",
            password="secret",
            role_state="client",
        )
        self.sender.city = "الخرج"
        self.sender.save(update_fields=["city"])
        self.recipient = user_model.objects.create_user(
            phone="0501000002",
            password="secret",
            role_state="provider",
        )
        self.recipient_provider = ProviderProfile.objects.create(
            user=self.recipient,
            provider_type="individual",
            display_name="مزود ثنائي الدور",
            bio="bio",
            city="الخرج",
            region="منطقة الرياض",
        )
        region, _ = SaudiRegion.objects.update_or_create(
            name_ar="منطقة الرياض",
            defaults={"sort_order": 1, "is_active": True},
        )
        SaudiCity.objects.update_or_create(
            region=region,
            name_ar="الخرج",
            defaults={"sort_order": 1, "is_active": True},
        )
        self.sender_api = APIClient()
        self.sender_api.force_authenticate(user=self.sender)
        self.recipient_api = APIClient()
        self.recipient_api.force_authenticate(user=self.recipient)

    def test_provider_targeted_direct_thread_isolated_from_client_mode(self):
        create_response = self.sender_api.post(
            "/api/messaging/direct/thread/?mode=client",
            {"provider_id": self.recipient_provider.id},
            format="json",
        )
        self.assertEqual(create_response.status_code, 200)
        thread = Thread.objects.get(id=create_response.data["id"])

        self.assertEqual(thread.participant_mode_for_user(self.sender), Thread.ContextMode.CLIENT)
        self.assertEqual(thread.participant_mode_for_user(self.recipient), Thread.ContextMode.PROVIDER)

        send_response = self.sender_api.post(
            f"/api/messaging/direct/thread/{thread.id}/messages/send/?mode=client",
            {"body": "رسالة للمزود"},
            format="json",
        )
        self.assertEqual(send_response.status_code, 201)

        notification = Notification.objects.filter(user=self.recipient).order_by("-id").first()
        self.assertIsNotNone(notification)
        self.assertEqual(notification.audience_mode, "provider")

        provider_threads_response = self.recipient_api.get("/api/messaging/direct/threads/?mode=provider")
        self.assertEqual(provider_threads_response.status_code, 200)
        self.assertEqual(len(provider_threads_response.data), 1)
        self.assertEqual(provider_threads_response.data[0]["peer_city"], "الخرج")
        self.assertEqual(provider_threads_response.data[0]["peer_city_display"], "الرياض - الخرج")

        client_threads_response = self.recipient_api.get("/api/messaging/direct/threads/?mode=client")
        self.assertEqual(client_threads_response.status_code, 200)
        self.assertEqual(len(client_threads_response.data), 0)

        provider_messages_response = self.recipient_api.get(
            f"/api/messaging/direct/thread/{thread.id}/messages/?mode=provider"
        )
        self.assertEqual(provider_messages_response.status_code, 200)

        client_messages_response = self.recipient_api.get(
            f"/api/messaging/direct/thread/{thread.id}/messages/?mode=client"
        )
        self.assertEqual(client_messages_response.status_code, 403)

        provider_notifications_response = self.recipient_api.get("/api/notifications/?mode=provider")
        self.assertEqual(provider_notifications_response.status_code, 200)
        self.assertEqual(provider_notifications_response.data["count"], 1)

        client_notifications_response = self.recipient_api.get("/api/notifications/?mode=client")
        self.assertEqual(client_notifications_response.status_code, 200)
        self.assertEqual(client_notifications_response.data["count"], 0)

        provider_badges_response = self.recipient_api.get("/api/core/unread-badges/?mode=provider")
        self.assertEqual(provider_badges_response.status_code, 200)
        self.assertEqual(provider_badges_response.data["chats"], 1)
        self.assertEqual(provider_badges_response.data["notifications"], 1)

        client_badges_response = self.recipient_api.get("/api/core/unread-badges/?mode=client")
        self.assertEqual(client_badges_response.status_code, 200)
        self.assertEqual(client_badges_response.data["chats"], 0)
        self.assertEqual(client_badges_response.data["notifications"], 0)


class SystemThreadReplyLockTests(TestCase):
    def setUp(self):
        user_model = get_user_model()
        self.sender = user_model.objects.create_user(
            phone="0502000001",
            password="secret",
            role_state="client",
        )
        self.recipient = user_model.objects.create_user(
            phone="0502000002",
            password="secret",
            role_state="provider",
        )
        self.recipient_provider = ProviderProfile.objects.create(
            user=self.recipient,
            provider_type="individual",
            display_name="مزود خدمة تجريبي",
            bio="bio",
        )
        self.sender_api = APIClient()
        self.sender_api.force_authenticate(user=self.sender)
        self.recipient_api = APIClient()
        self.recipient_api.force_authenticate(user=self.recipient)

    def test_reply_locked_system_thread_stays_separate_from_manual_chat(self):
        system_thread = Thread.objects.create(
            is_direct=True,
            is_system_thread=True,
            system_thread_key="verification",
            context_mode=Thread.ContextMode.CLIENT,
            participant_1=self.sender,
            participant_2=self.recipient,
            participant_1_mode=Thread.ContextMode.CLIENT,
            participant_2_mode=Thread.ContextMode.PROVIDER,
        )
        create_system_message(
            thread=system_thread,
            sender=self.sender,
            body="رسالة آلية للاختبار",
            sender_team_name="فريق التوثيق",
            system_thread_key="verification",
            reply_restricted_to=self.recipient,
            reply_restriction_reason="الردود مغلقة على الرسائل الآلية من فريق التوثيق.",
        )

        state_response = self.recipient_api.get(
            f"/api/messaging/thread/{system_thread.id}/state/?mode=provider"
        )
        self.assertEqual(state_response.status_code, 200)
        self.assertTrue(state_response.data["reply_restricted_to_me"])
        self.assertEqual(state_response.data["system_sender_label"], "فريق التوثيق")

        messages_response = self.recipient_api.get(
            f"/api/messaging/direct/thread/{system_thread.id}/messages/?mode=provider"
        )
        self.assertEqual(messages_response.status_code, 200)
        self.assertEqual(messages_response.data["results"][0]["sender_name"], "فريق التوثيق")
        self.assertTrue(messages_response.data["results"][0]["is_system_generated"])

        blocked_send_response = self.recipient_api.post(
            f"/api/messaging/direct/thread/{system_thread.id}/messages/send/?mode=provider",
            {"body": "رد غير مسموح"},
            format="json",
        )
        self.assertEqual(blocked_send_response.status_code, 403)
        self.assertIn("الردود مغلقة", blocked_send_response.data["detail"])

        sender_send_response = self.sender_api.post(
            f"/api/messaging/direct/thread/{system_thread.id}/messages/send/?mode=client",
            {"body": "متابعة من الفريق"},
            format="json",
        )
        self.assertEqual(sender_send_response.status_code, 201)

        manual_thread_response = self.sender_api.post(
            "/api/messaging/direct/thread/?mode=client",
            {"provider_id": self.recipient_provider.id},
            format="json",
        )
        self.assertEqual(manual_thread_response.status_code, 200)
        self.assertNotEqual(manual_thread_response.data["id"], system_thread.id)
        self.assertFalse(Thread.objects.get(id=manual_thread_response.data["id"]).is_system_thread)