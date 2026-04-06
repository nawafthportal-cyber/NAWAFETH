from django.db import OperationalError
from django.test import SimpleTestCase
from unittest.mock import patch

from apps.content.services import (
    DEFAULT_FOOTER_BRAND_DESCRIPTION,
    DEFAULT_FOOTER_BRAND_TITLE,
    DEFAULT_TOPBAR_BRAND_SUBTITLE,
    DEFAULT_TOPBAR_BRAND_TITLE,
    public_content_payload,
    template_site_payload,
)


class PublicContentFallbackTests(SimpleTestCase):
    def test_template_site_payload_falls_back_when_database_is_unavailable(self):
        with patch("apps.content.services._block_payloads", side_effect=OperationalError("db down")):
            payload = template_site_payload()

        self.assertEqual(payload["brand"]["topbar_title"], DEFAULT_TOPBAR_BRAND_TITLE)
        self.assertEqual(payload["brand"]["topbar_subtitle"], DEFAULT_TOPBAR_BRAND_SUBTITLE)
        self.assertEqual(payload["brand"]["footer_title"], DEFAULT_FOOTER_BRAND_TITLE)
        self.assertEqual(payload["brand"]["footer_description"], DEFAULT_FOOTER_BRAND_DESCRIPTION)
        self.assertEqual(payload["links"], {
            "x_url": "",
            "instagram_url": "",
            "snapchat_url": "",
            "tiktok_url": "",
            "youtube_url": "",
            "whatsapp_url": "",
            "email": "",
            "android_store": "",
            "ios_store": "",
            "website_url": "",
        })
        self.assertEqual(payload["social_links"], [])
        self.assertEqual(payload["store_links"], [])

    def test_public_content_payload_falls_back_when_database_is_unavailable(self):
        with patch("apps.content.services._block_payloads", side_effect=OperationalError("db down")):
            payload = public_content_payload()

        self.assertEqual(payload["blocks"], {})
        self.assertEqual(payload["documents"], {})
        self.assertEqual(payload["links"]["website_url"], "")
        self.assertEqual(payload["branding"]["topbar_title"], DEFAULT_TOPBAR_BRAND_TITLE)