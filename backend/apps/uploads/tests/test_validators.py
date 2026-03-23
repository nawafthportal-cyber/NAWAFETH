import pytest
from django.core.exceptions import ValidationError
from django.core.files.uploadedfile import SimpleUploadedFile

from apps.uploads.validators import (
    DOCUMENT_EXTENSIONS,
    DOCUMENT_MIME_TYPES,
    validate_secure_upload,
)


pytestmark = pytest.mark.django_db


def test_validate_secure_upload_blocks_path_traversal_name():
    class DummyUpload:
        def __init__(self):
            self.name = "../secret.pdf"
            self.size = len(b"fake-pdf")
            self.content_type = "application/pdf"

    file_obj = DummyUpload()
    with pytest.raises(ValidationError):
        validate_secure_upload(
            file_obj,
            allowed_extensions=DOCUMENT_EXTENSIONS,
            allowed_mime_types=DOCUMENT_MIME_TYPES,
            max_size_mb=5,
        )


def test_validate_secure_upload_can_rename_file_safely():
    file_obj = SimpleUploadedFile(
        "my report.pdf",
        b"fake-pdf",
        content_type="application/pdf",
    )
    new_name = validate_secure_upload(
        file_obj,
        allowed_extensions=DOCUMENT_EXTENSIONS,
        allowed_mime_types=DOCUMENT_MIME_TYPES,
        max_size_mb=5,
        rename=True,
        rename_prefix="doc",
    )
    assert new_name.startswith("doc_")
    assert new_name.endswith(".pdf")
    assert "/" not in new_name
    assert "\\" not in new_name
