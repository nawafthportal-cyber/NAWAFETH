from django.db import migrations, models


def _visibility_label(hours: int) -> str:
    if int(hours or 0) <= 0:
        return "لحظياً"
    return f"بعد {int(hours)} ساعة"


def _fallback_delay(plan) -> int:
    code = str(getattr(plan, "code", "") or "").strip().lower()
    tier = str(getattr(plan, "tier", "") or "").strip().lower()
    title = str(getattr(plan, "title", "") or "").strip().lower()

    if code in {"pro", "pro_month", "pro_year", "pro_yearly", "professional", "professional_month", "professional_year"}:
        return 0
    if code in {"riyadi", "riyadi_month", "leading", "leading_month", "entrepreneur", "entrepreneur_month", "pioneer", "pioneer_month"}:
        return 24
    if tier == "pro" or "احتراف" in title or "professional" in title:
        return 0
    if tier == "riyadi" or "رياد" in title or "pioneer" in title or "leading" in title:
        return 24
    return 72


def backfill_urgent_visibility_settings(apps, schema_editor):
    SubscriptionPlan = apps.get_model("subscriptions", "SubscriptionPlan")

    for plan in SubscriptionPlan.objects.all().order_by("id"):
        updates = {}
        delay = getattr(plan, "urgent_visibility_delay_hours", None)
        label = str(getattr(plan, "urgent_visibility_label", "") or "").strip()

        if delay is None:
            competitive_delay = getattr(plan, "competitive_visibility_delay_hours", None)
            delay = int(competitive_delay) if competitive_delay is not None else _fallback_delay(plan)
            updates["urgent_visibility_delay_hours"] = delay

        if not label:
            competitive_label = str(getattr(plan, "competitive_visibility_label", "") or "").strip()
            label = competitive_label or _visibility_label(delay)
            updates["urgent_visibility_label"] = label

        if updates:
            SubscriptionPlan.objects.filter(pk=plan.pk).update(**updates)


class Migration(migrations.Migration):

    dependencies = [
        ("subscriptions", "0011_polish_subscription_plan_wording"),
    ]

    operations = [
        migrations.AddField(
            model_name="subscriptionplan",
            name="urgent_visibility_delay_hours",
            field=models.PositiveIntegerField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="subscriptionplan",
            name="urgent_visibility_label",
            field=models.CharField(blank=True, max_length=80),
        ),
        migrations.RunPython(backfill_urgent_visibility_settings, migrations.RunPython.noop),
    ]