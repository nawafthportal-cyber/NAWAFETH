import pytest
from rest_framework.test import APIClient
from decimal import Decimal

from apps.accounts.models import User
from apps.subscriptions.models import SubscriptionPlan, PlanPeriod, Subscription, SubscriptionStatus


pytestmark = pytest.mark.django_db


@pytest.fixture
def api():
    return APIClient()


@pytest.fixture
def user():
    return User.objects.create_user(phone="0500000001", password="Pass12345!")


def test_my_features(api, user):
    # خطة فيها promo
    plan = SubscriptionPlan.objects.create(
        code="pro_features_test",
        tier="pro",
        title="Pro",
        period=PlanPeriod.MONTH,
        price=Decimal("10.00"),
        features=["promo_ads"],
        is_active=True,
    )
    Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
    )

    api.force_authenticate(user=user)
    r = api.get("/api/features/my/")
    assert r.status_code == 200
    assert r.data["promo_ads"] is True
    assert r.data["current_tier"] == "professional"
    assert r.data["capabilities"]["banner_images"]["limit"] == 10
    assert r.data["capabilities"]["promotional_controls"]["notification_messages"] is True
    assert r.data["capabilities"]["support"]["sla_hours"] == 5


def test_my_features_does_not_treat_verification_as_subscription_feature(api, user):
    plan = SubscriptionPlan.objects.create(
        code="VERIFY_ONLY",
        title="Verify Only",
        period=PlanPeriod.MONTH,
        price=Decimal("10.00"),
        features=["verify_blue", "verify_green"],
        is_active=True,
    )
    Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
    )

    api.force_authenticate(user=user)
    r = api.get("/api/features/my/")
    assert r.status_code == 200
    assert r.data["verify_blue"] is False
    assert r.data["verify_green"] is False


def test_my_features_returns_pioneer_capabilities_even_without_legacy_feature_flags(api, user):
    plan = SubscriptionPlan.objects.create(
        code="riyadi_features_test",
        title="الريادية",
        tier="riyadi",
        period=PlanPeriod.YEAR,
        price=Decimal("199.00"),
        features=[],
        is_active=True,
    )
    Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
    )

    api.force_authenticate(user=user)
    r = api.get("/api/features/my/")
    assert r.status_code == 200
    assert r.data["current_tier"] == "pioneer"
    assert r.data["priority_support"] is True
    assert r.data["promo_ads"] is False
    assert r.data["max_upload_mb"] == 20
    assert r.data["capabilities"]["competitive_requests"]["visibility_delay_hours"] == 24
    assert r.data["capabilities"]["messaging"]["direct_chat_quota"] == 10
    assert r.data["capabilities"]["reminders"]["schedule_hours"] == [24, 120]
