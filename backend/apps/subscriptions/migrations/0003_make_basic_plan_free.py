from decimal import Decimal

from django.db import migrations


def make_basic_plan_free(apps, schema_editor):
    SubscriptionPlan = apps.get_model("subscriptions", "SubscriptionPlan")

    basic = None
    for plan in SubscriptionPlan.objects.all().order_by("id"):
        code = (getattr(plan, "code", "") or "").strip().lower()
        tier = (getattr(plan, "tier", "") or "").strip().lower()
        if code == "basic":
            basic = plan
            break
        if basic is None and tier == "basic":
            basic = plan

    if basic is None:
        SubscriptionPlan.objects.create(
            code="basic",
            tier="basic",
            title="أساسية",
            description="مناسبة للبداية",
            period="month",
            price=Decimal("0.00"),
            features=["verify_green"],
            is_active=True,
        )
        return

    updates = {}
    if (getattr(basic, "code", "") or "").strip().lower() == "basic":
        if basic.price != Decimal("0.00"):
            updates["price"] = Decimal("0.00")
        if not basic.is_active:
            updates["is_active"] = True
        if (basic.tier or "").strip().lower() != "basic":
            updates["tier"] = "basic"
    else:
        if basic.price != Decimal("0.00"):
            updates["price"] = Decimal("0.00")
        if not basic.is_active:
            updates["is_active"] = True
        if (basic.tier or "").strip().lower() != "basic":
            updates["tier"] = "basic"

    if updates:
        SubscriptionPlan.objects.filter(pk=basic.pk).update(**updates)


class Migration(migrations.Migration):

    dependencies = [
        ("subscriptions", "0002_subscriptionplan_tier_and_seed_v2"),
    ]

    operations = [
        migrations.RunPython(make_basic_plan_free, migrations.RunPython.noop),
    ]
