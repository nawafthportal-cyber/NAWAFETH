from __future__ import annotations

import logging
import uuid

from django.http import HttpResponseNotFound

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
