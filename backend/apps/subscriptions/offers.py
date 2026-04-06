from __future__ import annotations

from datetime import timedelta
from decimal import Decimal, ROUND_HALF_UP

from .capabilities import plan_capabilities_for_plan
from .configuration import (
    canonical_subscription_plan_for_tier,
    resolved_plan_decimal,
    resolved_plan_string,
    resolved_plan_string_list,
    template_subscription_plan_for_plan,
)
from .models import PlanPeriod
from .tiering import CanonicalPlanTier, canonical_tier_from_inputs, canonical_tier_order


def _money(value) -> Decimal:
    return Decimal(str(value or "0.00")).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


SUBSCRIPTION_BILLING_CYCLE_YEARLY = "yearly"
SUBSCRIPTION_BILLING_CYCLE_MONTHLY = "monthly"
SUBSCRIPTION_BILLING_CYCLE_LABELS = {
    PlanPeriod.YEAR: "سنوي",
    PlanPeriod.MONTH: "شهري",
}
SUBSCRIPTION_PRICE_INTERVAL_LABELS = {
    PlanPeriod.YEAR: "سنويًا",
    PlanPeriod.MONTH: "شهريًا",
}
SUBSCRIPTION_TAX_POLICY = "exclusive"
SUBSCRIPTION_TAX_POLICY_LABEL = "تضاف الضريبة عند الفوترة"


def _subscription_additional_vat_percent() -> Decimal:
    from apps.billing.pricing import get_vat_percent

    return _money(get_vat_percent("default"))


def _subscription_tax_note() -> str:
    return "يضاف على سعر الباقة ضريبة القيمة المضافة بحسب إعدادات المنصة عند إنشاء فاتورة الاشتراك."


def _billing_cycle_payload(period: str) -> tuple[str, str, str]:
    normalized_period = period if period in {PlanPeriod.YEAR, PlanPeriod.MONTH} else PlanPeriod.YEAR
    billing_cycle = (
        SUBSCRIPTION_BILLING_CYCLE_YEARLY
        if normalized_period == PlanPeriod.YEAR
        else SUBSCRIPTION_BILLING_CYCLE_MONTHLY
    )
    return (
        billing_cycle,
        SUBSCRIPTION_BILLING_CYCLE_LABELS[normalized_period],
        SUBSCRIPTION_PRICE_INTERVAL_LABELS[normalized_period],
    )


def _offer_payload_for_plan(plan, *, canonical: str) -> dict[str, object]:
    template = template_subscription_plan_for_plan(plan, fallback_tier=canonical)
    price = _money(resolved_plan_decimal(plan, template, "price", default="0.00"))
    additional_vat_percent = _subscription_additional_vat_percent()
    billing_cycle, billing_cycle_label, interval_label = _billing_cycle_payload(
        resolved_plan_string(plan, template, "period", default=PlanPeriod.YEAR)
    )
    plan_name = resolved_plan_string(plan, template, "title")
    description = resolved_plan_string(plan, template, "description")
    feature_bullets = resolved_plan_string_list(plan, template, method_name="marketing_bullets")
    return {
        "tier": canonical,
        "plan_name": plan_name,
        "description": description,
        "feature_bullets": list(feature_bullets),
        "price": str(price),
        "price_amount": str(price),
        "annual_price": str(price),
        "annual_price_label": "مجانية" if price <= Decimal("0.00") else f"{price} ر.س {interval_label}",
        "billing_cycle": billing_cycle,
        "billing_cycle_label": billing_cycle_label,
        "tax_policy": SUBSCRIPTION_TAX_POLICY,
        "tax_policy_label": SUBSCRIPTION_TAX_POLICY_LABEL,
        "tax_included": False,
        "additional_vat_percent": str(additional_vat_percent),
        "tax_note": _subscription_tax_note(),
        "final_payable_amount": str(price),
        "final_payable_label": "مجانية" if price <= Decimal("0.00") else f"{price} ر.س",
    }


def official_plan_name_for_tier(value) -> str:
    return resolved_plan_string(None, canonical_subscription_plan_for_tier(value), "title")


def canonical_tier_from_value(value, *, fallback: str = CanonicalPlanTier.BASIC) -> str:
    return canonical_tier_from_inputs(tier=value, fallback=fallback)


