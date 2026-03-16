from django.db import migrations, models
import django.core.validators


class Migration(migrations.Migration):

    dependencies = [
        ("promo", "0006_promorequestitem_message_delivery_fields"),
    ]

    operations = [
        migrations.AddField(
            model_name="homebanner",
            name="desktop_scale",
            field=models.PositiveSmallIntegerField(
                default=100,
                validators=[
                    django.core.validators.MinValueValidator(40),
                    django.core.validators.MaxValueValidator(160),
                ],
                verbose_name="حجم المحتوى للديسكتوب (%)",
            ),
        ),
        migrations.AddField(
            model_name="homebanner",
            name="mobile_scale",
            field=models.PositiveSmallIntegerField(
                default=100,
                validators=[
                    django.core.validators.MinValueValidator(40),
                    django.core.validators.MaxValueValidator(140),
                ],
                verbose_name="حجم المحتوى للجوال (%)",
            ),
        ),
        migrations.AddField(
            model_name="homebanner",
            name="tablet_scale",
            field=models.PositiveSmallIntegerField(
                default=100,
                validators=[
                    django.core.validators.MinValueValidator(40),
                    django.core.validators.MaxValueValidator(150),
                ],
                verbose_name="حجم المحتوى للأجهزة المتوسطة (%)",
            ),
        ),
    ]
