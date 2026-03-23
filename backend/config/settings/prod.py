from .base import *  # noqa

import os

DEBUG = False

# Keep key operational surfaces enabled in production by default.
# These can still be turned off explicitly through environment variables.
FEATURE_MODERATION_CENTER = env_bool("FEATURE_MODERATION_CENTER", True)
FEATURE_ANALYTICS_EVENTS = env_bool("FEATURE_ANALYTICS_EVENTS", True)
FEATURE_ANALYTICS_KPI_SURFACES = env_bool("FEATURE_ANALYTICS_KPI_SURFACES", True)

# Fallback when staticfiles was not pre-collected in ephemeral environments.
WHITENOISE_USE_FINDERS = env_bool("WHITENOISE_USE_FINDERS", True)

# Production resilience: avoid runtime 500s from manifest hash resolution
# mismatches on ephemeral deploy environments.
STATICFILES_BACKEND = "whitenoise.storage.CompressedStaticFilesStorage"
STORAGES["staticfiles"] = {"BACKEND": STATICFILES_BACKEND}


def _unique_list(values):
	items = []
	for value in values:
		normalized = (value or "").strip().rstrip("/")
		if normalized and normalized not in items:
			items.append(normalized)
	return items


def _expand_https_default_port(origins):
	expanded = []
	for origin in origins:
		normalized = (origin or "").strip().rstrip("/")
		if not normalized:
			continue
		expanded.append(normalized)
		host = normalized.split("://", 1)[-1]
		if normalized.startswith("https://") and ":" not in host:
			expanded.append(f"{normalized}:443")
	return _unique_list(expanded)

# Never allow OTP test helpers in production.
OTP_TEST_MODE = False
OTP_TEST_KEY = ""
OTP_TEST_CODE = ""
OTP_DEV_BYPASS_ENABLED = False
OTP_DEV_ACCEPT_ANY_4_DIGITS = False
OTP_DEV_TEST_CODE = ""
OTP_DEV_ACCEPT_ANY_CODE = False

# Emergency OTP bypass can be enabled in production through environment
# variables. When enabled, any 4-digit code is accepted after otp/send.
OTP_APP_BYPASS = os.getenv("OTP_APP_BYPASS", "0") == "1"
OTP_APP_BYPASS_ALLOWLIST = [
	p.strip()
	for p in os.getenv("OTP_APP_BYPASS_ALLOWLIST", "").split(",")
	if p.strip()
]

# Render (and similar PaaS) hostnames + custom domain
for _host in (".onrender.com", ".nawafthportal.com", "nawafthportal.com", "www.nawafthportal.com"):
	if _host not in ALLOWED_HOSTS and "*" not in ALLOWED_HOSTS:
		ALLOWED_HOSTS.append(_host)

SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
USE_X_FORWARDED_HOST = True

SECURE_SSL_REDIRECT = True
# Render's port scan / health checks may hit the service over plain HTTP.
# Exempt health endpoints (and root, which maps to liveness) so these checks
# can succeed without being redirected to HTTPS.
SECURE_REDIRECT_EXEMPT = [
	r"^health/",
	r"^healthz/?$",
	r"^$",
]
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True

SECURE_HSTS_SECONDS = 60 * 60 * 24 * 30
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True

X_FRAME_OPTIONS = "DENY"
SECURE_REFERRER_POLICY = "same-origin"

# CORS (Production)
CORS_ALLOW_ALL_ORIGINS = False
DEFAULT_CORS_ALLOWED_ORIGINS = [
	"https://nawafthportal.com",
	"https://www.nawafthportal.com",
]
CORS_ALLOWED_ORIGINS = list(DEFAULT_CORS_ALLOWED_ORIGINS)
DEFAULT_CORS_ALLOWED_ORIGIN_REGEXES = [
	r"^https://[a-z0-9-]+\.onrender\.com$",
	r"^https://([a-z0-9-]+\.)?nawafthportal\.com$",
]
CORS_ALLOWED_ORIGIN_REGEXES = list(DEFAULT_CORS_ALLOWED_ORIGIN_REGEXES)

_cors_env = os.getenv("DJANGO_CORS_ALLOWED_ORIGINS", "").strip()
if _cors_env:
	CORS_ALLOWED_ORIGINS = _unique_list(
		DEFAULT_CORS_ALLOWED_ORIGINS + [o.strip() for o in _cors_env.split(",") if o.strip()]
	)

_cors_regex_env = os.getenv("DJANGO_CORS_ALLOWED_ORIGIN_REGEXES", "").strip()
if _cors_regex_env:
	CORS_ALLOWED_ORIGIN_REGEXES = _unique_list(
		DEFAULT_CORS_ALLOWED_ORIGIN_REGEXES + [o.strip() for o in _cors_regex_env.split(",") if o.strip()]
	)