def subscription_offer_for_tier(value) -> dict[str, object]:
    canonical = canonical_tier_from_value(value)
    plan = canonical_subscription_plan_for_tier(canonical)
    return _offer_payload_for_plan(plan, canonical=canonical)


def _verification_label(amount_text: str) -> str:
    amount = _money(amount_text)
    if amount <= Decimal("0.00"):
        return "مشمول مجانًا"
    return f"{amount} ر.س سنويًا"


def _combined_verification_label(blue_amount: str, green_amount: str) -> str:
    blue = _money(blue_amount)
    green = _money(green_amount)
    if blue <= Decimal("0.00") and green <= Decimal("0.00"):
        return "التوثيق الأزرق والأخضر مشمولان مجانًا"
    if blue == green:
        return f"{blue} ر.س سنويًا لكل شارة"
    return f"الأزرق {blue} ر.س - الأخضر {green} ر.س سنويًا"


def _promotional_permissions_label(capabilities: dict) -> str:
    promo = capabilities.get("promotional_controls") or {}
    if promo.get("chat_messages") and promo.get("notification_messages"):
        return "متاحة للمحادثات والإشعارات"
    return "غير متاحة"


def _notifications_label(capabilities: dict) -> str:
    return "مفعلة" if capabilities.get("notifications_enabled") else "غير مفعلة"


def _support_priority_label(capabilities: dict) -> str:
    support = capabilities.get("support") or {}
    if support.get("is_priority"):
        return "أولوية عالية"
    priority = str(support.get("priority") or "").strip().lower()
    mapping = {
        "high": "أولوية عالية",
        "normal": "أولوية عادية",
        "low": "أولوية منخفضة",
    }
    return mapping.get(priority, "أولوية عادية")


def subscription_plan_action_for_user(plan, user) -> dict[str, object]:
    target_tier = canonical_tier_from_inputs(
        tier=getattr(plan, "tier", ""),
        code=getattr(plan, "code", ""),
        title=getattr(plan, "title", ""),
        features=getattr(plan, "feature_keys", lambda: [])(),
    )
    if not getattr(user, "is_authenticated", False):
        return {
            "state": "upgrade",
            "label": "ترقية",
            "enabled": True,
            "current_tier": CanonicalPlanTier.BASIC,
            "current_plan_name": official_plan_name_for_tier(CanonicalPlanTier.BASIC),
        }

    from .models import Subscription, SubscriptionStatus
    from .services import get_effective_active_subscription, plan_to_tier

    pending = (
        Subscription.objects.filter(
            user=user,
            plan=plan,
            status__in=(SubscriptionStatus.PENDING_PAYMENT, SubscriptionStatus.AWAITING_REVIEW),
        )
        .order_by("-id")
        .first()
    )
    if pending is not None:
        pending_status = str(getattr(pending, "status", "") or "").strip().lower()
        return {
            "state": "pending",
            "label": "بانتظار المراجعة" if pending_status == SubscriptionStatus.AWAITING_REVIEW else "قيد التفعيل",
            "enabled": False,
            "subscription_id": pending.id,
            "current_tier": target_tier,
            "current_plan_name": official_plan_name_for_tier(target_tier),
        }

    current = get_effective_active_subscription(user)
    current_tier = plan_to_tier(getattr(current, "plan", None)) if current is not None else CanonicalPlanTier.BASIC
    current_plan_name = official_plan_name_for_tier(current_tier)

    if target_tier == current_tier:
        return {
            "state": "current",
            "label": "الباقة الحالية",
            "enabled": False,
            "current_tier": current_tier,
            "current_plan_name": current_plan_name,
            "subscription_id": getattr(current, "id", None),
            "current_status": getattr(current, "status", None),
            "current_status_label": getattr(current, "get_status_display", lambda: None)(),
        }

    if canonical_tier_order(target_tier) > canonical_tier_order(current_tier):
        return {
            "state": "upgrade",
            "label": "ترقية",
            "enabled": True,
            "current_tier": current_tier,
            "current_plan_name": current_plan_name,
            "subscription_id": getattr(current, "id", None),
            "current_status": getattr(current, "status", None),
            "current_status_label": getattr(current, "get_status_display", lambda: None)(),
        }

    return {
        "state": "unavailable",
        "label": "غير متاحة",
        "enabled": False,
        "current_tier": current_tier,
        "current_plan_name": current_plan_name,
        "subscription_id": getattr(current, "id", None),
        "current_status": getattr(current, "status", None),
        "current_status_label": getattr(current, "get_status_display", lambda: None)(),
    }


