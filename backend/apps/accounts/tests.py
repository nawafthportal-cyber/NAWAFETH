from django.test import override_settings
from rest_framework.test import APITestCase

from .models import User, UserRole


@override_settings(OTP_COOLDOWN_SECONDS=90)
class OtpSendApiTests(APITestCase):
    def test_otp_send_success_includes_cooldown_metadata(self):
        response = self.client.post(
            "/api/accounts/otp/send/",
            {"phone": "0500000000"},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data["ok"])
        self.assertEqual(response.data["cooldown_seconds"], 90)
        self.assertEqual(response.data["cooldown_text"], "1 د 30 ث")

    def test_otp_send_cooldown_includes_retry_after_metadata(self):
        first = self.client.post(
            "/api/accounts/otp/send/",
            {"phone": "0500000001"},
            format="json",
        )
        self.assertEqual(first.status_code, 200)

        second = self.client.post(
            "/api/accounts/otp/send/",
            {"phone": "0500000001"},
            format="json",
        )

        self.assertEqual(second.status_code, 429)
        self.assertEqual(second.data["code"], "otp_cooldown")
        self.assertIn("retry_after_seconds", second.data)
        self.assertGreater(second.data["retry_after_seconds"], 0)
        self.assertLessEqual(second.data["retry_after_seconds"], 90)
        self.assertEqual(second["Retry-After"], str(second.data["retry_after_seconds"]))


class SkipCompletionApiTests(APITestCase):
    def test_skip_completion_upgrades_phone_only_user_to_client(self):
        user = User.objects.create_user(
            phone="0500000010",
            role_state=UserRole.PHONE_ONLY,
            username="0500000010",
        )
        self.client.force_authenticate(user=user)

        response = self.client.post("/api/accounts/skip-completion/", {}, format="json")

        self.assertEqual(response.status_code, 200)
        user.refresh_from_db()
        self.assertEqual(user.role_state, UserRole.CLIENT)
        self.assertEqual(response.data["role_state"], UserRole.CLIENT)
        self.assertFalse(response.data["needs_completion"])
        self.assertEqual(response.data["profile_status"], "partial")

    def test_skip_completion_is_idempotent_for_existing_client(self):
        user = User.objects.create_user(
            phone="0500000011",
            role_state=UserRole.CLIENT,
            username="client_0500000011",
        )
        self.client.force_authenticate(user=user)

        response = self.client.post("/api/accounts/skip-completion/", {}, format="json")

        self.assertEqual(response.status_code, 200)
        user.refresh_from_db()
        self.assertEqual(user.role_state, UserRole.CLIENT)
        self.assertEqual(user.username, "client_0500000011")
        self.assertEqual(response.data["profile_status"], "partial")