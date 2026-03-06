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
        code="PRO",
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