def subscription_offer_for_plan(plan, *, user=None) -> dict[str, object]:
    canonical = canonical_tier_from_inputs(
        tier=getattr(plan, "tier", ""),
        code=getattr(plan, "code", ""),
        title=getattr(plan, "title", ""),
        features=getattr(plan, "feature_keys", lambda: [])(),
    )
    offer = _offer_payload_for_plan(plan, canonical=canonical)
    capabilities = plan_capabilities_for_plan(plan)

    from apps.verification.services import verification_price_amount, verification_pricing_for_plan

    verification = verification_pricing_for_plan(plan)
    blue_amount = verification_price_amount(verification, "blue", prefer_final=True)
    green_amount = verification_price_amount(verification, "green", prefer_final=True)

    card_rows = [
        {"key": "annual_price", "label": "سعر الباقة", "value": offer["annual_price_label"]},
        {"key": "verification_blue", "label": "التوثيق الأزرق", "value": _verification_label(blue_amount)},
        {"key": "verification_green", "label": "التوثيق الأخضر", "value": _verification_label(green_amount)},
        {
            "key": "competitive_requests",
            "label": "وقت استقبال الطلبات التنافسية",
            "value": capabilities["competitive_requests"]["visibility_label"],
        },
        {
            "key": "banner_images",
            "label": "عدد صور شعار المنصة",
            "value": capabilities["banner_images"]["label"],
        },
        {
            "key": "chats_quota",
            "label": "عدد المحادثات المتاحة",
            "value": capabilities["messaging"]["label"],
        },
        {
            "key": "support_sla",
            "label": "زمن الدعم الفني",
            "value": capabilities["support"]["sla_label"],
        },
        {
            "key": "support_priority",
            "label": "أولوية الدعم",
            "value": _support_priority_label(capabilities),
        },
        {
            "key": "promotional_controls",
            "label": "الرسائل الدعائية",
            "value": _promotional_permissions_label(capabilities),
        },
        {
            "key": "notifications",
            "label": "الإشعارات",
            "value": _notifications_label(capabilities),
        },
        {
            "key": "reminders",
            "label": "سياسة رسائل التذكير",
            "value": capabilities["reminders"]["label"],
        },
        {
            "key": "storage",
            "label": "سعة التخزين والرفع",
            "value": capabilities["storage"]["label"],
        },
    ]

    payload = {
        **offer,
        "plan_name": offer["plan_name"],
        "request_access_label": capabilities["competitive_requests"]["visibility_label"],
        "banner_images_limit": capabilities["banner_images"]["limit"],
        "banner_images_label": capabilities["banner_images"]["label"],
        "chats_quota": capabilities["messaging"]["direct_chat_quota"],
        "chats_label": capabilities["messaging"]["label"],
        "support_sla_hours": capabilities["support"]["sla_hours"],
        "support_sla_label": capabilities["support"]["sla_label"],
        "support_priority_label": _support_priority_label(capabilities),
        "promotional_permissions_label": _promotional_permissions_label(capabilities),
        "notifications_label": _notifications_label(capabilities),
        "reminder_policy_label": capabilities["reminders"]["label"],
        "storage_label": capabilities["storage"]["label"],
        "verification_blue_amount": str(_money(blue_amount)),
        "verification_green_amount": str(_money(green_amount)),
        "verification_blue_label": _verification_label(blue_amount),
        "verification_green_label": _verification_label(green_amount),
        "verification_effect_label": _combined_verification_label(blue_amount, green_amount),
        "card_rows": card_rows,
        "summary_rows": list(card_rows),
    }
    if user is not None:
        payload["cta"] = subscription_plan_action_for_user(plan, user)
    return payload


def subscription_offer_end_at(*, plan, start_at, duration_count: int = 1):
    from apps.core.models import PlatformConfig
    config = PlatformConfig.load()
    template = template_subscription_plan_for_plan(plan, fallback_tier=CanonicalPlanTier.BASIC)
    period = resolved_plan_string(plan, template, "period", default=PlanPeriod.YEAR)
    normalized_duration = max(1, int(duration_count or 1))
    if period == PlanPeriod.YEAR:
        return start_at + timedelta(days=config.subscription_yearly_duration_days * normalized_duration)
    return start_at + timedelta(days=config.subscription_monthly_duration_days * normalized_duration)
