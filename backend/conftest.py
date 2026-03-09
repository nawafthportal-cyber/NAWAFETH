import pytest
from django.core.cache import cache


@pytest.fixture(autouse=True)
def use_local_file_storage_for_tests(settings, tmp_path):
    """
    Force local filesystem storage in tests so they never depend on
    external S3/R2 permissions or network state.
    """
    settings.MEDIA_ROOT = str(tmp_path)
    settings.DEFAULT_FILE_STORAGE = "django.core.files.storage.FileSystemStorage"
    settings.STORAGES = {
        "default": {
            "BACKEND": "django.core.files.storage.FileSystemStorage",
        },
        "staticfiles": {
            "BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage",
        },
    }


@pytest.fixture(autouse=True)
def clear_runtime_cache_between_tests():
    cache.clear()
    yield
    cache.clear()
