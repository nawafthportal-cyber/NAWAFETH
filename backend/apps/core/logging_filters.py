import logging


class ExcludeHealthCheckAccessFilter(logging.Filter):
    """Drop noisy access logs for health endpoints to reduce log/IO overhead."""

    def filter(self, record: logging.LogRecord) -> bool:
        message = record.getMessage()
        return '"GET /health' not in message and '"HEAD /health' not in message


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
        ):
            return False

        # uvicorn.access lines like:
        # 1.2.3.4 - "GET /api/notifications/unread-count/?mode=client HTTP/1.1" 401
        unread_notifications = '/api/notifications/unread-count/' in message
        unread_messages = '/api/messaging/direct/unread-count/' in message
        if (unread_notifications or unread_messages) and '" 401' in message:
            return False

        return True
