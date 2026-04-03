import shutil
from pathlib import Path

import pytest
from django.core.cache import cache


@pytest.fixture(autouse=True)
def use_local_file_storage_for_tests(settings):
    """
    Force local filesystem storage in tests so they never depend on
    external S3/R2 permissions or network state.
    """
    base_dir = Path(getattr(settings, "BASE_DIR", Path(__file__).resolve().parent))
    media_root = base_dir / ".tmp_test_media"
    shutil.rmtree(media_root, ignore_errors=True)
    media_root.mkdir(parents=True, exist_ok=True)
    settings.MEDIA_ROOT = str(media_root)
    settings.DEFAULT_FILE_STORAGE = "django.core.files.storage.FileSystemStorage"
    settings.STORAGES = {
        "default": {
            "BACKEND": "django.core.files.storage.FileSystemStorage",
        },
        "staticfiles": {
            "BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage",
        },
    }
    yield
    shutil.rmtree(media_root, ignore_errors=True)


@pytest.fixture(autouse=True)
def clear_runtime_cache_between_tests():
    cache.clear()
    yield
    cache.clear()
