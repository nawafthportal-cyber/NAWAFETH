from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("messaging", "0008_system_threads_and_reply_restrictions"),
    ]

    operations = [
        migrations.AddField(
            model_name="threaduserstate",
            name="is_deleted",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="threaduserstate",
            name="deleted_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddIndex(
            model_name="threaduserstate",
            index=models.Index(fields=["user", "is_deleted"], name="messaging_t_user_id_deleted_idx"),
        ),
    ]