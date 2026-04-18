from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.urls import reverse

from apps.accounts.models import User, UserRole
from apps.extras_portal.views import _report_option_card_catalog

from .models import ContentShareChannel, ContentShareContentType, ProviderContentShare, ProviderPortfolioItem, ProviderProfile


class ProviderContentShareTrackingTests(TestCase):
    def setUp(self):
        self.provider_user = User.objects.create_user(
            phone="0503300001",
            username="provider.share.target",
            role_state=UserRole.PROVIDER,
        )
        self.provider = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود المشاركة",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.client_user = User.objects.create_user(
            phone="0503300002",
            username="provider.share.client",
            role_state=UserRole.CLIENT,
        )
        self.portfolio_item = ProviderPortfolioItem.objects.create(
            provider=self.provider,
            file_type="image",
            file=SimpleUploadedFile("portfolio.jpg", b"img", content_type="image/jpeg"),
        )

    def test_anonymous_profile_share_is_tracked_and_visible_in_reports(self):
        response = self.client.post(
            reverse("providers:share", args=[self.provider.id]),
            {"content_type": "profile", "channel": "copy_link"},
        )

        self.assertEqual(response.status_code, 200)
        share = ProviderContentShare.objects.get()
        self.assertEqual(share.provider_id, self.provider.id)
        self.assertIsNone(share.user_id)
        self.assertEqual(share.content_type, ContentShareContentType.PROFILE)
        self.assertEqual(share.channel, ContentShareChannel.COPY_LINK)
        self.assertTrue(share.session_id)
        self.assertEqual(
            _report_option_card_catalog(self.provider)["option_cards_by_key"]["platform_metrics"]["stats"][2],
            {"label": "عدد مرات مشاركة منصتي", "value": "1"},
        )

    def test_authenticated_portfolio_share_records_user_and_content(self):
        self.client.force_login(self.client_user)

        response = self.client.post(
            reverse("providers:share", args=[self.provider.id]),
            {
                "content_type": "portfolio",
                "content_id": str(self.portfolio_item.id),
                "channel": "whatsapp",
            },
        )

        self.assertEqual(response.status_code, 200)
        share = ProviderContentShare.objects.get()
        self.assertEqual(share.user_id, self.client_user.id)
        self.assertEqual(share.content_type, ContentShareContentType.PORTFOLIO)
        self.assertEqual(share.content_id, self.portfolio_item.id)
        self.assertEqual(share.channel, ContentShareChannel.WHATSAPP)

    def test_share_tracking_rejects_foreign_content_items(self):
        other_provider_user = User.objects.create_user(
            phone="0503300003",
            username="provider.share.other",
            role_state=UserRole.PROVIDER,
        )
        other_provider = ProviderProfile.objects.create(
            user=other_provider_user,
            provider_type="individual",
            display_name="مزود آخر",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        other_item = ProviderPortfolioItem.objects.create(
            provider=other_provider,
            file_type="image",
            file=SimpleUploadedFile("other.jpg", b"img", content_type="image/jpeg"),
        )

        response = self.client.post(
            reverse("providers:share", args=[self.provider.id]),
            {
                "content_type": "portfolio",
                "content_id": str(other_item.id),
                "channel": "other",
            },
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(ProviderContentShare.objects.count(), 0)