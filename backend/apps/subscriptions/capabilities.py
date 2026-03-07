from __future__ import annotations

from copy import deepcopy
from datetime import timedelta

from django.utils import timezone

from .tiering import CanonicalPlanTier, canonical_tier_from_value


PLAN_CAPABILITIES = {
    CanonicalPlanTier.BASIC: {
        "notifications_enabled": True,
        "competitive_requests": {
            "visibility_delay_hours": 72,
            "visibility_label": "بعد 72 ساعة",
        },
        "banner_images": {
            "limit": 1,
            "label": "صورة واحدة",
        },
        "messaging": {
            "direct_chat_quota": 3,
            "label": "3 محادثات مباشرة",
        },
        "promotional_controls": {
            "chat_messages": False,
            "notification_messages": False,
        },
        "reminders": {
            "schedule_hours": [24],
            "label": "التذكير الأول بعد 24 ساعة",
        },
        "support": {
            "priority": "normal",
            "is_priority": False,
            "sla_hours": 120,
            "sla_label": "خلال 5 أيام",
        },
        "storage": {
            "policy": "basic",
            "label": "السعة المجانية الأساسية",
            "multiplier": 1,
            "upload_max_mb": 10,
        },
    },
    CanonicalPlanTier.PIONEER: {
        "notifications_enabled": True,
        "competitive_requests": {
            "visibility_delay_hours": 24,
            "visibility_label": "بعد 24 ساعة",
        },
        "banner_images": {
            "limit": 3,
            "label": "3 صور",
        },
        "messaging": {
            "direct_chat_quota": 10,
            "label": "10 محادثات مباشرة",
        },
        "promotional_controls": {
            "chat_messages": False,
            "notification_messages": False,
        },
        "reminders": {
            "schedule_hours": [24, 120],
            "label": "التذكير الأول ثم الثاني بعد 120 ساعة",
        },
        "support": {
            "priority": "high",
            "is_priority": True,
            "sla_hours": 48,
            "sla_label": "خلال يومين",
        },
        "storage": {
            "policy": "double_basic",
            "label": "ضعف السعة المجانية",
            "multiplier": 2,
            "upload_max_mb": 20,
        },
    },
    CanonicalPlanTier.PROFESSIONAL: {
        "notifications_enabled": True,
        "competitive_requests": {
            "visibility_delay_hours": 0,
            "visibility_label": "فوري",
        },
        "banner_images": {
            "limit": 10,
            "label": "10 صور",
        },
        "messaging": {
            "direct_chat_quota": 50,
            "label": "50 محادثة مباشرة",
        },
        "promotional_controls": {
            "chat_messages": True,
            "notification_messages": True,
        },
        "reminders": {
            "schedule_hours": [24, 120, 240],
            "label": "التذكير الأول والثاني والثالث حتى 240 ساعة",
        },
        "support": {
            "priority": "high",
            "is_priority": True,
            "sla_hours": 5,
            "sla_label": "خلال 5 ساعات",
        },
        "storage": {
            "policy": "open",
            "label": "سعة مفتوحة",
            "multiplier": None,
            "upload_max_mb": 100,
        },
    },
}


SUBSCRIPTION_FEATURE_FLAGS = {
    "promo_ads": lambda caps: bool(
        caps["promotional_controls"]["chat_messages"]
        or caps["promotional_controls"]["notification_messages"]
    ),
    "priority_support": lambda caps: bool(caps["support"]["is_priority"]),
}


def _normalized_tier(value) -> str:
    return canonical_tier_from_value(value, fallback=CanonicalPlanTier.BASIC) or CanonicalPlanTier.BASIC


def plan_capabilities_for_tier(value) -> dict:
    tier = _normalized_tier(value)
    payload = deepcopy(PLAN_CAPABILITIES[tier])
    payload["tier"] = tier
    payload["tier_label"] = CanonicalPlanTier(tier).label
    return payload


def plan_capabilities_for_user(user) -> dict:
    if not user or not getattr(user, "is_authenticated", False):
        return plan_capabilities_for_tier(CanonicalPlanTier.BASIC)

    from .services import user_plan_tier

    return plan_capabilities_for_tier(user_plan_tier(user, fallback=CanonicalPlanTier.BASIC))


def subscription_feature_flag_for_user(user, feature_key: str) -> bool | None:
    resolver = SUBSCRIPTION_FEATURE_FLAGS.get((feature_key or "").strip().lower())
    if resolver is None:
        return None
    return bool(resolver(plan_capabilities_for_user(user)))


def competitive_request_delay_hours_for_tier(value) -> int:
    caps = plan_capabilities_for_tier(value)
    return int(caps["competitive_requests"]["visibility_delay_hours"])


def competitive_request_delay_for_tier(value) -> timedelta:
    return timedelta(hours=competitive_request_delay_hours_for_tier(value))


def competitive_request_delay_for_user(user) -> timedelta:
    return competitive_request_delay_for_tier(plan_capabilities_for_user(user)["tier"])


def competitive_request_is_visible(*, created_at, tier=None, user=None, now=None) -> bool:
    if user is not None:
        delay = competitive_request_delay_for_user(user)
    else:
        delay = competitive_request_delay_for_tier(tier)
    if delay.total_seconds() <= 0:
        return True
    if created_at is None:
        return False
    return created_at + delay <= (now or timezone.now())


def banner_image_limit_for_tier(value) -> int:
    caps = plan_capabilities_for_tier(value)
    return int(caps["banner_images"]["limit"])


def banner_image_limit_for_user(user) -> int:
    return banner_image_limit_for_tier(plan_capabilities_for_user(user)["tier"])


def direct_chat_quota_for_tier(value) -> int:
    caps = plan_capabilities_for_tier(value)
    return int(caps["messaging"]["direct_chat_quota"])


def direct_chat_quota_for_user(user) -> int:
    return direct_chat_quota_for_tier(plan_capabilities_for_user(user)["tier"])


def promotional_chat_controls_enabled_for_tier(value) -> bool:
    caps = plan_capabilities_for_tier(value)
    return bool(caps["promotional_controls"]["chat_messages"])


def promotional_chat_controls_enabled_for_user(user) -> bool:
    return promotional_chat_controls_enabled_for_tier(plan_capabilities_for_user(user)["tier"])


def promotional_notification_controls_enabled_for_tier(value) -> bool:
    caps = plan_capabilities_for_tier(value)
    return bool(caps["promotional_controls"]["notification_messages"])


def promotional_notification_controls_enabled_for_user(user) -> bool:
    return promotional_notification_controls_enabled_for_tier(plan_capabilities_for_user(user)["tier"])


def support_priority_for_tier(value) -> str:
    caps = plan_capabilities_for_tier(value)
    return str(caps["support"]["priority"])


def support_priority_for_user(user) -> str:
    return support_priority_for_tier(plan_capabilities_for_user(user)["tier"])


def support_sla_for_tier(value) -> dict:
    caps = plan_capabilities_for_tier(value)
    return dict(caps["support"])


def support_sla_for_user(user) -> dict:
    return support_sla_for_tier(plan_capabilities_for_user(user)["tier"])


def storage_upload_limit_mb_for_tier(value) -> int:
    caps = plan_capabilities_for_tier(value)
    return int(caps["storage"]["upload_max_mb"])


def storage_upload_limit_mb_for_user(user) -> int:
    return storage_upload_limit_mb_for_tier(plan_capabilities_for_user(user)["tier"])
