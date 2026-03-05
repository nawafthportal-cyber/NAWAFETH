from __future__ import annotations

from decimal import Decimal
from typing import Iterable

from django.db import transaction

from .models import SubscriptionPlan, PlanPeriod, PlanTier


CANONICAL_PLAN_CODES = ("basic", "riyadi", "pro")


DEFAULT_SUBSCRIPTION_PLANS = [
    {
        "code": "basic",
        "tier": PlanTier.BASIC,
        "title": "أساسية",
        "description": "مناسبة للبداية",
        "period": PlanPeriod.MONTH,
        "price": Decimal("49.00"),
        "features": ["verify_green"],
        "is_active": True,
    },
    {
        "code": "riyadi",
        "tier": PlanTier.RIYADI,
        "title": "ريادية",
        "description": "للنمو وتوسيع الفرص",
        "period": PlanPeriod.MONTH,
        "price": Decimal("79.00"),
        "features": ["verify_green", "promo_ads"],
        "is_active": True,
    },
    {
        "code": "pro",
        "tier": PlanTier.PRO,
        "title": "احترافية",
        "description": "للعملاء النشطين",
        "period": PlanPeriod.MONTH,
        "price": Decimal("99.00"),
        "features": ["verify_blue", "verify_green", "promo_ads", "priority_support", "advanced_analytics"],
        "is_active": True,
    },
]


LEGACY_CODE_TO_TIER = {
    "basic": PlanTier.BASIC,
    "basic_month": PlanTier.BASIC,
    "riyadi": PlanTier.RIYADI,
    "riyadi_month": PlanTier.RIYADI,
    "entrepreneur": PlanTier.RIYADI,
    "entrepreneur_month": PlanTier.RIYADI,
    "leading": PlanTier.RIYADI,
    "leading_month": PlanTier.RIYADI,
    "pro": PlanTier.PRO,
    "pro_month": PlanTier.PRO,
    "pro_year": PlanTier.PRO,
    "pro_yearly": PlanTier.PRO,
    "professional": PlanTier.PRO,
    "professional_month": PlanTier.PRO,
    "professional_year": PlanTier.PRO,
}


LEGACY_CODE_TO_CANONICAL = {
    "basic_month": "basic",
    "riyadi_month": "riyadi",
    "entrepreneur": "riyadi",
    "entrepreneur_month": "riyadi",
    "leading": "riyadi",
    "leading_month": "riyadi",
    "pro_month": "pro",
    "professional": "pro",
    "professional_month": "pro",
}


def infer_plan_tier(*, code: str, title: str, features: Iterable[str] | None = None) -> str:
    code_key = (code or "").strip().lower()
    if code_key in LEGACY_CODE_TO_TIER:
        return LEGACY_CODE_TO_TIER[code_key]

    normalized_title = (title or "").strip().lower()
    if "رياد" in normalized_title:
        return PlanTier.RIYADI
    if "احتراف" in normalized_title or "professional" in normalized_title:
        return PlanTier.PRO

    values = {str(item or "").strip().lower() for item in (features or [])}
    if "advanced_analytics" in values or "verify_blue" in values:
        return PlanTier.PRO
    if "priority_support" in values or "promo_ads" in values:
        return PlanTier.RIYADI
    return PlanTier.BASIC


def normalize_existing_subscription_plans() -> int:
    updated = 0
    with transaction.atomic():
        existing_by_code = {
            (plan.code or "").strip().lower(): plan.id
            for plan in SubscriptionPlan.objects.all().only("id", "code")
        }
        for plan in SubscriptionPlan.objects.all().order_by("id"):
            updates = {}

            target_tier = infer_plan_tier(
                code=plan.code,
                title=plan.title,
                features=(plan.features or []),
            )
            if (plan.tier or "").strip().lower() != target_tier:
                updates["tier"] = target_tier

            code_key = (plan.code or "").strip().lower()
            target_code = LEGACY_CODE_TO_CANONICAL.get(code_key)
            if target_code:
                owner_id = existing_by_code.get(target_code)
                if owner_id in (None, plan.id):
                    updates["code"] = target_code
                    existing_by_code[target_code] = plan.id

            if updates:
                SubscriptionPlan.objects.filter(pk=plan.pk).update(**updates)
                updated += 1

    return updated


def seed_default_subscription_plans(*, force_update: bool = True) -> int:
    normalize_existing_subscription_plans()

    count = 0
    with transaction.atomic():
        for p in DEFAULT_SUBSCRIPTION_PLANS:
            defaults = dict(p)
            code = defaults.pop("code")
            if force_update:
                SubscriptionPlan.objects.update_or_create(code=code, defaults=defaults)
            else:
                SubscriptionPlan.objects.get_or_create(code=code, defaults=defaults)
            count += 1
    return count


def ensure_subscription_plans_exist() -> None:
    has_canonical = SubscriptionPlan.objects.filter(code__in=CANONICAL_PLAN_CODES).count()
    if has_canonical >= len(CANONICAL_PLAN_CODES):
        return
    seed_default_subscription_plans(force_update=False)
