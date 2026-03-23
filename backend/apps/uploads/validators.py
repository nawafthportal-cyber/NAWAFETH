from __future__ import annotations

import mimetypes
import ntpath
import posixpath
import re
import uuid
from pathlib import Path

from django.core.exceptions import ValidationError


IMAGE_EXTENSIONS = frozenset({".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg"})
VIDEO_EXTENSIONS = frozenset({".mp4", ".mov", ".avi", ".webm", ".mkv", ".m4v"})
AUDIO_EXTENSIONS = frozenset({".aac", ".mp3", ".wav", ".ogg", ".m4a"})
DOCUMENT_EXTENSIONS = frozenset({".pdf", ".doc", ".docx", ".txt", ".csv", ".xlsx"})

IMAGE_MIME_TYPES = frozenset(
    {
        "image/jpeg",
        "image/png",
        "image/gif",
        "image/webp",
        "image/svg+xml",
    }
)
VIDEO_MIME_TYPES = frozenset(
    {
        "video/mp4",
        "video/quicktime",
        "video/x-msvideo",
        "video/webm",
        "video/x-matroska",
        "video/mp4v-es",
    }
)
AUDIO_MIME_TYPES = frozenset(
    {
        "audio/aac",
        "audio/mpeg",
        "audio/wav",
        "audio/x-wav",
        "audio/ogg",
        "audio/mp4",
    }
)
DOCUMENT_MIME_TYPES = frozenset(
    {
        "application/pdf",
        "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "text/plain",
        "text/csv",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    }
)

ALL_SAFE_EXTENSIONS = IMAGE_EXTENSIONS | VIDEO_EXTENSIONS | AUDIO_EXTENSIONS | DOCUMENT_EXTENSIONS
ALL_SAFE_MIME_TYPES = IMAGE_MIME_TYPES | VIDEO_MIME_TYPES | AUDIO_MIME_TYPES | DOCUMENT_MIME_TYPES

_UNSAFE_FILENAME_CHARS = re.compile(r"[^A-Za-z0-9._-]+")


def _content_type_only(content_type: str) -> str:
    return (content_type or "").split(";", 1)[0].strip().lower()


def safe_basename(filename: str) -> str:
    raw = str(filename or "").strip()
    if not raw:
        return ""
    # Defend against mixed slash styles and path traversal attempts.
    leaf = posixpath.basename(ntpath.basename(raw))
    return leaf.strip()


def _safe_stem(stem: str, *, fallback: str = "upload") -> str:
    cleaned = _UNSAFE_FILENAME_CHARS.sub("_", (stem or "").strip())
    cleaned = cleaned.strip("._-")
    return cleaned[:50] or fallback


def build_safe_upload_name(filename: str, *, prefix: str = "upload") -> str:
    leaf = safe_basename(filename)
    ext = Path(leaf).suffix.lower()
    stem = _safe_stem(Path(leaf).stem, fallback=prefix)
    return f"{prefix}_{stem}_{uuid.uuid4().hex[:12]}{ext}"


def validate_user_file_size(file_obj, max_mb: int):
    size_limit = max(1, int(max_mb or 1)) * 1024 * 1024
    if (getattr(file_obj, "size", 0) or 0) > size_limit:
        raise ValidationError(f"الملف كبير جدًا. الحد الأقصى {max_mb}MB")


def validate_secure_upload(
    file_obj,
    *,
    allowed_extensions: set[str] | frozenset[str] | None = None,
    allowed_mime_types: set[str] | frozenset[str] | None = None,
    max_size_mb: int = 50,
    rename: bool = False,
    rename_prefix: str = "upload",
) -> str:
    if file_obj is None:
        return ""

    raw_name = str(getattr(file_obj, "name", "") or "")
    leaf = safe_basename(raw_name)
    if not leaf:
        raise ValidationError("اسم الملف غير صالح.")
    if leaf != raw_name:
        raise ValidationError("اسم الملف غير صالح.")

    ext = Path(leaf).suffix.lower()
    if not ext:
        raise ValidationError("امتداد الملف مطلوب.")

    allowed_extensions = set(allowed_extensions or ALL_SAFE_EXTENSIONS)
    if ext not in allowed_extensions:
        raise ValidationError("امتداد الملف غير مسموح.")

    validate_user_file_size(file_obj, max_size_mb)

    allowed_mime_types = set(allowed_mime_types or ALL_SAFE_MIME_TYPES)
    content_type = _content_type_only(getattr(file_obj, "content_type", "") or "")
    guessed_content_type, _ = mimetypes.guess_type(leaf)
    guessed_content_type = _content_type_only(guessed_content_type or "")

    if content_type and content_type not in allowed_mime_types:
        raise ValidationError("نوع الملف غير مسموح.")
    if guessed_content_type and guessed_content_type not in allowed_mime_types:
        raise ValidationError("نوع الملف غير مسموح.")

    # Ensure the stored name never keeps user-supplied path fragments.
    if rename:
        file_obj.name = build_safe_upload_name(leaf, prefix=rename_prefix)
    else:
        file_obj.name = leaf
    return file_obj.name
