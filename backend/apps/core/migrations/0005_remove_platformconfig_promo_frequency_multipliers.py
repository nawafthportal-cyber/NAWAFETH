from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ("core", "0004_add_extras_vat_percent"),
    ]

    operations = [
        migrations.RemoveField(
            model_name="platformconfig",
            name="promo_frequency_multipliers",
        ),
    ]
