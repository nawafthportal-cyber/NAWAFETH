from __future__ import annotations

from copy import deepcopy
from datetime import timedelta

from django.utils import timezone

from .configuration import (
    canonical_subscription_plan_for_tier,
    resolved_plan_bool,
    resolved_plan_int,
    resolved_plan_int_list,
    resolved_plan_string,
    template_subscription_plan_for_plan,
)
from .models import SubscriptionPlan
from .tiering import CanonicalPlanTier, canonical_tier_from_value


PROVIDER_UNSUBSCRIBED_SUPPORT_SLA_HOURS = 24 * 5


SUBSCRIPTION_FEATURE_FLAGS = {
    "promo_ads": lambda caps: bool(
        caps["promotional_controls"]["chat_messages"]
        or caps["promotional_controls"]["notification_messages"]
    ),
    "priority_support": lambda caps: bool(caps["support"]["is_priority"]),
}


def _normalized_tier(value) -> str:
    return canonical_tier_from_value(value, fallback=CanonicalPlanTier.BASIC) or CanonicalPlanTier.BASIC


def _visibility_label(hours: int) -> str:
    if int(hours or 0) <= 0:
        return "لحظياً"
    return f"بعد {int(hours)} ساعة"


def _banner_images_label(limit: int) -> str:
    limit = int(limit or 0)
    if limit == 1:
        return "صورة واحدة"
    return f"{limit} صور"


def _direct_chat_label(quota: int) -> str:
    quota = int(quota or 0)
    if quota == 1:
        return "محادثة مباشرة واحدة"
    if quota == 2:
        return "محادثتان مباشرتان"
    if 3 <= quota <= 10:
        return f"{quota} محادثات مباشرة"
    return f"{quota} محادثة مباشرة"


def _reminders_label(schedule_hours: list[int]) -> str:
    if not schedule_hours:
        return "بدون رسائل تذكير"
    if len(schedule_hours) == 1:
        return f"أول تنبيه بعد اكتمال الطلب بـ {schedule_hours[0]} ساعة"
    if len(schedule_hours) == 2:
        return f"أول تنبيه + إرسال ثاني تنبيه بعد اكتمال الطلب بـ {schedule_hours[-1]} ساعة"
    return f"أول تنبيه + ثاني تنبيه + إرسال ثالث تنبيه بعد اكتمال الطلب بـ {schedule_hours[-1]} ساعة"


def _support_sla_label(hours: int) -> str:
    hours = int(hours or 0)
    if hours <= 0:
        return "فوري"
    if hours % 24 == 0:
        days = hours // 24
        if days == 1:
            return "خلال يوم"
        if days == 2:
            return "خلال يومين"
        if 3 <= days <= 10:
            return f"خلال {days} أيام"
        return f"خلال {days} يوم"
    if hours == 1:
        return "خلال ساعة"
    if hours == 2:
        return "خلال ساعتين"
    if 3 <= hours <= 10:
        return f"خلال {hours} ساعات"
    return f"خلال {hours} ساعة"


def _storage_label(*, policy: str, multiplier, upload_max_mb: int) -> str:
    normalized_policy = str(policy or "").strip().lower()
    if normalized_policy == "open":
        return "سعة مفتوحة"
    if multiplier:
        multiplier = int(multiplier)
        if multiplier == 2:
            return "ضعف السعة المجانية المتاحة"
        if multiplier > 2:
            return f"{multiplier}x من السعة المجانية المتاحة"
    return "السعة المجانية المتاحة"


def _explicit_plan_string(plan: SubscriptionPlan | None, field_name: str) -> str:
    if plan is None:
        return ""
    return str(getattr(plan, field_name, "") or "").strip()


def _plan_has_value(plan: SubscriptionPlan | None, field_name: str) -> bool:
    return plan is not None and getattr(plan, field_name, None) is not None


def _resolved_capability_label(
    plan: SubscriptionPlan | None,
    template: SubscriptionPlan,
    *,
    field_name: str,
    derived_default: str,
    plan_overrides_source: bool = False,
) -> str:
    explicit_value = _explicit_plan_string(plan, field_name)
    if explicit_value:
        return explicit_value
    if plan_overrides_source:
        return derived_default

    template_value = str(getattr(template, field_name, "") or "").strip()
    if template_value:
        return template_value
    return derived_default


def configured_subscription_plan_for_tier(value) -> SubscriptionPlan:
    return canonical_subscription_plan_for_tier(_normalized_tier(value))


