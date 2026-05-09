from django.test import TestCase
from django.test import override_settings
from django.test import RequestFactory
from django.http import QueryDict
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole

from . import db_outage
from .context_processors import safe_server_auth
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


class DatabaseOutageTtlTests(TestCase):
    @override_settings(
        DEBUG=True,
        DB_OUTAGE_TTL_SECONDS=30,
        DATABASES={"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": ":memory:"}},
    )
    def test_outage_ttl_is_short_in_local_debug_sqlite(self):
        self.assertEqual(db_outage._outage_ttl_seconds(), 3)

    @override_settings(
        DEBUG=False,
        DB_OUTAGE_TTL_SECONDS=30,
        DATABASES={"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": ":memory:"}},
    )
    def test_outage_ttl_keeps_production_floor_for_sqlite(self):
        self.assertEqual(db_outage._outage_ttl_seconds(), 30)

    @override_settings(
        DEBUG=True,
        DB_OUTAGE_TTL_SECONDS=30,
        DATABASES={"default": {"ENGINE": "django.db.backends.postgresql", "NAME": "nawafeth"}},
    )
    def test_outage_ttl_keeps_production_floor_for_non_sqlite(self):
        self.assertEqual(db_outage._outage_ttl_seconds(), 30)


class SafeServerAuthTests(TestCase):
    def setUp(self):
        self.factory = RequestFactory()

    def test_partial_client_is_exposed_as_phone_only_profile_status(self):
        user = User.objects.create_user(
            phone="0505500091",
            username="partial.server.auth",
            role_state=UserRole.CLIENT,
        )
        request = self.factory.get("/")
        request.user = user

        payload = safe_server_auth(request)["safe_server_auth"]

        self.assertTrue(payload["is_authenticated"])
        self.assertEqual(payload["role_state"], UserRole.CLIENT)
        self.assertEqual(payload["profile_status"], "phone_only")

    def test_completed_client_is_exposed_as_complete_profile_status(self):
        user = User.objects.create_user(
            phone="0505500092",
            username="complete.server.auth",
            first_name="عميل",
            last_name="مكتمل",
            email="complete.server.auth@example.com",
            role_state=UserRole.CLIENT,
            terms_accepted_at=timezone.now(),
        )
        request = self.factory.get("/")
        request.user = user

        payload = safe_server_auth(request)["safe_server_auth"]

        self.assertEqual(payload["profile_status"], "complete")
