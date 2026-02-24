from __future__ import annotations

from decimal import Decimal

from django.db import transaction

from .models import SubscriptionPlan, PlanPeriod


DEFAULT_SUBSCRIPTION_PLANS = [
    {
        "code": "BASIC_MONTH",
        "title": "أساسية",
        "description": "مناسبة للبداية",
        "period": PlanPeriod.MONTH,
        "price": Decimal("49.00"),
        "features": ["verify_green"],
        "is_active": True,
    },
    {
        "code": "PRO_MONTH",
        "title": "احترافية",
        "description": "للعملاء النشطين",
        "period": PlanPeriod.MONTH,
        "price": Decimal("99.00"),
        "features": ["verify_blue", "promo_ads", "priority_support"],
        "is_active": True,
    },
    {
        "code": "PRO_YEAR",
        "title": "احترافية سنوية",
        "description": "خصم سنوي",
        "period": PlanPeriod.YEAR,
        "price": Decimal("999.00"),
        "features": ["verify_blue", "promo_ads", "priority_support", "advanced_analytics"],
        "is_active": True,
    },
]


def seed_default_subscription_plans(*, force_update: bool = True) -> int:
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
    if SubscriptionPlan.objects.filter(is_active=True).exists():
        return
    seed_default_subscription_plans(force_update=False)
