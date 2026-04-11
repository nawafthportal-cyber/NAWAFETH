from __future__ import annotations

from io import BytesIO

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import SimpleTestCase, override_settings

from PIL import Image

from .media_optimizer import optimize_upload_for_storage


def _make_jpeg(width: int, height: int, *, quality: int = 96) -> bytes:
    image = Image.new("RGB", (width, height), (240, 120, 70))
    payload = BytesIO()
    image.save(payload, format="JPEG", quality=quality)
    return payload.getvalue()


class MediaOptimizerTests(SimpleTestCase):
    @override_settings(
        MEDIA_UPLOAD_OPTIMIZATION_ENABLED=True,
        MEDIA_IMAGE_OPTIMIZATION_ENABLED=True,
        MEDIA_IMAGE_OPTIMIZE_MIN_BYTES=1,
        MEDIA_IMAGE_MAX_DIMENSION=900,
        MEDIA_IMAGE_MIN_SAVINGS_RATIO=0.0,
    )
    def test_optimize_large_jpeg(self):
        original_payload = _make_jpeg(2600, 1800, quality=96)
        uploaded = SimpleUploadedFile("profile.jpg", original_payload, content_type="image/jpeg")

        optimized = optimize_upload_for_storage(uploaded, declared_type="image")

        self.assertIsNotNone(optimized)
        self.assertTrue(str(getattr(optimized, "name", "") or "").endswith(".jpg"))
        self.assertLess(int(getattr(optimized, "size", 0) or 0), len(original_payload))

    @override_settings(MEDIA_UPLOAD_OPTIMIZATION_ENABLED=True)
    def test_document_upload_kept_as_is(self):
        uploaded = SimpleUploadedFile(
            "terms.pdf",
            b"%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n",
            content_type="application/pdf",
        )

        optimized = optimize_upload_for_storage(uploaded)

        self.assertIs(optimized, uploaded)
