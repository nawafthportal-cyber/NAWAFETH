from __future__ import annotations

from decimal import Decimal

from .models import SubscriptionPlan
from .tiering import CanonicalPlanTier, canonical_tier_from_value, db_tier_for_canonical


def canonical_subscription_plan_for_tier(value) -> SubscriptionPlan:
    canonical_tier = canonical_tier_from_value(value, fallback=CanonicalPlanTier.BASIC) or CanonicalPlanTier.BASIC
    canonical_code = db_tier_for_canonical(canonical_tier)
    plan = SubscriptionPlan.objects.filter(code__iexact=canonical_code).order_by("id").first()
    if plan is None:
        from .bootstrap import seed_default_subscription_plans

        seed_default_subscription_plans(force_update=False)
        plan = SubscriptionPlan.objects.filter(code__iexact=canonical_code).order_by("id").first()
    if plan is None:
        raise SubscriptionPlan.DoesNotExist(f"Missing canonical subscription plan for tier '{canonical_tier}'")
    return plan


def template_subscription_plan_for_plan(
    plan: SubscriptionPlan | None,
    *,
    fallback_tier: str = CanonicalPlanTier.BASIC,
) -> SubscriptionPlan:
    if plan is None:
        return canonical_subscription_plan_for_tier(fallback_tier)
    return canonical_subscription_plan_for_tier(plan.normalized_tier())


def resolved_plan_string(
    plan: SubscriptionPlan | None,
    template: SubscriptionPlan,
    field_name: str,
    *,
    default: str = "",
) -> str:
    if plan is not None:
        current = str(getattr(plan, field_name, "") or "").strip()
        if current:
            return current

    template_value = str(getattr(template, field_name, "") or "").strip()
    if template_value:
        return template_value
    return str(default or "").strip()


def resolved_plan_bool(
    plan: SubscriptionPlan | None,
    template: SubscriptionPlan,
    field_name: str,
    *,
    default: bool = False,
) -> bool:
    if plan is not None:
        current = getattr(plan, field_name, None)
        if current is not None:
            return bool(current)

    template_value = getattr(template, field_name, None)
    if template_value is not None:
        return bool(template_value)
    return bool(default)


def resolved_plan_int(
    plan: SubscriptionPlan | None,
    template: SubscriptionPlan,
    field_name: str,
    *,
    default: int | None = 0,
    allow_none: bool = False,
) -> int | None:
    if plan is not None:
        current = getattr(plan, field_name, None)
        if current is not None:
            return int(current)

    template_value = getattr(template, field_name, None)
    if template_value is not None:
        return int(template_value)

    if allow_none:
        return None
    return int(default or 0)


def resolved_plan_decimal(
    plan: SubscriptionPlan | None,
    template: SubscriptionPlan,
    field_name: str,
    *,
    default: str | Decimal = "0.00",
) -> Decimal:
    if plan is not None:
        current = getattr(plan, field_name, None)
        if current is not None:
            return Decimal(str(current))

    template_value = getattr(template, field_name, None)
    if template_value is not None:
        return Decimal(str(template_value))
    return Decimal(str(default))


def resolved_plan_string_list(
    plan: SubscriptionPlan | None,
    template: SubscriptionPlan,
    *,
    method_name: str,
) -> list[str]:
    if plan is not None:
        current = list(getattr(plan, method_name, lambda: [])() or [])
        if current:
            return current
    return list(getattr(template, method_name, lambda: [])() or [])


def resolved_plan_int_list(
    plan: SubscriptionPlan | None,
    template: SubscriptionPlan,
    *,
    method_name: str,
) -> list[int]:
    if plan is not None:
        current = list(getattr(plan, method_name, lambda: [])() or [])
        if current:
            return [int(value) for value in current]
    return [int(value) for value in (getattr(template, method_name, lambda: [])() or [])]
