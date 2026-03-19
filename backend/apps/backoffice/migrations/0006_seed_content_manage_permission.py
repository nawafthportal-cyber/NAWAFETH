"""
Phase 4B: Seed the content.manage permission for content panel hardening.
"""

from django.db import migrations


PERMISSION_ROWS = [
    {
        "code": "content.manage",
        "name_ar": "إدارة محتوى المنصة",
        "dashboard_code": "content",
        "description": "يتيح تعديل البلوكات والمستندات القانونية وروابط المنصة.",
        "sort_order": 20,
    },
]


def seed_forward(apps, schema_editor):
    AccessPermission = apps.get_model("backoffice", "AccessPermission")
    for row in PERMISSION_ROWS:
        AccessPermission.objects.get_or_create(
            code=row["code"],
            defaults={
                "name_ar": row["name_ar"],
                "dashboard_code": row["dashboard_code"],
                "description": row["description"],
                "sort_order": row["sort_order"],
                "is_active": True,
            },
        )


def seed_reverse(apps, schema_editor):
    AccessPermission = apps.get_model("backoffice", "AccessPermission")
    AccessPermission.objects.filter(code__in=[r["code"] for r in PERMISSION_ROWS]).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("backoffice", "0005_seed_phase2_dashboards_permissions"),
    ]

    operations = [
        migrations.RunPython(seed_forward, seed_reverse),
    ]
