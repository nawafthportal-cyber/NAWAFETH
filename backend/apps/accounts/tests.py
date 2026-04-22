from datetime import timedelta

from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from .models import OTP, User, UserRole


class AccountProfileStatusTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.url = reverse("accounts:me")

    def _get_profile(self, user: User):
        self.client.force_authenticate(user=user)
        response = self.client.get(self.url)
        self.client.force_authenticate(user=None)
        return response

    def test_phone_only_role_is_labeled_phone_only_client(self):
        user = User.objects.create(
            phone="0500000001",
            username="0500000001",
            role_state=UserRole.PHONE_ONLY,
        )

        response = self._get_profile(user)

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["profile_status"], "phone_only")
        self.assertEqual(response.data["role_label"], "عميل برقم الجوال")

    def test_partial_client_is_still_labeled_phone_only_client(self):
        user = User.objects.create(
            phone="0500000002",
            username="0500000002",
            role_state=UserRole.CLIENT,
        )

        response = self._get_profile(user)

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["profile_status"], "phone_only")
        self.assertEqual(response.data["role_label"], "عميل برقم الجوال")

    def test_completed_client_is_labeled_as_client(self):
        user = User.objects.create(
            phone="0500000003",
            username="completed.client",
            first_name="عميل",
            last_name="مكتمل",
            email="completed@example.com",
            role_state=UserRole.CLIENT,
            terms_accepted_at=timezone.now(),
        )

        response = self._get_profile(user)

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["profile_status"], "complete")
        self.assertEqual(response.data["role_label"], "عميل")


class AccountSessionActionTests(TestCase):
    def setUp(self):
        self.client = APIClient()

    def test_logout_accepts_session_auth_without_refresh_token(self):
        user = User.objects.create_user(
            phone="0500000010",
            password="StrongPass123!",
            username="session.logout",
            role_state=UserRole.CLIENT,
        )
        self.client.force_login(user)

        response = self.client.post(reverse("accounts:logout"), {}, format="json")

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data["ok"])

    def test_delete_account_removes_user_with_session_auth(self):
        user = User.objects.create_user(
            phone="0500000011",
            password="StrongPass123!",
            username="session.delete",
            role_state=UserRole.CLIENT,
        )
        user_id = user.id
        self.client.force_login(user)

        response = self.client.delete(reverse("accounts:delete_account"))

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data["ok"])
        self.assertFalse(User.objects.filter(id=user_id).exists())


@override_settings(
    OTP_APP_BYPASS=True,
    OTP_APP_BYPASS_ALLOWLIST=[],
    OTP_DEV_BYPASS_ENABLED=True,
    OTP_DEV_ACCEPT_ANY_4_DIGITS=True,
    OTP_DEV_TEST_CODE="0000",
    OTP_TEST_MODE=False,
    OTP_TEST_CODE="",
)
class OtpVerifyBypassScopeTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.url = reverse("accounts:otp_verify")
        self.phone = "0500000012"

    def _create_otp(self, code: str = "1234") -> None:
        OTP.objects.create(
            phone=self.phone,
            code=code,
            expires_at=timezone.now() + timedelta(minutes=5),
        )

    def test_web_verify_does_not_use_mobile_bypass_flags(self):
        self._create_otp(code="1234")

        response = self.client.post(
            self.url,
            {"phone": self.phone, "code": "1111"},
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("detail", response.data)

    def test_mobile_verify_can_use_mobile_bypass_when_enabled(self):
        self._create_otp(code="1234")

        response = self.client.post(
            self.url,
            {"phone": self.phone, "code": "1111", "mobile_any_otp": True},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.assertIn("access", response.data)
        self.assertIn("refresh", response.data)
