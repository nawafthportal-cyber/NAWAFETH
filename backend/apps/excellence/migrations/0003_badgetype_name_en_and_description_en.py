from django.db import migrations, models


BADGE_TRANSLATIONS = {
    "featured_service": ("Featured Service", "Awarded to the highest-rated specialists during the current review cycle."),
    "high_achievement": ("High Achievement", "Awarded to the specialists with the strongest completed-order achievement over the past year."),
    "top_100_club": ("Top 100 Club", "Awarded to the top 100 specialists by following and overall platform impact."),
}


def populate_badge_translations(apps, schema_editor):
    BadgeType = apps.get_model("excellence", "ExcellenceBadgeType")
    for badge in BadgeType.objects.all().only("id", "code", "name_en", "description_en"):
        translation = BADGE_TRANSLATIONS.get((badge.code or "").strip().lower())
        if not translation:
            continue
        name_en, description_en = translation
        updated_fields = []
        if badge.name_en != name_en:
            badge.name_en = name_en
            updated_fields.append("name_en")
        if badge.description_en != description_en:
            badge.description_en = description_en
            updated_fields.append("description_en")
        if updated_fields:
            badge.save(update_fields=updated_fields)


class Migration(migrations.Migration):
    dependencies = [
        ("excellence", "0002_seed_excellence_dashboard"),
    ]

    operations = [
        migrations.AddField(
            model_name="excellencebadgetype",
            name="name_en",
            field=models.CharField(blank=True, default="", max_length=120),
        ),
        migrations.AddField(
            model_name="excellencebadgetype",
            name="description_en",
            field=models.CharField(blank=True, default="", max_length=255),
        ),
        migrations.RunPython(populate_badge_translations, migrations.RunPython.noop),
    ]