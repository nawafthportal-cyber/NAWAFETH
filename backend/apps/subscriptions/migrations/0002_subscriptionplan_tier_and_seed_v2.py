from decimal import Decimal

from django.db import migrations, models


CANONICAL_DEFAULTS = [
    {
        "code": "basic",
        "tier": "basic",
        "title": "أساسية",
        "description": "مناسبة للبداية",
        "period": "month",
        "price": Decimal("49.00"),
        "features": ["verify_green"],
        "is_active": True,
    },
    {
        "code": "riyadi",
        "tier": "riyadi",
        "title": "ريادية",
        "description": "للنمو وتوسيع الفرص",
        "period": "month",
        "price": Decimal("79.00"),
        "features": ["verify_green", "promo_ads"],
        "is_active": True,
    },
    {
        "code": "pro",
        "tier": "pro",
        "title": "احترافية",
        "description": "للعملاء النشطين",
        "period": "month",
        "price": Decimal("99.00"),
        "features": ["verify_blue", "verify_green", "promo_ads", "priority_support", "advanced_analytics"],
        "is_active": True,
    },
]


def _infer_tier(code: str, title: str, features) -> str:
    code_key = (code or "").strip().lower()
    if code_key in {"riyadi", "riyadi_month", "entrepreneur", "entrepreneur_month", "leading", "leading_month"}:
        return "riyadi"
    if code_key in {"pro", "pro_month", "pro_year", "pro_yearly", "professional", "professional_month", "professional_year"}:
        return "pro"
    if code_key in {"basic", "basic_month"}:
        return "basic"

    title_key = (title or "").strip().lower()
    if "رياد" in title_key:
        return "riyadi"
    if "احتراف" in title_key or "professional" in title_key:
        return "pro"

    feature_values = {str(item or "").strip().lower() for item in (features or [])}
    if "verify_blue" in feature_values or "advanced_analytics" in feature_values:
        return "pro"
    if "priority_support" in feature_values or "promo_ads" in feature_values:
        return "riyadi"
    return "basic"


def migrate_plan_tiers_and_codes(apps, schema_editor):
    SubscriptionPlan = apps.get_model("subscriptions", "SubscriptionPlan")

    legacy_to_canonical = {
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

    existing_by_code = {
        (plan.code or "").strip().lower(): plan.id
        for plan in SubscriptionPlan.objects.all().only("id", "code")
    }

    for plan in SubscriptionPlan.objects.all().order_by("id"):
        update_fields = []

        tier = _infer_tier(plan.code, plan.title, plan.features or [])
        if (plan.tier or "").strip().lower() != tier:
            plan.tier = tier
            update_fields.append("tier")

        code_key = (plan.code or "").strip().lower()
        target_code = legacy_to_canonical.get(code_key)
        if target_code:
            owner_id = existing_by_code.get(target_code)
            if owner_id in (None, plan.id):
                if code_key != target_code:
                    plan.code = target_code
                    update_fields.append("code")
                    existing_by_code[target_code] = plan.id

        if update_fields:
            plan.save(update_fields=update_fields)

    for raw in CANONICAL_DEFAULTS:
        defaults = dict(raw)
        code = defaults.pop("code")
        SubscriptionPlan.objects.update_or_create(code=code, defaults=defaults)


def noop_reverse(apps, schema_editor):
    return


class Migration(migrations.Migration):

    dependencies = [
        ("subscriptions", "0001_initial"),
    ]

    operations = [
        migrations.AddField(
            model_name="subscriptionplan",
            name="tier",
            field=models.CharField(
                choices=[("basic", "أساسية"), ("riyadi", "ريادية"), ("pro", "احترافية")],
                default="basic",
                max_length=20,
            ),
        ),
        migrations.RunPython(migrate_plan_tiers_and_codes, reverse_code=noop_reverse),
    ]
