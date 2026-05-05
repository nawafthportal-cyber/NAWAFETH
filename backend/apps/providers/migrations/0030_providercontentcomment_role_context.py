from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("providers", "0029_providercontentcommentlike"),
    ]

    operations = [
        migrations.AddField(
            model_name="providercontentcomment",
            name="role_context",
            field=models.CharField(
                choices=[("client", "عميل"), ("provider", "مزود خدمة")],
                db_index=True,
                default="client",
                max_length=20,
            ),
        ),
    ]