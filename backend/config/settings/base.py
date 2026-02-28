from pathlib import Path
import os
from datetime import timedelta
from dotenv import load_dotenv

load_dotenv()

BASE_DIR = Path(__file__).resolve().parent.parent.parent

SECRET_KEY = os.getenv("DJANGO_SECRET_KEY", "dev-secret-key-change-me")
DEBUG = os.getenv("DJANGO_DEBUG", "1") == "1"

ALLOWED_HOSTS = [h.strip() for h in os.getenv("DJANGO_ALLOWED_HOSTS", "127.0.0.1,localhost").split(",") if h.strip()]
if DEBUG:
    # Local development defaults (Android emulator uses 10.0.2.2)
    for host in ("127.0.0.1", "localhost", "10.0.2.2", "0.0.0.0", "::1"):
        if host not in ALLOWED_HOSTS:
            ALLOWED_HOSTS.append(host)

INSTALLED_APPS = [
    # Django
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",

    # Third-party
    "rest_framework",
    "corsheaders",
    "django_filters",
    "channels",

    # Local apps (سنضيفها بعد قليل)
    "apps.accounts.apps.AccountsConfig",
    "apps.providers.apps.ProvidersConfig",
    "apps.marketplace.apps.MarketplaceConfig",
    "apps.messaging.apps.MessagingConfig",
    "apps.dashboard.apps.DashboardConfig",
    "apps.backoffice.apps.BackofficeConfig",
    "apps.unified_requests.apps.UnifiedRequestsConfig",
    "apps.support.apps.SupportConfig",
    "apps.billing.apps.BillingConfig",
    "apps.verification.apps.VerificationConfig",
    "apps.promo.apps.PromoConfig",
    "apps.subscriptions.apps.SubscriptionsConfig",
    "apps.extras.apps.ExtrasConfig",
    "apps.extras_portal.apps.ExtrasPortalConfig",
    "apps.features.apps.FeaturesConfig",
    "apps.analytics.apps.AnalyticsConfig",
    "apps.audit.apps.AuditConfig",
    "apps.notifications.apps.NotificationsConfig",
    "apps.reviews.apps.ReviewsConfig",
    "apps.content.apps.ContentConfig",
]

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",

    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.locale.LocaleMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "apps.features.middleware.SubscriptionRefreshMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [BASE_DIR / "templates"],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"

# ✅ Channels
ASGI_APPLICATION = "config.asgi.application"

REDIS_URL = os.getenv("REDIS_URL", "")
if REDIS_URL:
    # Redis (مفضل للإنتاج)
    CHANNEL_LAYERS = {
        "default": {
            "BACKEND": "channels_redis.core.RedisChannelLayer",
            "CONFIG": {
                "hosts": [REDIS_URL],
            },
        }
    }
else:
    # محلي بدون Redis (غير مفضل للإنتاج)
    CHANNEL_LAYERS = {"default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}}

# Database
DATABASE_URL = os.getenv("DATABASE_URL", "")
if DATABASE_URL:
    # Render style DATABASE_URL
    import dj_database_url  # type: ignore
    DATABASES = {"default": dj_database_url.parse(DATABASE_URL, conn_max_age=600)}
else:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": BASE_DIR / "db.sqlite3",
        }
    }

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "ar-sa"
LANGUAGES = [
    ("ar", "العربية"),
    ("en", "English"),
]
LOCALE_PATHS = [BASE_DIR / "locale"]
TIME_ZONE = "Asia/Riyadh"
USE_I18N = True
USE_TZ = True

STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
STATICFILES_STORAGE = "whitenoise.storage.CompressedManifestStaticFilesStorage"

MEDIA_URL = "/media/"
_media_root_override = (os.getenv("DJANGO_MEDIA_ROOT", "") or "").strip()
_render_disk_path = (os.getenv("RENDER_DISK_PATH", "") or "").strip()
if _media_root_override:
    MEDIA_ROOT = Path(_media_root_override)
elif _render_disk_path:
    # On Render, mount your persistent disk (e.g. /var/data) and store media under it.
    MEDIA_ROOT = Path(_render_disk_path) / "media"
else:
    MEDIA_ROOT = BASE_DIR / "media"

# Serve /media/ via Django when no reverse proxy/static host is configured.
# On Render this is the simplest option when using a persistent disk.
SERVE_MEDIA = (os.getenv("DJANGO_SERVE_MEDIA", "1") == "1")

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# ✅ Custom User
AUTH_USER_MODEL = "accounts.User"

# ✅ DRF
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ),
    "DEFAULT_PERMISSION_CLASSES": (
        "rest_framework.permissions.IsAuthenticated",
    ),
    "DEFAULT_THROTTLE_CLASSES": [
        "rest_framework.throttling.UserRateThrottle",
        "rest_framework.throttling.AnonRateThrottle",
    ],
    "DEFAULT_THROTTLE_RATES": {
        "user": "200/min",
        "anon": "60/min",
        "otp": "5/min",
		# Sensitive endpoints
		"auth": "15/min",
		"refresh": "60/min",
    },
    "DEFAULT_FILTER_BACKENDS": ["django_filters.rest_framework.DjangoFilterBackend"],
}

