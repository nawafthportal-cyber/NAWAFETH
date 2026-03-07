from __future__ import annotations

from datetime import timedelta
from decimal import Decimal, ROUND_HALF_UP

from .capabilities import plan_capabilities_for_tier
from .tiering import CanonicalPlanTier, canonical_tier_from_inputs, canonical_tier_order


def _money(value) -> Decimal:
    return Decimal(str(value or "0.00")).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


SUBSCRIPTION_BILLING_CYCLE = "yearly"
SUBSCRIPTION_BILLING_CYCLE_LABEL = "سنوي"
SUBSCRIPTION_TAX_POLICY = "inclusive"
SUBSCRIPTION_TAX_POLICY_LABEL = "شامل الضريبة"
SUBSCRIPTION_ADDITIONAL_VAT_PERCENT = Decimal("0.00")
SUBSCRIPTION_TAX_NOTE = (
    "المبلغ المعروض هو الرسم السنوي النهائي للباقة، ولا تضاف ضريبة أو رسوم إضافية عند إنشاء "
    "فاتورة الاشتراك."
)


OFFICIAL_SUBSCRIPTION_OFFERS = {
    CanonicalPlanTier.BASIC: {
        "plan_name": "الأساسية",
        "price": Decimal("0.00"),
        "description": "تشمل الخدمات الأساسية لاكتشاف مقدم الخدمة واستخدام المنصة.",
        "feature_bullets": [
            "جميع الخدمات الأساسية لمقدم الخدمة داخل المنصة",
            "الوصول الافتراضي المجاني مع إشعارات مفعلة",
            "مناسبة للبداية مع حدود الاستخدام الأساسية",
        ],
    },
    CanonicalPlanTier.PIONEER: {
        "plan_name": "الريادية",
        "price": Decimal("199.00"),
        "description": "تشمل مزايا الأساسية مع وصول أسرع للطلبات وسعة استخدام أكبر.",
        "feature_bullets": [
            "كل مزايا الأساسية مع تحسين الوصول للطلبات",
            "سعة أكبر للمحادثات ومواد المنصة",
            "دعم فني أسرع ورسوم توثيق أقل",
        ],
    },
    CanonicalPlanTier.PROFESSIONAL: {
        "plan_name": "الاحترافية",
        "price": Decimal("999.00"),
        "description": "تشمل جميع المزايا مع وصول فوري وصلاحيات دعائية كاملة.",
        "feature_bullets": [
            "كل مزايا الأساسية والريادية ضمن باقة واحدة",
            "وصول فوري للطلبات التنافسية وصلاحيات دعائية كاملة",
            "توثيق مشمول ودعم فني خلال 5 ساعات",
        ],
    },
}


def official_plan_name_for_tier(value) -> str:
    canonical = canonical_tier_from_value(value)
    return OFFICIAL_SUBSCRIPTION_OFFERS[canonical]["plan_name"]


def canonical_tier_from_value(value, *, fallback: str = CanonicalPlanTier.BASIC) -> str:
    return canonical_tier_from_inputs(tier=value, fallback=fallback)


def subscription_offer_for_tier(value) -> dict[str, object]:
    canonical = canonical_tier_from_value(value)
    raw = OFFICIAL_SUBSCRIPTION_OFFERS[canonical]
    price = _money(raw["price"])
    return {
        "tier": canonical,
        "plan_name": raw["plan_name"],
        "description": raw["description"],
        "feature_bullets": list(raw["feature_bullets"]),
        "price": str(price),
        "price_amount": str(price),
        "annual_price": str(price),
        "annual_price_label": "مجانية" if price <= Decimal("0.00") else f"{price} ر.س سنويًا",
        "billing_cycle": SUBSCRIPTION_BILLING_CYCLE,
        "billing_cycle_label": SUBSCRIPTION_BILLING_CYCLE_LABEL,
        "tax_policy": SUBSCRIPTION_TAX_POLICY,
        "tax_policy_label": SUBSCRIPTION_TAX_POLICY_LABEL,
        "tax_included": True,
        "additional_vat_percent": str(_money(SUBSCRIPTION_ADDITIONAL_VAT_PERCENT)),
        "tax_note": SUBSCRIPTION_TAX_NOTE,
        "final_payable_amount": str(price),
        "final_payable_label": "مجانية" if price <= Decimal("0.00") else f"{price} ر.س",
    }


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


def subscription_plan_action_for_user(plan, user) -> dict[str, object]:
    target_tier = canonical_tier_from_inputs(
        tier=getattr(plan, "tier", ""),
        code=getattr(plan, "code", ""),
        title=getattr(plan, "title", ""),
        features=getattr(plan, "features", []) or [],
    )
    if not getattr(user, "is_authenticated", False):
        return {
            "state": "upgrade",
            "label": "ترقية",
            "enabled": True,
            "current_tier": CanonicalPlanTier.BASIC,
            "current_plan_name": OFFICIAL_SUBSCRIPTION_OFFERS[CanonicalPlanTier.BASIC]["plan_name"],
        }

    from .models import Subscription, SubscriptionStatus
    from .services import get_effective_active_subscription, plan_to_tier

    pending = (
        Subscription.objects.filter(
            user=user,
            plan=plan,
            status=SubscriptionStatus.PENDING_PAYMENT,
        )
        .order_by("-id")
        .first()
    )
    if pending is not None:
        return {
            "state": "pending",
            "label": "قيد التفعيل",
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
        features=getattr(plan, "features", []) or [],
    )
    offer = subscription_offer_for_tier(canonical)
    capabilities = plan_capabilities_for_tier(canonical)

    from apps.verification.services import verification_pricing_for_plan

    verification = verification_pricing_for_plan(plan)
    blue_amount = ((verification.get("prices") or {}).get("blue") or {}).get("final_amount", "100.00")
    green_amount = ((verification.get("prices") or {}).get("green") or {}).get("final_amount", "100.00")

    card_rows = [
        {"key": "annual_price", "label": "السعر السنوي", "value": offer["annual_price_label"]},
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
            "key": "promotional_controls",
            "label": "الرسائل الدعائية",
            "value": _promotional_permissions_label(capabilities),
        },
        {
            "key": "reminders",
            "label": "سياسة رسائل التذكير",
            "value": capabilities["reminders"]["label"],
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
        "promotional_permissions_label": _promotional_permissions_label(capabilities),
        "reminder_policy_label": capabilities["reminders"]["label"],
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


def subscription_offer_end_at(*, plan, start_at):
    offer = subscription_offer_for_plan(plan)
    if offer["billing_cycle"] == SUBSCRIPTION_BILLING_CYCLE:
        return start_at + timedelta(days=365)
    return start_at + timedelta(days=30)
