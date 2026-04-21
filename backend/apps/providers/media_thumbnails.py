import io
import os
import posixpath
import shutil
import subprocess
import tempfile
from typing import Optional

from django.core.files.base import ContentFile

from PIL import Image, ImageDraw, ImageFilter, ImageOps


def _thumbnail_filename(original_name: str) -> str:
    original = (original_name or "").replace("\\", "/")
    base = posixpath.splitext(posixpath.basename(original))[0] or "media"
    return f"{base}_thumb.jpg"


def _ffmpeg_binary() -> Optional[str]:
    return shutil.which("ffmpeg")


def _try_extract_frame_with_ffmpeg(src_path: str) -> Optional[bytes]:
    ffmpeg = _ffmpeg_binary()
    if not ffmpeg or not src_path or not os.path.exists(src_path):
        return None

    tmp = tempfile.NamedTemporaryFile(suffix=".jpg", delete=False)
    tmp.close()
    try:
        cmd = [
            ffmpeg,
            "-y",
            "-ss",
            "0.2",
            "-i",
            src_path,
            "-frames:v",
            "1",
            "-q:v",
            "3",
            tmp.name,
        ]
        proc = subprocess.run(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
            timeout=15,
        )
        if proc.returncode != 0:
            return None
        if not os.path.exists(tmp.name) or os.path.getsize(tmp.name) <= 0:
            return None
        with open(tmp.name, "rb") as fh:
            return fh.read()
    except Exception:
        return None
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass


def _build_fallback_video_poster() -> bytes:
    width, height = 960, 540
    image = Image.new("RGB", (width, height), (238, 234, 252))
    draw = ImageDraw.Draw(image)

    # Soft diagonal bands to avoid a flat placeholder.
    draw.rectangle([0, 0, width, height], fill=(236, 232, 250))
    draw.polygon([(0, 0), (width * 0.55, 0), (width * 0.18, height)], fill=(226, 219, 247))
    draw.polygon([(width, height), (width * 0.45, height), (width * 0.82, 0)], fill=(216, 206, 242))

    cx, cy = width // 2, height // 2
    radius = 64
    draw.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=(87, 63, 138))
    draw.polygon(
        [(cx - 14, cy - 24), (cx - 14, cy + 24), (cx + 28, cy)],
        fill=(255, 255, 255),
    )

    # Minimal text without custom fonts (keeps dependency simple).
    label = "VIDEO"
    tw = 6 * len(label)
    draw.rounded_rectangle(
        [cx - tw - 20, cy + 86, cx + tw + 20, cy + 120],
        radius=14,
        fill=(255, 255, 255),
    )
    draw.text((cx - tw, cy + 93), label, fill=(87, 63, 138))

    out = io.BytesIO()
    image.save(out, format="JPEG", quality=88, optimize=True)
    return out.getvalue()


def _image_thumb_dimensions(instance) -> tuple[int, int]:
    model_name = str(getattr(getattr(instance, "_meta", None), "model_name", "") or "").strip().lower()
    if model_name == "providerspotlightitem":
        return (720, 1280)  # 9:16 for spotlight/reels surfaces.
    return (800, 1000)  # 4:5 for portfolio showcase cards.


def _build_image_cover_thumbnail(file_field, *, width: int, height: int) -> Optional[bytes]:
    if not file_field:
        return None
    source_handle = None
    try:
        source_handle = file_field.open("rb")
        with Image.open(source_handle) as source_image:
            prepared = ImageOps.exif_transpose(source_image).convert("RGB")
            resampling_attr = getattr(Image, "Resampling", None)
            resample = resampling_attr.LANCZOS if resampling_attr else getattr(Image, "LANCZOS", Image.BICUBIC)
            canvas_w, canvas_h = int(width), int(height)

            # Keep the full media visible: foreground uses contain (no crop).
            contained = ImageOps.contain(prepared, (canvas_w, canvas_h), method=resample)

            # Fill remaining space using a blurred version of the same image.
            background = ImageOps.fit(prepared, (canvas_w, canvas_h), method=resample, centering=(0.5, 0.5))
            background = background.filter(ImageFilter.GaussianBlur(radius=18))
            background = Image.blend(background, Image.new("RGB", (canvas_w, canvas_h), (18, 20, 26)), alpha=0.16)

            offset_x = (canvas_w - contained.width) // 2
            offset_y = (canvas_h - contained.height) // 2
            background.paste(contained, (offset_x, offset_y))
            out = io.BytesIO()
            background.save(out, format="JPEG", quality=86, optimize=True, progressive=True)
            return out.getvalue()
    except Exception:
        return None
    finally:
        if source_handle is not None:
            try:
                source_handle.close()
            except Exception:
                pass


def ensure_media_thumbnail(instance, *, force: bool = False) -> bool:
    """Best-effort thumbnail generation for portfolio/spotlight image and video items.

    Returns True when a thumbnail is saved, otherwise False.
    Never raises to avoid breaking upload flows.
    """
    try:
        file_type = str(getattr(instance, "file_type", "") or "").strip().lower()
        if file_type not in {"image", "video"}:
            return False
        if not getattr(instance, "file", None):
            return False
        thumb_field = getattr(instance, "thumbnail", None)
        if thumb_field is None:
            return False
        existing_name = (getattr(thumb_field, "name", "") or "").strip()
        if existing_name and not force:
            try:
                if thumb_field.storage.exists(existing_name):
                    return False
            except Exception:
                return False

        payload = None
        if file_type == "image":
            width, height = _image_thumb_dimensions(instance)
            payload = _build_image_cover_thumbnail(getattr(instance, "file", None), width=width, height=height)
        else:
            src_path = None
            try:
                src_path = instance.file.path
            except Exception:
                src_path = None
            payload = _try_extract_frame_with_ffmpeg(src_path) or _build_fallback_video_poster()

        if not payload:
            return False

        storage_name = _thumbnail_filename(getattr(instance.file, "name", ""))
        if existing_name and existing_name != storage_name:
            try:
                thumb_field.delete(save=False)
            except Exception:
                pass
        thumb_field.save(storage_name, ContentFile(payload), save=False)
        instance.save(update_fields=["thumbnail"])
        return True
    except Exception:
        return False


def ensure_video_thumbnail(instance, *, force: bool = False) -> bool:
    """Best-effort thumbnail generation for ProviderPortfolio/Spotlight video items.

    Returns True when a thumbnail is saved, otherwise False.
    Never raises to avoid breaking upload flows.
    """
    return ensure_media_thumbnail(instance, force=force) if getattr(instance, "file_type", None) == "video" else False
