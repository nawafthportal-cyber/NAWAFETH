import pytest
from decimal import Decimal

from apps.subscriptions.bootstrap import (
    CANONICAL_PLAN_CODES,
    ensure_basic_subscription_plan,
    normalize_existing_subscription_plans,
    seed_default_subscription_plans,
)
from apps.subscriptions.configuration import canonical_subscription_plan_for_tier
from apps.subscriptions.models import PlanPeriod, PlanTier, SubscriptionPlan


pytestmark = pytest.mark.django_db


def test_seed_default_subscription_plans_creates_canonical_snapshot():
    seed_default_subscription_plans(force_update=True)

    plans = SubscriptionPlan.objects.filter(code__in=CANONICAL_PLAN_CODES).order_by("code")
    codes = [plan.code for plan in plans]

    assert codes == ["basic", "pro", "riyadi"]
    assert plans.count() == 3
    assert plans.filter(code="basic", tier=PlanTier.BASIC, period=PlanPeriod.YEAR).exists()
    assert plans.filter(code="riyadi", tier=PlanTier.RIYADI, period=PlanPeriod.YEAR).exists()
    assert plans.filter(code="pro", tier=PlanTier.PRO, period=PlanPeriod.YEAR).exists()
    assert plans.get(code="basic").price == Decimal("0.00")
    assert plans.get(code="riyadi").price == Decimal("199.00")
    assert plans.get(code="pro").price == Decimal("999.00")
    assert plans.get(code="basic").direct_chat_quota == 3
    assert plans.get(code="riyadi").storage_upload_max_mb == 20
    assert plans.get(code="pro").verification_blue_fee == Decimal("0.00")
    assert plans.get(code="pro").feature_bullets == [
        "كل مزايا الأساسية والريادية ضمن باقة واحدة",
        "وصول فوري للطلبات التنافسية وصلاحيات دعائية كاملة",
        "توثيق مشمول ودعم فني خلال 5 ساعات",
    ]


def test_normalize_existing_subscription_plans_maps_legacy_codes_without_dropping_variants():
    SubscriptionPlan.objects.all().delete()

    basic_legacy = SubscriptionPlan.objects.create(
        code="BASIC_MONTH",
        title="أساسية قديمة",
        tier=PlanTier.BASIC,
        period=PlanPeriod.MONTH,
        price=Decimal("10.00"),
        features=["verify_green"],
    )
    pro_legacy = SubscriptionPlan.objects.create(
        code="PRO_MONTH",
        title="احترافية شهرية",
        tier=PlanTier.BASIC,
        period=PlanPeriod.MONTH,
        price=Decimal("20.00"),
        features=["verify_blue"],
    )
    pro_yearly_legacy = SubscriptionPlan.objects.create(
        code="PRO_YEAR",
        title="احترافية سنوية",
        tier=PlanTier.BASIC,
        period=PlanPeriod.YEAR,
        price=Decimal("200.00"),
        features=["verify_blue", "advanced_analytics"],
    )

    normalize_existing_subscription_plans()

    basic_legacy.refresh_from_db()
    pro_legacy.refresh_from_db()
    pro_yearly_legacy.refresh_from_db()

    assert basic_legacy.code == "basic"
    assert basic_legacy.tier == PlanTier.BASIC

    assert pro_legacy.code == "pro"
    assert pro_legacy.tier == PlanTier.PRO

    assert pro_yearly_legacy.code == "PRO_YEAR"
    assert pro_yearly_legacy.tier == PlanTier.PRO

    # canonical set must always be seedable/idempotent after normalization
    seed_default_subscription_plans(force_update=False)
    assert SubscriptionPlan.objects.filter(code="basic").exists()
    assert SubscriptionPlan.objects.filter(code="riyadi").exists()
    assert SubscriptionPlan.objects.filter(code="pro").exists()


def test_canonical_plan_lookup_reseeds_missing_defaults():
    SubscriptionPlan.objects.all().delete()

    plan = canonical_subscription_plan_for_tier("basic")
    basic = ensure_basic_subscription_plan()

    assert plan.code == "basic"
    assert basic.code == "basic"
    assert SubscriptionPlan.objects.filter(code__in=CANONICAL_PLAN_CODES).count() == 3
