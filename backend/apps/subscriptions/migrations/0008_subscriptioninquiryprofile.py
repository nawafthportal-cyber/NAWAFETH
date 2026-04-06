from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("support", "0001_initial"),
        ("subscriptions", "0007_subscription_awaiting_review_status"),
    ]

    operations = [
        migrations.CreateModel(
            name="SubscriptionInquiryProfile",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("operator_comment", models.CharField(blank=True, default="", max_length=300)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "ticket",
                    models.OneToOneField(
                        on_delete=models.deletion.CASCADE,
                        related_name="subscription_profile",
                        to="support.supportticket",
                    ),
                ),
            ],
            options={
                "verbose_name": "ملف استفسار الاشتراكات",
                "verbose_name_plural": "ملفات استفسارات الاشتراكات",
            },
        ),
    ]