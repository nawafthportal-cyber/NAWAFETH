from django.contrib.auth import get_user_model
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from datetime import timedelta
from unittest.mock import patch

from apps.accounts.models import UserRole
from apps.marketplace.models import RequestStatus, RequestType, ServiceRequest
from apps.notifications.models import Notification, NotificationPreference, NotificationTier
from apps.providers.models import Category, ProviderCategory, ProviderProfile, SubCategory
from apps.subscriptions.models import PlanPeriod, PlanTier, Subscription, SubscriptionPlan, SubscriptionStatus


class ReviewNotificationTests(TestCase):
    def setUp(self):
        self.api_client = APIClient()
        user_model = get_user_model()

        self.provider_user = user_model.objects.create_user(
            phone="0500000720",
            password="secret",
            role_state=UserRole.PROVIDER,
        )
        self.provider_profile = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود تقييمات",
            bio="نبذة",
            city="الرياض",
        )
        professional_plan = SubscriptionPlan.objects.create(
            code="TEST-PRO-REVIEWS",
            tier=PlanTier.PRO,
            title="باقة احترافية للاختبار",
            period=PlanPeriod.MONTH,
            price=0,
            notifications_enabled=True,
            is_active=True,
        )
        Subscription.objects.create(
            user=self.provider_user,
            plan=professional_plan,
            status=SubscriptionStatus.ACTIVE,
            start_at=timezone.now(),
            end_at=timezone.now() + timedelta(days=30),
        )

        self.client_user = user_model.objects.create_user(
            phone="0500000721",
            password="secret",
            role_state=UserRole.CLIENT,
        )

        category = Category.objects.create(name="تصميم")
        subcategory = SubCategory.objects.create(category=category, name="هوية")
        ProviderCategory.objects.create(
            provider=self.provider_profile,
            subcategory=subcategory,
            accepts_urgent=False,
        )

        self.request_obj = ServiceRequest.objects.create(
            client=self.client_user,
            provider=self.provider_profile,
            subcategory=subcategory,
            title="طلب مكتمل",
            description="تفاصيل الطلب",
            request_type=RequestType.NORMAL,
            status=RequestStatus.COMPLETED,
            city="الرياض",
            is_urgent=False,
        )

        self.api_client.force_authenticate(user=self.client_user)

    def _submit_review(self, payload: dict):
        with patch("apps.reviews.tasks.recalculate_provider_rating.delay"):
            with self.captureOnCommitCallbacks(execute=True):
                return self.api_client.post(
                    f"/api/reviews/requests/{self.request_obj.id}/review/",
                    payload,
                    format="json",
                )

    def test_positive_review_creates_provider_notification(self):
        response = self._submit_review(
            {
                "response_speed": 5,
                "cost_value": 5,
                "quality": 5,
                "credibility": 5,
                "on_time": 5,
                "comment": "خدمة ممتازة وسريعة",
            }
        )

        self.assertEqual(response.status_code, 201)
        notification = Notification.objects.filter(user=self.provider_user).order_by("-id").first()
        self.assertIsNotNone(notification)
        self.assertEqual(notification.audience_mode, Notification.AudienceMode.PROVIDER)
        self.assertIn("تقييم إيجابي", notification.title)
        self.assertIn("5/5", notification.body)

    def test_negative_review_creates_provider_notification(self):
        response = self._submit_review(
            {
                "response_speed": 1,
                "cost_value": 1,
                "quality": 1,
                "credibility": 1,
                "on_time": 1,
                "comment": "التجربة غير مرضية",
            }
        )

        self.assertEqual(response.status_code, 201)
        notification = Notification.objects.filter(user=self.provider_user).order_by("-id").first()
        self.assertIsNotNone(notification)
        self.assertEqual(notification.audience_mode, Notification.AudienceMode.PROVIDER)
        self.assertIn("تقييم سلبي", notification.title)
        self.assertIn("1/5", notification.body)

    def test_disabled_positive_review_preference_blocks_notification(self):
        NotificationPreference.objects.create(
            user=self.provider_user,
            key="positive_review",
            audience_mode=NotificationPreference.AudienceMode.PROVIDER,
            enabled=False,
            tier=NotificationTier.PROFESSIONAL,
        )

        response = self._submit_review(
            {
                "response_speed": 4,
                "cost_value": 4,
                "quality": 4,
                "credibility": 4,
                "on_time": 4,
                "comment": "خدمة جيدة جداً",
            }
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(Notification.objects.filter(user=self.provider_user).count(), 0)