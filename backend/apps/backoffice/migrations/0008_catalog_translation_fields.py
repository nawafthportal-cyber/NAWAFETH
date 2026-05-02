from django.db import migrations, models


DASHBOARD_NAME_EN = {
    "admin_control": "Access Management & Reports",
    "support": "Support & Help",
    "content": "Content Management",
    "moderation": "Moderation",
    "reviews": "Reviews",
    "promo": "Promotions",
    "verify": "Verification",
    "subs": "Subscriptions",
    "extras": "Additional Services",
    "analytics": "Analytics",
    "client_extras": "Client Portal",
}

PERMISSION_TRANSLATIONS = {
    "admin_control.manage_access": ("Manage User Access Profiles", "Allows managing and updating user access profiles."),
    "admin_control.view_audit": ("View Audit Log", "Allows browsing and viewing the audit log."),
    "admin_control.view_reports": ("View Platform Reports", "Allows viewing platform analytics reports."),
    "moderation.assign": ("Assign Moderation Cases", "Allows assigning moderation center cases."),
    "moderation.resolve": ("Resolve Moderation Cases", "Allows changing case status and recording the final decision."),
    "content.manage": ("Manage Platform Content", "Allows editing content blocks, legal documents, and platform links."),
    "content.hide_delete": ("Hide/Delete Content", "Sensitive action on public content."),
    "reviews.moderate": ("Manage Client Reviews", "Allows approving, hiding, or rejecting reviews in the content dashboard."),
    "support.assign": ("Assign Support Tickets", "Allows assigning support tickets to operators."),
    "support.resolve": ("Resolve Support Tickets", "Allows updating ticket status to resolved or closed."),
    "promo.quote_activate": ("Price/Activate Promotions", "Allows pricing campaigns or activating them."),
    "verification.finalize": ("Finalize Verification", "Allows finalizing verification requests."),
    "analytics.export": ("Export Reports", "Allows exporting analytics data and reports."),
    "subscriptions.manage": ("Manage Subscription Operations", "Allows assigning, processing, and activating subscription requests and accounts in backoffice operations."),
    "extras.manage": ("Manage Additional Services Operations", "Allows assigning, processing, and activating additional services in backoffice operations."),
}


def populate_catalog_translations(apps, schema_editor):
    Dashboard = apps.get_model("backoffice", "Dashboard")
    AccessPermission = apps.get_model("backoffice", "AccessPermission")

    for dashboard in Dashboard.objects.all().only("id", "code", "name_en"):
        name_en = DASHBOARD_NAME_EN.get((dashboard.code or "").strip().lower(), "")
        if name_en and dashboard.name_en != name_en:
            dashboard.name_en = name_en
            dashboard.save(update_fields=["name_en"])

    for permission in AccessPermission.objects.all().only("id", "code", "name_en", "description_en"):
        translation = PERMISSION_TRANSLATIONS.get((permission.code or "").strip().lower())
        if not translation:
            continue
        name_en, description_en = translation
        updated_fields = []
        if permission.name_en != name_en:
            permission.name_en = name_en
            updated_fields.append("name_en")
        if permission.description_en != description_en:
            permission.description_en = description_en
            updated_fields.append("description_en")
        if updated_fields:
            permission.save(update_fields=updated_fields)


class Migration(migrations.Migration):
    dependencies = [
        ("backoffice", "0007_finalize_dashboard_codes"),
    ]

    operations = [
        migrations.AddField(
            model_name="dashboard",
            name="name_en",
            field=models.CharField(blank=True, default="", max_length=120),
        ),
        migrations.AddField(
            model_name="accesspermission",
            name="name_en",
            field=models.CharField(blank=True, default="", max_length=120),
        ),
        migrations.AddField(
            model_name="accesspermission",
            name="description_en",
            field=models.CharField(blank=True, default="", max_length=255),
        ),
        migrations.RunPython(populate_catalog_translations, migrations.RunPython.noop),
    ]