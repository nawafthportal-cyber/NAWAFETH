from django.db import migrations, models


def backfill_providercategory_accepts_urgent(apps, schema_editor):
    ProviderCategory = apps.get_model("providers", "ProviderCategory")
    ProviderProfile = apps.get_model("providers", "ProviderProfile")

    urgent_provider_ids = set(
        ProviderProfile.objects.filter(accepts_urgent=True).values_list("id", flat=True)
    )
    if not urgent_provider_ids:
        return

    ProviderCategory.objects.filter(provider_id__in=urgent_provider_ids).update(accepts_urgent=True)


class Migration(migrations.Migration):

    dependencies = [
        ("providers", "0016_providerprofile_seo_title"),
    ]

    operations = [
        migrations.AddField(
            model_name="providercategory",
            name="accepts_urgent",
            field=models.BooleanField(default=False),
        ),
        migrations.RunPython(
            backfill_providercategory_accepts_urgent,
            migrations.RunPython.noop,
        ),
    ]