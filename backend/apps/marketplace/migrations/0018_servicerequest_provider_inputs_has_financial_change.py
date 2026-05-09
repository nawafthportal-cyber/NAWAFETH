from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("marketplace", "0017_servicerequest_client_response_fields"),
    ]

    operations = [
        migrations.AddField(
            model_name="servicerequest",
            name="provider_inputs_has_financial_change",
            field=models.BooleanField(default=False),
        ),
    ]