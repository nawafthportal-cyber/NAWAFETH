from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from io import BytesIO
from pathlib import Path

from django.conf import settings
from django.core.files.uploadedfile import SimpleUploadedFile

from PIL import Image, ImageOps, UnidentifiedImageError

from .validators import (
    AUDIO_EXTENSIONS,
    DOCUMENT_EXTENSIONS,
    IMAGE_EXTENSIONS,
    VIDEO_EXTENSIONS,
)


def _bool_setting(name: str, default: bool) -> bool:
    return bool(getattr(settings, name, default))


def _int_setting(name: str, default: int, *, minimum: int, maximum: int) -> int:
    raw = getattr(settings, name, default)
    try:
        parsed = int(raw)
    except Exception:
        parsed = int(default)
    return max(minimum, min(parsed, maximum))


def _float_setting(name: str, default: float, *, minimum: float, maximum: float) -> float:
    raw = getattr(settings, name, default)
    try:
        parsed = float(raw)
    except Exception:
        parsed = float(default)
    return max(minimum, min(parsed, maximum))


def _content_type_only(content_type: str) -> str:
    return (content_type or "").split(";", 1)[0].strip().lower()


def _suffix(uploaded_file) -> str:
    return Path(str(getattr(uploaded_file, "name", "") or "")).suffix.lower()


def infer_media_kind(uploaded_file, declared_type: str | None = None) -> str:
    declared = str(declared_type or "").strip().lower()
    if declared in {"image", "video", "audio", "document", "file"}:
        return "document" if declared == "file" else declared

    content_type = _content_type_only(str(getattr(uploaded_file, "content_type", "") or ""))
    if content_type.startswith("image/"):
        return "image"
    if content_type.startswith("video/"):
        return "video"
    if content_type.startswith("audio/"):
        return "audio"

    ext = _suffix(uploaded_file)
    if ext in IMAGE_EXTENSIONS:
        return "image"
    if ext in VIDEO_EXTENSIONS:
        return "video"
    if ext in AUDIO_EXTENSIONS:
        return "audio"
    if ext in DOCUMENT_EXTENSIONS:
        return "document"
    return ""


def _safe_seek_start(uploaded_file) -> None:
    try:
        uploaded_file.seek(0)
    except Exception:
        pass


def _optimized_name(source_name: str, target_ext: str, *, force_suffix: bool = False) -> str:
    source = Path(str(source_name or "").strip() or "upload")
    stem = source.stem or "upload"
    source_ext = source.suffix.lower()
    if source_ext == target_ext and not force_suffix:
        return source.name
    return f"{stem}-opt{target_ext}"


def _image_quality_steps(start: int, minimum: int) -> list[int]:
    current = max(minimum, min(start, 95))
    values: list[int] = []
    while current >= minimum:
        values.append(current)
        if current == minimum:
            break
        current = max(minimum, current - 6)
    return values


def _has_alpha(image: Image.Image) -> bool:
    if image.mode in {"RGBA", "LA"}:
        return True
    return image.mode == "P" and "transparency" in image.info


def _image_target_format(ext: str, has_alpha: bool) -> tuple[str, str, str]:
    if ext in {".jpg", ".jpeg"}:
        return ("JPEG", ".jpg", "image/jpeg")
    if ext == ".webp":
        return ("WEBP", ".webp", "image/webp")
    if ext == ".png" or has_alpha:
        return ("PNG", ".png", "image/png")
    return ("JPEG", ".jpg", "image/jpeg")


def _save_image_bytes(image: Image.Image, fmt: str, quality: int | None = None) -> bytes:
    output = BytesIO()
    if fmt == "JPEG":
        image.save(output, format="JPEG", quality=int(quality or 88), optimize=True, progressive=True)
    elif fmt == "WEBP":
        image.save(output, format="WEBP", quality=int(quality or 86), method=6)
    else:
        image.save(output, format="PNG", optimize=True, compress_level=9)
    return output.getvalue()


