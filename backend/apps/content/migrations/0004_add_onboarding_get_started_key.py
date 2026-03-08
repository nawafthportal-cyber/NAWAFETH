from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("content", "0003_sitecontentblock_media_file"),
    ]

    operations = [
        migrations.AlterField(
            model_name="sitecontentblock",
            name="key",
            field=models.CharField(
                choices=[
                    ("onboarding_first_time", "الدخول أول مرة"),
                    ("onboarding_intro", "صفحة التعريف"),
                    ("onboarding_get_started", "صفحة الانطلاق"),
                    ("settings_help", "معلومات المساعدة"),
                    ("settings_info", "معلومات الإعدادات"),
                ],
                max_length=80,
                unique=True,
            ),
        ),
    ]
