import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient

from apps.content.models import SiteContentBlock, SiteLegalDocument, SiteLinks


pytestmark = pytest.mark.django_db


def test_public_content_api_returns_blocks_docs_links(settings):
    block = SiteContentBlock.objects.create(
        key="onboarding_first_time",
        title_ar="عنوان",
        body_ar="محتوى",
        is_active=True,
    )
    SiteLinks.objects.create(
        x_url="https://x.com/nawafeth",
        email="ops@nawafeth.test",
    )
    file_obj = SimpleUploadedFile(
        "terms.pdf",
        b"%PDF-1.4 test",
        content_type="application/pdf",
    )
    SiteLegalDocument.objects.create(
        doc_type="terms",
        file=file_obj,
        version="1.0",
        is_active=True,
    )

    client = APIClient()
    res = client.get("/api/content/public/")
    assert res.status_code == 200
    assert "onboarding_first_time" in res.data["blocks"]
    assert res.data["blocks"]["onboarding_first_time"]["title_ar"] == block.title_ar
    assert res.data["links"]["x_url"] == "https://x.com/nawafeth"
    assert res.data["documents"]["terms"]["version"] == "1.0"
