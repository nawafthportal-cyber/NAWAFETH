from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0008_user_city"),
    ]

    operations = [
        migrations.AddField(
            model_name="user",
            name="cover_image",
            field=models.FileField(blank=True, null=True, upload_to="accounts/cover/%Y/%m/"),
        ),
        migrations.AddField(
            model_name="user",
            name="profile_image",
            field=models.FileField(blank=True, null=True, upload_to="accounts/profile/%Y/%m/"),
        ),
    ]
