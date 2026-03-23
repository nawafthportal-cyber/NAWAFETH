from pathlib import Path
import hashlib
from importlib import import_module
import json
import os
from datetime import timedelta
from celery.schedules import crontab
from dotenv import load_dotenv

load_dotenv()

BASE_DIR = Path(__file__).resolve().parent.parent.parent


def env_bool(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def env_json(name: str, default):
    raw = os.getenv(name)
    if raw is None or not raw.strip():
        return default
    try:
        return json.loads(raw)
    except Exception:
        return default


SECRET_KEY = os.getenv("DJANGO_SECRET_KEY", "dev-secret-key-change-me")
DEBUG = os.getenv("DJANGO_DEBUG", "1") == "1"
FEATURE_MODERATION_CENTER = env_bool("FEATURE_MODERATION_CENTER", False)
FEATURE_MODERATION_DUAL_WRITE = env_bool("FEATURE_MODERATION_DUAL_WRITE", False)
FEATURE_RBAC_ENFORCE = env_bool("FEATURE_RBAC_ENFORCE", False)
RBAC_AUDIT_ONLY = env_bool("RBAC_AUDIT_ONLY", True)
FEATURE_ANALYTICS_EVENTS = env_bool("FEATURE_ANALYTICS_EVENTS", False)
FEATURE_ANALYTICS_KPI_SURFACES = env_bool("FEATURE_ANALYTICS_KPI_SURFACES", False)

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
    "storages",

    # Local apps (سنضيفها بعد قليل)
    "apps.core.apps.CoreConfig",
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
    "apps.excellence.apps.ExcellenceConfig",
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
    "apps.moderation.apps.ModerationConfig",
    "apps.mobile_web.apps.MobileWebConfig",
]

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "apps.core.middleware.RequestContextMiddleware",

    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.locale.LocaleMiddleware",
    "apps.core.admin_middleware.AdminArabicLocaleMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "apps.audit.middleware.ExportAuditMiddleware",
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

CACHES = (
    {
        "default": {
            "BACKEND": "django.core.cache.backends.redis.RedisCache",
            "LOCATION": REDIS_URL,
        }
    }
    if REDIS_URL
    else {
        "default": {
            "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
            "LOCATION": "nawafeth-default",
        }
    }
)

# Database
DATABASE_URL = os.getenv("DATABASE_URL", "")
DB_CONN_MAX_AGE = int(os.getenv("DB_CONN_MAX_AGE", "300"))
DB_CONNECT_TIMEOUT = int(os.getenv("DB_CONNECT_TIMEOUT", "5"))
DB_APPLICATION_NAME = (os.getenv("DB_APPLICATION_NAME", "nawafeth") or "nawafeth").strip()
if DATABASE_URL:
    # Render style DATABASE_URL
    import dj_database_url  # type: ignore
    DATABASES = {"default": dj_database_url.parse(DATABASE_URL, conn_max_age=DB_CONN_MAX_AGE)}
else:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": BASE_DIR / "db.sqlite3",
        }
    }

if DATABASES["default"]["ENGINE"] != "django.db.backends.sqlite3":
    DATABASES["default"]["CONN_MAX_AGE"] = DB_CONN_MAX_AGE
    DATABASES["default"]["CONN_HEALTH_CHECKS"] = True
    database_options = DATABASES["default"].setdefault("OPTIONS", {})
    database_options.setdefault("connect_timeout", DB_CONNECT_TIMEOUT)
    database_options.setdefault("application_name", DB_APPLICATION_NAME)

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

