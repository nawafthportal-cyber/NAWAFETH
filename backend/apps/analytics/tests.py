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

    def test_batch_events_are_accepted(self):
        response = self.client.post(
            "/api/analytics/events/",
            {
                "events": [
                    {
                        "event_name": "search.direct_request_click",
                        "channel": "mobile_web",
                        "surface": "search.results",
                        "object_type": "provider",
                        "object_id": "7",
                    },
                    {
                        "event_name": "search.direct_request_click",
                        "channel": "flutter",
                        "surface": "home.hero",
                        "object_type": "provider",
                        "object_id": "8",
                    },
                ]
            },
            format="json",
        )

        self.assertEqual(response.status_code, 202)
        self.assertTrue(response.data["accepted"])
        self.assertEqual(response.data["count"], 2)
        self.assertEqual(
            AnalyticsEvent.objects.filter(event_name="search.direct_request_click").count(),
            2,
        )
