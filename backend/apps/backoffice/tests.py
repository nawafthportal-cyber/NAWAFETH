from django.test import TestCase
from rest_framework.test import APIRequestFactory

from .models import AccessPermission, Dashboard
from .serializers import AccessPermissionSerializer, DashboardSerializer


class BackofficeSerializerLocalizationTests(TestCase):
    def setUp(self):
        self.factory = APIRequestFactory()

    def test_dashboard_serializer_returns_english_name_when_available(self):
        dashboard = Dashboard.objects.create(
            code="support-test-dashboard",
            name_ar="الدعم والمساعدة",
            name_en="Support & Help",
            is_active=True,
            sort_order=10,
        )
        request = self.factory.get("/api/backoffice/dashboards/")
        request.LANGUAGE_CODE = "en"

        payload = DashboardSerializer(dashboard, context={"request": request}).data

        self.assertEqual(payload["name"], "Support & Help")
        self.assertEqual(payload["name_ar"], "الدعم والمساعدة")
        self.assertEqual(payload["name_en"], "Support & Help")

    def test_access_permission_serializer_localizes_description(self):
        permission = AccessPermission.objects.create(
            code="support.assign.test",
            name_ar="إسناد تذاكر الدعم",
            name_en="Assign Support Tickets",
            dashboard_code="support",
            description="يتيح إسناد تذاكر الدعم للمشغلين.",
            description_en="Allows assigning support tickets to operators.",
            is_active=True,
            sort_order=10,
        )
        request = self.factory.get("/api/backoffice/my-access/")
        request.LANGUAGE_CODE = "en"

        payload = AccessPermissionSerializer(permission, context={"request": request}).data

        self.assertEqual(payload["name"], "Assign Support Tickets")
        self.assertEqual(payload["description"], "Allows assigning support tickets to operators.")
        self.assertEqual(payload["description_ar"], "يتيح إسناد تذاكر الدعم للمشغلين.")
        self.assertEqual(payload["description_en"], "Allows assigning support tickets to operators.")