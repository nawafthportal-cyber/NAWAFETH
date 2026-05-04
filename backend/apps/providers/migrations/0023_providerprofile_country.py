from django.db import migrations, models


def backfill_provider_country_and_location(apps, schema_editor):
    ProviderProfile = apps.get_model("providers", "ProviderProfile")
    default_country = "السعودية"
    for profile in ProviderProfile.objects.all().iterator():
        city = str(getattr(profile, "city", "") or "").strip()
        country = str(getattr(profile, "country", "") or "").strip()
        changed = []

        if city and " - " not in city:
            profile.city = default_country + " - " + city
            changed.append("city")

        if not country and city:
            profile.country = default_country
            changed.append("country")

        if str(getattr(profile, "region", "") or "").strip():
            profile.region = ""
            changed.append("region")

        if changed:
            profile.save(update_fields=changed)


class Migration(migrations.Migration):

    dependencies = [
        ("providers", "0022_providercontentcomment_parent"),
    ]

    operations = [
        migrations.AddField(
            model_name="providerprofile",
            name="country",
            field=models.CharField(blank=True, default="", max_length=100),
        ),
        migrations.RunPython(backfill_provider_country_and_location, migrations.RunPython.noop),
    ]