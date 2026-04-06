from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("messaging", "0006_thread_context_mode"),
    ]

    operations = [
        migrations.AddField(
            model_name="thread",
            name="participant_1_mode",
            field=models.CharField(blank=True, choices=[("client", "عميل"), ("provider", "مزود"), ("shared", "مشترك")], db_index=True, default="", max_length=20),
        ),
        migrations.AddField(
            model_name="thread",
            name="participant_2_mode",
            field=models.CharField(blank=True, choices=[("client", "عميل"), ("provider", "مزود"), ("shared", "مشترك")], db_index=True, default="", max_length=20),
        ),
    ]