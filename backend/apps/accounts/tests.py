from django.test import override_settings
from rest_framework.test import APITestCase


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