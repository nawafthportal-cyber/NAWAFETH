from django.db import migrations


def seed_twofa_blocks(apps, schema_editor):
    SiteContentBlock = apps.get_model("content", "SiteContentBlock")

    defaults = {
        "twofa_title": {
            "title_ar": "التحقق من الرمز",
            "body_ar": "",
            "is_active": True,
        },
        "twofa_description": {
            "title_ar": "أدخل رمز التحقق المكوّن من 4 أرقام الذي تم إرساله إلى رقم الجوال.",
            "body_ar": "",
            "is_active": True,
        },
        "twofa_submit_label": {
            "title_ar": "تأكيد الرمز",
            "body_ar": "",
            "is_active": True,
        },
        "twofa_resend_label": {
            "title_ar": "إعادة الإرسال",
            "body_ar": "",
            "is_active": True,
        },
        "twofa_change_phone_label": {
            "title_ar": "تغيير رقم الجوال",
            "body_ar": "",
            "is_active": True,
        },
        "twofa_success_resend_label": {
            "title_ar": "تم إرسال رمز جديد",
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
        ("content", "0010_add_twofa_content_keys"),
    ]

    operations = [
        migrations.RunPython(seed_twofa_blocks, noop_reverse),
    ]
