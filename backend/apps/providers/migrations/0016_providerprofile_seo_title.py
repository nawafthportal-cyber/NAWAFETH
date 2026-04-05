from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("providers", "0015_providerprofile_excellence_badges_cache"),
    ]

    operations = [
        migrations.AddField(
            model_name="providerprofile",
            name="seo_title",
            field=models.CharField(blank=True, default="", max_length=160),
        ),
    ]