CELERY_BROKER_URL = os.getenv("CELERY_BROKER_URL", REDIS_URL or "redis://127.0.0.1:6379/0")
CELERY_RESULT_BACKEND = os.getenv("CELERY_RESULT_BACKEND", CELERY_BROKER_URL)
CELERY_ACCEPT_CONTENT = ["json"]
CELERY_TASK_SERIALIZER = "json"
CELERY_RESULT_SERIALIZER = "json"
CELERY_TIMEZONE = TIME_ZONE
CELERY_BEAT_SCHEDULE = {
    "marketplace-dispatch-ready-urgent": {
        "task": "marketplace.dispatch_ready_urgent_windows",
        "schedule": timedelta(minutes=1),
        "args": (200,),
    },
    "verification-expire-badges": {
        "task": "verification.expire_badges_and_sync",
        "schedule": timedelta(hours=1),
        "args": (1000, 10),
    },
    "excellence-generate-candidates": {
        "task": "excellence.generate_candidates",
        "schedule": timedelta(hours=12),
    },
    "excellence-expire-awards": {
        "task": "excellence.expire_awards",
        "schedule": timedelta(hours=1),
        "args": (500, 10),
    },
    "excellence-rebuild-all-cache": {
        "task": "excellence.rebuild_all_cache",
        "schedule": crontab(hour=3, minute=15),
        "kwargs": {"batch_size": 500},
    },
    # ── Phase 2: تنبيهات الانتهاء والتجديد ──
    "core-subscription-renewal-reminders": {
        "task": "core.send_subscription_renewal_reminders",
        "schedule": timedelta(hours=6),
    },
    "core-verification-expiry-reminders": {
        "task": "core.send_verification_expiry_reminders",
        "schedule": timedelta(hours=12),
    },
    "core-send-due-promo-messages": {
        "task": "core.send_due_promo_messages",
        "schedule": timedelta(minutes=5),
    },
    "core-auto-complete-expired-promos": {
        "task": "core.auto_complete_expired_promos",
        "schedule": timedelta(hours=1),
    },
    "analytics-rebuild-daily-stats": {
        "task": "analytics.rebuild_daily_stats",
        "schedule": crontab(hour=2, minute=20),
    },
}

STATIC_URL = "/static/"
STATICFILES_DIRS = [BASE_DIR / "static"]
STATIC_ROOT = BASE_DIR / "staticfiles"
STATICFILES_BACKEND = "whitenoise.storage.CompressedManifestStaticFilesStorage"
WHITENOISE_MANIFEST_STRICT = env_bool("WHITENOISE_MANIFEST_STRICT", False)
# Optional resilient fallback: let Django serve /static/ when explicitly enabled.
# Useful on some PaaS deploys where collectstatic artifacts are unexpectedly absent.
SERVE_STATIC = env_bool("DJANGO_SERVE_STATIC", False)

# Cloudflare R2 / S3-compatible media storage (optional)
USE_R2_MEDIA = env_bool("USE_R2_MEDIA", False)

R2_BUCKET_NAME = (os.getenv("R2_BUCKET_NAME", "") or "").strip()
R2_ENDPOINT_URL = (os.getenv("R2_ENDPOINT_URL", "") or "").strip()
R2_PUBLIC_BASE_URL = (os.getenv("R2_PUBLIC_BASE_URL", "") or "").strip()

AWS_ACCESS_KEY_ID = (os.getenv("AWS_ACCESS_KEY_ID", os.getenv("R2_ACCESS_KEY_ID", "")) or "").strip()
AWS_SECRET_ACCESS_KEY = (
    os.getenv("AWS_SECRET_ACCESS_KEY", os.getenv("R2_SECRET_ACCESS_KEY", "")) or ""
).strip()
AWS_STORAGE_BUCKET_NAME = (os.getenv("AWS_STORAGE_BUCKET_NAME", R2_BUCKET_NAME) or "").strip()
AWS_S3_ENDPOINT_URL = (os.getenv("AWS_S3_ENDPOINT_URL", R2_ENDPOINT_URL) or "").strip()
AWS_S3_REGION_NAME = (os.getenv("AWS_S3_REGION_NAME", "auto") or "auto").strip()
AWS_S3_SIGNATURE_VERSION = (os.getenv("AWS_S3_SIGNATURE_VERSION", "s3v4") or "s3v4").strip()
AWS_S3_ADDRESSING_STYLE = (os.getenv("AWS_S3_ADDRESSING_STYLE", "path") or "path").strip()
AWS_DEFAULT_ACL = None
AWS_QUERYSTRING_AUTH = env_bool("AWS_QUERYSTRING_AUTH", False)
AWS_S3_FILE_OVERWRITE = env_bool("AWS_S3_FILE_OVERWRITE", False)

_r2_media_ready = USE_R2_MEDIA and all(
    [
        AWS_ACCESS_KEY_ID,
        AWS_SECRET_ACCESS_KEY,
        AWS_STORAGE_BUCKET_NAME,
        AWS_S3_ENDPOINT_URL,
    ]
)

