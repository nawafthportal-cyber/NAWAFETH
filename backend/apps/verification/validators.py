from django.core.exceptions import ValidationError

from apps.uploads.validators import (
    DOCUMENT_EXTENSIONS,
    DOCUMENT_MIME_TYPES,
    IMAGE_EXTENSIONS,
    IMAGE_MIME_TYPES,
    validate_secure_upload,
)

MAX_FILE_SIZE_MB = 100
MAX_FILE_SIZE = MAX_FILE_SIZE_MB * 1024 * 1024

ALLOWED_EXT = {".jpg", ".jpeg", ".png", ".pdf"}


def validate_file_size(file_obj):
    validate_secure_upload(
        file_obj,
        allowed_extensions=IMAGE_EXTENSIONS | DOCUMENT_EXTENSIONS,
        allowed_mime_types=IMAGE_MIME_TYPES | DOCUMENT_MIME_TYPES,
        max_size_mb=MAX_FILE_SIZE_MB,
        rename=False,
    )


def validate_extension(file_obj):
    name = (getattr(file_obj, "name", "") or "").lower().strip()
    ext = "." + name.split(".")[-1] if "." in name else ""
    if ext and ext not in ALLOWED_EXT:
        raise ValidationError("امتداد الملف غير مسموح. المسموح: jpg, png, pdf")
