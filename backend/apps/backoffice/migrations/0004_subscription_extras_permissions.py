from django.db import migrations


PERMISSION_ROWS = [
    {
        "code": "subscriptions.manage",
        "name_ar": "إدارة تشغيل الاشتراكات",
        "dashboard_code": "subs",
        "description": "يتيح إسناد ومعالجة وتفعيل طلبات وحسابات الاشتراكات داخل التشغيل الداخلي.",
        "sort_order": 85,
    },
    {
        "code": "extras.manage",
        "name_ar": "إدارة تشغيل الخدمات الإضافية",
        "dashboard_code": "extras",
        "description": "يتيح إسناد ومعالجة وتفعيل الخدمات الإضافية داخل التشغيل الداخلي.",
        "sort_order": 86,
    },
]


def seed_permissions(apps, schema_editor):
    AccessPermission = apps.get_model("backoffice", "AccessPermission")
    UserAccessProfile = apps.get_model("backoffice", "UserAccessProfile")

    permissions = {}
    for row in PERMISSION_ROWS:
        permission, _ = AccessPermission.objects.get_or_create(
            code=row["code"],
            defaults={
                "name_ar": row["name_ar"],
                "dashboard_code": row["dashboard_code"],
                "description": row["description"],
                "sort_order": row["sort_order"],
                "is_active": True,
            },
        )
        permissions[row["code"]] = permission

    for profile in UserAccessProfile.objects.filter(level__in=("admin", "power", "user")):
        if profile.level in {"admin", "power"}:
            profile.granted_permissions.add(*permissions.values())
            continue
        allowed = set(profile.allowed_dashboards.values_list("code", flat=True))
        if "subs" in allowed:
            profile.granted_permissions.add(permissions["subscriptions.manage"])
        if "extras" in allowed:
            profile.granted_permissions.add(permissions["extras.manage"])


def unseed_permissions(apps, schema_editor):
    AccessPermission = apps.get_model("backoffice", "AccessPermission")
    AccessPermission.objects.filter(code__in=[row["code"] for row in PERMISSION_ROWS]).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("backoffice", "0003_reviews_moderate_permission"),
    ]

    operations = [
        migrations.RunPython(seed_permissions, unseed_permissions),
    ]
