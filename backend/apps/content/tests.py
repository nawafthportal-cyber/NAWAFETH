from django.test import TestCase

from .models import ContentBlockKey, LegalDocumentType, SiteContentBlock, SiteLegalDocument
from .services import invalidate_public_content_cache, public_content_payload, template_site_payload


class ContentBilingualPayloadTests(TestCase):
    def tearDown(self):
        invalidate_public_content_cache()

    def test_template_payload_uses_explicit_english_branding_fields(self):
        SiteContentBlock.objects.update_or_create(
            key=ContentBlockKey.TOPBAR_BRAND_TITLE,
            defaults={
                "title_ar": "نوافذ",
                "title_en": "Nawafeth",
                "body_ar": "",
                "body_en": "",
                "is_active": True,
            },
        )
        SiteContentBlock.objects.update_or_create(
            key=ContentBlockKey.FOOTER_BRAND_DESCRIPTION,
            defaults={
                "title_ar": "وصف المنصة",
                "title_en": "Platform Description",
                "body_ar": "منصة عربية للخدمات.",
                "body_en": "A services platform.",
                "is_active": True,
            },
        )

        payload = template_site_payload()

        self.assertEqual(payload["brand"]["topbar_title"], "نوافذ")
        self.assertEqual(payload["brand"]["topbar_title_en"], "Nawafeth")
        self.assertEqual(payload["brand"]["footer_description"], "منصة عربية للخدمات.")
        self.assertEqual(payload["brand"]["footer_description_en"], "A services platform.")

    def test_public_content_payload_exposes_english_block_and_legal_fields(self):
        SiteContentBlock.objects.update_or_create(
            key=ContentBlockKey.CONTACT_PAGE_TITLE,
            defaults={
                "title_ar": "تواصل مع منصة نوافذ",
                "title_en": "Contact Nawafeth",
                "body_ar": "",
                "body_en": "",
                "is_active": True,
            },
        )
        SiteLegalDocument.objects.create(
            doc_type=LegalDocumentType.TERMS,
            body_ar="النص العربي",
            body_en="English legal text",
            version="1.0",
            is_active=True,
        )

        payload = public_content_payload()
        block = payload["blocks"][ContentBlockKey.CONTACT_PAGE_TITLE]
        document = payload["documents"][LegalDocumentType.TERMS]

        self.assertEqual(block["title_en"], "Contact Nawafeth")
        self.assertEqual(document["label_en"], "Terms & Conditions")
        self.assertEqual(document["body_en"], "English legal text")