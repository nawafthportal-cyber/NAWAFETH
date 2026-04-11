from django.db import migrations, models


def backfill_support_team_dashboard_code(apps, schema_editor):
    SupportTeam = apps.get_model("support", "SupportTeam")

    code_to_dashboard = {
        "support": "support",
        "content": "content",
        "promo": "promo",
        "verification": "verify",
        "verify": "verify",
        "finance": "subs",
        "subs": "subs",
        "extras": "extras",
    }

    for team in SupportTeam.objects.all().only("id", "code", "dashboard_code"):
        if str(team.dashboard_code or "").strip():
            continue
        mapped = code_to_dashboard.get(str(team.code or "").strip().lower(), "support")
        team.dashboard_code = mapped
        team.save(update_fields=["dashboard_code"])


def noop_reverse(apps, schema_editor):
    pass


class Migration(migrations.Migration):

    dependencies = [
        ("support", "0005_supportticket_entrypoint"),
    ]

    operations = [
        migrations.AddField(
            model_name="supportteam",
            name="dashboard_code",
            field=models.CharField(blank=True, default="", max_length=50),
        ),
        migrations.RunPython(backfill_support_team_dashboard_code, noop_reverse),
    ]
