from __future__ import annotations

from collections.abc import Iterable

from django.db import models


class CanonicalPlanTier(models.TextChoices):
    BASIC = "basic", "أساسية"
    PIONEER = "pioneer", "ريادية"
    PROFESSIONAL = "professional", "احترافية"


CANONICAL_TIER_ORDER = {
    CanonicalPlanTier.BASIC: 1,
    CanonicalPlanTier.PIONEER: 2,
    CanonicalPlanTier.PROFESSIONAL: 3,
}


CANONICAL_TO_DB_TIER = {
    CanonicalPlanTier.BASIC: "basic",
    CanonicalPlanTier.PIONEER: "riyadi",
    CanonicalPlanTier.PROFESSIONAL: "pro",
}


CANONICAL_TO_NOTIFICATION_TIER = {
    CanonicalPlanTier.BASIC: "basic",
    CanonicalPlanTier.PIONEER: "leading",
    CanonicalPlanTier.PROFESSIONAL: "professional",
}


TIER_ALIASES = {
    "basic": CanonicalPlanTier.BASIC,
    "basic_month": CanonicalPlanTier.BASIC,
    "riyadi": CanonicalPlanTier.PIONEER,
    "riyadi_month": CanonicalPlanTier.PIONEER,
    "leading": CanonicalPlanTier.PIONEER,
    "leading_month": CanonicalPlanTier.PIONEER,
    "entrepreneur": CanonicalPlanTier.PIONEER,
    "entrepreneur_month": CanonicalPlanTier.PIONEER,
    "pioneer": CanonicalPlanTier.PIONEER,
    "pioneer_month": CanonicalPlanTier.PIONEER,
    "pro": CanonicalPlanTier.PROFESSIONAL,
    "pro_month": CanonicalPlanTier.PROFESSIONAL,
    "pro_year": CanonicalPlanTier.PROFESSIONAL,
    "pro_yearly": CanonicalPlanTier.PROFESSIONAL,
    "professional": CanonicalPlanTier.PROFESSIONAL,
    "professional_month": CanonicalPlanTier.PROFESSIONAL,
    "professional_year": CanonicalPlanTier.PROFESSIONAL,
}


CANONICAL_TIER_ALIASES = {
    CanonicalPlanTier.BASIC: tuple(sorted({alias for alias, tier in TIER_ALIASES.items() if tier == CanonicalPlanTier.BASIC})),
    CanonicalPlanTier.PIONEER: tuple(sorted({alias for alias, tier in TIER_ALIASES.items() if tier == CanonicalPlanTier.PIONEER})),
    CanonicalPlanTier.PROFESSIONAL: tuple(sorted({alias for alias, tier in TIER_ALIASES.items() if tier == CanonicalPlanTier.PROFESSIONAL})),
}


def canonical_tier_from_value(value, *, fallback: str | None = CanonicalPlanTier.BASIC) -> str | None:
    normalized = str(value or "").strip().lower()
    if not normalized:
        return fallback
    if normalized in TIER_ALIASES:
        return TIER_ALIASES[normalized]
    return fallback


def canonical_tier_from_inputs(
    *,
    tier: str | None = None,
    code: str | None = None,
    title: str | None = None,
    features: Iterable[str] | None = None,
    fallback: str = CanonicalPlanTier.BASIC,
) -> str:
    for candidate in (tier, code):
        resolved = canonical_tier_from_value(candidate, fallback=None)
        if resolved:
            return resolved

    normalized_title = str(title or "").strip().lower()
    if "رياد" in normalized_title or "رائد" in normalized_title or "pioneer" in normalized_title:
        return CanonicalPlanTier.PIONEER
    if "احتراف" in normalized_title or "professional" in normalized_title or "pro" == normalized_title:
        return CanonicalPlanTier.PROFESSIONAL

    values = {str(item or "").strip().lower() for item in (features or [])}
    if "advanced_analytics" in values or "verify_blue" in values:
        return CanonicalPlanTier.PROFESSIONAL
    if "priority_support" in values or "promo_ads" in values:
        return CanonicalPlanTier.PIONEER
    return fallback


def canonical_tier_label(value, *, fallback: str = CanonicalPlanTier.BASIC) -> str:
    canonical = canonical_tier_from_value(value, fallback=fallback) or fallback
    return CanonicalPlanTier(canonical).label


def canonical_tier_order(value, *, fallback: str = CanonicalPlanTier.BASIC) -> int:
    canonical = canonical_tier_from_value(value, fallback=fallback) or fallback
    return CANONICAL_TIER_ORDER.get(canonical, CANONICAL_TIER_ORDER[CanonicalPlanTier.BASIC])


def db_tier_for_canonical(value, *, fallback: str = CanonicalPlanTier.BASIC) -> str:
    canonical = canonical_tier_from_value(value, fallback=fallback) or fallback
    return CANONICAL_TO_DB_TIER.get(canonical, CANONICAL_TO_DB_TIER[CanonicalPlanTier.BASIC])


def notification_tier_for_canonical(value, *, fallback: str = CanonicalPlanTier.BASIC) -> str:
    canonical = canonical_tier_from_value(value, fallback=fallback) or fallback
    return CANONICAL_TO_NOTIFICATION_TIER.get(canonical, CANONICAL_TO_NOTIFICATION_TIER[CanonicalPlanTier.BASIC])


def canonical_tier_aliases(value, *, fallback: str = CanonicalPlanTier.BASIC) -> tuple[str, ...]:
    canonical = canonical_tier_from_value(value, fallback=fallback) or fallback
    return CANONICAL_TIER_ALIASES.get(canonical, ())
