from __future__ import annotations

from decimal import Decimal
from typing import Iterable

from django.db import transaction

from .models import SubscriptionPlan, PlanPeriod, PlanTier
from .tiering import CanonicalPlanTier, canonical_tier_from_inputs, db_tier_for_canonical


CANONICAL_PLAN_CODES = ("basic", "riyadi", "pro")


DEFAULT_SUBSCRIPTION_PLANS = [
    {
        "code": "basic",
        "tier": PlanTier.BASIC,
        "title": "الأساسية",
        "description": "الباقة الأساسية المناسبة للانطلاق مع مزايا المنصة الافتراضية.",
        "period": PlanPeriod.YEAR,
        "price": Decimal("0.00"),
        "features": ["verify_green"],
        "feature_bullets": [
            "الوصول إلى جميع الخدمات الأساسية للمنصة كعميل وكمختص.",
            "تنبيهات مفعلة وسعة التخزين المجانية المتاحة افتراضياً.",
            "مناسبة للبداية مع وصول تدريجي للطلبات ورسوم توثيق مستقلة.",
        ],
        "notifications_enabled": True,
        "competitive_visibility_delay_hours": 72,
        "competitive_visibility_label": "بعد 72 ساعة",
        "banner_images_limit": 1,
        "banner_images_label": "صورة واحدة",
        "direct_chat_quota": 3,
        "direct_chat_label": "3 محادثات مباشرة",
        "promotional_chat_messages_enabled": False,
        "promotional_notification_messages_enabled": False,
        "reminder_schedule_hours": [24],
        "reminder_policy_label": "أول تنبيه بعد اكتمال الطلب بـ 24 ساعة",
        "support_priority": "normal",
        "support_is_priority": False,
        "support_sla_hours": 120,
        "support_sla_label": "خلال 5 أيام",
        "storage_policy": "basic",
        "storage_label": "السعة المجانية المتاحة",
        "storage_multiplier": 1,
        "storage_upload_max_mb": 10,
        "verification_blue_fee": Decimal("100.00"),
        "verification_green_fee": Decimal("100.00"),
        "is_active": True,
    },
    {
        "code": "riyadi",
        "tier": PlanTier.RIYADI,
        "title": "الريادية",
        "description": "ترقية عملية لتوسيع السعة وزيادة فرص الوصول وتحسين رسوم التوثيق.",
        "period": PlanPeriod.YEAR,
        "price": Decimal("199.00"),
        "features": ["verify_green", "promo_ads"],
        "feature_bullets": [
            "تشمل مزايا الأساسية مع تحسينات إضافية في الوصول والسعة والمحادثات.",
            "رسوم توثيق أقل مع سعة تخزينية مضاعفة وحد أعلى للمحادثات.",
            "مناسبة للنمو التشغيلي مع دعم أسرع من الباقة الأساسية.",
        ],
        "notifications_enabled": True,
        "competitive_visibility_delay_hours": 24,
        "competitive_visibility_label": "بعد 24 ساعة",
        "banner_images_limit": 3,
        "banner_images_label": "3 صور",
        "direct_chat_quota": 10,
        "direct_chat_label": "10 محادثات مباشرة",
        "promotional_chat_messages_enabled": False,
        "promotional_notification_messages_enabled": False,
        "reminder_schedule_hours": [24, 120],
        "reminder_policy_label": "أول تنبيه + إرسال ثاني تنبيه بعد اكتمال الطلب بـ 120 ساعة",
        "support_priority": "high",
        "support_is_priority": True,
        "support_sla_hours": 48,
        "support_sla_label": "خلال يومين",
        "storage_policy": "double_basic",
        "storage_label": "ضعف السعة المجانية المتاحة",
        "storage_multiplier": 2,
        "storage_upload_max_mb": 20,
        "verification_blue_fee": Decimal("50.00"),
        "verification_green_fee": Decimal("50.00"),
        "is_active": True,
    },
    {
        "code": "pro",
        "tier": PlanTier.PRO,
        "title": "الاحترافية",
        "description": "أعلى باقة اشتراك بمزايا دعائية كاملة وتوثيق مشمول ودعم فني سريع.",
        "period": PlanPeriod.YEAR,
        "price": Decimal("999.00"),
        "features": ["verify_blue", "verify_green", "promo_ads", "priority_support", "advanced_analytics"],
        "feature_bullets": [
            "تشمل مزايا الأساسية والريادية مع كامل الصلاحيات الاحترافية.",
            "وصول لحظي للطلبات التنافسية ورسائل دعائية كاملة داخل المحادثات والتنبيهات.",
            "توثيق أزرق وأخضر مشمول مع دعم فني خلال 5 ساعات.",
        ],
        "notifications_enabled": True,
        "competitive_visibility_delay_hours": 0,
        "competitive_visibility_label": "لحظياً",
        "banner_images_limit": 10,
        "banner_images_label": "10 صور",
        "direct_chat_quota": 50,
        "direct_chat_label": "50 محادثة مباشرة",
        "promotional_chat_messages_enabled": True,
        "promotional_notification_messages_enabled": True,
        "reminder_schedule_hours": [24, 120, 240],
        "reminder_policy_label": "أول تنبيه + ثاني تنبيه + إرسال ثالث تنبيه بعد اكتمال الطلب بـ 240 ساعة",
        "support_priority": "high",
        "support_is_priority": True,
        "support_sla_hours": 5,
        "support_sla_label": "خلال 5 ساعات",
        "storage_policy": "open",
        "storage_label": "سعة مفتوحة",
        "storage_multiplier": None,
        "storage_upload_max_mb": 100,
        "verification_blue_fee": Decimal("0.00"),
        "verification_green_fee": Decimal("0.00"),
        "is_active": True,
    },
]


DEFAULT_BASIC_SUBSCRIPTION_PLAN = dict(DEFAULT_SUBSCRIPTION_PLANS[0])


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
    canonical = canonical_tier_from_inputs(
        tier=None,
        code=code,
        title=title,
        features=features,
        fallback=CanonicalPlanTier.BASIC,
    )
    return db_tier_for_canonical(canonical)


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


def ensure_basic_subscription_plan() -> SubscriptionPlan:
    code = DEFAULT_BASIC_SUBSCRIPTION_PLAN["code"]
    plan = SubscriptionPlan.objects.filter(code=code).first()
    if plan is None:
        seed_default_subscription_plans(force_update=False)
        plan = SubscriptionPlan.objects.filter(code=code).first()
    if plan is None:
        raise SubscriptionPlan.DoesNotExist("Canonical basic subscription plan is missing")
    return plan


def ensure_subscription_plans_exist() -> None:
    missing_codes = [
        code for code in CANONICAL_PLAN_CODES
        if not SubscriptionPlan.objects.filter(code=code).exists()
    ]
    if missing_codes:
        seed_default_subscription_plans(force_update=False)
        still_missing = [
            code for code in CANONICAL_PLAN_CODES
            if not SubscriptionPlan.objects.filter(code=code).exists()
        ]
        if still_missing:
            raise SubscriptionPlan.DoesNotExist(
                f"Missing canonical subscription plan rows: {', '.join(sorted(still_missing))}"
            )
