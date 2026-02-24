from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("reviews", "0003_review_provider_reply"),
    ]

    operations = [
        migrations.AddField(
            model_name="review",
            name="provider_reply_edited_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]

