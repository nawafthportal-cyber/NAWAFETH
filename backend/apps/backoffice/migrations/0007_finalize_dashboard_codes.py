from __future__ import annotations

from django.db import migrations


DASHBOARD_ROWS = [
    {"code": "support", "name_ar": "الدعم والمساعدة", "sort_order": 10},
    {"code": "content", "name_ar": "إدارة المحتوى", "sort_order": 20},
    {"code": "moderation", "name_ar": "الإشراف", "sort_order": 25},
    {"code": "reviews", "name_ar": "المراجعات", "sort_order": 27},
    {"code": "promo", "name_ar": "الترويج", "sort_order": 30},
    {"code": "verify", "name_ar": "التوثيق", "sort_order": 40},
    {"code": "subs", "name_ar": "الاشتراكات", "sort_order": 50},
    {"code": "extras", "name_ar": "الخدمات الإضافية", "sort_order": 60},
    {"code": "analytics", "name_ar": "التحليلات", "sort_order": 70},
    {"code": "admin_control", "name_ar": "الإدارة", "sort_order": 80},
    {"code": "client_extras", "name_ar": "بوابة العميل", "sort_order": 90},
]


def forward(apps, schema_editor):
    Dashboard = apps.get_model("backoffice", "Dashboard")
    UserAccessProfile = apps.get_model("backoffice", "UserAccessProfile")

    for row in DASHBOARD_ROWS:
        Dashboard.objects.update_or_create(
            code=row["code"],
            defaults={
                "name_ar": row["name_ar"],
                "sort_order": row["sort_order"],
                "is_active": True,
            },
        )

    admin_control = Dashboard.objects.filter(code="admin_control").first()
    if not admin_control:
        return

    for legacy_code in ("access", "admin"):
        legacy_dashboard = Dashboard.objects.filter(code=legacy_code).first()
        if not legacy_dashboard:
            continue
        for profile in UserAccessProfile.objects.filter(allowed_dashboards=legacy_dashboard):
            profile.allowed_dashboards.add(admin_control)
        legacy_dashboard.delete()


def backward(apps, schema_editor):
    # One-way normalization migration.
    pass


class Migration(migrations.Migration):
    dependencies = [
        ("backoffice", "0006_seed_content_manage_permission"),
    ]

    operations = [
        migrations.RunPython(forward, backward),
    ]
