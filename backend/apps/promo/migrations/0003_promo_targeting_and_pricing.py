from decimal import Decimal
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("providers", "0005_providerprofile_updated_at_and_portfolio"),
        ("promo", "0002_promorequest_assignment"),
    ]

    operations = [
        migrations.AddField(
            model_name="promorequest",
            name="target_provider",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="promo_requests",
                to="providers.providerprofile",
            ),
        ),
        migrations.AddField(
            model_name="promorequest",
            name="target_portfolio_item",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="promo_requests",
                to="providers.providerportfolioitem",
            ),
        ),
        migrations.AddField(
            model_name="promorequest",
            name="message_title",
            field=models.CharField(blank=True, default="", max_length=160),
        ),
        migrations.AddField(
            model_name="promorequest",
            name="message_body",
            field=models.CharField(blank=True, default="", max_length=500),
        ),
        migrations.CreateModel(
            name="PromoAdPrice",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                (
                    "ad_type",
                    models.CharField(
                        choices=[
                            ("banner_home", "بانر الصفحة الرئيسية"),
                            ("banner_category", "بانر صفحة القسم"),
                            ("banner_search", "بانر صفحة البحث"),
                            ("popup_home", "نافذة منبثقة رئيسية"),
                            ("popup_category", "نافذة منبثقة داخل قسم"),
                            ("featured_top5", "تمييز ضمن أول 5"),
                            ("featured_top10", "تمييز ضمن أول 10"),
                            ("boost_profile", "تعزيز ملف مقدم الخدمة"),
                            ("push_notification", "إشعار دفع (Push)"),
                        ],
                        max_length=30,
                        unique=True,
                    ),
                ),
                ("price_per_day", models.DecimalField(decimal_places=2, default=Decimal("0.00"), max_digits=12)),
                ("is_active", models.BooleanField(default=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
            ],
            options={
                "ordering": ["ad_type"],
            },
        ),
    ]