# ✅ JWT
SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=int(os.getenv("JWT_ACCESS_MIN", "60"))),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=int(os.getenv("JWT_REFRESH_DAYS", "30"))),
    "AUTH_HEADER_TYPES": ("Bearer",),
}

# ✅ CORS (Flutter/Web)
CORS_ALLOW_ALL_ORIGINS = os.getenv("CORS_ALLOW_ALL", "1") == "1"
CORS_ALLOWED_ORIGINS = [o.strip() for o in os.getenv("CORS_ALLOWED_ORIGINS", "").split(",") if o.strip()]

# ✅ Marketplace
URGENT_REQUEST_EXPIRY_MINUTES = int(os.getenv("URGENT_REQUEST_EXPIRY_MINUTES", "15"))

# VAT
DEFAULT_VAT_PERCENT = 15  # السعودية 15%

# Settings للباقات (اختياري الآن)
SUBS_GRACE_DAYS = 7  # فترة سماح بعد الانتهاء

# إعدادات افتراضية للإضافات (اختياري الآن)
EXTRAS_GRACE_DAYS = 0

EXTRA_SKUS = {
    "uploads_10gb_month": {"title": "زيادة سعة مرفقات 10GB (شهري)", "price": 59},
    "uploads_50gb_month": {"title": "زيادة سعة مرفقات 50GB (شهري)", "price": 199},
    "vip_support_month": {"title": "دعم VIP (شهري)", "price": 149},
    "promo_boost_7d": {"title": "Boost إعلان 7 أيام", "price": 99},
    "tickets_100": {"title": "رصيد 100 تذكرة دعم", "price": 79},
}

# إعدادات تسعير افتراضية (اختياري الآن)
PROMO_VAT_PERCENT = 15

# تسعير مبدئي (SAR) حسب نوع الإعلان
PROMO_BASE_PRICES = {
    "banner_home": 400,
    "banner_category": 300,
    "banner_search": 250,
    "popup_home": 600,
    "popup_category": 500,
    "featured_top5": 800,
    "featured_top10": 600,
    "boost_profile": 350,
    "push_notification": 700,
}

# مضاعفات حسب موقع الظهور/الأولوية
PROMO_POSITION_MULTIPLIER = {
    "first": 1.5,
    "second": 1.2,
    "top5": 1.35,
    "top10": 1.15,
    "normal": 1.0,
}

# مضاعفات حسب معدل الظهور
PROMO_FREQUENCY_MULTIPLIER = {
    "10s": 1.6,
    "20s": 1.3,
    "30s": 1.1,
    "60s": 1.0,
}

# ✅ Notifications
NOTIFICATIONS_RETENTION_DAYS = int(os.getenv("NOTIFICATIONS_RETENTION_DAYS", "90"))

# ✅ OTP (Development)
# When enabled (and DEBUG=True), any 4-digit code will be accepted by /otp/verify.
OTP_DEV_ACCEPT_ANY_CODE = os.getenv("OTP_DEV_ACCEPT_ANY_CODE", "0") == "1"

# ✅ OTP (Testing/Staging)
# For internal testing only: return the generated OTP code when a secret header matches.
# NOTE: This is forcibly disabled in production settings.
OTP_TEST_MODE = (os.getenv("OTP_TEST_MODE", os.getenv("OTP_DEV_MODE", "0")) == "1")
OTP_TEST_KEY = os.getenv("OTP_TEST_KEY", "").strip()
OTP_TEST_HEADER = os.getenv("OTP_TEST_HEADER", "X-OTP-TEST-KEY").strip() or "X-OTP-TEST-KEY"
OTP_TEST_CODE = os.getenv("OTP_TEST_CODE", "").strip()

# ✅ OTP (App QA bypass - Staging only)
# For QA builds (Flutter), allow /otp/verify to accept any 4-digit code WITHOUT headers.
# NOTE: Must be forcibly disabled in production settings.
OTP_APP_BYPASS = os.getenv("OTP_APP_BYPASS", "0") == "1"
OTP_APP_BYPASS_ALLOWLIST = [
    p.strip()
    for p in os.getenv("OTP_APP_BYPASS_ALLOWLIST", "").split(",")
    if p.strip()
]

# ✅ OTP limits (defense-in-depth)
OTP_COOLDOWN_SECONDS = int(os.getenv("OTP_COOLDOWN_SECONDS", "60"))
OTP_PHONE_HOURLY_LIMIT = int(os.getenv("OTP_PHONE_HOURLY_LIMIT", "5"))
OTP_PHONE_DAILY_LIMIT = int(os.getenv("OTP_PHONE_DAILY_LIMIT", "10"))
OTP_IP_HOURLY_LIMIT = int(os.getenv("OTP_IP_HOURLY_LIMIT", "50"))
