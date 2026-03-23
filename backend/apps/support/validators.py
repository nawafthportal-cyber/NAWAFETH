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


def validate_file_size(file_obj):
    validate_secure_upload(
        file_obj,
        allowed_extensions=IMAGE_EXTENSIONS | VIDEO_EXTENSIONS | DOCUMENT_EXTENSIONS,
        allowed_mime_types=IMAGE_MIME_TYPES | VIDEO_MIME_TYPES | DOCUMENT_MIME_TYPES,
        max_size_mb=MAX_FILE_SIZE_MB,
        rename=False,
    )
