from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("promo", "0005_promopricingrule_promorequest_ops_completed_at_and_more"),
    ]

    operations = [
        migrations.AddField(
            model_name="promorequestitem",
            name="message_dispatch_error",
            field=models.CharField(blank=True, default="", max_length=255),
        ),
        migrations.AddField(
            model_name="promorequestitem",
            name="message_recipients_count",
            field=models.PositiveIntegerField(default=0),
        ),
        migrations.AddField(
            model_name="promorequestitem",
            name="message_sent_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
