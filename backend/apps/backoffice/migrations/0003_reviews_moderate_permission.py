from django.db import migrations


def seed_reviews_permission(apps, schema_editor):
    AccessPermission = apps.get_model("backoffice", "AccessPermission")
    UserAccessProfile = apps.get_model("backoffice", "UserAccessProfile")

    permission, _ = AccessPermission.objects.get_or_create(
        code="reviews.moderate",
        defaults={
            "name_ar": "إدارة مراجعات العملاء",
            "dashboard_code": "content",
            "description": "يتيح اعتماد/إخفاء/رفض المراجعات داخل لوحة المحتوى.",
            "sort_order": 35,
            "is_active": True,
        },
    )

    for profile in UserAccessProfile.objects.filter(level="user"):
        allowed = set(profile.allowed_dashboards.values_list("code", flat=True))
        if "content" in allowed:
            profile.granted_permissions.add(permission)


def unseed_reviews_permission(apps, schema_editor):
    AccessPermission = apps.get_model("backoffice", "AccessPermission")
    AccessPermission.objects.filter(code="reviews.moderate").delete()


class Migration(migrations.Migration):
    dependencies = [
        ("backoffice", "0002_accesspermission_and_more"),
    ]

    operations = [
        migrations.RunPython(seed_reviews_permission, unseed_reviews_permission),
    ]
