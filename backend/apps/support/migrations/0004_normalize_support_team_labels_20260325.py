from django.db import migrations


def normalize_support_team_labels(apps, schema_editor):
    SupportTeam = apps.get_model("support", "SupportTeam")
    SupportTicket = apps.get_model("support", "SupportTicket")

    canonical_teams = [
        ("support", "فريق الدعم والمساعدة", 10),
        ("content", "فريق إدارة المحتوى", 20),
        ("promo", "فريق إدارة الإعلانات والترويج", 30),
        ("verification", "فريق التوثيق", 40),
        ("finance", "فريق إدارة الترقية والاشتراكات", 50),
        ("extras", "فريق إدارة الخدمات الإضافية", 60),
    ]

    for code, name_ar, sort_order in canonical_teams:
        team, _ = SupportTeam.objects.get_or_create(
            code=code,
            defaults={
                "name_ar": name_ar,
                "sort_order": sort_order,
                "is_active": True,
            },
        )

        update_fields = []
        if team.name_ar != name_ar:
            team.name_ar = name_ar
            update_fields.append("name_ar")
        if team.sort_order != sort_order:
            team.sort_order = sort_order
            update_fields.append("sort_order")
        if not team.is_active:
            team.is_active = True
            update_fields.append("is_active")

        if update_fields:
            team.save(update_fields=update_fields)

    # Migrate legacy "technical" assignments to the canonical support team,
    # then disable legacy row so API /teams does not show duplicate support labels.
    support_team = SupportTeam.objects.filter(code="support").first()
    technical_team = SupportTeam.objects.filter(code="technical").first()
    if support_team and technical_team:
        SupportTicket.objects.filter(assigned_team_id=technical_team.id).update(assigned_team_id=support_team.id)
        changed = []
        if technical_team.name_ar != "فريق الدعم والمساعدة":
            technical_team.name_ar = "فريق الدعم والمساعدة"
            changed.append("name_ar")
        if technical_team.is_active:
            technical_team.is_active = False
            changed.append("is_active")
        if changed:
            technical_team.save(update_fields=changed)


def noop_reverse(apps, schema_editor):
    # Keep normalized labels on rollback.
    pass


class Migration(migrations.Migration):

    dependencies = [
        ("support", "0003_seed_default_support_teams"),
    ]

    operations = [
        migrations.RunPython(normalize_support_team_labels, noop_reverse),
    ]
