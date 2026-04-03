from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("verification", "0007_verificationblueprofile"),
    ]

    operations = [
        migrations.AddField(
            model_name="verificationrequirement",
            name="evidence_expires_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
