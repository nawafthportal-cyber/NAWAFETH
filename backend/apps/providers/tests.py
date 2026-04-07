from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from rest_framework.test import APIClient

from apps.accounts.models import UserRole
from apps.marketplace.models import RequestStatus, RequestType, ServiceRequest

from .models import Category, ProviderCategory, ProviderProfile, ProviderSpotlightItem, SubCategory


class ProviderSubscriptionRestrictionTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(phone="0500000600", password="secret")
        self.user.role_state = UserRole.PROVIDER
        self.user.save(update_fields=["role_state"])
        self.provider_profile = ProviderProfile.objects.create(
            user=self.user,
            provider_type="individual",
            display_name="مزود جديد",
            bio="نبذة مختصرة",
            city="الرياض",
            accepts_urgent=True,
        )
        self.client_user = get_user_model().objects.create_user(phone="0500000601", password="secret")
        self.category = Category.objects.create(name="تصميم")
        self.subcategory = SubCategory.objects.create(category=self.category, name="هوية بصرية")
        ProviderCategory.objects.create(
            provider=self.provider_profile,
            subcategory=self.subcategory,
            accepts_urgent=True,
        )
        ServiceRequest.objects.create(
            client=self.client_user,
            subcategory=self.subcategory,
            title="طلب عاجل",
            description="تفاصيل عاجلة",
            request_type=RequestType.URGENT,
            status=RequestStatus.NEW,
            city="الرياض",
            is_urgent=True,
        )
        ServiceRequest.objects.create(
            client=self.client_user,
            subcategory=self.subcategory,
            title="طلب تنافسي",
            description="تفاصيل تنافسية",
            request_type=RequestType.COMPETITIVE,
            status=RequestStatus.NEW,
            city="الرياض",
            is_urgent=False,
        )
        self.api_client = APIClient()
        self.api_client.force_authenticate(user=self.user)

    def test_available_urgent_requests_is_empty_without_active_subscription(self):
        response = self.api_client.get("/api/marketplace/provider/urgent/available/")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), [])

    def test_available_competitive_requests_is_empty_without_active_subscription(self):
        response = self.api_client.get("/api/marketplace/provider/competitive/available/")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), [])

    def test_spotlight_upload_requires_active_subscription(self):
        upload = SimpleUploadedFile("spotlight.mp4", b"fake-video", content_type="video/mp4")

        response = self.api_client.post(
            "/api/providers/me/spotlights/",
            {"file": upload, "file_type": "video"},
            format="multipart",
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["code"][0], "subscription_required")
        self.assertEqual(ProviderSpotlightItem.objects.filter(provider=self.provider_profile).count(), 0)