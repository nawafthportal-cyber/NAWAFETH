from django.test import TestCase
from django.http import QueryDict
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole

from .views import HomeAggregateView


class HomeAggregateViewTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            phone="0505500001",
            username="home.aggregate.user",
            role_state=UserRole.CLIENT,
            email="client@example.com",
            first_name="Client",
            last_name="User",
        )

    def test_home_aggregate_does_not_expose_user_specific_payload(self):
        self.client.force_authenticate(user=self.user)

        response = self.client.get("/api/home/aggregate/?providers_limit=10")

        self.assertEqual(response.status_code, 200)
        self.assertNotIn("user", response.data)
        self.assertNotIn("badges", response.data)

    def test_home_aggregate_cache_key_is_public_for_same_query(self):
        view = HomeAggregateView()
        guest_request = type(
            "GuestRequest",
            (),
            {"query_params": QueryDict("providers_limit=10"), "user": None},
        )()
        user_request = type(
            "UserRequest",
            (),
            {"query_params": QueryDict("providers_limit=10"), "user": self.user},
        )()

        self.assertEqual(
            view._cache_key(guest_request),
            view._cache_key(user_request),
        )


class RootServiceWorkerViewTests(TestCase):
    def setUp(self):
        self.client = APIClient()

    def test_service_worker_compat_path_is_available(self):
        response = self.client.get("/service-worker.js")

        self.assertEqual(response.status_code, 200)
        self.assertIn("application/javascript", response["Content-Type"])
        self.assertEqual(response["Service-Worker-Allowed"], "/")

    def test_legacy_sw_path_remains_available(self):
        response = self.client.get("/sw.js")

        self.assertEqual(response.status_code, 200)
        self.assertIn("application/javascript", response["Content-Type"])
