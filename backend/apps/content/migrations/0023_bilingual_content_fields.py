from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("content", "0022_platformlogoblock"),
    ]

    operations = [
        migrations.AddField(
            model_name="sitecontentblock",
            name="title_en",
            field=models.CharField(blank=True, default="", max_length=255),
        ),
        migrations.AddField(
            model_name="sitecontentblock",
            name="body_en",
            field=models.TextField(blank=True, default=""),
        ),
        migrations.AddField(
            model_name="sitelegaldocument",
            name="body_en",
            field=models.TextField(blank=True, default=""),
        ),
    ]