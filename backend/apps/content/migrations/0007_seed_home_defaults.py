from django.db import migrations


def seed_home_blocks(apps, schema_editor):
    SiteContentBlock = apps.get_model("content", "SiteContentBlock")

    defaults = {
        "home_hero_title": {
            "title_ar": "اعثر على الخدمة المناسبة",
            "body_ar": "",
            "is_active": True,
        },
        "home_hero_subtitle": {
            "title_ar": "مزودون موثّقون وخدمات مرتبة لتبدأ بشكل أسرع وأكثر وضوحًا.",
            "body_ar": "",
            "is_active": True,
        },
        "home_search_placeholder": {
            "title_ar": "ابحث عن خدمة أو مقدم خدمة...",
            "body_ar": "",
            "is_active": True,
        },
        "home_categories_title": {
            "title_ar": "التصنيفات",
            "body_ar": "",
            "is_active": True,
        },
        "home_providers_title": {
            "title_ar": "مقدمو الخدمة",
            "body_ar": "",
            "is_active": True,
        },
        "home_banners_title": {
            "title_ar": "عروض ترويجية",
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
        ("content", "0006_add_home_content_keys"),
    ]

    operations = [
        migrations.RunPython(seed_home_blocks, noop_reverse),
    ]
