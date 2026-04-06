from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ("messaging", "0007_thread_participant_modes"),
    ]

    operations = [
        migrations.AddField(
            model_name="message",
            name="is_system_generated",
            field=models.BooleanField(db_index=True, default=False),
        ),
        migrations.AddField(
            model_name="message",
            name="sender_team_name",
            field=models.CharField(blank=True, default="", max_length=120),
        ),
        migrations.AddField(
            model_name="thread",
            name="is_system_thread",
            field=models.BooleanField(db_index=True, default=False),
        ),
        migrations.AddField(
            model_name="thread",
            name="reply_restricted_to",
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name="reply_restricted_threads", to=settings.AUTH_USER_MODEL),
        ),
        migrations.AddField(
            model_name="thread",
            name="reply_restriction_reason",
            field=models.CharField(blank=True, default="", max_length=255),
        ),
        migrations.AddField(
            model_name="thread",
            name="system_sender_label",
            field=models.CharField(blank=True, default="", max_length=120),
        ),
        migrations.AddField(
            model_name="thread",
            name="system_thread_key",
            field=models.CharField(blank=True, db_index=True, default="", max_length=64),
        ),
    ]