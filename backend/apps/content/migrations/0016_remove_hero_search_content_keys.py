"""Remove home_hero_title, home_hero_subtitle, home_search_placeholder content blocks."""

from django.db import migrations


def deactivate_hero_blocks(apps, schema_editor):
    SiteContentBlock = apps.get_model("content", "SiteContentBlock")
    SiteContentBlock.objects.filter(
        key__in=[
            "home_hero_title",
            "home_hero_subtitle",
            "home_search_placeholder",
        ]
    ).delete()


def noop(apps, schema_editor):
    pass


class Migration(migrations.Migration):
    dependencies = [
        ("content", "0015_seed_about_terms_contact_defaults"),
    ]

    operations = [
        migrations.RunPython(deactivate_hero_blocks, noop),
    ]
