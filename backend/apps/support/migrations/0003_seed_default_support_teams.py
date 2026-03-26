from django.db import migrations


def seed_default_support_teams(apps, schema_editor):
    SupportTeam = apps.get_model("support", "SupportTeam")

    required_teams = [
        ("support", "فريق الدعم والمساعدة", 10),
        ("content", "فريق إدارة المحتوى", 20),
        ("promo", "فريق إدارة الإعلانات والترويج", 30),
        ("verification", "فريق التوثيق", 40),
        ("finance", "فريق إدارة الترقية والاشتراكات", 50),
        ("extras", "فريق إدارة الخدمات الإضافية", 60),
    ]

    for code, name_ar, sort_order in required_teams:
        obj, _ = SupportTeam.objects.get_or_create(
            code=code,
            defaults={
                "name_ar": name_ar,
                "sort_order": sort_order,
                "is_active": True,
            },
        )

        update_fields = []
        if obj.name_ar != name_ar:
            obj.name_ar = name_ar
            update_fields.append("name_ar")
        if obj.sort_order != sort_order:
            obj.sort_order = sort_order
            update_fields.append("sort_order")
        if not obj.is_active:
            obj.is_active = True
            update_fields.append("is_active")

        if update_fields:
            obj.save(update_fields=update_fields)


def noop_reverse(apps, schema_editor):
    # Preserve existing data on rollback.
    pass


class Migration(migrations.Migration):

    dependencies = [
        ("support", "0002_supportticket_reported_target_fields"),
    ]

    operations = [
        migrations.RunPython(seed_default_support_teams, noop_reverse),
    ]
