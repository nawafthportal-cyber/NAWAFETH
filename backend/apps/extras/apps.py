from django.apps import AppConfig


class ExtrasConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.extras"
    verbose_name = "الخدمات الإضافية"

    def ready(self):
        from . import signals  # noqa
