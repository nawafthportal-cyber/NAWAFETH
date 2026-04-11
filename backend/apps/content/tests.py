from django.contrib import admin
from django.contrib.auth import get_user_model
from django.db import OperationalError
from django.test import RequestFactory, SimpleTestCase, TestCase
from unittest.mock import patch

from apps.content.admin import HomePageFallbackBannerBlockAdmin
from apps.content.models import HomePageFallbackBannerBlock
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


class HomePageFallbackBannerAdminTests(TestCase):
    def setUp(self):
        self.factory = RequestFactory()
        self.admin_instance = HomePageFallbackBannerBlockAdmin(
            HomePageFallbackBannerBlock,
            admin.site,
        )
        self.user = get_user_model().objects.create_superuser(
            phone="0500001234",
            username="admin_content_banner",
            password="test-pass-123",
        )

    def _request(self):
        request = self.factory.get("/admin/content/homepagefallbackbannerblock/")
        request.user = self.user
        return request

    def test_has_add_permission_is_true_when_fallback_banner_is_missing(self):
        HomePageFallbackBannerBlock.objects.filter(key="home_banners_fallback").delete()
        request = self._request()
        self.assertTrue(self.admin_instance.has_add_permission(request))

    def test_has_add_permission_is_false_when_fallback_banner_already_exists(self):
        request = self._request()
        self.assertFalse(self.admin_instance.has_add_permission(request))

    def test_save_model_forces_singleton_key_for_fallback_banner(self):
        HomePageFallbackBannerBlock.objects.filter(key="home_banners_fallback").delete()
        request = self._request()
        obj = HomePageFallbackBannerBlock(
            key="home_categories_title",
            title_ar="بنر احتياطي",
            body_ar="محتوى تجريبي",
            is_active=True,
        )

        self.admin_instance.save_model(request, obj, form=None, change=False)

        obj.refresh_from_db()
        self.assertEqual(obj.key, "home_banners_fallback")
        self.assertEqual(obj.updated_by, self.user)
