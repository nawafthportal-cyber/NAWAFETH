from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("subscriptions", "0008_subscriptioninquiryprofile"),
    ]

    operations = [
        migrations.AddField(
            model_name="subscription",
            name="duration_count",
            field=models.PositiveIntegerField(default=1),
        ),
    ]