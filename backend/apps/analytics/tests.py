from django.test import TestCase
from rest_framework.test import APIClient

from .models import AnalyticsEvent


class AnalyticsEventIngestTests(TestCase):
    def setUp(self):
        self.client = APIClient()

    def test_search_direct_request_click_is_accepted(self):
        response = self.client.post(
            "/api/analytics/events/",
            {
                "event_name": "search.direct_request_click",
                "channel": "mobile_web",
                "surface": "search.results",
                "object_type": "provider",
                "object_id": "3",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 202)
        self.assertTrue(response.data["accepted"])
        self.assertTrue(
            AnalyticsEvent.objects.filter(event_name="search.direct_request_click").exists()
        )