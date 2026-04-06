from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("providers", "0010_providerspotlightitem"),
        ("promo", "0009_remove_frequency_fields"),
    ]

    operations = [
        migrations.AddField(
            model_name="promorequest",
            name="target_spotlight_item",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="promo_requests",
                to="providers.providerspotlightitem",
            ),
        ),
        migrations.AddField(
            model_name="promorequestitem",
            name="target_spotlight_item",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="promo_request_items",
                to="providers.providerspotlightitem",
            ),
        ),
    ]