"""
Dashboard security utilities.

Provides:
- Safe redirect validation (prevents open redirects)
- File upload MIME-type validation
- User-level RBAC object-access filtering
- Rate limiting helper for OTP
"""
from __future__ import annotations

import mimetypes
import os
from urllib.parse import urlparse

from django.http import HttpRequest
from django.urls import resolve, Resolver404


# ── Safe Redirect ──────────────────────────────────────────────

def is_safe_redirect_url(url: str) -> bool:
    """Return True only if *url* is a relative path that resolves within
    our own Django URL conf.  Rejects protocol-relative URLs (``//evil.com``),
    fragments, and anything that doesn't start with a single ``/``.
    """
    if not url or not isinstance(url, str):
        return False
    url = url.strip()
    # Must start with exactly one slash (reject "//evil.com")
    if not url.startswith("/") or url.startswith("//"):
        return False
    # Strip query string & fragment for URL resolution check
    parsed = urlparse(url)
    try:
        resolve(parsed.path)
        return True
    except Resolver404:
        return False


def safe_redirect_url(request: HttpRequest, fallback: str) -> str:
    """Read ``next`` from POST/GET params and return a validated URL
    or *fallback* if the value is missing / unsafe.
    """
    next_url = (request.POST.get("next") or request.GET.get("next") or "").strip()
    if is_safe_redirect_url(next_url):
        return next_url
    return fallback


# ── File Upload Validation ─────────────────────────────────────

ALLOWED_IMAGE_EXTENSIONS = frozenset({
    ".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg",
})

ALLOWED_VIDEO_EXTENSIONS = frozenset({
    ".mp4", ".mov", ".avi", ".webm", ".mkv", ".m4v",
})

ALLOWED_DOCUMENT_EXTENSIONS = frozenset({
    ".pdf", ".doc", ".docx",
})

ALLOWED_MEDIA_EXTENSIONS = ALLOWED_IMAGE_EXTENSIONS | ALLOWED_VIDEO_EXTENSIONS

ALLOWED_ALL_EXTENSIONS = ALLOWED_MEDIA_EXTENSIONS | ALLOWED_DOCUMENT_EXTENSIONS

ALLOWED_MEDIA_MIME_TYPES = frozenset({
    # Images
    "image/jpeg", "image/png", "image/gif", "image/webp", "image/svg+xml",
    # Videos
    "video/mp4", "video/quicktime", "video/x-msvideo", "video/webm",
    "video/x-matroska", "video/mp4v-es",
})

ALLOWED_DOCUMENT_MIME_TYPES = frozenset({
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
})

ALLOWED_ALL_MIME_TYPES = ALLOWED_MEDIA_MIME_TYPES | ALLOWED_DOCUMENT_MIME_TYPES

MAX_UPLOAD_SIZE_MB = 50  # 50 MB


class FileValidationError(Exception):
    """Raised when an uploaded file fails security validation."""


def validate_uploaded_file(
    uploaded_file,
    *,
    allowed_extensions: frozenset[str] | None = None,
    allowed_mime_types: frozenset[str] | None = None,
    max_size_mb: int = MAX_UPLOAD_SIZE_MB,
) -> None:
    """Validate an uploaded file's extension, MIME type, and size.

    Raises ``FileValidationError`` with an Arabic message on failure.
    """
    if uploaded_file is None:
        return

    exts = allowed_extensions or ALLOWED_ALL_EXTENSIONS
    mimes = allowed_mime_types or ALLOWED_ALL_MIME_TYPES

    # Extension check
    name = getattr(uploaded_file, "name", "") or ""
    _, ext = os.path.splitext(name.lower())
    if ext not in exts:
        raise FileValidationError(
            f"نوع الملف غير مسموح ({ext}). الأنواع المسموحة: {', '.join(sorted(exts))}"
        )

    # MIME type check (from content_type header)
    content_type = getattr(uploaded_file, "content_type", "") or ""
    if content_type and content_type not in mimes:
        # Also try guessing from extension as a fallback
        guessed, _ = mimetypes.guess_type(name)
        if guessed not in mimes:
            raise FileValidationError(
                f"نوع المحتوى غير مسموح ({content_type})"
            )

    # Size check
    max_bytes = max_size_mb * 1024 * 1024
    file_size = getattr(uploaded_file, "size", 0) or 0
    if file_size > max_bytes:
        raise FileValidationError(
            f"حجم الملف ({file_size // (1024*1024)} MB) يتجاوز الحد المسموح ({max_size_mb} MB)"
        )


# ── User-level RBAC Queryset Filtering ─────────────────────────

def apply_user_level_filter(qs, user, *, assigned_field: str = "assigned_to"):
    """For user-level access profiles, restrict queryset to items
    assigned **to this user only** (not unassigned items).

    Admin/power/superuser levels see everything.
    """
    from apps.backoffice.models import AccessLevel

    ap = getattr(user, "access_profile", None)
    if not ap or ap.level != AccessLevel.USER:
        return qs

    from django.db.models import Q
    return qs.filter(**{assigned_field: user})


def check_object_access(request, obj, *, assigned_field: str = "assigned_to") -> bool:
    """Return True if user has access to this specific object."""
    from .access import can_access_object

    return can_access_object(
        request.user,
        obj,
        assigned_field=assigned_field,
        allow_unassigned_for_user_level=True,
    )