def _optimize_image(uploaded_file):
    source_name = str(getattr(uploaded_file, "name", "") or "upload")
    source_size = int(getattr(uploaded_file, "size", 0) or 0)
    ext = _suffix(uploaded_file)

    if ext in {".svg", ".gif"}:
        return uploaded_file

    min_input_bytes = _int_setting(
        "MEDIA_IMAGE_OPTIMIZE_MIN_BYTES",
        350 * 1024,
        minimum=32 * 1024,
        maximum=20 * 1024 * 1024,
    )
    max_input_bytes = _int_setting(
        "MEDIA_IMAGE_OPTIMIZE_MAX_INPUT_BYTES",
        40 * 1024 * 1024,
        minimum=256 * 1024,
        maximum=500 * 1024 * 1024,
    )
    if source_size and source_size < min_input_bytes:
        return uploaded_file
    if source_size and source_size > max_input_bytes:
        return uploaded_file

    _safe_seek_start(uploaded_file)
    try:
        with Image.open(uploaded_file) as source_image:
            prepared = ImageOps.exif_transpose(source_image)
            has_alpha = _has_alpha(prepared)
            working = prepared.convert("RGBA" if has_alpha else "RGB")
    except (UnidentifiedImageError, OSError):
        _safe_seek_start(uploaded_file)
        return uploaded_file

    original_width, original_height = working.size
    max_dimension = _int_setting("MEDIA_IMAGE_MAX_DIMENSION", 2560, minimum=512, maximum=12000)
    resized = False
    if original_width > max_dimension or original_height > max_dimension:
        resized = True
        resampling_attr = getattr(Image, "Resampling", None)
        resample = resampling_attr.LANCZOS if resampling_attr else getattr(Image, "LANCZOS", Image.BICUBIC)
        working.thumbnail((max_dimension, max_dimension), resample)

    fmt, output_ext, content_type = _image_target_format(ext, has_alpha)
    quality_start = _int_setting("MEDIA_IMAGE_QUALITY_START", 90, minimum=70, maximum=95)
    quality_min = _int_setting("MEDIA_IMAGE_QUALITY_MIN", 80, minimum=60, maximum=quality_start)
    target_bytes = _int_setting(
        "MEDIA_IMAGE_TARGET_BYTES",
        1200 * 1024,
        minimum=250 * 1024,
        maximum=10 * 1024 * 1024,
    )

    best_payload = b""
    best_size = source_size if source_size > 0 else 2**31 - 1
    if fmt in {"JPEG", "WEBP"}:
        for quality in _image_quality_steps(quality_start, quality_min):
            try:
                payload = _save_image_bytes(working, fmt, quality=quality)
            except Exception:
                _safe_seek_start(uploaded_file)
                return uploaded_file
            payload_size = len(payload)
            if payload_size and payload_size < best_size:
                best_payload = payload
                best_size = payload_size
            if payload_size and payload_size <= target_bytes:
                break
    else:
        try:
            best_payload = _save_image_bytes(working, fmt)
        except Exception:
            _safe_seek_start(uploaded_file)
            return uploaded_file
        best_size = len(best_payload)

    if not best_payload:
        _safe_seek_start(uploaded_file)
        return uploaded_file

    if source_size <= 0:
        source_size = int(best_size)
    min_ratio = _float_setting("MEDIA_IMAGE_MIN_SAVINGS_RATIO", 0.06, minimum=0.0, maximum=0.8)
    savings_ratio = ((source_size - best_size) / float(source_size)) if source_size > 0 else 0.0
    if best_size >= source_size:
        _safe_seek_start(uploaded_file)
        return uploaded_file
    if not resized and savings_ratio < min_ratio:
        _safe_seek_start(uploaded_file)
        return uploaded_file

    _safe_seek_start(uploaded_file)
    target_name = _optimized_name(source_name, output_ext, force_suffix=output_ext != ext)
    return SimpleUploadedFile(target_name, best_payload, content_type=content_type)


def _resolve_ffmpeg_binary() -> str:
    ffmpeg_bin = shutil.which("ffmpeg")
    if ffmpeg_bin:
        return ffmpeg_bin
    try:
        from imageio_ffmpeg import get_ffmpeg_exe
    except Exception:
        return ""
    try:
        return str(get_ffmpeg_exe() or "")
    except Exception:
        return ""


def _stream_uploaded_file(uploaded_file, target_path: str) -> int:
    written = 0
    _safe_seek_start(uploaded_file)
    with open(target_path, "wb") as handle:
        chunks = getattr(uploaded_file, "chunks", None)
        if callable(chunks):
            for chunk in chunks():
                if not chunk:
                    continue
                handle.write(chunk)
                written += len(chunk)
        else:
            while True:
                chunk = uploaded_file.read(1024 * 1024)
                if not chunk:
                    break
                handle.write(chunk)
                written += len(chunk)
    _safe_seek_start(uploaded_file)
    return written