def plan_capabilities_for_plan(plan: SubscriptionPlan | None) -> dict:
    template = template_subscription_plan_for_plan(plan, fallback_tier=CanonicalPlanTier.BASIC)
    tier = plan.normalized_tier() if plan is not None else template.normalized_tier()

    visibility_delay_hours = int(
        resolved_plan_int(plan, template, "competitive_visibility_delay_hours", default=0) or 0
    )
    banner_images_limit = int(
        resolved_plan_int(plan, template, "banner_images_limit", default=0) or 0
    )
    direct_chat_quota = int(
        resolved_plan_int(plan, template, "direct_chat_quota", default=0) or 0
    )
    reminder_schedule = resolved_plan_int_list(plan, template, method_name="reminder_schedule")
    support_is_priority = resolved_plan_bool(plan, template, "support_is_priority", default=False)
    support_priority = resolved_plan_string(
        plan,
        template,
        "support_priority",
        default="high" if support_is_priority else "normal",
    ).lower()
    support_sla_hours = int(
        resolved_plan_int(plan, template, "support_sla_hours", default=0) or 0
    )
    storage_policy = resolved_plan_string(plan, template, "storage_policy", default="basic").lower()
    storage_multiplier = resolved_plan_int(
        plan,
        template,
        "storage_multiplier",
        default=None,
        allow_none=True,
    )
    storage_upload_max_mb = int(
        resolved_plan_int(plan, template, "storage_upload_max_mb", default=0) or 0
    )

    return {
        "notifications_enabled": resolved_plan_bool(plan, template, "notifications_enabled", default=True),
        "competitive_requests": {
            "visibility_delay_hours": visibility_delay_hours,
            "visibility_label": _resolved_capability_label(
                plan,
                template,
                field_name="competitive_visibility_label",
                derived_default=_visibility_label(visibility_delay_hours),
                plan_overrides_source=_plan_has_value(plan, "competitive_visibility_delay_hours"),
            ),
        },
        "banner_images": {
            "limit": banner_images_limit,
            "label": _resolved_capability_label(
                plan,
                template,
                field_name="banner_images_label",
                derived_default=_banner_images_label(banner_images_limit),
                plan_overrides_source=_plan_has_value(plan, "banner_images_limit"),
            ),
        },
        "messaging": {
            "direct_chat_quota": direct_chat_quota,
            "label": _resolved_capability_label(
                plan,
                template,
                field_name="direct_chat_label",
                derived_default=_direct_chat_label(direct_chat_quota),
                plan_overrides_source=_plan_has_value(plan, "direct_chat_quota"),
            ),
        },
        "promotional_controls": {
            "chat_messages": resolved_plan_bool(
                plan,
                template,
                "promotional_chat_messages_enabled",
                default=False,
            ),
            "notification_messages": resolved_plan_bool(
                plan,
                template,
                "promotional_notification_messages_enabled",
                default=False,
            ),
        },
        "reminders": {
            "schedule_hours": reminder_schedule,
            "label": _resolved_capability_label(
                plan,
                template,
                field_name="reminder_policy_label",
                derived_default=_reminders_label(reminder_schedule),
                plan_overrides_source=bool(getattr(plan, "reminder_schedule_hours", None)) if plan is not None else False,
            ),
        },
        "support": {
            "priority": support_priority,
            "is_priority": support_is_priority,
            "sla_hours": support_sla_hours,
            "sla_label": _resolved_capability_label(
                plan,
                template,
                field_name="support_sla_label",
                derived_default=_support_sla_label(support_sla_hours),
                plan_overrides_source=_plan_has_value(plan, "support_sla_hours"),
            ),
        },
        "storage": {
            "policy": storage_policy,
            "label": _resolved_capability_label(
                plan,
                template,
                field_name="storage_label",
                derived_default=_storage_label(
                    policy=storage_policy,
                    multiplier=storage_multiplier,
                    upload_max_mb=storage_upload_max_mb,
                ),
                plan_overrides_source=(
                    bool(_explicit_plan_string(plan, "storage_policy"))
                    or _plan_has_value(plan, "storage_multiplier")
                    or _plan_has_value(plan, "storage_upload_max_mb")
                ),
            ),
            "multiplier": storage_multiplier,
            "upload_max_mb": storage_upload_max_mb,
        },
        "tier": tier,
        "tier_label": CanonicalPlanTier(tier).label,
    }


def plan_capabilities_for_tier(value) -> dict:
    return plan_capabilities_for_plan(configured_subscription_plan_for_tier(value))


