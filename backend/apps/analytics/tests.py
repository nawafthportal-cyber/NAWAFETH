from datetime import timedelta

from django.contrib.auth import get_user_model
from django.test import SimpleTestCase, TestCase
from django.utils import timezone

from apps.accounts.models import UserRole
from apps.extras.models import ExtraPurchase, ExtraPurchaseStatus, ExtraType
from apps.notifications.models import Notification
from apps.providers.models import ProviderProfile
from apps.subscriptions.models import PlanPeriod, PlanTier, Subscription, SubscriptionPlan, SubscriptionStatus

from .models import AnalyticsChannel, AnalyticsEvent
from .serializers import AnalyticsEventIngestSerializer


class AnalyticsEventIngestSerializerTests(SimpleTestCase):
    def test_accepts_featured_specialist_click_event(self):
        serializer = AnalyticsEventIngestSerializer(data={"event_name": "promo.featured_specialist_click"})

        self.assertTrue(serializer.is_valid(), serializer.errors)

    def test_accepts_portfolio_showcase_click_event(self):
        serializer = AnalyticsEventIngestSerializer(data={"event_name": "promo.portfolio_showcase_click"})

        self.assertTrue(serializer.is_valid(), serializer.errors)


class AdVisitNotificationSignalTests(TestCase):
    def setUp(self):
        user_model = get_user_model()
        self.viewer = user_model.objects.create_user(
            phone="0500001980",
            password="secret",
        )
        self.provider_user = user_model.objects.create_user(
            phone="0500001981",
            password="secret",
            role_state=UserRole.PROVIDER,
        )
        self.provider = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود إعلان",
            bio="نبذة",
            city="الرياض",
        )
        plan = SubscriptionPlan.objects.create(
            code="ad-visit-basic",
            tier=PlanTier.BASIC,
            title="أساسية",
            period=PlanPeriod.MONTH,
            price="0.00",
            notifications_enabled=True,
            is_active=True,
        )
        Subscription.objects.create(
            user=self.provider_user,
            plan=plan,
            status=SubscriptionStatus.ACTIVE,
            start_at=timezone.now() - timedelta(days=1),
            end_at=timezone.now() + timedelta(days=30),
        )
        ExtraPurchase.objects.create(
            user=self.provider_user,
            sku="promo_boost_search_30d",
            title="تعزيز ترويجي",
            extra_type=ExtraType.TIME_BASED,
            status=ExtraPurchaseStatus.ACTIVE,
            start_at=timezone.now() - timedelta(days=1),
            end_at=timezone.now() + timedelta(days=30),
        )

    def test_click_event_creates_provider_ad_visit_notification(self):
        with self.captureOnCommitCallbacks(execute=True):
            AnalyticsEvent.objects.create(
                event_name="promo.banner_click",
                channel=AnalyticsChannel.MOBILE_WEB,
                surface="صفحة البحث",
                object_type="ProviderProfile",
                object_id=str(self.provider.id),
                actor=self.viewer,
                payload={"provider_id": self.provider.id},
            )

        notification = Notification.objects.get(user=self.provider_user)
        self.assertEqual(notification.audience_mode, Notification.AudienceMode.PROVIDER)
        self.assertIn("زيارة جديدة", notification.title)
        self.assertIn("صفحة البحث", notification.body)

    def test_impression_event_does_not_create_provider_ad_visit_notification(self):
        with self.captureOnCommitCallbacks(execute=True):
            AnalyticsEvent.objects.create(
                event_name="promo.banner_impression",
                channel=AnalyticsChannel.MOBILE_WEB,
                surface="الواجهة الرئيسية",
                object_type="ProviderProfile",
                object_id=str(self.provider.id),
                actor=self.viewer,
                payload={"provider_id": self.provider.id},
            )

        self.assertFalse(Notification.objects.filter(user=self.provider_user).exists())