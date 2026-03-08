from __future__ import annotations

from decimal import Decimal

from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion
from django.db.models import Q
import django.utils.timezone


def seed_badge_types(apps, schema_editor):
    BadgeType = apps.get_model("excellence", "ExcellenceBadgeType")
    seeds = [
        {
            "code": "featured_service",
            "name_ar": "الخدمة المتميزة",
            "icon": "sparkles",
            "color": "#C0841A",
            "description": "تُمنح للمختصين الأعلى تقييمًا ضمن دورة المراجعة الحالية.",
            "review_cycle_days": 90,
            "sort_order": 10,
        },
        {
            "code": "high_achievement",
            "name_ar": "الإنجاز العالي",
            "icon": "bolt",
            "color": "#0F766E",
            "description": "تُمنح للمختصين الأعلى إنجازًا في الطلبات المكتملة خلال آخر سنة.",
            "review_cycle_days": 90,
            "sort_order": 20,
        },
        {
            "code": "top_100_club",
            "name_ar": "نادي المئة الكبار",
            "icon": "trophy",
            "color": "#7C3AED",
            "description": "تُمنح لأعلى 100 مختص في المتابعات والتأثير العام على المنصة.",
            "review_cycle_days": 90,
            "sort_order": 30,
        },
    ]
    for item in seeds:
        BadgeType.objects.update_or_create(code=item["code"], defaults=item)


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ("providers", "0014_add_role_context_isolation"),
    ]

    operations = [
        migrations.CreateModel(
            name="ExcellenceBadgeType",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("code", models.SlugField(max_length=50, unique=True)),
                ("name_ar", models.CharField(max_length=120)),
                ("icon", models.CharField(default="workspace_premium", max_length=50)),
                ("color", models.CharField(default="#C0841A", max_length=20)),
                ("description", models.CharField(blank=True, default="", max_length=255)),
                ("review_cycle_days", models.PositiveSmallIntegerField(default=90)),
                ("is_active", models.BooleanField(default=True)),
                ("sort_order", models.PositiveIntegerField(default=0)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
            ],
            options={"ordering": ["sort_order", "id"]},
        ),
        migrations.CreateModel(
            name="ExcellenceBadgeCandidate",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("evaluation_period_start", models.DateTimeField()),
                ("evaluation_period_end", models.DateTimeField()),
                ("metric_value", models.DecimalField(decimal_places=2, default=Decimal("0.00"), max_digits=10)),
                ("rank_position", models.PositiveIntegerField(default=1)),
                ("followers_count", models.PositiveIntegerField(default=0)),
                ("completed_orders_count", models.PositiveIntegerField(default=0)),
                ("rating_avg", models.DecimalField(decimal_places=2, default=Decimal("0.00"), max_digits=4)),
                ("rating_count", models.PositiveIntegerField(default=0)),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("pending", "بانتظار الاعتماد"),
                            ("approved", "معتمد"),
                            ("revoked", "مسحوب"),
                            ("expired", "منتهي"),
                        ],
                        db_index=True,
                        default="pending",
                        max_length=20,
                    ),
                ),
                ("review_note", models.CharField(blank=True, default="", max_length=300)),
                ("reviewed_at", models.DateTimeField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "badge_type",
                    models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="candidates", to="excellence.excellencebadgetype"),
                ),
                (
                    "category",
                    models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name="excellence_candidates", to="providers.category"),
                ),
                (
                    "provider",
                    models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="excellence_candidates", to="providers.providerprofile"),
                ),
                (
                    "reviewed_by",
                    models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name="reviewed_excellence_candidates", to=settings.AUTH_USER_MODEL),
                ),
                (
                    "subcategory",
                    models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name="excellence_candidates", to="providers.subcategory"),
                ),
            ],
            options={
                "ordering": ["badge_type__sort_order", "rank_position", "provider_id"],
                "indexes": [
                    models.Index(fields=["badge_type", "status", "evaluation_period_end"], name="excellence__badge_t_8984f9_idx"),
                    models.Index(fields=["provider", "evaluation_period_end"], name="excellence__provide_584736_idx"),
                ],
            },
        ),
        migrations.CreateModel(
            name="ExcellenceBadgeAward",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("category_name", models.CharField(blank=True, default="", max_length=100)),
                ("subcategory_name", models.CharField(blank=True, default="", max_length=100)),
                ("metric_value", models.DecimalField(decimal_places=2, default=Decimal("0.00"), max_digits=10)),
                ("rank_position", models.PositiveIntegerField(default=1)),
                ("followers_count", models.PositiveIntegerField(default=0)),
                ("completed_orders_count", models.PositiveIntegerField(default=0)),
                ("rating_avg", models.DecimalField(decimal_places=2, default=Decimal("0.00"), max_digits=4)),
                ("rating_count", models.PositiveIntegerField(default=0)),
                ("awarded_at", models.DateTimeField(default=django.utils.timezone.now)),
                ("valid_until", models.DateTimeField()),
                ("approval_note", models.CharField(blank=True, default="", max_length=300)),
                ("is_active", models.BooleanField(default=True)),
                ("revoked_at", models.DateTimeField(blank=True, null=True)),
                ("revoke_note", models.CharField(blank=True, default="", max_length=300)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "approved_by",
                    models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name="approved_excellence_awards", to=settings.AUTH_USER_MODEL),
                ),
                (
                    "badge_type",
                    models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="awards", to="excellence.excellencebadgetype"),
                ),
                (
                    "candidate",
                    models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name="awards", to="excellence.excellencebadgecandidate"),
                ),
                (
                    "provider",
                    models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="excellence_awards", to="providers.providerprofile"),
                ),
                (
                    "revoked_by",
                    models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name="revoked_excellence_awards", to=settings.AUTH_USER_MODEL),
                ),
            ],
            options={
                "ordering": ["-is_active", "-awarded_at", "-id"],
                "indexes": [
                    models.Index(fields=["provider", "is_active", "valid_until"], name="excellence__provide_ec0613_idx"),
                    models.Index(fields=["badge_type", "is_active", "valid_until"], name="excellence__badge_t_f4cbda_idx"),
                ],
            },
        ),
        migrations.AddConstraint(
            model_name="excellencebadgecandidate",
            constraint=models.UniqueConstraint(fields=("badge_type", "provider", "evaluation_period_start", "evaluation_period_end"), name="uniq_excellence_candidate_cycle"),
        ),
        migrations.AddConstraint(
            model_name="excellencebadgeaward",
            constraint=models.UniqueConstraint(condition=Q(("is_active", True)), fields=("badge_type", "provider"), name="uniq_active_excellence_award_per_type"),
        ),
        migrations.RunPython(seed_badge_types, migrations.RunPython.noop),
    ]
