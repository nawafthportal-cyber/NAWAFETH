from django.apps import AppConfig


class ExcellenceConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.excellence"
    verbose_name = "التميز"

    def ready(self):
        from . import signals  # noqa: F401
