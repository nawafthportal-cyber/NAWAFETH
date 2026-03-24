from __future__ import annotations

from pathlib import Path

from django.conf import settings
from django.core.exceptions import ValidationError

from PIL import Image, UnidentifiedImageError

from apps.uploads.validators import (
    DOCUMENT_EXTENSIONS,
    DOCUMENT_MIME_TYPES,
    IMAGE_EXTENSIONS,
    IMAGE_MIME_TYPES,
    VIDEO_EXTENSIONS,
    VIDEO_MIME_TYPES,
    validate_secure_upload,
)

MAX_FILE_SIZE_MB = 100
MAX_FILE_SIZE = MAX_FILE_SIZE_MB * 1024 * 1024

ALLOWED_EXT = {".jpg", ".jpeg", ".png", ".mp4", ".pdf"}

_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png"}
_VIDEO_EXTENSIONS = {".mp4"}


def _home_banner_required_dimensions() -> tuple[int, int]:
    raw = getattr(settings, "PROMO_HOME_BANNER_REQUIRED_DIMENSIONS", (1920, 840))
    try:
        width = int(raw[0])
        height = int(raw[1])
    except Exception:
        return (1920, 840)
    if width <= 0 or height <= 0:
        return (1920, 840)
    return (width, height)


def _detect_media_kind(file_obj, declared_asset_type: str | None = None) -> str | None:
    normalized_declared = str(declared_asset_type or "").strip().lower()
    if normalized_declared in {"image", "video"}:
        return normalized_declared

    content_type = str(getattr(file_obj, "content_type", "") or "").strip().lower()
    if content_type.startswith("image/"):
        return "image"
    if content_type.startswith("video/"):
        return "video"

    ext = Path(str(getattr(file_obj, "name", "") or "")).suffix.lower()
    if ext in _IMAGE_EXTENSIONS:
        return "image"
    if ext in _VIDEO_EXTENSIONS:
        return "video"
    return None


def _read_image_dimensions(file_obj) -> tuple[int, int]:
    start = None
    try:
        start = file_obj.tell()
    except Exception:
        start = None

    try:
        file_obj.seek(0)
        with Image.open(file_obj) as img:
            width, height = img.size
    except UnidentifiedImageError as exc:
        raise ValidationError("تعذر قراءة أبعاد الصورة. تأكد أن الملف صورة صالحة.") from exc
    finally:
        try:
            if start is not None:
                file_obj.seek(start)
            else:
                file_obj.seek(0)
        except Exception:
            pass

    return int(width), int(height)


def _iter_mp4_boxes(file_obj, start: int, end: int):
    cursor = int(start)
    while cursor + 8 <= end:
        file_obj.seek(cursor)
        header = file_obj.read(8)
        if len(header) < 8:
            return

        size = int.from_bytes(header[:4], "big", signed=False)
        box_type = header[4:8].decode("latin-1", errors="ignore")
        header_size = 8

        if size == 1:
            ext_size = file_obj.read(8)
            if len(ext_size) < 8:
                return
            size = int.from_bytes(ext_size, "big", signed=False)
            header_size = 16
        elif size == 0:
            size = end - cursor

        if size < header_size:
            return

        box_end = cursor + size
        if box_end > end or box_end <= cursor:
            return

        yield box_type, cursor + header_size, box_end
        cursor = box_end


def _read_mp4_tkhd_dimensions(file_obj) -> tuple[int, int] | None:
    origin = None
    try:
        origin = file_obj.tell()
    except Exception:
        origin = None

    try:
        file_obj.seek(0, 2)
        total_size = file_obj.tell()
        file_obj.seek(0)

        def walk(start: int, end: int):
            for box_type, payload_start, box_end in _iter_mp4_boxes(file_obj, start, end):
                if box_type == "tkhd":
                    payload_len = box_end - payload_start
                    if payload_len < 8:
                        continue
                    file_obj.seek(payload_start)
                    payload = file_obj.read(payload_len)
                    if len(payload) < 8:
                        continue
                    width_fixed = int.from_bytes(payload[-8:-4], "big", signed=False)
                    height_fixed = int.from_bytes(payload[-4:], "big", signed=False)
                    width = width_fixed >> 16
                    height = height_fixed >> 16
                    if width > 0 and height > 0:
                        return int(width), int(height)
                elif box_type in {"moov", "trak", "mdia", "minf", "stbl", "edts"}:
                    nested = walk(payload_start, box_end)
                    if nested:
                        return nested
            return None

        return walk(0, total_size)
    finally:
        try:
            if origin is not None:
                file_obj.seek(origin)
            else:
                file_obj.seek(0)
        except Exception:
            pass


def validate_home_banner_media_dimensions(file_obj, *, asset_type: str | None = None):
    media_kind = _detect_media_kind(file_obj, asset_type)
    if media_kind not in {"image", "video"}:
        raise ValidationError("بنر الصفحة الرئيسية يقبل الصور أو فيديو MP4 فقط.")

    required_width, required_height = _home_banner_required_dimensions()

    if media_kind == "image":
        width, height = _read_image_dimensions(file_obj)
    else:
        dims = _read_mp4_tkhd_dimensions(file_obj)
        if not dims:
            raise ValidationError("تعذر قراءة أبعاد فيديو MP4. تأكد من أن الملف صالح وغير تالف.")
        width, height = dims

    if width != required_width or height != required_height:
        raise ValidationError(
            f"الأبعاد المعتمدة لبنر الصفحة الرئيسية هي {required_width}x{required_height} بكسل. "
            f"تم رفع ملف بأبعاد {width}x{height}."
        )


def validate_file_size(file_obj):
    validate_secure_upload(
        file_obj,
        allowed_extensions=IMAGE_EXTENSIONS | VIDEO_EXTENSIONS | DOCUMENT_EXTENSIONS,
        allowed_mime_types=IMAGE_MIME_TYPES | VIDEO_MIME_TYPES | DOCUMENT_MIME_TYPES,
        max_size_mb=MAX_FILE_SIZE_MB,
        rename=False,
    )


def validate_extension(file_obj):
    name = (getattr(file_obj, "name", "") or "").lower()
    ext = "." + name.split(".")[-1] if "." in name else ""
    if ext and ext not in ALLOWED_EXT:
        raise ValidationError("امتداد الملف غير مسموح. المسموح: jpg, png, mp4, pdf")
