from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("marketplace", "0009_unify_lifecycle_and_quote_deadline"),
    ]

    operations = [
        migrations.AddField(
            model_name="servicerequest",
            name="dispatch_mode",
            field=models.CharField(
                choices=[("all", "الكل"), ("nearest", "الأقرب")],
                default="all",
                max_length=20,
            ),
        ),
        migrations.CreateModel(
            name="ServiceRequestDispatch",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name="ID",
                    ),
                ),
                ("dispatch_tier", models.CharField(choices=[("basic", "أساسية"), ("riyadi", "ريادية"), ("pro", "احترافية")], max_length=20)),
                ("available_at", models.DateTimeField(db_index=True)),
                (
                    "dispatch_status",
                    models.CharField(
                        choices=[
                            ("pending", "معلّق"),
                            ("ready", "جاهز للإرسال"),
                            ("dispatched", "تم الإرسال"),
                            ("failed", "فشل الإرسال"),
                        ],
                        db_index=True,
                        default="pending",
                        max_length=20,
                    ),
                ),
                ("dispatched_at", models.DateTimeField(blank=True, null=True)),
                ("dispatch_attempts", models.PositiveSmallIntegerField(default=0)),
                ("last_error", models.CharField(blank=True, max_length=255)),
                ("idempotency_key", models.CharField(max_length=120, unique=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "request",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="dispatch_windows",
                        to="marketplace.servicerequest",
                    ),
                ),
            ],
            options={
                "indexes": [
                    models.Index(fields=["dispatch_tier", "dispatch_status", "available_at"], name="marketplace__dispatc_0fd4b8_idx"),
                    models.Index(fields=["request", "dispatch_status"], name="marketplace__request_b516ad_idx"),
                ],
                "constraints": [
                    models.UniqueConstraint(fields=("request", "dispatch_tier"), name="uniq_dispatch_window_request_tier"),
                ],
            },
        ),
    ]
