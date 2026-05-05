from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion
import django.utils.timezone


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ("providers", "0028_subcategory_policy_flags"),
    ]

    operations = [
        migrations.CreateModel(
            name="ProviderContentCommentLike",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("role_context", models.CharField(choices=[("client", "Client"), ("provider", "Provider")], db_index=True, default="client", max_length=20)),
                ("created_at", models.DateTimeField(default=django.utils.timezone.now)),
                ("comment", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="likes", to="providers.providercontentcomment")),
                ("user", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="provider_content_comment_likes", to=settings.AUTH_USER_MODEL)),
            ],
        ),
        migrations.AddConstraint(
            model_name="providercontentcommentlike",
            constraint=models.UniqueConstraint(fields=("user", "comment", "role_context"), name="uniq_like_user_content_comment_role"),
        ),
    ]