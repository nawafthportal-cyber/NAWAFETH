from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("core", "0001_initial"),
    ]

    operations = [
        migrations.AddField(
            model_name="platformconfig",
            name="extras_currency",
            field=models.CharField(default="SAR", max_length=10, verbose_name="عملة الخدمات الإضافية"),
        ),
        migrations.AddField(
            model_name="platformconfig",
            name="extras_short_duration_days",
            field=models.PositiveIntegerField(default=7, verbose_name="المدة القصيرة للخدمات الإضافية (أيام)"),
        ),
        migrations.AddField(
            model_name="platformconfig",
            name="promo_base_prices",
            field=models.JSONField(
                blank=True,
                default={
                    "banner_home": 400,
                    "banner_category": 300,
                    "banner_search": 250,
                    "boost_profile": 350,
                    "featured_top10": 600,
                    "featured_top5": 800,
                    "popup_category": 500,
                    "popup_home": 600,
                    "push_notification": 700,
                },
                verbose_name="الأسعار الأساسية legacy للترويج",
            ),
        ),
        migrations.AddField(
            model_name="platformconfig",
            name="promo_frequency_multipliers",
            field=models.JSONField(
                blank=True,
                default={"10s": 1.6, "20s": 1.3, "30s": 1.1, "60s": 1.0},
                verbose_name="مضاعفات تكرار الظهور legacy للترويج",
            ),
        ),
        migrations.AddField(
            model_name="platformconfig",
            name="promo_position_multipliers",
            field=models.JSONField(
                blank=True,
                default={"first": 1.5, "normal": 1.0, "second": 1.2, "top10": 1.15, "top5": 1.35},
                verbose_name="مضاعفات مواقع الظهور legacy للترويج",
            ),
        ),
    ]
