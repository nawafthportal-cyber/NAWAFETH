from .base import *  # noqa

import os

DEBUG = False

# Never allow OTP test helpers in production.
OTP_TEST_MODE = False
OTP_TEST_KEY = ""
OTP_TEST_CODE = ""

# ⚠️ OTP_APP_BYPASS: For staging/testing ONLY on Render.
# To enable (bypasses OTP verification for any 4-digit code):
# - Set environment variable OTP_APP_BYPASS=1 on Render
# - ⚠️ WARNING: This is a SECURITY RISK. Use only for testing/staging environments.
# - Remove or set to 0 before exposing to real users.
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
CORS_ALLOWED_ORIGINS = [
	"https://nawafeth.app",
	"https://admin.nawafeth.app",
	"https://nawafthportal.com",
	"https://www.nawafthportal.com",
]
CORS_ALLOWED_ORIGIN_REGEXES = [
	r"^https://[a-z0-9-]+\.onrender\.com$",
	r"^https://([a-z0-9-]+\.)?nawafthportal\.com$",
]

_cors_env = os.getenv("DJANGO_CORS_ALLOWED_ORIGINS", "").strip()
if _cors_env:
	CORS_ALLOWED_ORIGINS = [o.strip() for o in _cors_env.split(",") if o.strip()]

_cors_regex_env = os.getenv("DJANGO_CORS_ALLOWED_ORIGIN_REGEXES", "").strip()
if _cors_regex_env:
	CORS_ALLOWED_ORIGIN_REGEXES = [o.strip() for o in _cors_regex_env.split(",") if o.strip()]

# CSRF trusted origins (Render/custom domains)
_csrf_env = os.getenv("DJANGO_CSRF_TRUSTED_ORIGINS", "").strip()
CSRF_TRUSTED_ORIGINS = [
	"https://*.onrender.com",
	"https://nawafeth.app",
	"https://admin.nawafeth.app",
	"https://nawafthportal.com",
	"https://www.nawafthportal.com",
	"https://*.nawafthportal.com",
]
if _csrf_env:
	CSRF_TRUSTED_ORIGINS = [o.strip() for o in _csrf_env.split(",") if o.strip()]

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
			"format": "%(asctime)s %(levelname)s %(name)s %(message)s",
		}
	},
	"filters": {
		"exclude_health_access": {
			"()": "apps.core.logging_filters.ExcludeHealthCheckAccessFilter",
		},
		"exclude_bot_scan_404": {
			"()": "apps.core.logging_filters.ExcludeCommonBotScan404Filter",
		},
	},
	"handlers": {
		"console": {
			"class": "logging.StreamHandler",
			"formatter": "standard",
			"filters": ["exclude_bot_scan_404"],
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
	},
}
