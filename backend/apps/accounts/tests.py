from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from .models import User, UserRole


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