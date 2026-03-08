from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("content", "0007_seed_home_defaults"),
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
                    ("login_title", "الدخول - العنوان"),
                    ("login_description", "الدخول - الوصف"),
                    ("login_phone_hint", "الدخول - تلميح الجوال"),
                    ("login_submit_label", "الدخول - زر الإرسال"),
                    ("login_guest_label", "الدخول - زر الزائر"),
                    ("signup_title", "التسجيل - العنوان"),
                    ("signup_description", "التسجيل - الوصف"),
                    ("signup_submit_label", "التسجيل - زر الإكمال"),
                    ("signup_terms_label", "التسجيل - نص الشروط"),
                    ("settings_help", "معلومات المساعدة"),
                    ("settings_info", "معلومات الإعدادات"),
                ],
                max_length=80,
                unique=True,
            ),
        ),
    ]
