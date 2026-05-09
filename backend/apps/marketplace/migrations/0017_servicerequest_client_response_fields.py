from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("marketplace", "0016_servicerequestpaymentplan_and_more"),
    ]

    operations = [
        migrations.AddField(
            model_name="servicerequest",
            name="client_response_attachment_required",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="servicerequest",
            name="client_response_note_required",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="servicerequest",
            name="client_response_question",
            field=models.CharField(blank=True, max_length=255),
        ),
    ]