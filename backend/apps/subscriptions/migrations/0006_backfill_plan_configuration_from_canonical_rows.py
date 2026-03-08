from decimal import Decimal

from django.db import migrations


CANONICAL_CONFIGURATION = {
    "basic": {
        "tier": "basic",
        "title": "أساسية",
        "description": "مناسبة للبداية",
        "period": "year",
        "price": Decimal("0.00"),
        "features": ["verify_green"],
        "feature_bullets": [
            "جميع الخدمات الأساسية لمقدم الخدمة داخل المنصة",
            "الوصول الافتراضي المجاني مع إشعارات مفعلة",
            "مناسبة للبداية مع حدود الاستخدام الأساسية",
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
        "reminder_policy_label": "التذكير الأول بعد 24 ساعة",
        "support_priority": "normal",
        "support_is_priority": False,
        "support_sla_hours": 120,
        "support_sla_label": "خلال 5 أيام",
        "storage_policy": "basic",
        "storage_label": "السعة المجانية الأساسية",
        "storage_multiplier": 1,
        "storage_upload_max_mb": 10,
        "verification_blue_fee": Decimal("100.00"),
        "verification_green_fee": Decimal("100.00"),
        "is_active": True,
    },
    "riyadi": {
        "tier": "riyadi",
        "title": "ريادية",
        "description": "للنمو وتوسيع الفرص",
        "period": "year",
        "price": Decimal("199.00"),
        "features": ["verify_green", "promo_ads"],
        "feature_bullets": [
            "كل مزايا الأساسية مع تحسين الوصول للطلبات",
            "سعة أكبر للمحادثات ومواد المنصة",
            "دعم فني أسرع ورسوم توثيق أقل",
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
        "reminder_policy_label": "التذكير الأول ثم الثاني بعد 120 ساعة",
        "support_priority": "high",
        "support_is_priority": True,
        "support_sla_hours": 48,
        "support_sla_label": "خلال يومين",
        "storage_policy": "double_basic",
        "storage_label": "ضعف السعة المجانية",
        "storage_multiplier": 2,
        "storage_upload_max_mb": 20,
        "verification_blue_fee": Decimal("50.00"),
        "verification_green_fee": Decimal("50.00"),
        "is_active": True,
    },
    "pro": {
        "tier": "pro",
        "title": "احترافية",
        "description": "للعملاء النشطين",
        "period": "year",
        "price": Decimal("999.00"),
        "features": ["verify_blue", "verify_green", "promo_ads", "priority_support", "advanced_analytics"],
        "feature_bullets": [
            "كل مزايا الأساسية والريادية ضمن باقة واحدة",
            "وصول فوري للطلبات التنافسية وصلاحيات دعائية كاملة",
            "توثيق مشمول ودعم فني خلال 5 ساعات",
        ],
        "notifications_enabled": True,
        "competitive_visibility_delay_hours": 0,
        "competitive_visibility_label": "فوري",
        "banner_images_limit": 10,
        "banner_images_label": "10 صور",
        "direct_chat_quota": 50,
        "direct_chat_label": "50 محادثة مباشرة",
        "promotional_chat_messages_enabled": True,
        "promotional_notification_messages_enabled": True,
        "reminder_schedule_hours": [24, 120, 240],
        "reminder_policy_label": "التذكير الأول والثاني والثالث حتى 240 ساعة",
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
}

CONFIGURATION_FIELDS = (
    "feature_bullets",
    "notifications_enabled",
    "competitive_visibility_delay_hours",
    "competitive_visibility_label",
    "banner_images_limit",
    "banner_images_label",
    "direct_chat_quota",
    "direct_chat_label",
    "promotional_chat_messages_enabled",
    "promotional_notification_messages_enabled",
    "reminder_schedule_hours",
    "reminder_policy_label",
    "support_priority",
    "support_is_priority",
    "support_sla_hours",
    "support_sla_label",
    "storage_policy",
    "storage_label",
    "storage_multiplier",
    "storage_upload_max_mb",
    "verification_blue_fee",
    "verification_green_fee",
)


def _infer_tier(plan) -> str:
    code_key = (getattr(plan, "code", "") or "").strip().lower()
    if code_key in {"riyadi", "riyadi_month", "entrepreneur", "entrepreneur_month", "leading", "leading_month"}:
        return "riyadi"
    if code_key in {"pro", "pro_month", "pro_year", "pro_yearly", "professional", "professional_month", "professional_year"}:
        return "pro"
    if code_key in {"basic", "basic_month"}:
        return "basic"

    title_key = (getattr(plan, "title", "") or "").strip().lower()
    if "رياد" in title_key:
        return "riyadi"
    if "احتراف" in title_key or "professional" in title_key:
        return "pro"

    feature_values = {str(item or "").strip().lower() for item in (getattr(plan, "features", None) or [])}
    if "verify_blue" in feature_values or "advanced_analytics" in feature_values:
        return "pro"
    if "priority_support" in feature_values or "promo_ads" in feature_values:
        return "riyadi"
    return "basic"


def _is_missing(value) -> bool:
    return value in (None, "", [])


def backfill_subscription_plan_configuration(apps, schema_editor):
    SubscriptionPlan = apps.get_model("subscriptions", "SubscriptionPlan")

    for code, defaults in CANONICAL_CONFIGURATION.items():
        base_defaults = dict(defaults)
        plan = SubscriptionPlan.objects.filter(code=code).first()
        if plan is None:
            SubscriptionPlan.objects.create(code=code, **base_defaults)
            continue

        updates = {}
        for field_name in CONFIGURATION_FIELDS:
            if _is_missing(getattr(plan, field_name, None)):
                updates[field_name] = defaults[field_name]
        if updates:
            SubscriptionPlan.objects.filter(pk=plan.pk).update(**updates)

    for plan in SubscriptionPlan.objects.all().order_by("id"):
        template_defaults = CANONICAL_CONFIGURATION[_infer_tier(plan)]
        updates = {}
        for field_name in CONFIGURATION_FIELDS:
            if _is_missing(getattr(plan, field_name, None)):
                updates[field_name] = template_defaults[field_name]
        if updates:
            SubscriptionPlan.objects.filter(pk=plan.pk).update(**updates)


class Migration(migrations.Migration):

    dependencies = [
        ("subscriptions", "0005_subscriptionplan_banner_images_label_and_more"),
    ]

    operations = [
        migrations.RunPython(
            backfill_subscription_plan_configuration,
            migrations.RunPython.noop,
        ),
    ]