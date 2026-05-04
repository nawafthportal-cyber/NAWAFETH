from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("providers", "0025_providercategory_requires_geo_scope"),
    ]

    operations = [
        migrations.AlterField(
            model_name="providerportfolioitem",
            name="file_type",
            field=models.CharField(
                choices=[("image", "صورة"), ("video", "فيديو"), ("document", "ملف PDF")],
                max_length=20,
            ),
        ),
    ]