# Quick connectivity check for R2 to avoid silent 500s on every upload.
# Runs only once at startup; falls back to local storage on failure.
R2_HEAD_BUCKET_STRICT = env_bool("R2_HEAD_BUCKET_STRICT", False)
R2_HEAD_BUCKET_CONNECT_TIMEOUT = float(os.getenv("R2_HEAD_BUCKET_CONNECT_TIMEOUT", "3"))
R2_HEAD_BUCKET_READ_TIMEOUT = float(os.getenv("R2_HEAD_BUCKET_READ_TIMEOUT", "3"))
R2_HEAD_BUCKET_MAX_ATTEMPTS = int(os.getenv("R2_HEAD_BUCKET_MAX_ATTEMPTS", "1"))
if _r2_media_ready:
    try:
        boto3 = import_module("boto3")
        BotoConfig = import_module("botocore.config").Config
        _test_client = boto3.client(
            "s3",
            endpoint_url=AWS_S3_ENDPOINT_URL,
            aws_access_key_id=AWS_ACCESS_KEY_ID,
            aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
            region_name=AWS_S3_REGION_NAME,
            config=BotoConfig(
                signature_version=AWS_S3_SIGNATURE_VERSION,
                s3={"addressing_style": AWS_S3_ADDRESSING_STYLE},
                connect_timeout=R2_HEAD_BUCKET_CONNECT_TIMEOUT,
                read_timeout=R2_HEAD_BUCKET_READ_TIMEOUT,
                retries={"max_attempts": R2_HEAD_BUCKET_MAX_ATTEMPTS, "mode": "standard"},
            ),
        )
        _test_client.head_bucket(Bucket=AWS_STORAGE_BUCKET_NAME)
    except Exception as _r2_err:
        import logging as _log
        _logger = _log.getLogger("nawafeth.settings")

        # NOTE:
        # Some S3-compatible providers/tokens (including certain R2 tokens)
        # may reject HeadBucket with 403 while object-level operations still
        # work. In that case, do not force fallback unless strict mode is on.
        _is_head_bucket_forbidden = False
        _error_code = ""
        try:
            _ClientError = import_module("botocore.exceptions").ClientError
            if isinstance(_r2_err, _ClientError):
                _error_code = str(
                    ((_r2_err.response or {}).get("Error", {}) or {}).get("Code", "")
                ).strip()
                _is_head_bucket_forbidden = _error_code in {"403", "Forbidden", "AccessDenied"}
        except Exception:
            pass

        if _is_head_bucket_forbidden and not R2_HEAD_BUCKET_STRICT:
            _logger.warning(
                "R2/S3 HeadBucket returned %s. Keeping S3 storage enabled (set R2_HEAD_BUCKET_STRICT=1 to force fallback).",
                _error_code or "403",
            )
        else:
            _logger.warning(
                "R2/S3 connectivity check failed (%s). Falling back to local FileSystemStorage.",
                _r2_err,
            )
            _r2_media_ready = False

if _r2_media_ready:
    # ── Determine public base URL for media served from R2 ──
    _r2_public_url = R2_PUBLIC_BASE_URL.rstrip("/") if R2_PUBLIC_BASE_URL else ""

    # Storage options passed to django-storages S3Storage
    _s3_options: dict = {}

    if _r2_public_url:
        # Public domain (r2.dev subdomain or custom domain) → unsigned URLs
        # Strip the scheme for AWS_S3_CUSTOM_DOMAIN (django-storages expects host only)
        _custom_domain = _r2_public_url.split("://", 1)[-1].rstrip("/")
        _s3_options["custom_domain"] = _custom_domain
        AWS_S3_CUSTOM_DOMAIN = _custom_domain
        MEDIA_URL = f"{_r2_public_url}/"
        AWS_QUERYSTRING_AUTH = env_bool("AWS_QUERYSTRING_AUTH", False)
    else:
        # No public URL configured → use pre-signed URLs so browsers can
        # fetch objects directly from the R2 API endpoint.
        AWS_QUERYSTRING_AUTH = env_bool("AWS_QUERYSTRING_AUTH", True)
        AWS_QUERYSTRING_EXPIRE = int(os.getenv("AWS_QUERYSTRING_EXPIRE", "3600"))
        MEDIA_URL = f"{AWS_S3_ENDPOINT_URL.rstrip('/')}/{AWS_STORAGE_BUCKET_NAME}/"

    # Keep a local media root for admin/dev tools that may still touch local files.
    MEDIA_ROOT = BASE_DIR / "media"
    SERVE_MEDIA = False
    STORAGES = {
        "default": {
            "BACKEND": "storages.backends.s3.S3Storage",
            "OPTIONS": _s3_options,
        },
        "staticfiles": {
            "BACKEND": STATICFILES_BACKEND,
        },
    }
