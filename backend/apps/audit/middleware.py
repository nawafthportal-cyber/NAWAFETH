from __future__ import annotations

import logging
import re

from apps.audit.models import AuditAction
from apps.audit.services import log_action


logger = logging.getLogger(__name__)
_FILENAME_RE = re.compile(r'filename="(?P<name>[^"]+)"')
_EXPORT_PATH_PREFIXES = ("/dashboard/", "/api/analytics/", "/extras-portal/")


def _is_attachment_response(response) -> bool:
    disposition = str(response.get("Content-Disposition", "") or "").lower()
    return "attachment;" in disposition


def _extract_filename(response) -> str:
    disposition = str(response.get("Content-Disposition", "") or "")
    match = _FILENAME_RE.search(disposition)
    return (match.group("name") if match else "").strip()


def _detect_export_format(response, filename: str) -> str:
    content_type = str(response.get("Content-Type", "") or "").lower()
    if filename.endswith(".csv") or "text/csv" in content_type:
        return "csv"
    if filename.endswith(".xlsx") or "spreadsheetml.sheet" in content_type:
        return "xlsx"
    if filename.endswith(".pdf") or "application/pdf" in content_type:
        return "pdf"
    return "binary"


class ExportAuditMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        try:
            if not _is_attachment_response(response):
                return response
            path = str(getattr(request, "path", "") or "")
            if not path.startswith(_EXPORT_PATH_PREFIXES):
                return response

            user = getattr(request, "user", None)
            if not getattr(user, "is_authenticated", False):
                return response

            filename = _extract_filename(response)
            export_format = _detect_export_format(response, filename)
            log_action(
                actor=user,
                action=AuditAction.DATA_EXPORTED,
                reference_type="export",
                reference_id=filename or path,
                request=request,
                extra={
                    "path": path,
                    "method": getattr(request, "method", ""),
                    "format": export_format,
                    "filename": filename,
                    "query": dict(getattr(request, "GET", {}) or {}),
                },
            )
        except Exception:
            logger.exception("export audit middleware failed")
        return response
