from django.apps import AppConfig


class PromoConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.promo"
    verbose_name = "الترويج والإعلانات"

    def ready(self):
        from . import signals  # noqa
