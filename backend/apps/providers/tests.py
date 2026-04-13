from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from rest_framework.test import APIClient

from apps.accounts.models import UserRole
from apps.marketplace.models import RequestStatus, RequestType, ServiceRequest

from .location_formatter import format_city_display
from .models import (
    Category,
    ProviderCategory,
    ProviderProfile,
    ProviderSpotlightItem,
    SaudiCity,
    SaudiRegion,
    SubCategory,
)


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


class ProviderRegionCityCatalogTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = get_user_model().objects.create_user(phone="0500000610", password="secret")
        self.user.role_state = UserRole.CLIENT
        self.user.save(update_fields=["role_state"])
        self.client.force_authenticate(user=self.user)

        self.region_riyadh, _ = SaudiRegion.objects.update_or_create(
            name_ar="منطقة الرياض",
            defaults={"sort_order": 1, "is_active": True},
        )
        self.region_makkah, _ = SaudiRegion.objects.update_or_create(
            name_ar="منطقة مكة المكرمة",
            defaults={"sort_order": 2, "is_active": True},
        )
        SaudiCity.objects.update_or_create(
            region=self.region_riyadh,
            name_ar="الرياض",
            defaults={"sort_order": 1, "is_active": True},
        )
        SaudiCity.objects.update_or_create(
            region=self.region_makkah,
            name_ar="جدة",
            defaults={"sort_order": 1, "is_active": True},
        )

    def test_regions_cities_endpoint_returns_nested_catalog(self):
        response = self.client.get("/api/providers/geo/regions-cities/")

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertGreaterEqual(len(payload), 2)
        first_region = payload[0]
        self.assertIn("name_ar", first_region)
        self.assertIn("cities", first_region)

    def test_provider_register_rejects_city_not_in_selected_region(self):
        category = Category.objects.create(name="تصميم", is_active=True)
        subcategory = SubCategory.objects.create(category=category, name="هوية بصرية", is_active=True)

        response = self.client.post(
            "/api/providers/register/",
            {
                "provider_type": "individual",
                "display_name": "مزود اختبار",
                "bio": "نبذة",
                "region": "منطقة الرياض",
                "city": "جدة",
                "subcategory_ids": [subcategory.id],
            },
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("city", response.json())
        self.assertFalse(ProviderProfile.objects.filter(user=self.user).exists())

    def test_provider_register_accepts_valid_region_city_pair(self):
        category = Category.objects.create(name="برمجة", is_active=True)
        subcategory = SubCategory.objects.create(category=category, name="تطبيقات", is_active=True)

        response = self.client.post(
            "/api/providers/register/",
            {
                "provider_type": "individual",
                "display_name": "مزود صالح",
                "bio": "نبذة",
                "region": "منطقة مكة المكرمة",
                "city": "جدة",
                "whatsapp": "+966512345678",
                "subcategory_ids": [subcategory.id],
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        payload = response.json()
        profile = ProviderProfile.objects.get(user=self.user)
        self.assertEqual(profile.region, "منطقة مكة المكرمة")
        self.assertEqual(profile.city, "جدة")
        self.assertEqual(profile.whatsapp, "0512345678")
        self.assertEqual(payload.get("whatsapp_url"), "https://wa.me/966512345678")


class CityDisplayFormatterTests(TestCase):
    def setUp(self):
        self.region_riyadh, _ = SaudiRegion.objects.update_or_create(
            name_ar="منطقة الرياض",
            defaults={"sort_order": 1, "is_active": True},
        )
        SaudiCity.objects.update_or_create(
            region=self.region_riyadh,
            name_ar="الخرج",
            defaults={"sort_order": 1, "is_active": True},
        )

    def test_format_city_display_uses_explicit_region(self):
        self.assertEqual(
            format_city_display("الخرج", region="منطقة الرياض"),
            "الرياض - الخرج",
        )

    def test_format_city_display_infers_region_from_catalog(self):
        self.assertEqual(format_city_display("الخرج"), "الرياض - الخرج")

    def test_format_city_display_strips_full_region_prefix_variant(self):
        self.assertEqual(
            format_city_display("الدمام", region="المنطقة الشرقية"),
            "الشرقية - الدمام",
        )
