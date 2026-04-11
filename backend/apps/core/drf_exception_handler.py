from __future__ import annotations

import logging

from django.db import DatabaseError, OperationalError, close_old_connections
from rest_framework import status
from rest_framework.exceptions import Throttled
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_exception_handler

from apps.core.db_outage import mark_database_outage, outage_retry_after_seconds
from apps.core.throttling import build_retry_after_payload, normalize_retry_after_seconds


logger = logging.getLogger(__name__)


def api_exception_handler(exc, context):
    response = drf_exception_handler(exc, context)
    if response is not None:
        if isinstance(exc, Throttled):
            detail = "تم تجاوز الحد المسموح من الطلبات"
            if isinstance(response.data, dict):
                detail = str(response.data.get("detail") or response.data.get("error") or detail)
            elif getattr(exc, "detail", None):
                detail = str(exc.detail)

            wait_seconds = normalize_retry_after_seconds(getattr(exc, "wait", None))
            response.data = build_retry_after_payload(detail, wait_seconds, code="throttled")
            if wait_seconds is not None:
                response["Retry-After"] = str(wait_seconds)
        return response

    if isinstance(exc, (OperationalError, DatabaseError)):
        close_old_connections()
        mark_database_outage(reason="drf_exception_handler", exc=exc)
        request = context.get("request") if isinstance(context, dict) else None
        path = getattr(request, "path", "") or ""
        logger.warning(
            "Database request failed; returning 503 response. error=%s",
            str(exc)[:240],
            extra={"request_path": path, "log_category": "database"},
        )
        response = Response(
            {
                "detail": "الخدمة غير متاحة مؤقتًا. يرجى المحاولة مرة أخرى بعد قليل.",
                "code": "database_unavailable",
            },
            status=status.HTTP_503_SERVICE_UNAVAILABLE,
        )
        retry_after = outage_retry_after_seconds()
        if retry_after is not None:
            response["Retry-After"] = str(retry_after)
        return response

    return None
