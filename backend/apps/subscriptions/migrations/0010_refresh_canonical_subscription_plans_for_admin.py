from decimal import Decimal

from django.db import migrations


CANONICAL_PLAN_SPECS = {
    "basic": {
        "tier": "basic",
        "title": "الأساسية",
        "description": "الباقة الأساسية لمقدم الخدمة مع تفعيل خدمات المنصة الافتراضية.",
        "period": "year",
        "price": Decimal("0.00"),
        "features": ["verify_green"],
        "feature_bullets": [
            "الدخول لجميع الخدمات الأساسية للمنصة كعميل وكمختص.",
            "تنبيهات مفعلة وسعة التخزين المجانية المتاحة افتراضياً.",
            "مناسبة للبداية مع وصول تدرجي للطلبات ورسوم توثيق مستقلة.",
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
        "reminder_policy_label": "وقت إرسال أول تنبيه بعد اكتمال الطلب بـ 24 ساعة",
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
    "riyadi": {
        "tier": "riyadi",
        "title": "الريادية",
        "description": "ترقية مخصصة لتوسيع السعة والوصول وتحسين كلفة التوثيق.",
        "period": "year",
        "price": Decimal("199.00"),
        "features": ["verify_green", "promo_ads"],
        "feature_bullets": [
            "تشمل الأساسية مع مزايا إضافية للوصول والسعة والمحادثات.",
            "رسوم توثيق أقل مع سعة تخزين مضاعفة وحد أعلى للمحادثات.",
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
    "pro": {
        "tier": "pro",
        "title": "الاحترافية",
        "description": "أعلى باقة اشتراك مع صلاحيات كاملة للدعاية وتوثيق مشمول ودعم أسرع.",
        "period": "year",
        "price": Decimal("999.00"),
        "features": ["verify_blue", "verify_green", "promo_ads", "priority_support", "advanced_analytics"],
        "feature_bullets": [
            "تشمل الأساسية والريادية مع مزايا احترافية كاملة.",
            "وصول لحظي للطلبات التنافسية ورسائل دعائية كاملة داخل المحادثات والتنبيهات.",
            "توثيق أزرق وأخضر مشمول مع دعم فني خلال 5 ساعات.",
        ],
        "notifications_enabled": True,
        "competitive_visibility_delay_hours": 0,
        "competitive_visibility_label": "لحظياً",
        "banner_images_limit": 10,
        "banner_images_label": "عشر صور",
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
        "storage_label": "مفتوح",
        "storage_multiplier": None,
        "storage_upload_max_mb": 100,
        "verification_blue_fee": Decimal("0.00"),
        "verification_green_fee": Decimal("0.00"),
        "is_active": True,
    },
}


def refresh_canonical_subscription_plans(apps, schema_editor):
    SubscriptionPlan = apps.get_model("subscriptions", "SubscriptionPlan")

    for code, defaults in CANONICAL_PLAN_SPECS.items():
        SubscriptionPlan.objects.update_or_create(code=code, defaults=defaults)


class Migration(migrations.Migration):

    dependencies = [
        ("subscriptions", "0009_subscription_duration_count"),
    ]

    operations = [
        migrations.RunPython(
            refresh_canonical_subscription_plans,
            migrations.RunPython.noop,
        ),
    ]