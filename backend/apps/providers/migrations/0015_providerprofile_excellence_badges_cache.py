from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("providers", "0014_add_role_context_isolation"),
    ]

    operations = [
        migrations.AddField(
            model_name="providerprofile",
            name="excellence_badges_cache",
            field=models.JSONField(blank=True, default=list),
        ),
    ]
