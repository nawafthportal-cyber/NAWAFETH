from django.db import migrations, models


def seed_cover_gallery_from_legacy_cover(apps, schema_editor):
    ProviderProfile = apps.get_model("providers", "ProviderProfile")
    ProviderCoverImage = apps.get_model("providers", "ProviderCoverImage")

    for profile in ProviderProfile.objects.exclude(cover_image="").exclude(cover_image__isnull=True).iterator():
        if ProviderCoverImage.objects.filter(provider_id=profile.id).exists():
            continue
        ProviderCoverImage.objects.create(
            provider_id=profile.id,
            image=profile.cover_image,
            sort_order=0,
        )


class Migration(migrations.Migration):

    dependencies = [
        ("providers", "0026_providerportfolioitem_document_type"),
    ]

    operations = [
        migrations.CreateModel(
            name="ProviderCoverImage",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("image", models.FileField(upload_to="providers/cover_gallery/%Y/%m/")),
                ("sort_order", models.PositiveIntegerField(default=0)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("provider", models.ForeignKey(on_delete=models.deletion.CASCADE, related_name="cover_gallery", to="providers.providerprofile")),
            ],
            options={
                "ordering": ["sort_order", "id"],
            },
        ),
        migrations.RunPython(seed_cover_gallery_from_legacy_cover, migrations.RunPython.noop),
    ]