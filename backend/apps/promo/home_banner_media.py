from __future__ import annotations

from io import BytesIO
import os
import shutil
import subprocess
import tempfile

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.files.uploadedfile import SimpleUploadedFile

from PIL import Image, ImageOps, UnidentifiedImageError

from .validators import validate_home_banner_media_dimensions


def home_banner_required_dimensions() -> tuple[int, int]:
    raw = getattr(settings, "PROMO_HOME_BANNER_REQUIRED_DIMENSIONS", (1920, 840))
    try:
        width = int(raw[0])
        height = int(raw[1])
    except Exception:
        return (1920, 840)
    if width <= 0 or height <= 0:
        return (1920, 840)
    return (width, height)


def is_home_banner_dimensions_error(exc: Exception) -> bool:
    text = str(exc or "")
    return "الأبعاد المعتمدة" in text and "بنر الصفحة الرئيسية" in text


def transcode_home_banner_image_to_required_dims(file_obj):
    source_name = str(getattr(file_obj, "name", "banner-image") or "banner-image")
    required_width, required_height = home_banner_required_dimensions()

    try:
        file_obj.seek(0)
    except Exception:
        pass

    try:
        with Image.open(file_obj) as source_image:
            source_image.load()
            has_alpha = source_image.mode in {"RGBA", "LA"} or (
                source_image.mode == "P" and "transparency" in source_image.info
            )
            prepared_image = source_image.convert("RGBA" if has_alpha else "RGB")
    except (UnidentifiedImageError, OSError) as exc:
        raise ValidationError("تعذر معالجة صورة البنر تلقائياً. تأكد أن الملف صورة صالحة.") from exc
    finally:
        try:
            file_obj.seek(0)
        except Exception:
            pass

    resampling_attr = getattr(Image, "Resampling", None)
    resample_filter = resampling_attr.LANCZOS if resampling_attr else getattr(Image, "LANCZOS", Image.BICUBIC)
    try:
        contained_image = ImageOps.contain(prepared_image, (required_width, required_height), method=resample_filter)
    except TypeError:
        contained_image = ImageOps.contain(prepared_image, (required_width, required_height))

    target_mode = "RGBA" if prepared_image.mode == "RGBA" else "RGB"
    target_background = (15, 23, 42, 255) if target_mode == "RGBA" else (15, 23, 42)
    canvas = Image.new(target_mode, (required_width, required_height), target_background)
    offset = (
        (required_width - contained_image.width) // 2,
        (required_height - contained_image.height) // 2,
    )
    if target_mode == "RGBA":
        canvas.paste(contained_image, offset, contained_image)
    else:
        canvas.paste(contained_image, offset)

    output = BytesIO()
    if target_mode == "RGBA":
        canvas.save(output, format="PNG", optimize=True)
        content_type = "image/png"
        output_ext = ".png"
    else:
        canvas.save(output, format="JPEG", quality=92, optimize=True)
        content_type = "image/jpeg"
        output_ext = ".jpg"

    transformed_bytes = output.getvalue()
    if not transformed_bytes:
        raise ValidationError("فشل تجهيز صورة البنر بعد المعالجة.")

    base_name, _ = os.path.splitext(source_name)
    target_name = f"{base_name or 'banner-image'}-fit{output_ext}"
    return SimpleUploadedFile(target_name, transformed_bytes, content_type=content_type)


def transcode_home_banner_video_to_required_dims(file_obj):
    ffmpeg_bin = shutil.which("ffmpeg")
    if not ffmpeg_bin:
        raise ValidationError(
            "لا يمكن معالجة فيديو البنر تلقائياً لأن ffmpeg غير متوفر على الخادم. "
            "يرجى رفع فيديو MP4 بالأبعاد المعتمدة 1920x840 أو تفعيل ffmpeg على بيئة التشغيل."
        )

    source_name = str(getattr(file_obj, "name", "banner-video.mp4") or "banner-video.mp4")
    source_bytes = file_obj.read()
    try:
        file_obj.seek(0)
    except Exception:
        pass

    if not source_bytes:
        raise ValidationError("ملف الفيديو المرفوع فارغ أو غير صالح.")

    required_width, required_height = home_banner_required_dimensions()
    with tempfile.TemporaryDirectory(prefix="promo-home-banner-") as tmp_dir:
        input_path = os.path.join(tmp_dir, "input.mp4")
        output_path = os.path.join(tmp_dir, "output.mp4")

        with open(input_path, "wb") as handle:
            handle.write(source_bytes)

        filter_expr = (
            f"scale={required_width}:{required_height}:force_original_aspect_ratio=decrease,"
            f"pad={required_width}:{required_height}:(ow-iw)/2:(oh-ih)/2:color=black"
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
            "20",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            "-c:a",
            "aac",
            output_path,
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0 or not os.path.exists(output_path):
            raise ValidationError(
                "تعذر ضبط أبعاد فيديو البنر تلقائياً. "
                "يرجى رفع فيديو MP4 بالأبعاد المعتمدة 1920x840."
            )

        with open(output_path, "rb") as output_handle:
            transformed_bytes = output_handle.read()

    if not transformed_bytes:
        raise ValidationError("فشل تجهيز فيديو البنر بعد المعالجة.")

    base_name, _ = os.path.splitext(source_name)
    target_name = f"{base_name or 'banner-video'}-fit.mp4"
    return SimpleUploadedFile(target_name, transformed_bytes, content_type="video/mp4")


def maybe_autofit_home_banner_image(file_obj, *, asset_type: str, required_validation: bool):
    if not required_validation:
        return file_obj
    if str(asset_type or "").strip().lower() != "image":
        return file_obj

    try:
        validate_home_banner_media_dimensions(file_obj, asset_type="image")
        return file_obj
    except ValidationError as exc:
        if not is_home_banner_dimensions_error(exc):
            raise
        return transcode_home_banner_image_to_required_dims(file_obj)


def maybe_autofit_home_banner_video(file_obj, *, asset_type: str, required_validation: bool):
    if not required_validation:
        return file_obj
    if str(asset_type or "").strip().lower() != "video":
        return file_obj
    if not bool(getattr(settings, "PROMO_HOME_BANNER_VIDEO_AUTOFIT", False)):
        return file_obj

    try:
        validate_home_banner_media_dimensions(file_obj, asset_type="video")
        return file_obj
    except ValidationError as exc:
        if not is_home_banner_dimensions_error(exc):
            raise
        return transcode_home_banner_video_to_required_dims(file_obj)


def normalize_home_banner_media_upload(file_obj, *, asset_type: str, required_validation: bool):
    normalized = maybe_autofit_home_banner_image(
        file_obj,
        asset_type=asset_type,
        required_validation=required_validation,
    )
    return maybe_autofit_home_banner_video(
        normalized,
        asset_type=asset_type,
        required_validation=required_validation,
    )
