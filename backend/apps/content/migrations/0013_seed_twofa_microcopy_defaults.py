from django.db import migrations


def seed_twofa_microcopy_blocks(apps, schema_editor):
    SiteContentBlock = apps.get_model("content", "SiteContentBlock")

    defaults = {
        "twofa_phone_notice": {
            "title_ar": "تم إرسال الرمز إلى",
            "body_ar": "",
            "is_active": True,
        },
        "twofa_resend_prompt": {
            "title_ar": "لم يصلك الرمز؟",
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
        ("content", "0012_add_twofa_microcopy_keys"),
    ]

    operations = [
        migrations.RunPython(seed_twofa_microcopy_blocks, noop_reverse),
    ]
