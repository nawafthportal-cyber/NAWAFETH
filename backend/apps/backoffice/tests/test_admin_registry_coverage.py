import pytest
from django.apps import apps
from django.contrib import admin
from django.contrib.admin import ModelAdmin


pytestmark = pytest.mark.django_db


def _project_models():
    return sorted(
        [
            model
            for model in apps.get_models()
            if model.__module__.startswith("apps.")
            and not model._meta.abstract
            and not model._meta.auto_created
        ],
        key=lambda m: (m._meta.app_label, m.__name__),
    )


def test_all_project_models_are_registered_in_admin():
    models = _project_models()
    unregistered = [m for m in models if m not in admin.site._registry]
    assert not unregistered, (
        "Unregistered project models in Django Admin: "
        + ", ".join(f"{m._meta.app_label}.{m.__name__}" for m in unregistered)
    )


def test_all_project_models_use_explicit_model_admin():
    models = _project_models()
    default_admins = [
        m for m in models if type(admin.site._registry.get(m)) is ModelAdmin
    ]
    assert not default_admins, (
        "Project models registered with default ModelAdmin (needs explicit admin class): "
        + ", ".join(f"{m._meta.app_label}.{m.__name__}" for m in default_admins)
    )
