"""
Phase 2: Seed the 8 core dashboards + admin_control permissions.
Uses update_or_create to safely merge with any existing records.
"""

from django.db import migrations


DASHBOARD_ROWS = [
    {"code": "admin_control", "name_ar": "إدارة الصلاحيات والتقارير", "sort_order": 1},
    {"code": "support", "name_ar": "الدعم والمساعدة", "sort_order": 10},
    {"code": "content", "name_ar": "إدارة المحتوى", "sort_order": 20},
    {"code": "promo", "name_ar": "الإعلانات والترويج", "sort_order": 30},
    {"code": "verify", "name_ar": "التوثيق", "sort_order": 40},
    {"code": "subs", "name_ar": "الاشتراكات والترقية", "sort_order": 50},
    {"code": "extras", "name_ar": "الخدمات الإضافية", "sort_order": 60},
    {"code": "client_extras", "name_ar": "بوابة العميل", "sort_order": 70},
]

# Dashboards that already exist in the DB and only need sort_order update
_EXISTING_DASHBOARD_CODES = {"support", "content", "promo", "verify", "subs", "extras"}

PERMISSION_ROWS = [
    {
        "code": "admin_control.manage_access",
        "name_ar": "إدارة ملفات صلاحيات المستخدمين",
        "dashboard_code": "admin_control",
        "description": "يتيح إدارة وتعديل ملفات صلاحيات المستخدمين.",
        "sort_order": 1,
    },
    {
        "code": "admin_control.view_audit",
        "name_ar": "عرض سجل التدقيق",
        "dashboard_code": "admin_control",
        "description": "يتيح تصفح وعرض سجل التدقيق.",
        "sort_order": 2,
    },
    {
        "code": "admin_control.view_reports",
        "name_ar": "عرض تقارير المنصة",
        "dashboard_code": "admin_control",
        "description": "يتيح الاطلاع على تقارير المنصة الإحصائية.",
        "sort_order": 3,
    },
]


def seed_forward(apps, schema_editor):
    Dashboard = apps.get_model("backoffice", "Dashboard")
    AccessPermission = apps.get_model("backoffice", "AccessPermission")
    UserAccessProfile = apps.get_model("backoffice", "UserAccessProfile")

    # 1. Seed / update dashboards
    for row in DASHBOARD_ROWS:
        Dashboard.objects.update_or_create(
            code=row["code"],
            defaults={"name_ar": row["name_ar"], "sort_order": row["sort_order"], "is_active": True},
        )

    # 2. Migrate "access" dashboard code → "admin_control" for existing UserAccessProfile
    access_dashboard = Dashboard.objects.filter(code="access").first()
    admin_control_dashboard = Dashboard.objects.filter(code="admin_control").first()
    if access_dashboard and admin_control_dashboard:
        for profile in UserAccessProfile.objects.filter(allowed_dashboards=access_dashboard):
            profile.allowed_dashboards.add(admin_control_dashboard)

    # 3. Seed new permissions
    permission_map = {}
    for row in PERMISSION_ROWS:
        perm, _ = AccessPermission.objects.get_or_create(
            code=row["code"],
            defaults={
                "name_ar": row["name_ar"],
                "dashboard_code": row["dashboard_code"],
                "description": row["description"],
                "sort_order": row["sort_order"],
                "is_active": True,
            },
        )
        permission_map[row["code"]] = perm

    # 4. Grant admin_control permissions to admin/power profiles
    for profile in UserAccessProfile.objects.filter(level__in=("admin", "power")):
        profile.granted_permissions.add(*permission_map.values())

    # 5. Grant admin_control permissions to user profiles that have admin_control access
    if admin_control_dashboard:
        for profile in UserAccessProfile.objects.filter(
            level="user", allowed_dashboards=admin_control_dashboard
        ):
            profile.granted_permissions.add(*permission_map.values())


def seed_reverse(apps, schema_editor):
    Dashboard = apps.get_model("backoffice", "Dashboard")
    AccessPermission = apps.get_model("backoffice", "AccessPermission")

    AccessPermission.objects.filter(
        code__in=[row["code"] for row in PERMISSION_ROWS]
    ).delete()
    Dashboard.objects.filter(code__in=["admin_control", "client_extras"]).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("backoffice", "0004_subscription_extras_permissions"),
    ]

    operations = [
        migrations.RunPython(seed_forward, seed_reverse),
    ]
