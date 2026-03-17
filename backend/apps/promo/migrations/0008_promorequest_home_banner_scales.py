from django.db import migrations, models
import django.core.validators


class Migration(migrations.Migration):

    dependencies = [
        ("promo", "0007_homebanner_device_scales"),
    ]

    operations = [
        migrations.AddField(
            model_name="promorequest",
            name="desktop_scale",
            field=models.PositiveSmallIntegerField(
                default=100,
                validators=[
                    django.core.validators.MinValueValidator(40),
                    django.core.validators.MaxValueValidator(160),
                ],
                verbose_name="حجم محتوى بانر الرئيسية للديسكتوب (%)",
            ),
        ),
        migrations.AddField(
            model_name="promorequest",
            name="mobile_scale",
            field=models.PositiveSmallIntegerField(
                default=100,
                validators=[
                    django.core.validators.MinValueValidator(40),
                    django.core.validators.MaxValueValidator(140),
                ],
                verbose_name="حجم محتوى بانر الرئيسية للجوال (%)",
            ),
        ),
        migrations.AddField(
            model_name="promorequest",
            name="tablet_scale",
            field=models.PositiveSmallIntegerField(
                default=100,
                validators=[
                    django.core.validators.MinValueValidator(40),
                    django.core.validators.MaxValueValidator(150),
                ],
                verbose_name="حجم محتوى بانر الرئيسية للأجهزة المتوسطة (%)",
            ),
        ),
    ]
