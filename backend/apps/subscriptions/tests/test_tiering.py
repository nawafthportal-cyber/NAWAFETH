import pytest

from apps.subscriptions.models import PlanPeriod, SubscriptionPlan
from apps.subscriptions.services import plan_to_tier
from apps.subscriptions.tiering import (
    CanonicalPlanTier,
    canonical_tier_aliases,
    canonical_tier_from_inputs,
    canonical_tier_from_value,
    db_tier_for_canonical,
)


pytestmark = pytest.mark.django_db


@pytest.mark.parametrize(
    ("raw_value", "expected"),
    [
        ("basic", CanonicalPlanTier.BASIC),
        ("riyadi", CanonicalPlanTier.PIONEER),
        ("leading", CanonicalPlanTier.PIONEER),
        ("pioneer", CanonicalPlanTier.PIONEER),
        ("pro", CanonicalPlanTier.PROFESSIONAL),
        ("professional", CanonicalPlanTier.PROFESSIONAL),
    ],
)
def test_legacy_and_canonical_tier_aliases_resolve_to_one_domain(raw_value, expected):
    assert canonical_tier_from_value(raw_value) == expected


def test_plan_to_tier_returns_canonical_tier_for_legacy_db_values():
    plan = SubscriptionPlan.objects.create(
        code="RIYADI",
        tier="riyadi",
        title="الريادية",
        period=PlanPeriod.MONTH,
        price="79.00",
        features=["promo_ads"],
    )

    assert plan_to_tier(plan) == CanonicalPlanTier.PIONEER


def test_inferred_tier_supports_canonical_titles_and_features():
    assert canonical_tier_from_inputs(code="custom", title="Pioneer Plus") == CanonicalPlanTier.PIONEER
    assert canonical_tier_from_inputs(code="custom", title="خطة احترافية") == CanonicalPlanTier.PROFESSIONAL
    assert canonical_tier_from_inputs(code="custom", title="x", features=["priority_support"]) == CanonicalPlanTier.PIONEER


def test_canonical_tier_maps_back_to_legacy_storage_aliases():
    assert db_tier_for_canonical(CanonicalPlanTier.PIONEER) == "riyadi"
    assert db_tier_for_canonical(CanonicalPlanTier.PROFESSIONAL) == "pro"
    assert "leading" in canonical_tier_aliases(CanonicalPlanTier.PIONEER)
