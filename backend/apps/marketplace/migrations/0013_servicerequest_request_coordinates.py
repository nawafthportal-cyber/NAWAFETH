from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("marketplace", "0012_rename_marketplace__dispatc_0fd4b8_idx_marketplace_dispatc_7ea5ec_idx_and_more"),
    ]

    operations = [
        migrations.AddField(
            model_name="servicerequest",
            name="request_lat",
            field=models.DecimalField(blank=True, decimal_places=6, max_digits=9, null=True),
        ),
        migrations.AddField(
            model_name="servicerequest",
            name="request_lng",
            field=models.DecimalField(blank=True, decimal_places=6, max_digits=9, null=True),
        ),
    ]