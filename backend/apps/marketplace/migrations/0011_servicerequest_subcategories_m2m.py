from django.db import migrations, models


def backfill_subcategories_from_legacy_fk(apps, schema_editor):
    ServiceRequest = apps.get_model("marketplace", "ServiceRequest")
    through_model = ServiceRequest.subcategories.through

    for request_id, subcategory_id in ServiceRequest.objects.values_list("id", "subcategory_id"):
        if not subcategory_id:
            continue
        through_model.objects.get_or_create(
            servicerequest_id=request_id,
            subcategory_id=subcategory_id,
        )


def noop_reverse(apps, schema_editor):
    # Keep backward-compatible data when rolling back migration code.
    pass


class Migration(migrations.Migration):

    dependencies = [
        ("marketplace", "0010_dispatch_windows_and_mode"),
    ]

    operations = [
        migrations.AddField(
            model_name="servicerequest",
            name="subcategories",
            field=models.ManyToManyField(
                blank=True,
                related_name="service_requests_multi",
                to="providers.subcategory",
            ),
        ),
        migrations.RunPython(backfill_subcategories_from_legacy_fk, noop_reverse),
    ]
