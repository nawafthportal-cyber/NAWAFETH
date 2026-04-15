from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from datetime import timedelta

from apps.accounts.models import UserRole
from apps.marketplace.models import RequestStatus, RequestType, ServiceRequest
from apps.notifications.models import Notification
from apps.subscriptions.models import PlanPeriod, PlanTier, Subscription, SubscriptionPlan, SubscriptionStatus

from .location_formatter import format_city_display
from .models import (
    Category,
    ProviderContentComment,
    ProviderCategory,
    ProviderPortfolioItem,
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


class ProviderInteractionNotificationTests(TestCase):
    def setUp(self):
        self.api_client = APIClient()
        user_model = get_user_model()

        self.provider_user = user_model.objects.create_user(
            phone="0500000710",
            password="secret",
            role_state=UserRole.PROVIDER,
        )
        self.provider_profile = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود التفاعل",
            bio="نبذة",
            city="الرياض",
        )
        leading_plan = SubscriptionPlan.objects.create(
            code="TEST-RIYADI-PROVIDER-INTERACTIONS",
            tier=PlanTier.RIYADI,
            title="باقة ريادية للاختبار",
            period=PlanPeriod.MONTH,
            price=0,
            notifications_enabled=True,
            is_active=True,
        )
        Subscription.objects.create(
            user=self.provider_user,
            plan=leading_plan,
            status=SubscriptionStatus.ACTIVE,
            start_at=timezone.now(),
            end_at=timezone.now() + timedelta(days=30),
        )

        self.client_user = user_model.objects.create_user(
            phone="0500000711",
            password="secret",
            role_state=UserRole.CLIENT,
        )
        self.api_client.force_authenticate(user=self.client_user)

        self.portfolio_item = ProviderPortfolioItem.objects.create(
            provider=self.provider_profile,
            file_type="image",
            file=SimpleUploadedFile("portfolio.jpg", b"file-content", content_type="image/jpeg"),
            caption="عمل جديد",
        )
        self.spotlight_item = ProviderSpotlightItem.objects.create(
            provider=self.provider_profile,
            file_type="image",
            file=SimpleUploadedFile("spotlight.jpg", b"file-content", content_type="image/jpeg"),
            caption="إضاءة جديدة",
        )

    def test_follow_provider_creates_notification_for_provider(self):
        with self.captureOnCommitCallbacks(execute=True):
            response = self.api_client.post(f"/api/providers/{self.provider_profile.id}/follow/")

        self.assertEqual(response.status_code, 200)
        notification = Notification.objects.filter(user=self.provider_user).order_by("-id").first()
        self.assertIsNotNone(notification)
        self.assertEqual(notification.audience_mode, Notification.AudienceMode.PROVIDER)
        self.assertIn("متابعة جديدة", notification.title)
        self.assertEqual(notification.url, f"/provider/{self.provider_profile.id}/")

    def test_like_provider_profile_creates_notification_for_provider(self):
        with self.captureOnCommitCallbacks(execute=True):
            response = self.api_client.post(f"/api/providers/{self.provider_profile.id}/like/")

        self.assertEqual(response.status_code, 200)
        notification = Notification.objects.filter(user=self.provider_user).order_by("-id").first()
        self.assertIsNotNone(notification)
        self.assertEqual(notification.audience_mode, Notification.AudienceMode.PROVIDER)
        self.assertIn("إعجاب جديد بملفك الشخصي", notification.title)

    def test_like_portfolio_item_creates_service_like_notification(self):
        with self.captureOnCommitCallbacks(execute=True):
            response = self.api_client.post(f"/api/providers/portfolio/{self.portfolio_item.id}/like/")

        self.assertEqual(response.status_code, 200)
        notification = Notification.objects.filter(user=self.provider_user).order_by("-id").first()
        self.assertIsNotNone(notification)
        self.assertEqual(notification.audience_mode, Notification.AudienceMode.PROVIDER)
        self.assertIn("أحد أعمالك", notification.title)

    def test_approved_content_comment_creates_comment_notification(self):
        with self.captureOnCommitCallbacks(execute=True):
            ProviderContentComment.objects.create(
                provider=self.provider_profile,
                user=self.client_user,
                portfolio_item=self.portfolio_item,
                body="تعليق ممتاز على الخدمة",
                is_approved=True,
            )

        notification = Notification.objects.filter(user=self.provider_user).order_by("-id").first()
        self.assertIsNotNone(notification)
        self.assertEqual(notification.audience_mode, Notification.AudienceMode.PROVIDER)
        self.assertIn("تعليق جديد", notification.title)
        self.assertIn("تعليق ممتاز", notification.body)


