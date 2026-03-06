import apps.content.models
import django.core.validators
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("content", "0002_sitelegaldocument_body_ar_and_optional_file"),
    ]

    operations = [
        migrations.AddField(
            model_name="sitecontentblock",
            name="media_file",
            field=models.FileField(
                blank=True,
                upload_to="site_content/%Y/%m/",
                validators=[
                    django.core.validators.FileExtensionValidator(
                        allowed_extensions=["gif", "jpeg", "jpg", "m4v", "mov", "mp4", "png", "webm", "webp"]
                    ),
                    apps.content.models.validate_content_block_media,
                ],
            ),
        ),
    ]
