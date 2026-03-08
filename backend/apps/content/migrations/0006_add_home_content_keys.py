from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("content", "0005_seed_onboarding_defaults"),
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
                    ("home_hero_title", "الرئيسية - عنوان الهيرو"),
                    ("home_hero_subtitle", "الرئيسية - الوصف المختصر"),
                    ("home_search_placeholder", "الرئيسية - نص البحث"),
                    ("home_categories_title", "الرئيسية - عنوان التصنيفات"),
                    ("home_providers_title", "الرئيسية - عنوان مزودي الخدمة"),
                    ("home_banners_title", "الرئيسية - عنوان العروض الترويجية"),
                    ("settings_help", "معلومات المساعدة"),
                    ("settings_info", "معلومات الإعدادات"),
                ],
                max_length=80,
                unique=True,
            ),
        ),
    ]
