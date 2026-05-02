from django.test import TestCase
from rest_framework.test import APIRequestFactory

from .models import ExcellenceBadgeAward, ExcellenceBadgeType
from .selectors import serialize_active_excellence_badges
from .serializers import ExcellenceBadgeTypeSerializer


class ExcellenceLocalizationTests(TestCase):
    def setUp(self):
        self.factory = APIRequestFactory()

    def test_badge_catalog_serializer_returns_english_when_request_language_is_english(self):
        badge_type = ExcellenceBadgeType.objects.create(
            code="featured-service-test",
            name_ar="الخدمة المتميزة",
            name_en="Featured Service",
            description="وصف عربي",
            description_en="English description",
        )
        request = self.factory.get("/api/excellence/catalog/")
        request.LANGUAGE_CODE = "en"

        payload = ExcellenceBadgeTypeSerializer(badge_type, context={"request": request}).data

        self.assertEqual(payload["name"], "Featured Service")
        self.assertEqual(payload["description"], "English description")
        self.assertEqual(payload["name_en"], "Featured Service")

    def test_badge_cache_payload_exposes_name_en(self):
        badge_type = ExcellenceBadgeType.objects.create(
            code="top-club-test",
            name_ar="نادي المئة الكبار",
            name_en="Top 100 Club",
            description="وصف عربي",
            description_en="English description",
        )
        award = ExcellenceBadgeAward(badge_type=badge_type)

        payload = serialize_active_excellence_badges([award])

        self.assertEqual(payload[0]["name_ar"], "نادي المئة الكبار")
        self.assertEqual(payload[0]["name_en"], "Top 100 Club")