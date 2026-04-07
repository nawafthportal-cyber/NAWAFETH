from django.test import SimpleTestCase

from .serializers import AnalyticsEventIngestSerializer


class AnalyticsEventIngestSerializerTests(SimpleTestCase):
    def test_accepts_featured_specialist_click_event(self):
        serializer = AnalyticsEventIngestSerializer(data={"event_name": "promo.featured_specialist_click"})

        self.assertTrue(serializer.is_valid(), serializer.errors)

    def test_accepts_portfolio_showcase_click_event(self):
        serializer = AnalyticsEventIngestSerializer(data={"event_name": "promo.portfolio_showcase_click"})

        self.assertTrue(serializer.is_valid(), serializer.errors)