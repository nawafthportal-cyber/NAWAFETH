from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("extras", "0003_seed_service_catalog"),
    ]

    operations = [
        migrations.CreateModel(
            name="ExtrasBundlePricingRule",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("section_key", models.CharField(choices=[("reports", "التقارير"), ("clients", "إدارة العملاء"), ("finance", "الإدارة المالية")], max_length=20, verbose_name="القسم")),
                ("option_key", models.CharField(max_length=80, verbose_name="رمز البند")),
                ("fee", models.DecimalField(decimal_places=2, max_digits=10, verbose_name="السعر قبل الضريبة")),
                ("currency", models.CharField(default="SAR", max_length=10, verbose_name="العملة")),
                ("apply_year_multiplier", models.BooleanField(default=False, verbose_name="يضرب في مدة الاشتراك")),
                ("is_active", models.BooleanField(default=True, verbose_name="نشط")),
                ("sort_order", models.PositiveIntegerField(default=0, verbose_name="الترتيب")),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
            ],
            options={
                "verbose_name": "تسعير بند باقة خدمات إضافية",
                "verbose_name_plural": "تسعير بنود باقات الخدمات الإضافية",
                "ordering": ["section_key", "sort_order", "option_key"],
            },
        ),
        migrations.AddConstraint(
            model_name="extrasbundlepricingrule",
            constraint=models.UniqueConstraint(fields=("section_key", "option_key"), name="uniq_extras_bundle_pricing_rule"),
        ),
    ]
