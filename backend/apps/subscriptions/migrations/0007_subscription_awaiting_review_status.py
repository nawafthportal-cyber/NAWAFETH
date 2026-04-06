from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("subscriptions", "0006_backfill_plan_configuration_from_canonical_rows"),
    ]

    operations = [
        migrations.AlterField(
            model_name="subscription",
            name="status",
            field=models.CharField(
                choices=[
                    ("pending_payment", "بانتظار الدفع"),
                    ("awaiting_review", "بانتظار المراجعة"),
                    ("active", "نشط"),
                    ("grace", "فترة سماح"),
                    ("expired", "منتهي"),
                    ("cancelled", "ملغي"),
                ],
                default="pending_payment",
                max_length=20,
            ),
        ),
    ]