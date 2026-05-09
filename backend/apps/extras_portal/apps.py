from django.apps import AppConfig


class ExtrasPortalConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.extras_portal"
    verbose_name = "بوابة الخدمات الإضافية"

    def ready(self):
        from . import signals  # noqa: F401
