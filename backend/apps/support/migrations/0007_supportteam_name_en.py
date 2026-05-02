from django.db import migrations, models


SUPPORT_TEAM_NAME_EN = {
    "support": "Support & Help",
    "technical": "Support & Help",
    "finance": "Subscriptions",
    "subs": "Subscriptions",
    "verification": "Verification",
    "verify": "Verification",
    "content": "Content Management",
    "suggest": "Suggestions & Content",
    "promo": "Promotions",
    "ads": "Promotions",
    "extras": "Additional Services",
}


def populate_support_team_name_en(apps, schema_editor):
    SupportTeam = apps.get_model("support", "SupportTeam")
    for team in SupportTeam.objects.all().only("id", "code", "name_en"):
        name_en = SUPPORT_TEAM_NAME_EN.get((team.code or "").strip().lower(), "")
        if name_en and team.name_en != name_en:
            team.name_en = name_en
            team.save(update_fields=["name_en"])


class Migration(migrations.Migration):
    dependencies = [
        ("support", "0006_supportteam_dashboard_code"),
    ]

    operations = [
        migrations.AddField(
            model_name="supportteam",
            name="name_en",
            field=models.CharField(blank=True, default="", max_length=120),
        ),
        migrations.RunPython(populate_support_team_name_en, migrations.RunPython.noop),
    ]