class ProviderSameCategoryNotificationTests(TestCase):
    def setUp(self):
        user_model = get_user_model()
        self.category = Category.objects.create(name="تصميم", is_active=True)
        self.shared_subcategory = SubCategory.objects.create(
            category=self.category,
            name="هوية بصرية",
            is_active=True,
        )
        self.other_category = Category.objects.create(name="برمجة", is_active=True)
        self.other_subcategory = SubCategory.objects.create(
            category=self.other_category,
            name="تطبيقات",
            is_active=True,
        )

        self.recipient_user = user_model.objects.create_user(
            phone="0500000720",
            password="secret",
            role_state=UserRole.PROVIDER,
        )
        self.recipient_profile = ProviderProfile.objects.create(
            user=self.recipient_user,
            provider_type="individual",
            display_name="مزود متابع",
            bio="نبذة",
            city="الرياض",
        )
        ProviderCategory.objects.create(
            provider=self.recipient_profile,
            subcategory=self.shared_subcategory,
        )

        self.other_user = user_model.objects.create_user(
            phone="0500000721",
            password="secret",
            role_state=UserRole.PROVIDER,
        )
        self.other_profile = ProviderProfile.objects.create(
            user=self.other_user,
            provider_type="individual",
            display_name="مزود مختلف",
            bio="نبذة",
            city="الرياض",
        )
        ProviderCategory.objects.create(
            provider=self.other_profile,
            subcategory=self.other_subcategory,
        )

        professional_plan = SubscriptionPlan.objects.create(
            code="TEST-PRO-SAME-CATEGORY-NOTIFY",
            tier=PlanTier.PRO,
            title="باقة احترافية للاختبار",
            period=PlanPeriod.MONTH,
            price=0,
            notifications_enabled=True,
            is_active=True,
        )
        Subscription.objects.create(
            user=self.recipient_user,
            plan=professional_plan,
            status=SubscriptionStatus.ACTIVE,
            start_at=timezone.now(),
            end_at=timezone.now() + timedelta(days=30),
        )
        Subscription.objects.create(
            user=self.other_user,
            plan=professional_plan,
            status=SubscriptionStatus.ACTIVE,
            start_at=timezone.now(),
            end_at=timezone.now() + timedelta(days=30),
        )

        self.sender_user = user_model.objects.create_user(
            phone="0500000722",
            password="secret",
            role_state=UserRole.PROVIDER,
        )
        self.sender_profile = ProviderProfile.objects.create(
            user=self.sender_user,
            provider_type="individual",
            display_name="مزود جديد في الفئة",
            bio="نبذة",
            city="الرياض",
        )

    def test_new_provider_same_category_notifies_only_shared_category_providers(self):
        with self.captureOnCommitCallbacks(execute=True):
            ProviderCategory.objects.create(
                provider=self.sender_profile,
                subcategory=self.shared_subcategory,
            )

        recipient_notification = Notification.objects.filter(user=self.recipient_user).order_by("-id").first()
        self.assertIsNotNone(recipient_notification)
        self.assertIn("مقدم خدمة جديد", recipient_notification.title)
        self.assertIn("مزود جديد في الفئة", recipient_notification.body)
        self.assertFalse(Notification.objects.filter(user=self.other_user).exists())

    def test_highlight_same_category_notifies_only_shared_category_providers(self):
        ProviderCategory.objects.create(
            provider=self.sender_profile,
            subcategory=self.shared_subcategory,
        )
        Notification.objects.all().delete()

        with self.captureOnCommitCallbacks(execute=True):
            ProviderSpotlightItem.objects.create(
                provider=self.sender_profile,
                file_type="image",
                file=SimpleUploadedFile("same-category-spotlight.jpg", b"file-content", content_type="image/jpeg"),
                caption="لمحة جديدة داخل التصنيف",
            )

        recipient_notification = Notification.objects.filter(user=self.recipient_user).order_by("-id").first()
        self.assertIsNotNone(recipient_notification)
        self.assertIn("لمحة جديدة", recipient_notification.title)
        self.assertIn("داخل التصنيف", recipient_notification.body)
        self.assertFalse(Notification.objects.filter(user=self.other_user).exists())
