from django.db import migrations


def seed_excellence_dashboard(apps, schema_editor):
    Dashboard = apps.get_model("backoffice", "Dashboard")
    Dashboard.objects.update_or_create(
        code="excellence",
        defaults={
            "name_ar": "إدارة التميز للمختصين",
            "is_active": True,
            "sort_order": 45,
        },
    )


class Migration(migrations.Migration):

    dependencies = [
        ("backoffice", "0001_initial"),
        ("excellence", "0001_initial"),
    ]

    operations = [
        migrations.RunPython(seed_excellence_dashboard, migrations.RunPython.noop),
    ]