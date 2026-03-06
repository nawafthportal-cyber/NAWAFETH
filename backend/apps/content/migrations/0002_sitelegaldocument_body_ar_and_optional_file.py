import apps.content.models
import django.core.validators
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("content", "0001_initial"),
    ]

    operations = [
        migrations.AddField(
            model_name="sitelegaldocument",
            name="body_ar",
            field=models.TextField(blank=True, default=""),
        ),
        migrations.AlterField(
            model_name="sitelegaldocument",
            name="file",
            field=models.FileField(
                blank=True,
                upload_to="site_legal/%Y/%m/",
                validators=[
                    django.core.validators.FileExtensionValidator(
                        allowed_extensions=["pdf", "doc", "docx", "txt"]
                    ),
                    apps.content.models.validate_legal_document_file,
                ],
            ),
        ),
    ]
