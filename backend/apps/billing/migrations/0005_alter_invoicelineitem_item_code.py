from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("billing", "0004_invoice_payment_trust_and_webhook_idempotency"),
    ]

    operations = [
        migrations.AlterField(
            model_name="invoicelineitem",
            name="item_code",
            field=models.CharField(blank=True, default="", max_length=50),
        ),
    ]