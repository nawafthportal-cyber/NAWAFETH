from django.db import migrations, models


def backfill_entrypoint(apps, schema_editor):
    SupportTicket = apps.get_model("support", "SupportTicket")
    SupportTicket.objects.filter(reported_kind="thread").update(entrypoint="messaging_report")


def noop_reverse(apps, schema_editor):
    pass


class Migration(migrations.Migration):

    dependencies = [
        ("support", "0004_normalize_support_team_labels_20260325"),
    ]

    operations = [
        migrations.AddField(
            model_name="supportticket",
            name="entrypoint",
            field=models.CharField(
                choices=[
                    ("contact_platform", "تواصل مع المنصة"),
                    ("messaging_report", "بلاغ المحادثات"),
                ],
                default="contact_platform",
                max_length=32,
            ),
        ),
        migrations.RunPython(backfill_entrypoint, noop_reverse),
    ]