def provider_unsubscribed_capabilities() -> dict:
    caps = deepcopy(plan_capabilities_for_tier(CanonicalPlanTier.BASIC))
    caps["competitive_requests"] = {
        "enabled": False,
        "visibility_delay_hours": 0,
        "visibility_label": "غير متاحة قبل تفعيل الاشتراك",
    }
    caps["urgent_requests"] = {
        "enabled": False,
        "label": "غير متاحة قبل تفعيل الاشتراك",
    }
    caps["banner_images"] = {
        "limit": 0,
        "label": "غير متاح قبل تفعيل الاشتراك",
    }
    caps["reminders"] = {
        "schedule_hours": [],
        "label": "بدون رسائل تذكير",
    }
    caps["support"] = {
        "priority": "low",
        "is_priority": False,
        "sla_hours": PROVIDER_UNSUBSCRIBED_SUPPORT_SLA_HOURS,
        "sla_label": "خلال 5 أيام عمل",
    }
    caps["tier"] = "unsubscribed"
    caps["tier_label"] = "بدون اشتراك"
    caps["has_active_subscription"] = False
    caps["subscription_state"] = "unsubscribed"
    return caps


def plan_capabilities_for_user(user) -> dict:
    if not user or not getattr(user, "is_authenticated", False):
        return plan_capabilities_for_tier(CanonicalPlanTier.BASIC)

    from .services import get_effective_active_subscription

    active_sub = get_effective_active_subscription(user)
    if active_sub is None:
        if getattr(user, "provider_profile", None) is not None:
            return provider_unsubscribed_capabilities()
        return plan_capabilities_for_tier(CanonicalPlanTier.BASIC)
    caps = plan_capabilities_for_plan(getattr(active_sub, "plan", None))
    caps["urgent_requests"] = {
        "enabled": True,
        "label": "متاحة حسب أولوية الباقة",
    }
    caps["has_active_subscription"] = True
    caps["subscription_state"] = "active"
    return caps


def competitive_requests_enabled_for_user(user) -> bool:
    caps = plan_capabilities_for_user(user)
    competitive = caps.get("competitive_requests") or {}
    if "enabled" in competitive:
        return bool(competitive.get("enabled"))
    return True


def urgent_requests_enabled_for_user(user) -> bool:
    caps = plan_capabilities_for_user(user)
    urgent = caps.get("urgent_requests") or {}
    if "enabled" in urgent:
        return bool(urgent.get("enabled"))
    return True


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
    caps = plan_capabilities_for_user(user)
    return timedelta(hours=int(caps["competitive_requests"]["visibility_delay_hours"]))


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
    caps = plan_capabilities_for_user(user)
    return int(caps["banner_images"]["limit"])


def direct_chat_quota_for_tier(value) -> int:
    caps = plan_capabilities_for_tier(value)
    return int(caps["messaging"]["direct_chat_quota"])


def direct_chat_quota_for_user(user) -> int:
    caps = plan_capabilities_for_user(user)
    return int(caps["messaging"]["direct_chat_quota"])


def promotional_chat_controls_enabled_for_tier(value) -> bool:
    caps = plan_capabilities_for_tier(value)
    return bool(caps["promotional_controls"]["chat_messages"])


def promotional_chat_controls_enabled_for_user(user) -> bool:
    caps = plan_capabilities_for_user(user)
    return bool(caps["promotional_controls"]["chat_messages"])


def promotional_notification_controls_enabled_for_tier(value) -> bool:
    caps = plan_capabilities_for_tier(value)
    return bool(caps["promotional_controls"]["notification_messages"])


def promotional_notification_controls_enabled_for_user(user) -> bool:
    caps = plan_capabilities_for_user(user)
    return bool(caps["promotional_controls"]["notification_messages"])


def support_priority_for_tier(value) -> str:
    caps = plan_capabilities_for_tier(value)
    return str(caps["support"]["priority"])


def support_priority_for_user(user) -> str:
    caps = plan_capabilities_for_user(user)
    return str(caps["support"]["priority"])


def support_sla_for_tier(value) -> dict:
    caps = plan_capabilities_for_tier(value)
    return dict(caps["support"])


def support_sla_for_user(user) -> dict:
    caps = plan_capabilities_for_user(user)
    return dict(caps["support"])


def storage_upload_limit_mb_for_tier(value) -> int:
    caps = plan_capabilities_for_tier(value)
    return int(caps["storage"]["upload_max_mb"])


def storage_upload_limit_mb_for_user(user) -> int:
    caps = plan_capabilities_for_user(user)
    return int(caps["storage"]["upload_max_mb"])
