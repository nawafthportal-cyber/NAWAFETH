from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0007_rename_accounts_otp_phone_created_at_idx_accounts_ot_phone_463bcb_idx_and_more"),
    ]

    operations = [
        migrations.AddField(
            model_name="user",
            name="city",
            field=models.CharField(blank=True, max_length=100, null=True),
        ),
    ]
