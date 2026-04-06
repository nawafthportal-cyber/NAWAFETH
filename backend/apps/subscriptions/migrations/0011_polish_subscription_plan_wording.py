from decimal import Decimal

from django.db import migrations


POLISHED_PLAN_SPECS = {
    "basic": {
        "title": "الأساسية",
        "description": "الباقة الأساسية المناسبة للانطلاق مع مزايا المنصة الافتراضية.",
        "feature_bullets": [
            "الوصول إلى جميع الخدمات الأساسية للمنصة كعميل وكمختص.",
            "تنبيهات مفعلة وسعة التخزين المجانية المتاحة افتراضياً.",
            "مناسبة للبداية مع وصول تدريجي للطلبات ورسوم توثيق مستقلة.",
        ],
        "reminder_policy_label": "أول تنبيه بعد اكتمال الطلب بـ 24 ساعة",
        "storage_label": "السعة المجانية المتاحة",
        "direct_chat_label": "3 محادثات مباشرة",
    },
    "riyadi": {
        "title": "الريادية",
        "description": "ترقية عملية لتوسيع السعة وزيادة فرص الوصول وتحسين رسوم التوثيق.",
        "feature_bullets": [
            "تشمل مزايا الأساسية مع تحسينات إضافية في الوصول والسعة والمحادثات.",
            "رسوم توثيق أقل مع سعة تخزينية مضاعفة وحد أعلى للمحادثات.",
            "مناسبة للنمو التشغيلي مع دعم أسرع من الباقة الأساسية.",
        ],
        "reminder_policy_label": "أول تنبيه + إرسال ثاني تنبيه بعد اكتمال الطلب بـ 120 ساعة",
        "storage_label": "ضعف السعة المجانية المتاحة",
        "direct_chat_label": "10 محادثات مباشرة",
    },
    "pro": {
        "title": "الاحترافية",
        "description": "أعلى باقة اشتراك بمزايا دعائية كاملة وتوثيق مشمول ودعم فني سريع.",
        "feature_bullets": [
            "تشمل مزايا الأساسية والريادية مع كامل الصلاحيات الاحترافية.",
            "وصول لحظي للطلبات التنافسية ورسائل دعائية كاملة داخل المحادثات والتنبيهات.",
            "توثيق أزرق وأخضر مشمول مع دعم فني خلال 5 ساعات.",
        ],
        "competitive_visibility_label": "لحظياً",
        "banner_images_label": "10 صور",
        "reminder_policy_label": "أول تنبيه + ثاني تنبيه + إرسال ثالث تنبيه بعد اكتمال الطلب بـ 240 ساعة",
        "storage_label": "سعة مفتوحة",
        "direct_chat_label": "50 محادثة مباشرة",
        "verification_blue_fee": Decimal("0.00"),
        "verification_green_fee": Decimal("0.00"),
    },
}


def polish_subscription_plan_wording(apps, schema_editor):
    SubscriptionPlan = apps.get_model("subscriptions", "SubscriptionPlan")

    for code, defaults in POLISHED_PLAN_SPECS.items():
        SubscriptionPlan.objects.filter(code=code).update(**defaults)


class Migration(migrations.Migration):

    dependencies = [
        ("subscriptions", "0010_refresh_canonical_subscription_plans_for_admin"),
    ]

    operations = [
        migrations.RunPython(
            polish_subscription_plan_wording,
            migrations.RunPython.noop,
        ),
    ]