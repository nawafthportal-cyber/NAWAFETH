from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("providers", "0024_providerportfoliovisibilityblock"),
    ]

    operations = [
        migrations.AddField(
            model_name="providercategory",
            name="requires_geo_scope",
            field=models.BooleanField(default=True),
        ),
    ]