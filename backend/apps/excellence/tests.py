from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIRequestFactory

from apps.accounts.models import User, UserRole
from apps.marketplace.models import DispatchMode, RequestStatus, RequestType, ServiceRequest
from apps.providers.models import Category, ProviderCategory, ProviderFollow, ProviderProfile, SubCategory

from .models import ExcellenceBadgeAward, ExcellenceBadgeType
from .selectors import (
    get_featured_service_candidates,
    get_high_achievement_candidates,
    get_top_100_club_candidates,
    serialize_active_excellence_badges,
)
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


class ExcellenceCandidateSelectionTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls._phone_seq = 500000000
        cls.now = timezone.now()
        cls.category_a = Category.objects.create(name="Category A")
        cls.category_b = Category.objects.create(name="Category B")
        cls.subcategory_a = SubCategory.objects.create(category=cls.category_a, name="Sub A")
        cls.subcategory_b = SubCategory.objects.create(category=cls.category_b, name="Sub B")

    @classmethod
    def _next_phone(cls) -> str:
        cls._phone_seq += 1
        return f"05{cls._phone_seq:09d}"[:11]

    @classmethod
    def _create_provider(cls, *, name: str, subcategory: SubCategory, rating_avg: str, rating_count: int, joined_at):
        user = User.objects.create(
            phone=cls._next_phone(),
            role_state=UserRole.PROVIDER,
            is_active=True,
        )
        provider = ProviderProfile.objects.create(
            user=user,
            provider_type="individual",
            display_name=name,
            bio="bio",
            rating_avg=Decimal(rating_avg),
            rating_count=rating_count,
        )
        ProviderProfile.objects.filter(pk=provider.pk).update(created_at=joined_at)
        provider.refresh_from_db()
        ProviderCategory.objects.create(provider=provider, subcategory=subcategory)
        return provider

    @classmethod
    def _add_followers(cls, provider: ProviderProfile, count: int):
        followers = [
            User(phone=cls._next_phone(), role_state=UserRole.CLIENT, is_active=True)
            for _ in range(count)
        ]
        User.objects.bulk_create(followers)
        created = list(User.objects.filter(phone__in=[user.phone for user in followers]))
        ProviderFollow.objects.bulk_create([
            ProviderFollow(user=user, provider=provider)
            for user in created
        ])

    @classmethod
    def _add_completed_requests(cls, provider: ProviderProfile, subcategory: SubCategory, *, count: int, delivered_base):
        clients = [
            User(phone=cls._next_phone(), role_state=UserRole.CLIENT, is_active=True)
            for _ in range(count)
        ]
        User.objects.bulk_create(clients)
        created_clients = list(User.objects.filter(phone__in=[user.phone for user in clients]))
        requests = []
        for index, client in enumerate(created_clients, start=1):
            delivered_at = delivered_base + timedelta(days=index % 25)
            requests.append(ServiceRequest(
                client=client,
                provider=provider,
                subcategory=subcategory,
                title=f"Request {index}",
                description="desc",
                request_type=RequestType.NORMAL,
                dispatch_mode=DispatchMode.ALL,
                status=RequestStatus.COMPLETED,
                city="Riyadh",
                delivered_at=delivered_at,
            ))
        ServiceRequest.objects.bulk_create(requests)

    def test_featured_service_returns_top_rated_provider_per_category(self):
        joined_at = self.now - timedelta(days=400)
        top_a = self._create_provider(name="Top A", subcategory=self.subcategory_a, rating_avg="4.90", rating_count=12, joined_at=joined_at)
        self._create_provider(name="Lower A", subcategory=self.subcategory_a, rating_avg="4.70", rating_count=15, joined_at=joined_at)
        top_b = self._create_provider(name="Top B", subcategory=self.subcategory_b, rating_avg="4.10", rating_count=3, joined_at=joined_at)
        self._create_provider(name="No Rating", subcategory=self.subcategory_b, rating_avg="0.00", rating_count=0, joined_at=joined_at)

        rows = get_featured_service_candidates(now=self.now)

        self.assertEqual({row["provider_id"] for row in rows}, {top_a.id, top_b.id})
        self.assertTrue(all(row["rank_position"] == 1 for row in rows))

    def test_top_100_club_returns_top_followed_provider_per_category_above_100_followers(self):
        joined_at = self.now - timedelta(days=400)
        lower_a = self._create_provider(name="Lower Follow A", subcategory=self.subcategory_a, rating_avg="4.00", rating_count=2, joined_at=joined_at)
        top_a = self._create_provider(name="Top Follow A", subcategory=self.subcategory_a, rating_avg="4.20", rating_count=4, joined_at=joined_at)
        top_b = self._create_provider(name="Top Follow B", subcategory=self.subcategory_b, rating_avg="4.10", rating_count=5, joined_at=joined_at)
        excluded_b = self._create_provider(name="Excluded Follow B", subcategory=self.subcategory_b, rating_avg="4.00", rating_count=2, joined_at=joined_at)

        self._add_followers(lower_a, 101)
        self._add_followers(top_a, 130)
        self._add_followers(top_b, 111)
        self._add_followers(excluded_b, 100)

        rows = get_top_100_club_candidates(now=self.now)

        self.assertEqual({row["provider_id"] for row in rows}, {top_a.id, top_b.id})
        self.assertTrue(all(int(row["followers_count"]) > 100 for row in rows))
        self.assertTrue(all(row["rank_position"] == 1 for row in rows))

    def test_high_achievement_counts_last_365_days_and_requires_more_than_100(self):
        joined_at = self.now - timedelta(days=500)
        winner_a = self._create_provider(name="Winner A", subcategory=self.subcategory_a, rating_avg="4.50", rating_count=8, joined_at=joined_at)
        stale_a = self._create_provider(name="Stale A", subcategory=self.subcategory_a, rating_avg="4.40", rating_count=7, joined_at=joined_at)
        winner_b = self._create_provider(name="Winner B", subcategory=self.subcategory_b, rating_avg="4.30", rating_count=6, joined_at=joined_at)
        excluded_b = self._create_provider(name="Excluded B", subcategory=self.subcategory_b, rating_avg="4.20", rating_count=5, joined_at=joined_at)

        self._add_completed_requests(winner_a, self.subcategory_a, count=120, delivered_base=self.now - timedelta(days=120))
        self._add_completed_requests(stale_a, self.subcategory_a, count=150, delivered_base=self.now - timedelta(days=500))
        self._add_completed_requests(winner_b, self.subcategory_b, count=101, delivered_base=self.now - timedelta(days=160))
        self._add_completed_requests(excluded_b, self.subcategory_b, count=100, delivered_base=self.now - timedelta(days=140))

        rows = get_high_achievement_candidates(now=self.now)

        self.assertEqual({row["provider_id"] for row in rows}, {winner_a.id, winner_b.id})
        self.assertTrue(all(int(row["completed_orders_count"]) > 100 for row in rows))
        self.assertTrue(all(row["rank_position"] == 1 for row in rows))