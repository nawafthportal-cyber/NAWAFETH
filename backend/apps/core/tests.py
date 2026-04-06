from django.db import OperationalError
from django.test import SimpleTestCase
from rest_framework.exceptions import NotAuthenticated, Throttled

from apps.core.drf_exception_handler import api_exception_handler


class ApiExceptionHandlerTests(SimpleTestCase):
    def test_returns_service_unavailable_for_database_errors(self):
        response = api_exception_handler(OperationalError("ssl eof"), {"request": None})

        self.assertIsNotNone(response)
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.data["code"], "database_unavailable")

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