else:
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
    SERVE_MEDIA = env_bool("DJANGO_SERVE_MEDIA", True)
    STORAGES = {
        "default": {
            "BACKEND": "django.core.files.storage.FileSystemStorage",
        },
        "staticfiles": {
            "BACKEND": STATICFILES_BACKEND,
        },
    }

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
JWT_SIGNING_KEY = (
    (os.getenv("JWT_SIGNING_KEY", "") or "").strip()
    or hashlib.sha256(f"jwt:{SECRET_KEY}".encode("utf-8")).hexdigest()
)

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=int(os.getenv("JWT_ACCESS_MIN", "60"))),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=int(os.getenv("JWT_REFRESH_DAYS", "30"))),
    "AUTH_HEADER_TYPES": ("Bearer",),
    "SIGNING_KEY": JWT_SIGNING_KEY,
}

# ✅ CORS (Flutter/Web)
CORS_ALLOW_ALL_ORIGINS = os.getenv("CORS_ALLOW_ALL", "1") == "1"
CORS_ALLOWED_ORIGINS = [o.strip() for o in os.getenv("CORS_ALLOWED_ORIGINS", "").split(",") if o.strip()]

# ✅ Marketplace
URGENT_REQUEST_EXPIRY_MINUTES = int(os.getenv("URGENT_REQUEST_EXPIRY_MINUTES", "15"))

# VAT
DEFAULT_VAT_PERCENT = 15  # السعودية 15%

BILLING_WEBHOOK_SECRETS = env_json(
    "BILLING_WEBHOOK_SECRETS",
    {
        "mock": os.getenv("BILLING_WEBHOOK_SECRET_MOCK", SECRET_KEY),
    },
)

# Settings للباقات (اختياري الآن)
SUBS_GRACE_DAYS = 7  # فترة سماح بعد الانتهاء

# إعدادات افتراضية للإضافات (اختياري الآن)
EXTRAS_GRACE_DAYS = 0

# Firebase Cloud Messaging (optional)
FIREBASE_PUSH_ENABLED = env_bool("FIREBASE_PUSH_ENABLED", False)
FIREBASE_PROJECT_ID = (os.getenv("FIREBASE_PROJECT_ID", "") or "").strip()
FIREBASE_CREDENTIALS_PATH = (os.getenv("FIREBASE_CREDENTIALS_PATH", "") or "").strip()
FIREBASE_CREDENTIALS_JSON = (os.getenv("FIREBASE_CREDENTIALS_JSON", "") or "").strip()
FIREBASE_PUSH_SOUND = (os.getenv("FIREBASE_PUSH_SOUND", "default") or "default").strip()

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
UNREAD_BADGE_CACHE_TTL = int(os.getenv("UNREAD_BADGE_CACHE_TTL", "15"))
UNREAD_BADGE_STALE_CACHE_TTL = int(
    os.getenv("UNREAD_BADGE_STALE_CACHE_TTL", str(max(UNREAD_BADGE_CACHE_TTL * 8, 120)))
)

# ✅ OTP (Development)
# Explicit development-only OTP bypass contract.
OTP_DEV_BYPASS_ENABLED = env_bool(
    "OTP_DEV_BYPASS_ENABLED",
    env_bool("OTP_DEV_ACCEPT_ANY_CODE", False),
)
OTP_DEV_ACCEPT_ANY_4_DIGITS = env_bool(
    "OTP_DEV_ACCEPT_ANY_4_DIGITS",
    OTP_DEV_BYPASS_ENABLED,
)
OTP_DEV_TEST_CODE = (os.getenv("OTP_DEV_TEST_CODE", "") or "").strip()

# Backward-compatible alias for older code/tests until all call-sites converge.
OTP_DEV_ACCEPT_ANY_CODE = OTP_DEV_BYPASS_ENABLED and OTP_DEV_ACCEPT_ANY_4_DIGITS

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
