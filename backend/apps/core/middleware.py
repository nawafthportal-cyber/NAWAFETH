from __future__ import annotations

import logging
import uuid

from django.conf import settings
from django.core.cache import cache
from django.db import DatabaseError
from django.http import HttpResponseNotFound, JsonResponse
from django.utils import timezone

from .db_outage import is_database_outage_active, outage_retry_after_seconds
from .request_context import bind_request_context, clear_request_context


def is_common_bot_scan_path(path: str) -> bool:
    normalized = (path or "").strip().lower().replace("\\", "/")
    while "//" in normalized:
        normalized = normalized.replace("//", "/")

    return (
        normalized.startswith("/wp-admin")
        or normalized.startswith("/wordpress/")
        or normalized == "/xmlrpc.php"
        or "wlwmanifest.xml" in normalized
        or normalized == "/.env"
    )


class RequestContextMiddleware:
    bot_scan_logger = logging.getLogger("nawafeth.bot_scan")

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        request_id = self._request_id(request)
        request.request_id = request_id
        token = bind_request_context(
            request_id=request_id,
            request_path=request.path_info,
        )
        try:
            if is_common_bot_scan_path(request.path_info):
                self.bot_scan_logger.info(
                    "bot_scan_blocked method=%s path=%s remote=%s ua=%s",
                    request.method,
                    request.path_info,
                    self._client_ip(request),
                    (request.META.get("HTTP_USER_AGENT", "") or "-")[:200],
                    extra={"log_category": "bot_scan"},
                )
                response = HttpResponseNotFound()
            else:
                response = self.get_response(request)
            response["X-Request-ID"] = request_id
            return response
        finally:
            clear_request_context(token)

    @staticmethod
    def _request_id(request) -> str:
        forwarded = (
            request.META.get("HTTP_X_REQUEST_ID")
            or request.META.get("HTTP_CF_RAY")
            or request.META.get("HTTP_X_AMZN_TRACE_ID")
        )
        if forwarded:
            return str(forwarded).strip()[:64]
        return uuid.uuid4().hex

    @staticmethod
    def _client_ip(request) -> str:
        forwarded = (request.META.get("HTTP_X_FORWARDED_FOR") or "").strip()
        if forwarded:
            return forwarded.split(",")[0].strip()
        return (request.META.get("REMOTE_ADDR") or "-").strip()


class DatabaseOutageShortCircuitMiddleware:
    """Return fast 503 responses for API calls while DB outage marker is active."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.method.upper() == "OPTIONS":
            return self.get_response(request)

        if not is_database_outage_active():
            return self.get_response(request)

        path = str(getattr(request, "path_info", "") or "")
        if not self._should_short_circuit(path):
            return self.get_response(request)

        response = JsonResponse(
            {
                "detail": "الخدمة غير متاحة مؤقتًا. يرجى المحاولة مرة أخرى بعد قليل.",
                "code": "database_unavailable",
                "outage_cached": True,
            },
            status=503,
        )
        retry_after = outage_retry_after_seconds()
        if retry_after is not None:
            response["Retry-After"] = str(retry_after)
        response["X-Database-Outage-Guard"] = "1"
        return response

    @staticmethod
    def _should_short_circuit(path: str) -> bool:
        # Guard admin panel: return a plain 503 instead of crashing with 500
        # when the DB is unreachable (session/auth require DB).
        if path.startswith("/admin-panel"):
            return True
        if not path.startswith("/api/"):
            return False
        if path.startswith("/api/health") or path.startswith("/api/core/health"):
            return False
        # Keep identity/session endpoints reachable even when an outage marker
        # was set by a previous transient DB error so the frontend can recover
        # its active account mode instead of looking logged out.
        if path.startswith("/api/accounts/me/"):
            return False
        if path.startswith("/api/accounts/token/refresh/"):
            return False
        if path.startswith("/api/accounts/logout/"):
            return False
        if path.startswith("/api/content/public/"):
            return False
        if path.startswith("/api/core/unread-badges/"):
            return False
        if path.startswith("/api/public/badges/"):
            return False
        if path.startswith("/api/promo/banners/home/"):
            return False
        if path.startswith("/api/promo/home-carousel/"):
            return False
        if path.startswith("/api/promo/active/"):
            return False
        if path.startswith("/api/promo/pricing/guide/"):
            return False
        if path.startswith("/api/providers/") and path.endswith("/stats/"):
            return False
        return True


class InlinePromoSchedulerMiddleware:
    """
    Lightweight fallback scheduler for promo message dispatch/expiry.

    This keeps scheduled promo delivery moving in deployments where Celery Beat
    or workers are unavailable, while remaining safe to run alongside Celery.
    """

    logger = logging.getLogger("nawafeth.promo.inline_scheduler")
    throttle_cache_key = "promo:inline_scheduler:tick"

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)

        if not getattr(settings, "PROMO_INLINE_SCHEDULER_ENABLED", True):
            return response
        if self._should_skip(request):
            return response

        try:
            self._run_due_jobs()
        except Exception:
            # This is a best-effort fallback and must never affect request flow.
            self.logger.exception("inline promo scheduler failed")
        return response

    def _should_skip(self, request) -> bool:
        method = (getattr(request, "method", "") or "").upper()
        if method == "OPTIONS":
            return True

        path = str(getattr(request, "path_info", "") or "").strip()
        if not path:
            return True
        if not path.startswith("/api/"):
            return True

        static_url = str(getattr(settings, "STATIC_URL", "/static/") or "/static/").strip()
        media_url = str(getattr(settings, "MEDIA_URL", "/media/") or "/media/").strip()
        skipped_prefixes = tuple(
            prefix
            for prefix in (
                static_url,
                media_url,
                "/healthz",
                "/api/health",
                "/api/core/health",
                "/admin/jsi18n/",
            )
            if prefix
        )
        return path.startswith(skipped_prefixes)

    def _run_due_jobs(self) -> None:
        interval_seconds = max(
            30,
            int(getattr(settings, "PROMO_INLINE_SCHEDULER_INTERVAL_SECONDS", 60) or 60),
        )
        if not cache.add(self.throttle_cache_key, timezone.now().isoformat(), timeout=interval_seconds):
            return

        try:
            from apps.promo.services import expire_due_promos, send_due_promo_messages

            now = timezone.now()
            delivered_count = send_due_promo_messages(now=now, limit=100)
            expired_count = expire_due_promos(now=now)
            if delivered_count or expired_count:
                self.logger.info(
                    "inline promo scheduler processed delivered=%s expired=%s",
                    delivered_count,
                    expired_count,
                )
        except DatabaseError:
            pass
