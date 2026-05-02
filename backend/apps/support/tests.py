from django.test import TestCase
from rest_framework.test import APIRequestFactory

from .models import SupportTeam
from .serializers import SupportTeamSerializer


class SupportTeamSerializerLocalizationTests(TestCase):
    def setUp(self):
        self.factory = APIRequestFactory()

    def test_serializer_returns_english_name_when_request_language_is_english(self):
        team = SupportTeam.objects.create(
            code="support-test-en",
            name_ar="الدعم والمساعدة",
            name_en="Support & Help",
            dashboard_code="support",
        )
        request = self.factory.get("/api/support/teams/")
        request.LANGUAGE_CODE = "en"

        payload = SupportTeamSerializer(team, context={"request": request}).data

        self.assertEqual(payload["name"], "Support & Help")
        self.assertEqual(payload["name_ar"], "الدعم والمساعدة")
        self.assertEqual(payload["name_en"], "Support & Help")

    def test_serializer_falls_back_to_arabic_when_english_name_missing(self):
        team = SupportTeam.objects.create(
            code="content-test-fallback",
            name_ar="إدارة المحتوى",
            name_en="",
            dashboard_code="content",
        )
        request = self.factory.get("/api/support/teams/")
        request.LANGUAGE_CODE = "en"

        payload = SupportTeamSerializer(team, context={"request": request}).data

        self.assertEqual(payload["name"], "إدارة المحتوى")
