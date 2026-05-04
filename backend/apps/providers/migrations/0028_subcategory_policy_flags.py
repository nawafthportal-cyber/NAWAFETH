from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("providers", "0027_providercoverimage"),
    ]

    operations = [
        migrations.AddField(
            model_name="subcategory",
            name="allows_urgent_requests",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="subcategory",
            name="requires_geo_scope",
            field=models.BooleanField(default=True),
        ),
    ]