def _optimize_video(uploaded_file):
    ffmpeg_bin = _resolve_ffmpeg_binary()
    if not ffmpeg_bin:
        return uploaded_file

    source_name = str(getattr(uploaded_file, "name", "") or "video.mp4")
    source_size = int(getattr(uploaded_file, "size", 0) or 0)

    min_mb = _int_setting("MEDIA_VIDEO_OPTIMIZE_MIN_MB", 10, minimum=1, maximum=200)
    max_mb = _int_setting("MEDIA_VIDEO_OPTIMIZE_MAX_MB", 80, minimum=5, maximum=500)
    timeout_seconds = _int_setting("MEDIA_VIDEO_OPTIMIZE_TIMEOUT_SECONDS", 60, minimum=10, maximum=600)
    max_width = _int_setting("MEDIA_VIDEO_MAX_WIDTH", 1920, minimum=320, maximum=7680)
    max_height = _int_setting("MEDIA_VIDEO_MAX_HEIGHT", 1080, minimum=240, maximum=4320)
    crf = _int_setting("MEDIA_VIDEO_OPTIMIZE_CRF", 22, minimum=18, maximum=35)
    min_ratio = _float_setting("MEDIA_VIDEO_MIN_SAVINGS_RATIO", 0.1, minimum=0.0, maximum=0.8)

    if source_size and source_size < min_mb * 1024 * 1024:
        return uploaded_file
    if source_size and source_size > max_mb * 1024 * 1024:
        return uploaded_file

    with tempfile.TemporaryDirectory(prefix="upload-video-opt-") as tmp_dir:
        input_ext = _suffix(uploaded_file) or ".mp4"
        input_path = os.path.join(tmp_dir, f"input{input_ext}")
        output_path = os.path.join(tmp_dir, "output.mp4")

        written = _stream_uploaded_file(uploaded_file, input_path)
        if written <= 0:
            return uploaded_file
        if written < min_mb * 1024 * 1024:
            return uploaded_file
        if written > max_mb * 1024 * 1024:
            return uploaded_file

        filter_expr = (
            f"scale='min({max_width},iw)':'min({max_height},ih)':force_original_aspect_ratio=decrease,"
            "scale=trunc(iw/2)*2:trunc(ih/2)*2"
        )
        cmd = [
            ffmpeg_bin,
            "-y",
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            input_path,
            "-vf",
            filter_expr,
            "-c:v",
            "libx264",
            "-preset",
            "veryfast",
            "-crf",
            str(crf),
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            "-c:a",
            "aac",
            "-b:a",
            "128k",
            output_path,
        ]
        try:
            process = subprocess.run(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
                timeout=timeout_seconds,
            )
        except Exception:
            return uploaded_file
        if process.returncode != 0 or not os.path.exists(output_path):
            return uploaded_file

        output_size = os.path.getsize(output_path)
        if output_size <= 0:
            return uploaded_file
        if source_size > 0:
            savings_ratio = (source_size - output_size) / float(source_size)
            if savings_ratio < min_ratio:
                return uploaded_file

        with open(output_path, "rb") as handle:
            payload = handle.read()

    if not payload:
        return uploaded_file
    target_name = _optimized_name(source_name, ".mp4", force_suffix=True)
    return SimpleUploadedFile(target_name, payload, content_type="video/mp4")


def optimize_upload_for_storage(uploaded_file, *, declared_type: str | None = None):
    if uploaded_file is None:
        return uploaded_file
    if not _bool_setting("MEDIA_UPLOAD_OPTIMIZATION_ENABLED", True):
        return uploaded_file

    media_kind = infer_media_kind(uploaded_file, declared_type=declared_type)
    if media_kind == "image" and _bool_setting("MEDIA_IMAGE_OPTIMIZATION_ENABLED", True):
        return _optimize_image(uploaded_file)
    if media_kind == "video" and _bool_setting("MEDIA_VIDEO_OPTIMIZATION_ENABLED", True):
        return _optimize_video(uploaded_file)
    return uploaded_file
