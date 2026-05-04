from django.db import migrations, models


def backfill_spotlight_quota(apps, schema_editor):
    SubscriptionPlan = apps.get_model("subscriptions", "SubscriptionPlan")

    for plan in SubscriptionPlan.objects.all():
        changed_fields = []
        if getattr(plan, "spotlight_quota", None) in (None, 0):
            plan.spotlight_quota = int(getattr(plan, "direct_chat_quota", 0) or 0)
            changed_fields.append("spotlight_quota")
        if not str(getattr(plan, "spotlight_label", "") or "").strip():
            plan.spotlight_label = _spotlight_label_from_quota(plan.spotlight_quota)
            changed_fields.append("spotlight_label")
        if changed_fields:
            plan.save(update_fields=changed_fields)


def _spotlight_label_from_quota(quota: int) -> str:
    quota = int(quota or 0)
    if quota == 1:
        return "لمحة واحدة"
    if quota == 2:
        return "لمحتان"
    if 3 <= quota <= 10:
        return f"{quota} لمحات"
    return f"{quota} لمحة"


class Migration(migrations.Migration):

    dependencies = [
        ("subscriptions", "0012_subscriptionplan_urgent_visibility_settings"),
    ]

    operations = [
        migrations.AddField(
            model_name="subscriptionplan",
            name="spotlight_quota",
            field=models.PositiveIntegerField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="subscriptionplan",
            name="spotlight_label",
            field=models.CharField(blank=True, max_length=80),
        ),
        migrations.RunPython(backfill_spotlight_quota, migrations.RunPython.noop),
    ]