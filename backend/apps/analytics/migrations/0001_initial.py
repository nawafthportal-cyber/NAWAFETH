from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion
import django.utils.timezone


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="AnalyticsEvent",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("event_name", models.CharField(db_index=True, max_length=80)),
                ("channel", models.CharField(choices=[("server", "Server"), ("flutter", "Flutter"), ("mobile_web", "Mobile Web")], default="server", max_length=20)),
                ("surface", models.CharField(blank=True, default="", max_length=120)),
                ("source_app", models.CharField(blank=True, default="", max_length=50)),
                ("object_type", models.CharField(blank=True, default="", max_length=80)),
                ("object_id", models.CharField(blank=True, default="", max_length=50)),
                ("session_id", models.CharField(blank=True, default="", max_length=64)),
                ("dedupe_key", models.CharField(blank=True, db_index=True, default="", max_length=160)),
                ("version", models.PositiveSmallIntegerField(default=1)),
                ("occurred_at", models.DateTimeField(db_index=True, default=django.utils.timezone.now)),
                ("payload", models.JSONField(blank=True, default=dict)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("actor", models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name="analytics_events", to=settings.AUTH_USER_MODEL)),
            ],
            options={
                "ordering": ["-occurred_at", "-id"],
            },
        ),
        migrations.AddIndex(
            model_name="analyticsevent",
            index=models.Index(fields=["event_name", "occurred_at"], name="analytics_e_event_n_c7f9f9_idx"),
        ),
        migrations.AddIndex(
            model_name="analyticsevent",
            index=models.Index(fields=["channel", "occurred_at"], name="analytics_e_channel_03326e_idx"),
        ),
        migrations.AddIndex(
            model_name="analyticsevent",
            index=models.Index(fields=["object_type", "object_id"], name="analytics_e_object__b70c68_idx"),
        ),
    ]
