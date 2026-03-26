from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("reviews", "0005_review_management_reply_review_management_reply_at_and_more"),
    ]

    operations = [
        migrations.AddField(
            model_name="review",
            name="provider_liked",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="review",
            name="provider_liked_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
