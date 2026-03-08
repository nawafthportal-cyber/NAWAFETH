from django.db import migrations


def seed_onboarding_blocks(apps, schema_editor):
    SiteContentBlock = apps.get_model("content", "SiteContentBlock")

    defaults = {
        "onboarding_first_time": {
            "title_ar": "مرحبًا بك في نوافذ",
            "body_ar": (
                "منصة موحدة لاكتشاف الخدمات باحترافية أعلى، مع تجربة أوضح في الطلب، "
                "المتابعة، والتواصل منذ اللحظة الأولى."
            ),
            "is_active": True,
        },
        "onboarding_intro": {
            "title_ar": "للعملاء ومقدمي الخدمات",
            "body_ar": (
                "ابحث، قارن، وابدأ الطلب بثقة. وإذا كنت مقدم خدمة، اعرض خبرتك "
                "بطريقة منظمة واحترافية أمام العملاء المناسبين."
            ),
            "is_active": True,
        },
        "onboarding_get_started": {
            "title_ar": "ابدأ الآن",
            "body_ar": (
                "كل ما تراه هنا قابل للإدارة من لوحة التحكم. حدّث الرسائل والوسائط "
                "مباشرة من الداشبورد لتبقى تجربة البداية متزامنة بين التطبيق والويب."
            ),
            "is_active": True,
        },
    }

    for key, payload in defaults.items():
        SiteContentBlock.objects.get_or_create(
            key=key,
            defaults=payload,
        )


def noop_reverse(apps, schema_editor):
    pass


class Migration(migrations.Migration):

    dependencies = [
        ("content", "0004_add_onboarding_get_started_key"),
    ]

    operations = [
        migrations.RunPython(seed_onboarding_blocks, noop_reverse),
    ]
