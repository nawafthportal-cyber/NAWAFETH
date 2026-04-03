from django.db import migrations, models


def seed_branding_blocks(apps, schema_editor):
    SiteContentBlock = apps.get_model("content", "SiteContentBlock")

    defaults = {
        "home_banners_fallback": {
            "title_ar": "البنر الافتراضي",
            "body_ar": "يظهر هذا البنر عند عدم وجود إعلانات فعالة.",
            "is_active": True,
        },
        "topbar_brand_logo": {
            "title_ar": "شعار المنصة في الشريط العلوي",
            "body_ar": "ارفع شعار المنصة ليظهر بدل الشعار الافتراضي في الشريط العلوي.",
            "is_active": True,
        },
    }

    for key, payload in defaults.items():
        SiteContentBlock.objects.get_or_create(key=key, defaults=payload)


def noop_reverse(apps, schema_editor):
    pass


class Migration(migrations.Migration):

    dependencies = [
        ("content", "0017_remove_hero_search_choices"),
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
                    ("home_categories_title", "الرئيسية - عنوان التصنيفات"),
                    ("home_providers_title", "الرئيسية - عنوان مزودي الخدمة"),
                    ("home_banners_title", "الرئيسية - عنوان العروض الترويجية"),
                    ("home_banners_fallback", "الرئيسية - البنر الافتراضي"),
                    ("topbar_brand_logo", "الشريط العلوي - شعار المنصة"),
                    ("login_title", "الدخول - العنوان"),
                    ("login_description", "الدخول - الوصف"),
                    ("login_phone_hint", "الدخول - تلميح الجوال"),
                    ("login_submit_label", "الدخول - زر الإرسال"),
                    ("login_guest_label", "الدخول - زر الزائر"),
                    ("signup_title", "التسجيل - العنوان"),
                    ("signup_description", "التسجيل - الوصف"),
                    ("signup_submit_label", "التسجيل - زر الإكمال"),
                    ("signup_terms_label", "التسجيل - نص الشروط"),
                    ("twofa_title", "التحقق - العنوان"),
                    ("twofa_description", "التحقق - الوصف"),
                    ("twofa_submit_label", "التحقق - زر التأكيد"),
                    ("twofa_resend_label", "التحقق - إعادة الإرسال"),
                    ("twofa_change_phone_label", "التحقق - تغيير الجوال"),
                    ("twofa_success_resend_label", "التحقق - نجاح إعادة الإرسال"),
                    ("twofa_phone_notice", "التحقق - تم إرسال الرمز إلى"),
                    ("twofa_resend_prompt", "التحقق - لم يصلك الرمز"),
                    ("about_hero_title", "من نحن - عنوان الهيرو"),
                    ("about_hero_subtitle", "من نحن - الوصف المختصر"),
                    ("about_section_about", "من نحن - قسم من نحن"),
                    ("about_section_vision", "من نحن - قسم الرؤية"),
                    ("about_section_goals", "من نحن - قسم الأهداف"),
                    ("about_section_values", "من نحن - قسم القيم"),
                    ("about_section_app", "من نحن - قسم التطبيق"),
                    ("about_social_title", "من نحن - عنوان التواصل"),
                    ("about_website_label", "من نحن - زر الموقع الرسمي"),
                    ("terms_page_title", "الشروط - عنوان الصفحة"),
                    ("terms_empty_label", "الشروط - حالة الفراغ"),
                    ("terms_open_document_label", "الشروط - زر فتح المستند"),
                    ("terms_file_only_hint", "الشروط - تلميح المستند المرفق"),
                    ("terms_missing_document_hint", "الشروط - تلميح غياب المستند"),
                    ("contact_gate_title", "التواصل - عنوان بوابة الدخول"),
                    ("contact_gate_description", "التواصل - وصف بوابة الدخول"),
                    ("contact_gate_login_label", "التواصل - زر تسجيل الدخول"),
                    ("contact_page_title", "التواصل - عنوان الصفحة"),
                    ("contact_refresh_label", "التواصل - زر التحديث"),
                    ("contact_new_ticket_label", "التواصل - زر بلاغ جديد"),
                    ("contact_list_title", "التواصل - عنوان قائمة البلاغات"),
                    ("contact_create_title", "التواصل - عنوان إنشاء البلاغ"),
                    ("contact_detail_title", "التواصل - عنوان تفاصيل البلاغ"),
                    ("contact_empty_label", "التواصل - حالة فراغ البلاغات"),
                    ("contact_team_placeholder", "التواصل - اختيار فريق الدعم"),
                    ("contact_description_label", "التواصل - حقل التفاصيل"),
                    ("contact_attachments_label", "التواصل - حقل المرفقات"),
                    ("contact_cancel_label", "التواصل - زر الإلغاء"),
                    ("contact_submit_label", "التواصل - زر إرسال البلاغ"),
                    ("contact_reply_placeholder", "التواصل - حقل التعليق"),
                    ("contact_reply_submit_label", "التواصل - زر إرسال التعليق"),
                    ("settings_help", "معلومات المساعدة"),
                    ("settings_info", "معلومات الإعدادات"),
                ],
                max_length=80,
                unique=True,
            ),
        ),
        migrations.RunPython(seed_branding_blocks, noop_reverse),
    ]
