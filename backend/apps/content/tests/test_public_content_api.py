import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient

from apps.content.models import SiteContentBlock, SiteLegalDocument, SiteLinks


pytestmark = pytest.mark.django_db


def test_public_content_api_returns_blocks_docs_links(settings):
    image_obj = SimpleUploadedFile(
        "hero.png",
        (
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89"
            b"\x00\x00\x00\x0cIDATx\x9cc\xf8\xff\xff?\x00\x05\xfe\x02\xfeA\x89\x1e\x1b\x00\x00\x00\x00IEND\xaeB`\x82"
        ),
        content_type="image/png",
    )
    block, _ = SiteContentBlock.objects.update_or_create(
        key="onboarding_first_time",
        defaults={
            "title_ar": "عنوان",
            "body_ar": "محتوى",
            "media_file": image_obj,
            "is_active": True,
        },
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
        body_ar="البند الأول\nالبند الثاني",
        file=file_obj,
        version="1.0",
        is_active=True,
    )

    client = APIClient()
    res = client.get("/api/content/public/")
    assert res.status_code == 200
    assert "onboarding_first_time" in res.data["blocks"]
    assert res.data["blocks"]["onboarding_first_time"]["title_ar"] == block.title_ar
    assert res.data["blocks"]["onboarding_first_time"]["media_type"] == "image"
    assert res.data["blocks"]["onboarding_first_time"]["has_media"] is True
    assert res.data["blocks"]["onboarding_first_time"]["media_url"]
    assert res.data["links"]["x_url"] == "https://x.com/nawafeth"
    assert res.data["documents"]["terms"]["version"] == "1.0"
    assert res.data["documents"]["terms"]["body_ar"] == "البند الأول\nالبند الثاني"
    assert res.data["documents"]["terms"]["label_ar"] == "الشروط والأحكام"
    assert res.data["documents"]["terms"]["has_body"] is True
    assert res.data["documents"]["terms"]["has_file"] is True


def test_public_content_api_returns_text_only_legal_document():
    SiteLegalDocument.objects.create(
        doc_type="privacy",
        body_ar="سياسة خصوصية نصية فقط",
        version="2.0",
        is_active=True,
    )

    client = APIClient()
    res = client.get("/api/content/public/")

    assert res.status_code == 200
    assert res.data["documents"]["privacy"]["body_ar"] == "سياسة خصوصية نصية فقط"
    assert res.data["documents"]["privacy"]["file_url"] == ""
    assert res.data["documents"]["privacy"]["has_body"] is True
    assert res.data["documents"]["privacy"]["has_file"] is False


def test_public_content_api_returns_third_onboarding_block():
    SiteContentBlock.objects.update_or_create(
        key="onboarding_get_started",
        defaults={
            "title_ar": "ابدأ الآن",
            "body_ar": "هذه الشريحة تأتي من لوحة التحكم",
            "is_active": True,
        },
    )

    client = APIClient()
    res = client.get("/api/content/public/")

    assert res.status_code == 200
    assert res.data["blocks"]["onboarding_get_started"]["title_ar"] == "ابدأ الآن"
    assert res.data["blocks"]["onboarding_get_started"]["body_ar"] == "هذه الشريحة تأتي من لوحة التحكم"


def test_public_content_api_includes_home_content_blocks():
    client = APIClient()
    res = client.get("/api/content/public/")

    assert res.status_code == 200
    assert "home_categories_title" in res.data["blocks"]
    assert "home_hero_title" not in res.data["blocks"]
    assert "home_search_placeholder" not in res.data["blocks"]


def test_public_content_api_includes_auth_content_blocks():
    client = APIClient()
    res = client.get("/api/content/public/")

    assert res.status_code == 200
    assert "login_title" in res.data["blocks"]
    assert "signup_title" in res.data["blocks"]


def test_public_content_api_includes_twofa_content_blocks():
    client = APIClient()
    res = client.get("/api/content/public/")

    assert res.status_code == 200
    assert "twofa_title" in res.data["blocks"]
    assert "twofa_submit_label" in res.data["blocks"]
    assert "twofa_phone_notice" in res.data["blocks"]


def test_public_content_api_includes_about_terms_contact_blocks():
    client = APIClient()
    res = client.get("/api/content/public/")

    assert res.status_code == 200
    assert "about_hero_title" in res.data["blocks"]
    assert "terms_page_title" in res.data["blocks"]
    assert "contact_page_title" in res.data["blocks"]
