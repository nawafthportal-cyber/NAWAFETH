from django.db import migrations, models


def backfill_user_country_and_location(apps, schema_editor):
    User = apps.get_model("accounts", "User")
    default_country = "السعودية"
    for user in User.objects.all().iterator():
        city = str(getattr(user, "city", "") or "").strip()
        country = str(getattr(user, "country", "") or "").strip()
        changed = []

        if city and " - " not in city:
            user.city = default_country + " - " + city
            changed.append("city")

        if not country and city:
            user.country = default_country
            changed.append("country")

        if changed:
            user.save(update_fields=changed)


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0011_user_last_seen"),
    ]

    operations = [
        migrations.AddField(
            model_name="user",
            name="country",
            field=models.CharField(blank=True, max_length=100, null=True),
        ),
        migrations.AddField(
            model_name="user",
            name="lat",
            field=models.DecimalField(blank=True, decimal_places=6, max_digits=9, null=True),
        ),
        migrations.AddField(
            model_name="user",
            name="lng",
            field=models.DecimalField(blank=True, decimal_places=6, max_digits=9, null=True),
        ),
        migrations.RunPython(backfill_user_country_and_location, migrations.RunPython.noop),
    ]