from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("reviews", "0002_review_cost_value_review_credibility_review_on_time_and_more"),
    ]

    operations = [
        migrations.AddField(
            model_name="review",
            name="provider_reply",
            field=models.CharField(blank=True, max_length=500),
        ),
        migrations.AddField(
            model_name="review",
            name="provider_reply_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
