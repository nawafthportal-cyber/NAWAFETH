from django.http import HttpResponse
from django.db import OperationalError
from django.test import RequestFactory, SimpleTestCase
from rest_framework.exceptions import NotAuthenticated, Throttled
from unittest.mock import patch

from apps.core.db_outage import (
    clear_database_outage,
    is_database_outage_active,
    mark_database_outage,
    outage_retry_after_seconds,
)
from apps.core.drf_exception_handler import api_exception_handler
from apps.core.middleware import DatabaseOutageShortCircuitMiddleware


class ApiExceptionHandlerTests(SimpleTestCase):
    def setUp(self):
        super().setUp()
        clear_database_outage()

    def tearDown(self):
        clear_database_outage()
        super().tearDown()

    def test_returns_service_unavailable_for_database_errors(self):
        with patch("apps.core.drf_exception_handler.close_old_connections"):
            response = api_exception_handler(OperationalError("ssl eof"), {"request": None})

        self.assertIsNotNone(response)
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.data["code"], "database_unavailable")
        self.assertTrue(is_database_outage_active())
        self.assertIn("Retry-After", response)

    def test_delegates_standard_drf_exceptions(self):
        response = api_exception_handler(NotAuthenticated(), {"request": None})

        self.assertIsNotNone(response)
        self.assertEqual(response.status_code, 401)

    def test_throttled_exception_includes_retry_after_metadata(self):
        response = api_exception_handler(Throttled(wait=12.2), {"request": None})

        self.assertIsNotNone(response)
        self.assertEqual(response.status_code, 429)
        self.assertEqual(response.data["code"], "throttled")
        self.assertEqual(response.data["retry_after_seconds"], 13)
        self.assertEqual(response.data["retry_after_text"], "13 ث")
        self.assertEqual(response["Retry-After"], "13")


class DatabaseOutageGuardTests(SimpleTestCase):
    def setUp(self):
        super().setUp()
        clear_database_outage()
        self.factory = RequestFactory()

    def tearDown(self):
        clear_database_outage()
        super().tearDown()

    def test_marker_sets_and_exposes_retry_after(self):
        mark_database_outage(reason="test", exc=OperationalError("down"))
        self.assertTrue(is_database_outage_active())
        retry_after = outage_retry_after_seconds()
        self.assertIsNotNone(retry_after)
        self.assertGreaterEqual(retry_after, 1)

    def test_short_circuits_api_requests_when_outage_marker_is_active(self):
        mark_database_outage(reason="test", exc=OperationalError("down"))
        middleware = DatabaseOutageShortCircuitMiddleware(lambda request: HttpResponse("ok"))
        request = self.factory.get("/api/accounts/me/")

        response = middleware(request)

        self.assertEqual(response.status_code, 503)
        self.assertEqual(response["X-Database-Outage-Guard"], "1")
        self.assertIn("Retry-After", response)

    def test_does_not_short_circuit_non_api_requests(self):
        mark_database_outage(reason="test", exc=OperationalError("down"))
        middleware = DatabaseOutageShortCircuitMiddleware(lambda request: HttpResponse("ok"))
        request = self.factory.get("/add-service/")

        response = middleware(request)

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.content, b"ok")
