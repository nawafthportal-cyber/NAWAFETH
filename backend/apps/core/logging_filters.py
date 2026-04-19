import logging
import re

from .request_context import get_request_id, get_request_path


class ExcludePublicSuspiciousSessionFilter(logging.Filter):
    """Drop corrupted-session warnings for anonymous public endpoints.

    Public pages can fan out several parallel requests before the browser has a
    chance to discard an invalid session cookie, which turns one stale cookie
    into a burst of identical warnings. Keep the signal for authenticated/admin
    surfaces, but suppress it for known public routes.
    """

    _excluded_exact_paths = {
        "/",
        "/api/analytics/events/",
        "/api/content/public/",
        "/favicon.ico",
        "/robots.txt",
    }
    _excluded_prefixes = (
        "/static/",
        "/api/promo/active/",
        "/api/promo/banners/home/",
        "/api/promo/home-carousel/",
        "/api/providers/categories/",
        "/api/providers/list/",
        "/api/providers/spotlights/feed/",
    )

    def filter(self, record: logging.LogRecord) -> bool:
        if record.name != "django.security.SuspiciousSession":
            return True

        if "Session data corrupted" not in record.getMessage():
            return True

        path = str(getattr(record, "request_path", None) or get_request_path() or "")
        if not path:
            return True

        if path in self._excluded_exact_paths:
            return False
        return not path.startswith(self._excluded_prefixes)


class RequestContextLogFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = getattr(record, "request_id", None) or get_request_id()
        record.request_path = getattr(record, "request_path", None) or get_request_path()
        record.log_category = getattr(record, "log_category", None) or "-"
        return True


class ExcludeHealthCheckAccessFilter(logging.Filter):
    """Drop noisy access logs for health endpoints to reduce log/IO overhead."""

    def filter(self, record: logging.LogRecord) -> bool:
        message = record.getMessage()
        return '"GET /health' not in message and '"HEAD /health' not in message


class RedactSensitiveRequestDataFilter(logging.Filter):
    """Redact credentials and high-risk identifiers from access/error logs."""

    _patterns = (
        (re.compile(r"([?&]token=)[^&\s\"]+", re.IGNORECASE), r"\1[redacted]"),
        (re.compile(r"([?&]phone=)[^&\s\"]+", re.IGNORECASE), r"\1[redacted]"),
        (re.compile(r"\b(phone=)[0-9+]+", re.IGNORECASE), r"\1[redacted]"),
        (re.compile(r"(Authorization:\s*Bearer\s+)[A-Za-z0-9._\-]+", re.IGNORECASE), r"\1[redacted]"),
    )

    def filter(self, record: logging.LogRecord) -> bool:
        message = record.getMessage()
        redacted = message
        for pattern, replacement in self._patterns:
            redacted = pattern.sub(replacement, redacted)
        if redacted != message:
            record.msg = redacted
            record.args = ()
        return True


class ExcludeCommonBotScan404Filter(logging.Filter):
    """Drop noisy 404 probes from common internet scanners."""

    _blocked_markers = (
        "Not Found: /wp-admin/",
        "Not Found: /wordpress/wp-admin/",
        "Not Found: /wp-login.php",
        "Not Found: /xmlrpc.php",
        "Not Found: /.env",
    )

    def filter(self, record: logging.LogRecord) -> bool:
        message = record.getMessage()
        return not any(marker in message for marker in self._blocked_markers)


class ExcludeUnreadCountUnauthorizedFilter(logging.Filter):
    """Drop repetitive 401 warnings from unread counters when users are logged out."""

    def filter(self, record: logging.LogRecord) -> bool:
        message = record.getMessage()

        # django.request warning messages
        if (
            "Unauthorized: /api/notifications/unread-count/" in message
            or "Unauthorized: /api/messaging/direct/unread-count/" in message
            or "Unauthorized: /api/core/unread-badges/" in message
        ):
            return False

        # uvicorn.access lines like:
        # 1.2.3.4 - "GET /api/notifications/unread-count/?mode=client HTTP/1.1" 401
        unread_notifications = '/api/notifications/unread-count/' in message
        unread_messages = '/api/messaging/direct/unread-count/' in message
        unread_badges = '/api/core/unread-badges/' in message
        if (unread_notifications or unread_messages or unread_badges) and '" 401' in message:
            return False

        return True