# CSRF trusted origins (Render/custom domains)
_csrf_env = os.getenv("DJANGO_CSRF_TRUSTED_ORIGINS", "").strip()
DEFAULT_CSRF_TRUSTED_ORIGINS = [
	"https://*.onrender.com",
	"https://nawafthportal.com",
	"https://www.nawafthportal.com",
	"https://*.nawafthportal.com",
]
CSRF_TRUSTED_ORIGINS = list(DEFAULT_CSRF_TRUSTED_ORIGINS)
if _csrf_env:
	CSRF_TRUSTED_ORIGINS = _unique_list(
		DEFAULT_CSRF_TRUSTED_ORIGINS + [o.strip() for o in _csrf_env.split(",") if o.strip()]
	)
CSRF_TRUSTED_ORIGINS = _expand_https_default_port(CSRF_TRUSTED_ORIGINS)

# CSP (Production) - django-csp v4+ format
INSTALLED_APPS += ["csp"]
if "csp.middleware.CSPMiddleware" not in MIDDLEWARE:
	# Place near the top (after SecurityMiddleware is typical)
	try:
		sec_i = MIDDLEWARE.index("django.middleware.security.SecurityMiddleware")
		MIDDLEWARE.insert(sec_i + 1, "csp.middleware.CSPMiddleware")
	except ValueError:
		MIDDLEWARE.insert(0, "csp.middleware.CSPMiddleware")

CONTENT_SECURITY_POLICY = {
	"DIRECTIVES": {
		"default-src": ("'self'",),
		"img-src": ("'self'", "data:", "https:"),
		"media-src": ("'self'", "https:", "blob:"),
		"style-src": ("'self'", "'unsafe-inline'", "https:"),
		"script-src": ("'self'", "'unsafe-inline'", "https:"),
		"font-src": ("'self'", "https://fonts.gstatic.com", "data:"),
		"connect-src": ("'self'", "https:"),
	}
}

# Sentry
SENTRY_DSN = os.getenv("SENTRY_DSN", "")
if SENTRY_DSN:
	try:
		import importlib

		sentry_sdk = importlib.import_module("sentry_sdk")
		django_integration = importlib.import_module("sentry_sdk.integrations.django")
		DjangoIntegration = getattr(django_integration, "DjangoIntegration")
		sentry_sdk.init(
			dsn=SENTRY_DSN,
			integrations=[DjangoIntegration()],
			traces_sample_rate=0.2,
			send_default_pii=False,
		)
	except Exception:
		# Sentry is optional; ignore if it's not installed or fails to init.
		pass

# Structured logging
_log_level = os.getenv("DJANGO_LOG_LEVEL", "INFO").upper().strip()
LOGGING = {
	"version": 1,
	"disable_existing_loggers": False,
	"formatters": {
		"standard": {
			"format": "%(asctime)s %(levelname)s %(name)s request_id=%(request_id)s category=%(log_category)s path=%(request_path)s %(message)s",
		}
	},
	"filters": {
		"exclude_health_access": {
			"()": "apps.core.logging_filters.ExcludeHealthCheckAccessFilter",
		},
		"request_context": {
			"()": "apps.core.logging_filters.RequestContextLogFilter",
		},
		"exclude_bot_scan_404": {
			"()": "apps.core.logging_filters.ExcludeCommonBotScan404Filter",
		},
		"exclude_unread_unauthorized": {
			"()": "apps.core.logging_filters.ExcludeUnreadCountUnauthorizedFilter",
		},
	},
	"handlers": {
		"console": {
			"class": "logging.StreamHandler",
			"formatter": "standard",
			"filters": ["request_context", "exclude_bot_scan_404", "exclude_unread_unauthorized"],
		}
	},
	"root": {"handlers": ["console"], "level": _log_level},
	"loggers": {
		"django.request": {"handlers": ["console"], "level": _log_level, "propagate": False},
		"django.security": {"handlers": ["console"], "level": _log_level, "propagate": False},
		"uvicorn.access": {
			"handlers": ["console"],
			"level": "INFO",
			"propagate": False,
			"filters": ["exclude_health_access"],
		},
		"nawafeth.bot_scan": {"handlers": ["console"], "level": "INFO", "propagate": False},
		"nawafeth.polling": {"handlers": ["console"], "level": _log_level, "propagate": False},
		"nawafeth.db": {"handlers": ["console"], "level": _log_level, "propagate": False},
		"nawafeth.auth": {"handlers": ["console"], "level": _log_level, "propagate": False},
	},
}
