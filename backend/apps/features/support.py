from __future__ import annotations

from .checks import has_feature


def support_priority(user) -> str:
    """
    low / normal / high

    Business mapping by subscription tier:
    - Basic (الأساسية) -> low
    - Pioneer (الريادية) -> normal
    - Professional (الاحترافية) -> high
    """
    try:
        from apps.subscriptions.services import user_plan_tier
        from apps.subscriptions.tiering import CanonicalPlanTier

        tier = user_plan_tier(user)
        if tier == CanonicalPlanTier.PROFESSIONAL:
            return "high"
        if tier == CanonicalPlanTier.PIONEER:
            return "normal"
        return "low"
    except Exception:
        # Keep a safe fallback for any early import/runtime edge case.
        if has_feature(user, "priority_support"):
            return "high"
        return "normal"
