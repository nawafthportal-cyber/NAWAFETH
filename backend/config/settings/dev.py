from .base import *  # noqa

DEBUG = True

# During development (no SMS integration yet), use explicit dev OTP mode.
OTP_DEV_BYPASS_ENABLED = True
OTP_DEV_ACCEPT_ANY_4_DIGITS = True
OTP_DEV_TEST_CODE = "0000"
OTP_DEV_ACCEPT_ANY_CODE = True

# Enable automatic home-banner video fitting in local development by default.
PROMO_HOME_BANNER_VIDEO_AUTOFIT = env_bool("PROMO_HOME_BANNER_VIDEO_AUTOFIT", True)

# Default to local media storage during development. This avoids admin/forms
# touching remote R2 objects and failing on HeadObject/HeadBucket permission
# mismatches. Opt in explicitly only when remote media needs local testing.
if not env_bool("DEV_USE_R2_MEDIA", False):
    MEDIA_URL = "/media/"
    MEDIA_ROOT = BASE_DIR / "media"
    SERVE_MEDIA = True
    STORAGES = {
        "default": {
            "BACKEND": "django.core.files.storage.FileSystemStorage",
        },
        "staticfiles": {
            "BACKEND": STATICFILES_BACKEND,
        },
    }
