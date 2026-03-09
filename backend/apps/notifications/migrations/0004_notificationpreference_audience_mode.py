from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("notifications", "0003_notification_audience_mode"),
    ]

    operations = [
        migrations.AddField(
            model_name="notificationpreference",
            name="audience_mode",
            field=models.CharField(
                choices=[("client", "عميل"), ("provider", "مزود"), ("shared", "مشترك")],
                db_index=True,
                default="shared",
                max_length=20,
            ),
        ),
        migrations.RemoveIndex(
            model_name="notificationpreference",
            name="notificatio_user_id_ae5582_idx",
        ),
        migrations.RemoveIndex(
            model_name="notificationpreference",
            name="notificatio_user_id_757954_idx",
        ),
        migrations.AlterUniqueTogether(
            name="notificationpreference",
            unique_together={("user", "key", "audience_mode")},
        ),
        migrations.AddIndex(
            model_name="notificationpreference",
            index=models.Index(fields=["user", "tier", "audience_mode"], name="notificatio_user_id_4c13d1_idx"),
        ),
        migrations.AddIndex(
            model_name="notificationpreference",
            index=models.Index(fields=["user", "key", "audience_mode"], name="notificatio_user_id_8f3a77_idx"),
        ),
    ]
