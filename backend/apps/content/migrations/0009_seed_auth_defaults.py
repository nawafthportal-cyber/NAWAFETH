from django.db import migrations


def seed_auth_blocks(apps, schema_editor):
    SiteContentBlock = apps.get_model("content", "SiteContentBlock")

    defaults = {
        "login_title": {
            "title_ar": "تسجيل الدخول",
            "body_ar": "",
            "is_active": True,
        },
        "login_description": {
            "title_ar": "أدخل رقم الجوال وسنرسل لك رمز تحقق لإكمال الدخول بأمان.",
            "body_ar": "",
            "is_active": True,
        },
        "login_phone_hint": {
            "title_ar": "الصيغة المعتمدة: 05XXXXXXXX",
            "body_ar": "",
            "is_active": True,
        },
        "login_submit_label": {
            "title_ar": "إرسال رمز التحقق",
            "body_ar": "",
            "is_active": True,
        },
        "login_guest_label": {
            "title_ar": "المتابعة كضيف",
            "body_ar": "",
            "is_active": True,
        },
        "signup_title": {
            "title_ar": "إكمال التسجيل",
            "body_ar": "",
            "is_active": True,
        },
        "signup_description": {
            "title_ar": "أكمل بياناتك مرة واحدة لتفعيل الحساب والانتقال مباشرة إلى المنصة.",
            "body_ar": "",
            "is_active": True,
        },
        "signup_submit_label": {
            "title_ar": "إكمال التسجيل",
            "body_ar": "",
            "is_active": True,
        },
        "signup_terms_label": {
            "title_ar": "أوافق على الشروط والأحكام",
            "body_ar": "",
            "is_active": True,
        },
    }

    for key, payload in defaults.items():
        SiteContentBlock.objects.get_or_create(key=key, defaults=payload)


def noop_reverse(apps, schema_editor):
    pass


class Migration(migrations.Migration):

    dependencies = [
        ("content", "0008_add_auth_content_keys"),
    ]

    operations = [
        migrations.RunPython(seed_auth_blocks, noop_reverse),
    ]
