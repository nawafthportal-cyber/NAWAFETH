import json
from datetime import timedelta

from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import User, UserRole
from apps.extras_portal.views import _report_option_card_catalog
from apps.marketplace.models import RequestStatus, RequestType, ServiceRequest
from apps.messaging.models import Thread
from apps.moderation.models import ModerationCase
from apps.reviews.models import Review, ReviewModerationStatus
from apps.support.models import SupportTicket
from apps.subscriptions.models import Subscription, SubscriptionPlan, SubscriptionStatus

from .models import (
    Category,
    ContentShareChannel,
    ContentShareContentType,
    ProviderCategory,
    ProviderContentComment,
    ProviderContentCommentLike,
    ProviderContentShare,
    ProviderFollow,
    ProviderPortfolioItem,
    ProviderPortfolioLike,
    ProviderPortfolioSave,
    ProviderPortfolioVisibilityBlock,
    ProviderProfile,
    ProviderService,
    ProviderSpotlightItem,
    ProviderSpotlightLike,
    ProviderSpotlightSave,
    ProviderSpotlightVisibilityBlock,
    ProviderVisibilityBlock,
    SubCategory,
)


class ProviderContentCommentProfileCompletionGateTests(TestCase):
    def setUp(self):
        provider_user = User.objects.create_user(
            phone="0509200001",
            username="comment.provider",
            role_state=UserRole.PROVIDER,
        )
        self.provider = ProviderProfile.objects.create(
            user=provider_user,
            provider_type="individual",
            display_name="مزود التعليقات",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
        )
        self.portfolio_item = ProviderPortfolioItem.objects.create(
            provider=self.provider,
            file_type="image",
            file=SimpleUploadedFile("comment.jpg", b"img", content_type="image/jpeg"),
        )

    def test_partial_client_must_complete_registration_before_commenting(self):
        user = User.objects.create_user(
            phone="0509200002",
            username="partial.commenter",
            role_state=UserRole.CLIENT,
        )
        self.client.force_login(user)

        response = self.client.post(
            reverse("providers:portfolio_comments", kwargs={"item_id": self.portfolio_item.id}),
            {"body": "تعليق من حساب ناقص"},
        )

        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["error_code"], "profile_completion_required")

    def test_phone_only_can_still_like_content(self):
        user = User.objects.create_user(
            phone="0509200003",
            username="phone.only.like",
            role_state=UserRole.PHONE_ONLY,
        )
        self.client.force_login(user)

        response = self.client.post(
            reverse("providers:portfolio_like", kwargs={"item_id": self.portfolio_item.id})
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["ok"])


class SavedMediaEndpointsTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            phone="0503300101",
            username="saved.media.client",
            role_state=UserRole.CLIENT,
        )
        provider_user = User.objects.create_user(
            phone="0503300102",
            username="saved.media.provider",
            role_state=UserRole.PROVIDER,
        )
        self.provider = ProviderProfile.objects.create(
            user=provider_user,
            provider_type="individual",
            display_name="مزود ميديا",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.portfolio_saved = ProviderPortfolioItem.objects.create(
            provider=self.provider,
            file_type="image",
            file=SimpleUploadedFile("saved-portfolio.jpg", b"img", content_type="image/jpeg"),
        )
        self.portfolio_liked_only = ProviderPortfolioItem.objects.create(
            provider=self.provider,
            file_type="image",
            file=SimpleUploadedFile("liked-portfolio.jpg", b"img", content_type="image/jpeg"),
        )
        self.spotlight_saved = ProviderSpotlightItem.objects.create(
            provider=self.provider,
            file_type="image",
            file=SimpleUploadedFile("saved-spotlight.jpg", b"img", content_type="image/jpeg"),
            caption="saved",
        )
        self.spotlight_liked_only = ProviderSpotlightItem.objects.create(
            provider=self.provider,
            file_type="image",
            file=SimpleUploadedFile("liked-spotlight.jpg", b"img", content_type="image/jpeg"),
            caption="liked",
        )
        ProviderPortfolioSave.objects.create(user=self.user, item=self.portfolio_saved, role_context="client")
        ProviderPortfolioLike.objects.create(user=self.user, item=self.portfolio_liked_only, role_context="client")
        ProviderSpotlightSave.objects.create(user=self.user, item=self.spotlight_saved, role_context="client")
        ProviderSpotlightLike.objects.create(user=self.user, item=self.spotlight_liked_only, role_context="client")
        self.client.force_login(self.user)

    def test_saved_portfolio_endpoint_excludes_liked_only_items(self):
        response = self.client.get(reverse("providers:my_favorites_media") + "?mode=client")

        self.assertEqual(response.status_code, 200)
        returned_ids = {row["id"] for row in response.json()}
        self.assertEqual(returned_ids, {self.portfolio_saved.id})
        self.assertTrue(response.json()[0]["is_saved"])

    def test_saved_spotlights_endpoint_excludes_liked_only_items(self):
        response = self.client.get(reverse("providers:my_favorites_spotlights") + "?mode=client")

        self.assertEqual(response.status_code, 200)
        returned_ids = {row["id"] for row in response.json()}
        self.assertEqual(returned_ids, {self.spotlight_saved.id})
        self.assertTrue(response.json()[0]["is_saved"])

    def test_liked_portfolio_endpoint_excludes_saved_only_items(self):
        response = self.client.get(reverse("providers:my_liked_media") + "?mode=client")

        self.assertEqual(response.status_code, 200)
        returned_ids = {row["id"] for row in response.json()}
        self.assertEqual(returned_ids, {self.portfolio_liked_only.id})
        self.assertTrue(response.json()[0]["is_liked"])
        self.assertFalse(response.json()[0]["is_saved"])

    def test_liked_spotlights_endpoint_excludes_saved_only_items(self):
        response = self.client.get(reverse("providers:my_liked_spotlights") + "?mode=client")

        self.assertEqual(response.status_code, 200)
        returned_ids = {row["id"] for row in response.json()}
        self.assertEqual(returned_ids, {self.spotlight_liked_only.id})
        self.assertTrue(response.json()[0]["is_liked"])
        self.assertFalse(response.json()[0]["is_saved"])


class ProviderSubcategoryPolicyTests(TestCase):
    def setUp(self):
        cache.clear()
        self.user = User.objects.create_user(
            phone="0503301101",
            username="provider.subcategory.policy",
            role_state=UserRole.PROVIDER,
        )
        self.provider = ProviderProfile.objects.create(
            user=self.user,
            provider_type="individual",
            display_name="مزود سياسات",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.category = Category.objects.create(name="صيانة")
        self.subcategory = SubCategory.objects.create(
            category=self.category,
            name="سباكة",
            requires_geo_scope=True,
            allows_urgent_requests=False,
        )
        ProviderCategory.objects.create(
            provider=self.provider,
            subcategory=self.subcategory,
            accepts_urgent=True,
            requires_geo_scope=False,
        )
        self.client.force_login(self.user)

    def test_my_subcategories_uses_subcategory_policy_as_source_of_truth(self):
        response = self.client.get(reverse("providers:my_subcategories"))

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["subcategory_ids"], [self.subcategory.id])
        self.assertEqual(
            payload["subcategory_settings"],
            [
                {
                    "subcategory_id": self.subcategory.id,
                    "accepts_urgent": False,
                    "requires_geo_scope": True,
                }
            ],
        )

    def test_categories_endpoint_reflects_urgent_policy_change_immediately(self):
        first_response = self.client.get(reverse("providers:categories"))

        self.assertEqual(first_response.status_code, 200)
        self.assertFalse(first_response.json()[0]["subcategories"][0]["allows_urgent_requests"])

        self.subcategory.allows_urgent_requests = True
        self.subcategory.save(update_fields=["allows_urgent_requests"])

        second_response = self.client.get(reverse("providers:categories"))

        self.assertEqual(second_response.status_code, 200)
        self.assertTrue(second_response.json()[0]["subcategories"][0]["allows_urgent_requests"])


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
        self.spotlight_item = ProviderSpotlightItem.objects.create(
            provider=self.provider,
            file_type="image",
            file=SimpleUploadedFile("spotlight.jpg", b"img", content_type="image/jpeg"),
            caption="لمحة للاختبار",
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


class ProviderSpotlightQuotaTests(TestCase):
    def setUp(self):
        self.provider_user = User.objects.create_user(
            phone="0504400001",
            username="provider.spotlight.quota",
            role_state=UserRole.PROVIDER,
        )
        self.provider = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود اللمحات",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.plan = SubscriptionPlan.objects.create(
            code="spotlight-quota-basic",
            tier="basic",
            title="الأساسية",
            description="باقة اختبار للّمحات",
            period="year",
            price="0.00",
            notifications_enabled=True,
            banner_images_limit=1,
            spotlight_quota=3,
            support_sla_hours=120,
            storage_policy="basic",
            storage_multiplier=1,
            storage_upload_max_mb=10,
            is_active=True,
        )
        Subscription.objects.create(
            user=self.provider_user,
            plan=self.plan,
            status=SubscriptionStatus.ACTIVE,
            start_at=timezone.now() - timedelta(days=1),
            end_at=timezone.now() + timedelta(days=364),
            auto_renew=True,
        )
        self.client_user = User.objects.create_user(
            phone="0504400002",
            username="provider.spotlight.viewer",
            role_state=UserRole.CLIENT,
        )
        self.portfolio_item = ProviderPortfolioItem.objects.create(
            provider=self.provider,
            file_type="image",
            file=SimpleUploadedFile("portfolio.jpg", b"img", content_type="image/jpeg"),
        )
        self.spotlight_item = ProviderSpotlightItem.objects.create(
            provider=self.provider,
            file_type="image",
            file=SimpleUploadedFile("spotlight.jpg", b"img", content_type="image/jpeg"),
            caption="لمحة للاختبار",
        )
        self.client.force_login(self.provider_user)
        self.list_url = reverse("providers:my_spotlights")

    def _create_spotlight_item(self, name: str):
        return ProviderSpotlightItem.objects.create(
            provider=self.provider,
            file_type="image",
            file=SimpleUploadedFile(name, b"img", content_type="image/jpeg"),
            caption=name,
        )

    def _upload_payload(self, name: str):
        return {
            "file_type": "image",
            "caption": f"caption-{name}",
            "file": SimpleUploadedFile(name, b"img", content_type="image/jpeg"),
        }

    def test_create_spotlight_rejects_when_quota_is_full(self):
        self._create_spotlight_item("spot-1.jpg")
        self._create_spotlight_item("spot-2.jpg")
        self._create_spotlight_item("spot-3.jpg")

        response = self.client.post(self.list_url, self._upload_payload("spot-4.jpg"))

        self.assertEqual(response.status_code, 400)
        body = response.json()
        self.assertEqual(body.get("error_code"), "spotlight_quota_exceeded")
        self.assertEqual(body.get("spotlight_quota"), 3)
        self.assertEqual(body.get("current_count"), 3)
        self.assertIn("الحد الأقصى", body.get("detail", ""))
        self.assertEqual(ProviderSpotlightItem.objects.filter(provider=self.provider).count(), 3)

    def test_create_spotlight_allows_new_item_after_deleting_old_one(self):
        first = self._create_spotlight_item("spot-1.jpg")
        self._create_spotlight_item("spot-2.jpg")
        self._create_spotlight_item("spot-3.jpg")

        delete_response = self.client.delete(
            reverse("providers:my_spotlights_detail", kwargs={"pk": first.id})
        )

        self.assertEqual(delete_response.status_code, 204)

        create_response = self.client.post(self.list_url, self._upload_payload("spot-4.jpg"))

        self.assertEqual(create_response.status_code, 201)
        self.assertEqual(ProviderSpotlightItem.objects.filter(provider=self.provider).count(), 3)

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

    def test_authenticated_spotlight_share_records_user_and_content(self):
        self.client.force_login(self.client_user)

        response = self.client.post(
            reverse("providers:share", args=[self.provider.id]),
            {
                "content_type": "spotlight",
                "content_id": str(self.spotlight_item.id),
                "channel": "copy_link",
            },
        )

        self.assertEqual(response.status_code, 200)
        share = ProviderContentShare.objects.get(content_type=ContentShareContentType.SPOTLIGHT)
        self.assertEqual(share.user_id, self.client_user.id)
        self.assertEqual(share.content_id, self.spotlight_item.id)
        self.assertEqual(share.channel, ContentShareChannel.COPY_LINK)

    def test_public_spotlight_detail_returns_counts_and_authenticated_state(self):
        ProviderContentComment.objects.create(
            provider=self.provider,
            user=self.client_user,
            spotlight_item=self.spotlight_item,
            body="تعليق واضح",
            is_approved=True,
        )
        ProviderSpotlightLike.objects.create(
            user=self.client_user,
            item=self.spotlight_item,
            role_context="client",
        )
        ProviderSpotlightSave.objects.create(
            user=self.client_user,
            item=self.spotlight_item,
            role_context="client",
        )
        self.client.force_login(self.client_user)

        response = self.client.get(
            reverse("providers:spotlight_public_detail", kwargs={"item_id": self.spotlight_item.id})
        )

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["id"], self.spotlight_item.id)
        self.assertEqual(payload["provider_id"], self.provider.id)
        self.assertEqual(payload["caption"], self.spotlight_item.caption)
        self.assertEqual(payload["likes_count"], 1)
        self.assertEqual(payload["saves_count"], 1)
        self.assertEqual(payload["comments_count"], 1)
        self.assertTrue(payload["is_liked"])
        self.assertTrue(payload["is_saved"])

    def test_spotlight_comments_endpoint_lists_and_creates_comments(self):
        other_user = User.objects.create_user(
            phone="0503300005",
            username="provider.share.commenter",
            first_name="معلق",
            role_state=UserRole.CLIENT,
        )
        ProviderContentComment.objects.create(
            provider=self.provider,
            user=other_user,
            spotlight_item=self.spotlight_item,
            body="تعليق أول",
            is_approved=True,
        )
        ProviderContentComment.objects.create(
            provider=self.provider,
            user=other_user,
            spotlight_item=self.spotlight_item,
            body="تعليق مخفي",
            is_approved=False,
        )

        self.client.force_login(self.client_user)

        list_response = self.client.get(
            reverse("providers:spotlight_comments", kwargs={"item_id": self.spotlight_item.id})
        )
        self.assertEqual(list_response.status_code, 200)
        payload = list_response.json()
        self.assertEqual(payload["count"], 1)
        self.assertEqual(len(payload["results"]), 1)
        self.assertEqual(payload["results"][0]["body"], "تعليق أول")
        self.assertEqual(payload["results"][0]["likes_count"], 0)
        self.assertFalse(payload["results"][0]["is_liked"])

        create_response = self.client.post(
            reverse("providers:spotlight_comments", kwargs={"item_id": self.spotlight_item.id}),
            {"body": "تعليق جديد داخل اللمحة"},
            content_type="application/json",
        )
        self.assertEqual(create_response.status_code, 201, create_response.json())
        self.assertEqual(create_response.json()["body"], "تعليق جديد داخل اللمحة")
        self.assertTrue(create_response.json()["is_mine"])
        self.assertTrue(
            ProviderContentComment.objects.filter(
                spotlight_item=self.spotlight_item,
                user=self.client_user,
                body="تعليق جديد داخل اللمحة",
            ).exists()
        )

    def test_dual_role_comment_in_client_mode_stays_client_scoped(self):
        dual_role_user = User.objects.create_user(
            phone="0503300085",
            username="provider.dual.role.client.commenter",
            first_name="عميل",
            last_name="نشط",
            role_state=UserRole.CLIENT,
        )
        ProviderProfile.objects.create(
            user=dual_role_user,
            provider_type="individual",
            display_name="هوية المزود",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.client.force_login(dual_role_user)

        response = self.client.post(
            reverse("providers:spotlight_comments", kwargs={"item_id": self.spotlight_item.id}) + "?mode=client",
            {"body": "تعليق بحساب العميل"},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 201, response.json())
        self.assertEqual(response.json()["display_name"], "عميل نشط")
        self.assertFalse(response.json()["is_provider"])
        self.assertFalse(response.json()["is_verified_blue"])
        self.assertFalse(response.json()["is_verified_green"])
        self.assertEqual(
            ProviderContentComment.objects.get(body="تعليق بحساب العميل").role_context,
            "client",
        )

    def test_dual_role_comment_in_provider_mode_keeps_provider_identity(self):
        dual_role_user = User.objects.create_user(
            phone="0503300086",
            username="provider.dual.role.provider.commenter",
            first_name="مستخدم",
            last_name="ثنائي",
            role_state=UserRole.PROVIDER,
        )
        ProviderProfile.objects.create(
            user=dual_role_user,
            provider_type="individual",
            display_name="مزود معتمد",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
            is_verified_blue=True,
        )
        self.client.force_login(dual_role_user)

        response = self.client.post(
            reverse("providers:spotlight_comments", kwargs={"item_id": self.spotlight_item.id}) + "?mode=provider",
            {"body": "تعليق بحساب المزود"},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 201, response.json())
        self.assertEqual(response.json()["display_name"], "مزود معتمد")
        self.assertTrue(response.json()["is_provider"])
        self.assertTrue(response.json()["is_verified_blue"])
        self.assertEqual(
            ProviderContentComment.objects.get(body="تعليق بحساب المزود").role_context,
            "provider",
        )

    def test_spotlight_comment_like_and_report_create_visible_state_and_content_ticket(self):
        author = User.objects.create_user(
            phone="0503300025",
            username="provider.spotlight.comment.author",
            first_name="صاحب تعليق",
            role_state=UserRole.CLIENT,
        )
        comment = ProviderContentComment.objects.create(
            provider=self.provider,
            user=author,
            spotlight_item=self.spotlight_item,
            body="تعليق يستحق المراجعة",
            is_approved=True,
        )

        self.client.force_login(self.client_user)

        like_response = self.client.post(
            reverse("providers:spotlight_comment_like", kwargs={"item_id": self.spotlight_item.id, "comment_id": comment.id})
        )
        self.assertEqual(like_response.status_code, 200)
        self.assertTrue(
            ProviderContentCommentLike.objects.filter(
                user=self.client_user,
                comment=comment,
                role_context="client",
            ).exists()
        )

        list_response = self.client.get(
            reverse("providers:spotlight_comments", kwargs={"item_id": self.spotlight_item.id})
        )
        self.assertEqual(list_response.status_code, 200)
        payload = list_response.json()
        self.assertEqual(payload["results"][0]["likes_count"], 1)
        self.assertTrue(payload["results"][0]["is_liked"])

        report_response = self.client.post(
            reverse("providers:spotlight_comment_report", kwargs={"item_id": self.spotlight_item.id, "comment_id": comment.id}),
            {"reason": "مسيء", "details": "وصف غير مناسب"},
            content_type="application/json",
        )
        self.assertEqual(report_response.status_code, 201, report_response.json())
        ticket = SupportTicket.objects.get(id=report_response.json()["ticket_id"])
        self.assertEqual(ticket.reported_kind, "spotlight_comment")
        self.assertEqual(ticket.reported_object_id, str(comment.id))
        self.assertEqual(ticket.reported_user_id, author.id)
        self.assertIn("بلاغ تعليق على لمحة", ticket.description)

    def test_spotlight_comment_report_rejects_reporting_own_comment(self):
        comment = ProviderContentComment.objects.create(
            provider=self.provider,
            user=self.client_user,
            spotlight_item=self.spotlight_item,
            body="تعليقي الخاص",
            is_approved=True,
        )
        self.client.force_login(self.client_user)

        response = self.client.post(
            reverse("providers:spotlight_comment_report", kwargs={"item_id": self.spotlight_item.id, "comment_id": comment.id}),
            {"reason": "خطأ"},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 400)

    def test_spotlight_comments_support_replies_and_owner_delete(self):
        parent = ProviderContentComment.objects.create(
            provider=self.provider,
            user=self.client_user,
            spotlight_item=self.spotlight_item,
            body="تعليق أساسي",
            is_approved=True,
        )
        reply_author = User.objects.create_user(
            phone="0503300006",
            username="provider.reply.author",
            first_name="راد",
            role_state=UserRole.CLIENT,
        )
        reply = ProviderContentComment.objects.create(
            provider=self.provider,
            user=reply_author,
            spotlight_item=self.spotlight_item,
            parent=parent,
            body="رد موجود",
            is_approved=True,
        )

        self.client.force_login(self.client_user)

        list_response = self.client.get(
            reverse("providers:spotlight_comments", kwargs={"item_id": self.spotlight_item.id})
        )
        self.assertEqual(list_response.status_code, 200)
        payload = list_response.json()
        self.assertEqual(payload["count"], 2)
        self.assertEqual(len(payload["results"]), 1)
        self.assertEqual(payload["results"][0]["id"], parent.id)
        self.assertEqual(payload["results"][0]["replies_count"], 1)
        self.assertEqual(len(payload["results"][0]["replies"]), 1)
        self.assertEqual(payload["results"][0]["replies"][0]["id"], reply.id)
        self.assertEqual(payload["results"][0]["replies"][0]["parent_id"], parent.id)

        create_reply_response = self.client.post(
            reverse("providers:spotlight_comments", kwargs={"item_id": self.spotlight_item.id}),
            {"body": "رد جديد", "parent": parent.id},
            content_type="application/json",
        )
        self.assertEqual(create_reply_response.status_code, 201, create_reply_response.json())
        self.assertEqual(create_reply_response.json()["parent_id"], parent.id)

        delete_response = self.client.delete(
            reverse(
                "providers:spotlight_comment_detail",
                kwargs={"item_id": self.spotlight_item.id, "comment_id": parent.id},
            )
        )
        self.assertEqual(delete_response.status_code, 200)
        self.assertFalse(ProviderContentComment.objects.filter(id=parent.id).exists())
        self.assertFalse(ProviderContentComment.objects.filter(parent_id=parent.id).exists())

    def test_public_portfolio_detail_returns_counts_and_authenticated_state(self):
        ProviderContentComment.objects.create(
            provider=self.provider,
            user=self.client_user,
            portfolio_item=self.portfolio_item,
            body="تعليق على المشروع",
            is_approved=True,
        )
        self.client.force_login(self.client_user)
        self.client.post(reverse("providers:portfolio_like", kwargs={"item_id": self.portfolio_item.id}))
        self.client.post(reverse("providers:portfolio_save", kwargs={"item_id": self.portfolio_item.id}))

        response = self.client.get(
            reverse("providers:portfolio_public_detail", kwargs={"item_id": self.portfolio_item.id})
        )

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["id"], self.portfolio_item.id)
        self.assertEqual(payload["provider_id"], self.provider.id)
        self.assertEqual(payload["likes_count"], 1)
        self.assertEqual(payload["saves_count"], 1)
        self.assertEqual(payload["comments_count"], 1)
        self.assertTrue(payload["is_liked"])
        self.assertTrue(payload["is_saved"])

    def test_portfolio_comments_endpoint_lists_and_creates_comments(self):
        other_user = User.objects.create_user(
            phone="0503300015",
            username="provider.portfolio.commenter",
            first_name="معلق",
            role_state=UserRole.CLIENT,
        )
        ProviderContentComment.objects.create(
            provider=self.provider,
            user=other_user,
            portfolio_item=self.portfolio_item,
            body="تعليق مشروع أول",
            is_approved=True,
        )
        ProviderContentComment.objects.create(
            provider=self.provider,
            user=other_user,
            portfolio_item=self.portfolio_item,
            body="تعليق مشروع مخفي",
            is_approved=False,
        )

        self.client.force_login(self.client_user)

        list_response = self.client.get(
            reverse("providers:portfolio_comments", kwargs={"item_id": self.portfolio_item.id})
        )
        self.assertEqual(list_response.status_code, 200)
        payload = list_response.json()
        self.assertEqual(payload["count"], 1)
        self.assertEqual(len(payload["results"]), 1)
        self.assertEqual(payload["results"][0]["body"], "تعليق مشروع أول")
        self.assertEqual(payload["results"][0]["likes_count"], 0)
        self.assertFalse(payload["results"][0]["is_liked"])

        create_response = self.client.post(
            reverse("providers:portfolio_comments", kwargs={"item_id": self.portfolio_item.id}),
            {"body": "تعليق جديد داخل خدمات ومشاريع"},
            content_type="application/json",
        )
        self.assertEqual(create_response.status_code, 201, create_response.json())
        self.assertEqual(create_response.json()["body"], "تعليق جديد داخل خدمات ومشاريع")
        self.assertTrue(create_response.json()["is_mine"])
        self.assertTrue(
            ProviderContentComment.objects.filter(
                portfolio_item=self.portfolio_item,
                user=self.client_user,
                body="تعليق جديد داخل خدمات ومشاريع",
            ).exists()
        )

    def test_portfolio_comment_like_and_report_create_content_ticket(self):
        author = User.objects.create_user(
            phone="0503300026",
            username="provider.portfolio.comment.author",
            first_name="صاحب مشروع",
            role_state=UserRole.CLIENT,
        )
        comment = ProviderContentComment.objects.create(
            provider=self.provider,
            user=author,
            portfolio_item=self.portfolio_item,
            body="تعليق على خدمات ومشاريع",
            is_approved=True,
        )

        self.client.force_login(self.client_user)

        like_response = self.client.post(
            reverse("providers:portfolio_comment_like", kwargs={"item_id": self.portfolio_item.id, "comment_id": comment.id})
        )
        self.assertEqual(like_response.status_code, 200)
        self.assertTrue(
            ProviderContentCommentLike.objects.filter(
                user=self.client_user,
                comment=comment,
                role_context="client",
            ).exists()
        )

        report_response = self.client.post(
            reverse("providers:portfolio_comment_report", kwargs={"item_id": self.portfolio_item.id, "comment_id": comment.id}),
            {"reason": "غير لائق", "details": "تفاصيل البلاغ"},
            content_type="application/json",
        )
        self.assertEqual(report_response.status_code, 201, report_response.json())
        ticket = SupportTicket.objects.get(id=report_response.json()["ticket_id"])
        self.assertEqual(ticket.reported_kind, "portfolio_comment")
        self.assertEqual(ticket.reported_object_id, str(comment.id))
        self.assertIn("بلاغ تعليق على خدمات ومشاريع", ticket.description)

    def test_spotlight_comment_delete_rejects_non_owner(self):
        owner = User.objects.create_user(
            phone="0503300007",
            username="provider.comment.owner",
            first_name="مالك",
            role_state=UserRole.CLIENT,
        )
        comment = ProviderContentComment.objects.create(
            provider=self.provider,
            user=owner,
            spotlight_item=self.spotlight_item,
            body="تعليق غيري",
            is_approved=True,
        )
        self.client.force_login(self.client_user)

        response = self.client.delete(
            reverse(
                "providers:spotlight_comment_detail",
                kwargs={"item_id": self.spotlight_item.id, "comment_id": comment.id},
            )
        )

        self.assertEqual(response.status_code, 403)
        self.assertTrue(ProviderContentComment.objects.filter(id=comment.id).exists())

    def test_spotlight_feed_and_public_detail_expose_provider_verification_flags(self):
        self.provider.is_verified_blue = True
        self.provider.is_verified_green = False
        self.provider.save(update_fields=["is_verified_blue", "is_verified_green"])

        feed_response = self.client.get(reverse("providers:spotlights_feed"))
        self.assertEqual(feed_response.status_code, 200)
        feed_payload = feed_response.json()
        feed_rows = feed_payload.get("results", []) if isinstance(feed_payload, dict) else feed_payload
        self.assertTrue(feed_rows)
        spotlight_row = next(row for row in feed_rows if row["id"] == self.spotlight_item.id)
        self.assertTrue(spotlight_row["is_verified_blue"])
        self.assertFalse(spotlight_row["is_verified_green"])

        detail_response = self.client.get(
            reverse("providers:spotlight_public_detail", kwargs={"item_id": self.spotlight_item.id})
        )
        self.assertEqual(detail_response.status_code, 200)
        detail_payload = detail_response.json()
        self.assertTrue(detail_payload["is_verified_blue"])
        self.assertFalse(detail_payload["is_verified_green"])


class SpotlightModerationAndVisibilityTests(TestCase):
    def setUp(self):
        self.viewer = User.objects.create_user(
            phone="0503900001",
            username="spotlight.viewer",
            role_state=UserRole.CLIENT,
        )
        self.provider_user = User.objects.create_user(
            phone="0503900002",
            username="spotlight.blocked.provider",
            role_state=UserRole.PROVIDER,
        )
        self.provider = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود محظور",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.other_provider_user = User.objects.create_user(
            phone="0503900003",
            username="spotlight.other.provider",
            role_state=UserRole.PROVIDER,
        )
        self.other_provider = ProviderProfile.objects.create(
            user=self.other_provider_user,
            provider_type="individual",
            display_name="مزود آخر",
            bio="-",
            city="جدة",
            region="منطقة مكة",
            accepts_urgent=True,
        )
        self.blocked_spotlight = ProviderSpotlightItem.objects.create(
            provider=self.provider,
            file_type="image",
            file=SimpleUploadedFile("blocked-spotlight.jpg", b"img", content_type="image/jpeg"),
            caption="لمحة محظورة",
        )
        self.visible_spotlight = ProviderSpotlightItem.objects.create(
            provider=self.other_provider,
            file_type="image",
            file=SimpleUploadedFile("visible-spotlight.jpg", b"img", content_type="image/jpeg"),
            caption="لمحة ظاهرة",
        )
        self.client.force_login(self.viewer)

    @staticmethod
    def _rows_from_payload(payload):
        if isinstance(payload, dict):
            return payload.get("results", [])
        return payload

    def test_reporting_spotlight_creates_content_team_moderation_case(self):
        response = self.client.post(
            reverse("providers:spotlight_report", kwargs={"item_id": self.blocked_spotlight.id}),
            {
                "reason": "محتوى غير مناسب",
                "details": "تفاصيل البلاغ من عارض اللمحات",
            },
        )

        self.assertEqual(response.status_code, 201, response.json())
        case = ModerationCase.objects.get(id=response.json()["case_id"])
        self.assertEqual(case.reporter_id, self.viewer.id)
        self.assertEqual(case.reported_user_id, self.provider_user.id)
        self.assertEqual(case.source_app, "providers")
        self.assertEqual(case.source_model, "ProviderSpotlightItem")
        self.assertEqual(case.source_object_id, str(self.blocked_spotlight.id))
        self.assertEqual(case.assigned_team_code, "content")
        self.assertEqual(case.assigned_team_name, "المحتوى والمراجعات")

    def test_blocking_spotlight_hides_it_from_feed_and_public_detail(self):
        response = self.client.post(
            reverse("providers:spotlight_hide", kwargs={"item_id": self.blocked_spotlight.id}),
        )

        self.assertEqual(response.status_code, 200, response.json())
        self.assertTrue(
            ProviderSpotlightVisibilityBlock.objects.filter(
                user=self.viewer,
                spotlight_item=self.blocked_spotlight,
            ).exists()
        )

        feed_response = self.client.get(reverse("providers:spotlights_feed"))
        self.assertEqual(feed_response.status_code, 200)
        feed_ids = {row["id"] for row in self._rows_from_payload(feed_response.json())}
        self.assertNotIn(self.blocked_spotlight.id, feed_ids)
        self.assertIn(self.visible_spotlight.id, feed_ids)

        detail_response = self.client.get(
            reverse("providers:spotlight_public_detail", kwargs={"item_id": self.blocked_spotlight.id})
        )
        self.assertEqual(detail_response.status_code, 404)

    def test_blocking_provider_hides_provider_and_spotlights_from_public_surfaces(self):
        response = self.client.post(
            reverse("providers:provider_block", kwargs={"provider_id": self.provider.id}),
        )

        self.assertEqual(response.status_code, 200, response.json())
        self.assertTrue(
            ProviderVisibilityBlock.objects.filter(user=self.viewer, provider=self.provider).exists()
        )

        list_response = self.client.get(reverse("providers:provider_list"))
        self.assertEqual(list_response.status_code, 200)
        provider_ids = {row["id"] for row in self._rows_from_payload(list_response.json())}
        self.assertNotIn(self.provider.id, provider_ids)
        self.assertIn(self.other_provider.id, provider_ids)

        detail_response = self.client.get(reverse("providers:provider_detail", args=[self.provider.id]))
        self.assertEqual(detail_response.status_code, 404)


class PortfolioModerationAndVisibilityTests(TestCase):
    def setUp(self):
        self.viewer = User.objects.create_user(
            phone="0503900011",
            username="portfolio.viewer",
            role_state=UserRole.CLIENT,
        )
        self.provider_user = User.objects.create_user(
            phone="0503900012",
            username="portfolio.blocked.provider",
            role_state=UserRole.PROVIDER,
        )
        self.provider = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود المشاريع",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.other_provider_user = User.objects.create_user(
            phone="0503900013",
            username="portfolio.other.provider",
            role_state=UserRole.PROVIDER,
        )
        self.other_provider = ProviderProfile.objects.create(
            user=self.other_provider_user,
            provider_type="individual",
            display_name="مزود مشاريع آخر",
            bio="-",
            city="جدة",
            region="منطقة مكة",
            accepts_urgent=True,
        )
        self.blocked_portfolio = ProviderPortfolioItem.objects.create(
            provider=self.provider,
            file_type="image",
            file=SimpleUploadedFile("blocked-portfolio.jpg", b"img", content_type="image/jpeg"),
            caption="محتوى محظور",
        )
        self.visible_portfolio = ProviderPortfolioItem.objects.create(
            provider=self.other_provider,
            file_type="image",
            file=SimpleUploadedFile("visible-portfolio.jpg", b"img", content_type="image/jpeg"),
            caption="محتوى ظاهر",
        )
        self.client.force_login(self.viewer)

    @staticmethod
    def _rows_from_payload(payload):
        if isinstance(payload, dict):
            return payload.get("results", [])
        return payload

    def test_reporting_portfolio_creates_content_team_moderation_case(self):
        response = self.client.post(
            reverse("providers:portfolio_report", kwargs={"item_id": self.blocked_portfolio.id}),
            {
                "reason": "محتوى غير مناسب",
                "details": "تفاصيل البلاغ من عارض خدمات ومشاريع",
            },
        )

        self.assertEqual(response.status_code, 201, response.json())
        case = ModerationCase.objects.get(id=response.json()["case_id"])
        self.assertEqual(case.reporter_id, self.viewer.id)
        self.assertEqual(case.reported_user_id, self.provider_user.id)
        self.assertEqual(case.source_app, "providers")
        self.assertEqual(case.source_model, "ProviderPortfolioItem")
        self.assertEqual(case.source_object_id, str(self.blocked_portfolio.id))
        self.assertEqual(case.assigned_team_code, "content")
        self.assertEqual(case.assigned_team_name, "المحتوى والمراجعات")

    def test_blocking_portfolio_hides_it_from_feed_and_public_detail(self):
        response = self.client.post(
            reverse("providers:portfolio_hide", kwargs={"item_id": self.blocked_portfolio.id}),
        )

        self.assertEqual(response.status_code, 200, response.json())
        self.assertTrue(
            ProviderPortfolioVisibilityBlock.objects.filter(
                user=self.viewer,
                portfolio_item=self.blocked_portfolio,
            ).exists()
        )

        feed_response = self.client.get(reverse("providers:portfolio_feed"))
        self.assertEqual(feed_response.status_code, 200)
        feed_ids = {row["id"] for row in self._rows_from_payload(feed_response.json())}
        self.assertNotIn(self.blocked_portfolio.id, feed_ids)
        self.assertIn(self.visible_portfolio.id, feed_ids)

        detail_response = self.client.get(
            reverse("providers:portfolio_public_detail", kwargs={"item_id": self.blocked_portfolio.id})
        )
        self.assertEqual(detail_response.status_code, 404)


class VisibilityBlocksRoleIsolationTests(TestCase):
    def setUp(self):
        self.viewer = User.objects.create_user(
            phone="0503901011",
            username="visibility.dual.viewer",
            role_state=UserRole.CLIENT,
        )
        ProviderProfile.objects.create(
            user=self.viewer,
            provider_type="individual",
            display_name="مزود ثنائي الدور",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.target_provider_user = User.objects.create_user(
            phone="0503901012",
            username="visibility.target.provider",
            role_state=UserRole.PROVIDER,
        )
        self.target_provider = ProviderProfile.objects.create(
            user=self.target_provider_user,
            provider_type="individual",
            display_name="مزود مستهدف",
            bio="-",
            city="جدة",
            region="منطقة مكة",
            accepts_urgent=True,
        )
        self.portfolio_item = ProviderPortfolioItem.objects.create(
            provider=self.target_provider,
            file_type="image",
            file=SimpleUploadedFile("blocked-role-portfolio.jpg", b"img", content_type="image/jpeg"),
            caption="عنصر محظور بوضع المزود",
        )
        self.spotlight_item = ProviderSpotlightItem.objects.create(
            provider=self.target_provider,
            file_type="image",
            file=SimpleUploadedFile("blocked-role-spotlight.jpg", b"img", content_type="image/jpeg"),
            caption="لمحة محظورة بوضع المزود",
        )
        self.client.force_login(self.viewer)

    def test_provider_block_is_scoped_to_active_role(self):
        response = self.client.post(
            reverse("providers:provider_block", kwargs={"provider_id": self.target_provider.id}) + "?mode=provider"
        )

        self.assertEqual(response.status_code, 200, response.json())
        self.assertTrue(
            ProviderVisibilityBlock.objects.filter(
                user=self.viewer,
                provider=self.target_provider,
                role_context="provider",
            ).exists()
        )

        provider_blocks_response = self.client.get(reverse("providers:my_visibility_blocks") + "?mode=provider")
        self.assertEqual(provider_blocks_response.status_code, 200)
        self.assertEqual(len(provider_blocks_response.json()["blocked_providers"]), 1)

        client_blocks_response = self.client.get(reverse("providers:my_visibility_blocks") + "?mode=client")
        self.assertEqual(client_blocks_response.status_code, 200)
        self.assertEqual(client_blocks_response.json()["blocked_providers"], [])

    def test_content_blocks_are_scoped_to_active_role_and_include_portfolio(self):
        portfolio_response = self.client.post(
            reverse("providers:portfolio_hide", kwargs={"item_id": self.portfolio_item.id}) + "?mode=provider"
        )
        spotlight_response = self.client.post(
            reverse("providers:spotlight_hide", kwargs={"item_id": self.spotlight_item.id}) + "?mode=provider"
        )

        self.assertEqual(portfolio_response.status_code, 200, portfolio_response.json())
        self.assertEqual(spotlight_response.status_code, 200, spotlight_response.json())
        self.assertTrue(
            ProviderPortfolioVisibilityBlock.objects.filter(
                user=self.viewer,
                portfolio_item=self.portfolio_item,
                role_context="provider",
            ).exists()
        )
        self.assertTrue(
            ProviderSpotlightVisibilityBlock.objects.filter(
                user=self.viewer,
                spotlight_item=self.spotlight_item,
                role_context="provider",
            ).exists()
        )

        provider_blocks_response = self.client.get(reverse("providers:my_visibility_blocks") + "?mode=provider")
        self.assertEqual(provider_blocks_response.status_code, 200)
        payload = provider_blocks_response.json()
        self.assertEqual({row["portfolio_item_id"] for row in payload["blocked_portfolio"]}, {self.portfolio_item.id})
        self.assertEqual({row["spotlight_id"] for row in payload["blocked_spotlights"]}, {self.spotlight_item.id})

        client_blocks_response = self.client.get(reverse("providers:my_visibility_blocks") + "?mode=client")
        self.assertEqual(client_blocks_response.status_code, 200)
        self.assertEqual(client_blocks_response.json()["blocked_portfolio"], [])
        self.assertEqual(client_blocks_response.json()["blocked_spotlights"], [])


class ProviderServiceModerationReportTests(TestCase):
    def setUp(self):
        self.viewer = User.objects.create_user(
            phone="0503900021",
            username="service.viewer",
            role_state=UserRole.CLIENT,
        )
        self.provider_user = User.objects.create_user(
            phone="0503900022",
            username="service.report.provider",
            role_state=UserRole.PROVIDER,
        )
        self.provider = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود الخدمات",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        category = Category.objects.create(name="تنظيف")
        subcategory = SubCategory.objects.create(category=category, name="تنظيف منازل")
        self.service = ProviderService.objects.create(
            provider=self.provider,
            subcategory=subcategory,
            title="خدمة مخالفة",
            description="وصف الخدمة المخالفة",
            is_active=True,
        )
        self.client.force_login(self.viewer)

    def test_reporting_service_creates_content_team_moderation_case(self):
        response = self.client.post(
            reverse("providers:provider_service_report", kwargs={"item_id": self.service.id}),
            {
                "reason": "محتوى مضلل",
                "details": "تفاصيل البلاغ من صفحة الخدمة",
            },
        )

        self.assertEqual(response.status_code, 201, response.json())
        case = ModerationCase.objects.get(id=response.json()["case_id"])
        self.assertEqual(case.reporter_id, self.viewer.id)
        self.assertEqual(case.reported_user_id, self.provider_user.id)
        self.assertEqual(case.source_app, "providers")
        self.assertEqual(case.source_model, "ProviderService")
        self.assertEqual(case.source_object_id, str(self.service.id))
        self.assertEqual(case.category, "service")
        self.assertEqual(case.assigned_team_code, "content")


class ProviderProfileReportTests(TestCase):
    def setUp(self):
        self.viewer = User.objects.create_user(
            phone="0503900031",
            username="provider.report.viewer",
            role_state=UserRole.CLIENT,
        )
        self.provider_user = User.objects.create_user(
            phone="0503900032",
            username="provider.report.target",
            role_state=UserRole.PROVIDER,
        )
        self.provider = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود مبلّغ عنه",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.client.force_login(self.viewer)

    def test_reporting_provider_profile_creates_support_ticket(self):
        response = self.client.post(
            reverse("providers:provider_report", kwargs={"provider_id": self.provider.id}),
            {
                "reason": "انتحال أو احتيال",
                "details": "تفاصيل البلاغ على مزود الخدمة",
            },
        )

        self.assertEqual(response.status_code, 201, response.json())
        ticket = SupportTicket.objects.get(id=response.json()["ticket_id"])
        self.assertEqual(ticket.requester_id, self.viewer.id)
        self.assertEqual(ticket.reported_kind, "provider_profile")
        self.assertEqual(ticket.reported_object_id, str(self.provider.id))
        self.assertEqual(ticket.reported_user_id, self.provider_user.id)
        self.assertIn("بلاغ على مقدم خدمة", ticket.description)


class ProviderFollowersRoleIsolationTests(TestCase):
    def setUp(self):
        self.owner_user = User.objects.create_user(
            phone="0503400001",
            username="provider.owner",
            role_state=UserRole.PROVIDER,
        )
        self.owner_provider = ProviderProfile.objects.create(
            user=self.owner_user,
            provider_type="individual",
            display_name="مزودي",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.follower_user = User.objects.create_user(
            phone="0503400002",
            username="provider.follower",
            first_name="عميل",
            last_name="متابع",
            role_state=UserRole.PROVIDER,
        )
        self.follower_provider = ProviderProfile.objects.create(
            user=self.follower_user,
            provider_type="individual",
            display_name="مزود المتابع",
            bio="-",
            city="جدة",
            region="منطقة مكة",
            accepts_urgent=True,
            is_verified_blue=True,
        )
        ProviderFollow.objects.create(
            user=self.follower_user,
            provider=self.owner_provider,
            role_context="client",
        )
        ProviderFollow.objects.create(
            user=self.follower_user,
            provider=self.owner_provider,
            role_context="provider",
        )
        self.client.force_login(self.owner_user)

    @staticmethod
    def _rows_from_payload(payload):
        if isinstance(payload, dict):
            return payload.get("results", [])
        return payload

    def test_my_followers_returns_all_unique_followers_across_modes(self):
        response = self.client.get(
            reverse("providers:my_followers"),
            HTTP_X_ACCOUNT_MODE="provider",
        )

        self.assertEqual(response.status_code, 200)
        rows = self._rows_from_payload(response.json())
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["id"], self.follower_user.id)
        self.assertEqual(rows[0]["follow_role_context"], "provider")
        self.assertEqual(rows[0]["provider_id"], self.follower_provider.id)
        self.assertEqual(rows[0]["display_name"], self.follower_provider.display_name)

    def test_my_followers_respects_query_mode_over_header(self):
        response = self.client.get(
            f"{reverse('providers:my_followers')}?mode=client",
            HTTP_X_ACCOUNT_MODE="provider",
        )

        self.assertEqual(response.status_code, 200)
        rows = self._rows_from_payload(response.json())
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["id"], self.follower_user.id)
        self.assertEqual(rows[0]["follow_role_context"], "provider")
        self.assertEqual(rows[0]["provider_id"], self.follower_provider.id)
        self.assertEqual(rows[0]["display_name"], self.follower_provider.display_name)

    def test_public_followers_is_scoped_to_provider_mode(self):
        response = self.client.get(
            f"{reverse('providers:provider_followers', kwargs={'provider_id': self.owner_provider.id})}?mode=provider"
        )

        self.assertEqual(response.status_code, 200)
        rows = self._rows_from_payload(response.json())
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["id"], self.follower_user.id)
        self.assertEqual(rows[0]["follow_role_context"], "provider")
        self.assertEqual(rows[0]["provider_id"], self.follower_provider.id)
        self.assertEqual(rows[0]["display_name"], self.follower_provider.display_name)
        self.assertTrue(rows[0]["is_verified_blue"])
        self.assertFalse(rows[0]["is_verified_green"])

    def test_public_followers_respects_client_mode(self):
        response = self.client.get(
            f"{reverse('providers:provider_followers', kwargs={'provider_id': self.owner_provider.id})}?mode=client"
        )

        self.assertEqual(response.status_code, 200)
        rows = self._rows_from_payload(response.json())
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["id"], self.follower_user.id)
        self.assertEqual(rows[0]["follow_role_context"], "client")
        self.assertIsNone(rows[0]["provider_id"])
        self.assertEqual(rows[0]["display_name"], "عميل متابع")
        self.assertTrue(rows[0]["is_verified_blue"])

    def test_public_followers_scope_all_deduplicates_and_prefers_provider_identity(self):
        response = self.client.get(
            f"{reverse('providers:provider_followers', kwargs={'provider_id': self.owner_provider.id})}?scope=all"
        )

        self.assertEqual(response.status_code, 200)
        rows = self._rows_from_payload(response.json())
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["id"], self.follower_user.id)
        self.assertEqual(rows[0]["follow_role_context"], "provider")
        self.assertEqual(rows[0]["provider_id"], self.follower_provider.id)
        self.assertEqual(rows[0]["display_name"], self.follower_provider.display_name)

    def test_my_following_and_public_stats_use_unique_cross_mode_totals(self):
        request_category = Category.objects.create(name="طلبات المزود")
        followed_one = ProviderProfile.objects.create(
            user=User.objects.create_user(
                phone="0503400005",
                username="provider.followed.one",
                role_state=UserRole.PROVIDER,
            ),
            provider_type="individual",
            display_name="مزود أول",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        followed_two = ProviderProfile.objects.create(
            user=User.objects.create_user(
                phone="0503400006",
                username="provider.followed.two",
                role_state=UserRole.PROVIDER,
            ),
            provider_type="individual",
            display_name="مزود ثان",
            bio="-",
            city="جدة",
            region="منطقة مكة",
            accepts_urgent=True,
        )
        ProviderFollow.objects.create(user=self.owner_user, provider=followed_one, role_context="client")
        ProviderFollow.objects.create(user=self.owner_user, provider=followed_one, role_context="provider")
        ProviderFollow.objects.create(user=self.owner_user, provider=followed_two, role_context="provider")

        following_response = self.client.get(reverse("providers:my_following"))
        self.assertEqual(following_response.status_code, 200)
        following_rows = self._rows_from_payload(following_response.json())
        self.assertEqual(len(following_rows), 2)
        self.assertEqual({row["id"] for row in following_rows}, {followed_one.id, followed_two.id})

        repeat_requester = User.objects.create_user(
            phone="0503400007",
            username="provider.request.client.repeat",
            role_state=UserRole.CLIENT,
        )
        single_requester = User.objects.create_user(
            phone="0503400008",
            username="provider.request.client.single",
            role_state=UserRole.CLIENT,
        )
        request_subcategory = SubCategory.objects.create(category=request_category, name="طلب")
        ServiceRequest.objects.create(
            client=repeat_requester,
            provider=self.owner_provider,
            subcategory=request_subcategory,
            title="طلب أول",
            description="تفاصيل",
            request_type=RequestType.NORMAL,
            status=RequestStatus.CANCELLED,
            city="الرياض",
        )
        ServiceRequest.objects.create(
            client=repeat_requester,
            provider=self.owner_provider,
            subcategory=request_subcategory,
            title="طلب ثان",
            description="تفاصيل",
            request_type=RequestType.NORMAL,
            status=RequestStatus.COMPLETED,
            city="الرياض",
        )
        ServiceRequest.objects.create(
            client=single_requester,
            provider=self.owner_provider,
            subcategory=request_subcategory,
            title="طلب ثالث",
            description="تفاصيل",
            request_type=RequestType.NORMAL,
            status=RequestStatus.NEW,
            city="الرياض",
        )

        stats_response = self.client.get(
            reverse("providers:provider_public_stats", args=[self.owner_provider.id])
        )
        self.assertEqual(stats_response.status_code, 200)
        stats = stats_response.json()
        self.assertEqual(int(stats["followers_count"]), 1)
        self.assertEqual(int(stats["following_count"]), 2)
        self.assertEqual(int(stats["total_clients"]), 2)
        self.assertEqual(int(stats["completed_requests"]), 1)

    def test_public_following_returns_actual_verification_flags(self):
        response = self.client.get(
            f"{reverse('providers:provider_following', kwargs={'provider_id': self.owner_provider.id})}?scope=all"
        )

        self.assertEqual(response.status_code, 200)
        rows = self._rows_from_payload(response.json())
        self.assertEqual(rows, [])

        owner_follows_verified = ProviderProfile.objects.create(
            user=User.objects.create_user(
                phone="0503400003",
                username="provider.followed.verified",
                role_state=UserRole.PROVIDER,
            ),
            provider_type="individual",
            display_name="مزود موثق",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
            is_verified_blue=True,
        )
        owner_follows_plain = ProviderProfile.objects.create(
            user=User.objects.create_user(
                phone="0503400004",
                username="provider.followed.plain",
                role_state=UserRole.PROVIDER,
            ),
            provider_type="individual",
            display_name="مزود غير موثق",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        ProviderFollow.objects.create(user=self.owner_user, provider=owner_follows_verified, role_context="provider")
        ProviderFollow.objects.create(user=self.owner_user, provider=owner_follows_plain, role_context="provider")

        response = self.client.get(
            f"{reverse('providers:provider_following', kwargs={'provider_id': self.owner_provider.id})}?scope=all"
        )

        self.assertEqual(response.status_code, 200)
        rows = self._rows_from_payload(response.json())
        rows_by_name = {row["display_name"]: row for row in rows}
        self.assertTrue(rows_by_name["مزود موثق"]["is_verified_blue"])
        self.assertFalse(rows_by_name["مزود غير موثق"]["is_verified_blue"])
        self.assertFalse(rows_by_name["مزود غير موثق"]["is_verified_green"])


class ProviderRatingDisplayTests(TestCase):
    def setUp(self):
        self.category = Category.objects.create(name="خدمات منزلية")
        self.subcategory = SubCategory.objects.create(category=self.category, name="صيانة")
        self.provider_user = User.objects.create_user(
            phone="0503500001",
            username="provider.rating.owner",
            role_state=UserRole.PROVIDER,
        )
        self.provider = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود التقييم",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )

    @staticmethod
    def _rows_from_payload(payload):
        if isinstance(payload, dict):
            return payload.get("results", [])
        return payload

    def _create_review(self, *, rating: int, phone_suffix: str) -> Review:
        client_user = User.objects.create_user(
            phone=f"050350{phone_suffix}",
            username=f"provider.rating.client.{phone_suffix}",
            role_state=UserRole.CLIENT,
        )
        request = ServiceRequest.objects.create(
            client=client_user,
            provider=self.provider,
            subcategory=self.subcategory,
            title="طلب تقييم",
            description="طلب مكتمل لاختبار التقييم",
            request_type=RequestType.NORMAL,
            status=RequestStatus.COMPLETED,
            city="الرياض",
        )
        with self.captureOnCommitCallbacks(execute=True):
            return Review.objects.create(
                request=request,
                provider=self.provider,
                client=client_user,
                rating=rating,
                response_speed=rating,
                cost_value=rating,
                quality=rating,
                credibility=rating,
                on_time=rating,
                moderation_status=ReviewModerationStatus.APPROVED,
            )

    def test_review_save_refreshes_provider_rating_without_celery_worker(self):
        self._create_review(rating=5, phone_suffix="0002")

        self.provider.refresh_from_db()
        self.assertEqual(self.provider.rating_count, 1)
        self.assertEqual(float(self.provider.rating_avg), 5.0)

    def test_public_provider_surfaces_use_approved_reviews_when_cached_rating_is_stale(self):
        self._create_review(rating=5, phone_suffix="0003")
        self._create_review(rating=4, phone_suffix="0004")
        ProviderProfile.objects.filter(id=self.provider.id).update(
            rating_avg=0,
            rating_count=0,
        )

        list_response = self.client.get(reverse("providers:provider_list"))
        self.assertEqual(list_response.status_code, 200)
        rows = self._rows_from_payload(list_response.json())
        row = next(item for item in rows if item["id"] == self.provider.id)
        self.assertEqual(int(row["rating_count"]), 2)
        self.assertAlmostEqual(float(row["rating_avg"]), 4.5)

        detail_response = self.client.get(reverse("providers:provider_detail", args=[self.provider.id]))
        self.assertEqual(detail_response.status_code, 200)
        detail = detail_response.json()
        self.assertEqual(int(detail["rating_count"]), 2)
        self.assertAlmostEqual(float(detail["rating_avg"]), 4.5)

        stats_response = self.client.get(reverse("providers:provider_public_stats", args=[self.provider.id]))
        self.assertEqual(stats_response.status_code, 200)
        stats = stats_response.json()
        self.assertEqual(int(stats["rating_count"]), 2)
        self.assertAlmostEqual(float(stats["rating_avg"]), 4.5)


class ProviderReviewChatThreadAccessTests(TestCase):
    def setUp(self):
        self.category = Category.objects.create(name="خدمات منزلية")
        self.subcategory = SubCategory.objects.create(category=self.category, name="تنظيف")
        self.provider_user = User.objects.create_user(
            phone="0503510001",
            username="provider.review.chat.owner",
            role_state=UserRole.PROVIDER,
        )
        self.provider = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود التقييم",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.reviewer_user = User.objects.create_user(
            phone="0503510002",
            username="provider.review.chat.reviewer",
            role_state=UserRole.CLIENT,
            first_name="مراجع",
        )
        self.viewer_user = User.objects.create_user(
            phone="0503510003",
            username="provider.review.chat.viewer",
            role_state=UserRole.CLIENT,
            first_name="زائر",
        )
        self.service_request = ServiceRequest.objects.create(
            client=self.reviewer_user,
            provider=self.provider,
            subcategory=self.subcategory,
            title="طلب مكتمل",
            description="-",
            request_type=RequestType.NORMAL,
            status=RequestStatus.COMPLETED,
            city="الرياض",
        )
        self.review = Review.objects.create(
            request=self.service_request,
            provider=self.provider,
            client=self.reviewer_user,
            rating=5,
            response_speed=5,
            cost_value=5,
            quality=5,
            credibility=5,
            on_time=5,
            moderation_status=ReviewModerationStatus.APPROVED,
        )

    def test_logged_in_user_can_open_chat_with_review_author(self):
        self.client.force_login(self.viewer_user)

        response = self.client.post(reverse("reviews:provider_chat_thread", args=[self.review.id]))

        self.assertEqual(response.status_code, 200, response.json())
        payload = response.json()
        thread = Thread.objects.get(id=payload["thread_id"])
        self.assertTrue(thread.is_direct)
        self.assertEqual({thread.participant_1_id, thread.participant_2_id}, {self.viewer_user.id, self.reviewer_user.id})
        self.assertEqual(thread.participant_mode_for_user(self.reviewer_user), Thread.ContextMode.CLIENT)

    def test_review_author_cannot_open_chat_with_self(self):
        self.client.force_login(self.reviewer_user)

        response = self.client.post(reverse("reviews:provider_chat_thread", args=[self.review.id]))

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["detail"], "لا يمكنك محادثة نفسك")


class ProviderRegistrationLocationTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            phone="0503300099",
            password="StrongPass123!",
            username="provider.location.client",
            role_state=UserRole.CLIENT,
            first_name="عميل",
        )
        self.url = reverse("providers:provider_register")

    def test_provider_registration_saves_multiple_selected_subcategories(self):
        self.client.force_login(self.user)
        first_category = Category.objects.create(name="الخدمات المنزلية")
        second_category = Category.objects.create(name="الخدمات التقنية")
        first_subcategory = SubCategory.objects.create(category=first_category, name="كهرباء")
        second_subcategory = SubCategory.objects.create(category=second_category, name="شبكات")

        response = self.client.post(
            self.url,
            {
                "provider_type": "individual",
                "display_name": "مزود متعدد الأقسام",
                "bio": "نبذة مختصرة عن مزود الخدمة",
                "country": "السعودية",
                "city": "الرياض",
                "location_label": "السعودية - الرياض",
                "lat": "24.713552",
                "lng": "46.675297",
                "subcategory_ids": [first_subcategory.id, second_subcategory.id],
                "coverage_radius_km": 25,
            },
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 201, response.json())
        self.user.refresh_from_db()
        profile = self.user.provider_profile
        self.assertEqual(self.user.role_state, UserRole.PROVIDER)
        self.assertEqual(
            list(profile.providercategory_set.order_by("subcategory_id").values_list("subcategory_id", flat=True)),
            sorted([first_subcategory.id, second_subcategory.id]),
        )

    def test_provider_registration_saves_country_location_label_and_coordinates(self):
        self.client.force_login(self.user)

        response = self.client.post(
            self.url,
            {
                "provider_type": "individual",
                "display_name": "مزود جدة",
                "bio": "نبذة مختصرة عن مزود الخدمة",
                "country": "السعودية",
                "city": "جدة",
                "location_label": "السعودية - جدة",
                "lat": "21.543333",
                "lng": "39.172779",
                "coverage_radius_km": 25,
            },
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 201, response.json())
        self.user.refresh_from_db()
        profile = self.user.provider_profile
        self.assertEqual(self.user.role_state, UserRole.PROVIDER)
        self.assertEqual(profile.country, "السعودية")
        self.assertEqual(profile.city, "السعودية - جدة")
        self.assertEqual(profile.region, "")
        self.assertEqual(str(profile.lat), "21.543333")
        self.assertEqual(str(profile.lng), "39.172779")

    def test_provider_registration_allows_missing_location(self):
        self.client.force_login(self.user)

        response = self.client.post(
            self.url,
            {
                "provider_type": "individual",
                "display_name": "مزود بدون موقع",
                "bio": "نبذة مختصرة عن مزود الخدمة",
                "country": "",
                "city": "",
                "location_label": "",
                "lat": None,
                "lng": None,
                "coverage_radius_km": 25,
            },
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 201, response.json())
        self.user.refresh_from_db()
        profile = self.user.provider_profile
        self.assertEqual(self.user.role_state, UserRole.PROVIDER)
        self.assertEqual(profile.country, "")
        self.assertEqual(profile.city, "")
        self.assertEqual(profile.region, "")
        self.assertIsNone(profile.lat)
        self.assertIsNone(profile.lng)

    def test_provider_registration_rejects_coverage_radius_above_300(self):
        self.client.force_login(self.user)

        response = self.client.post(
            self.url,
            {
                "provider_type": "individual",
                "display_name": "مزود نطاق واسع",
                "bio": "نبذة مختصرة عن مزود الخدمة",
                "country": "السعودية",
                "city": "الرياض",
                "location_label": "السعودية - الرياض",
                "lat": "24.713552",
                "lng": "46.675297",
                "coverage_radius_km": 301,
            },
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("coverage_radius_km", response.json())


class MyProviderProfileCoverageRadiusTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            phone="0503300107",
            password="StrongPass123!",
            username="provider.radius.owner",
            role_state=UserRole.PROVIDER,
            first_name="مزود",
        )
        self.provider = ProviderProfile.objects.create(
            user=self.user,
            provider_type="individual",
            display_name="مزود نطاق الخدمة",
            bio="نبذة مختصرة عن مزود الخدمة",
            country="السعودية",
            city="السعودية - الرياض",
            coverage_radius_km=25,
        )
        self.url = reverse("providers:my_profile")

    def test_profile_update_rejects_coverage_radius_above_300(self):
        self.client.force_login(self.user)

        response = self.client.patch(
            self.url,
            {"coverage_radius_km": 301},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("coverage_radius_km", response.json())
        self.provider.refresh_from_db()
        self.assertEqual(self.provider.coverage_radius_km, 25)

    def test_profile_update_accepts_coverage_radius_300(self):
        self.client.force_login(self.user)

        response = self.client.patch(
            self.url,
            {"coverage_radius_km": 300},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 200, response.json())
        self.provider.refresh_from_db()
        self.assertEqual(self.provider.coverage_radius_km, 300)


class MyProviderSubcategoriesViewTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            phone="0503300108",
            password="StrongPass123!",
            username="provider.subcategories.owner",
            role_state=UserRole.PROVIDER,
            first_name="مزود",
        )
        self.provider = ProviderProfile.objects.create(
            user=self.user,
            provider_type="individual",
            display_name="مزود التصنيفات",
            bio="-",
            city="الرياض",
        )
        self.url = reverse("providers:my_subcategories")

    def test_put_replaces_provider_subcategories_and_preserves_explicit_urgent_flags(self):
        self.client.force_login(self.user)
        first_category = Category.objects.create(name="الخدمات المنزلية")
        second_category = Category.objects.create(name="الخدمات التقنية")
        first_subcategory = SubCategory.objects.create(category=first_category, name="كهرباء")
        second_subcategory = SubCategory.objects.create(category=second_category, name="شبكات")

        response = self.client.put(
            self.url,
            data=json.dumps(
                {
                    "subcategory_ids": [first_subcategory.id, second_subcategory.id],
                    "subcategory_settings": [
                        {
                            "subcategory_id": first_subcategory.id,
                            "accepts_urgent": True,
                            "requires_geo_scope": True,
                        },
                        {
                            "subcategory_id": second_subcategory.id,
                            "accepts_urgent": False,
                            "requires_geo_scope": False,
                        },
                    ],
                }
            ),
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 200, response.json())
        self.assertEqual(
            response.json()["subcategory_ids"],
            [first_subcategory.id, second_subcategory.id],
        )
        self.assertEqual(
            list(self.provider.providercategory_set.order_by("subcategory_id").values_list("subcategory_id", flat=True)),
            [first_subcategory.id, second_subcategory.id],
        )
        self.assertEqual(
            list(
                self.provider.providercategory_set.order_by("subcategory_id").values_list(
                    "accepts_urgent", flat=True
                )
            ),
            [True, False],
        )
        self.assertEqual(
            list(
                self.provider.providercategory_set.order_by("subcategory_id").values_list(
                    "requires_geo_scope", flat=True
                )
            ),
            [True, False],
        )

    def test_get_returns_requires_geo_scope_for_each_selected_subcategory(self):
        self.client.force_login(self.user)
        category = Category.objects.create(name="الخدمات الإبداعية")
        local_subcategory = SubCategory.objects.create(category=category, name="تصوير")
        remote_subcategory = SubCategory.objects.create(category=category, name="ترجمة")
        self.provider.providercategory_set.create(
            subcategory=local_subcategory,
            accepts_urgent=True,
            requires_geo_scope=True,
        )
        self.provider.providercategory_set.create(
            subcategory=remote_subcategory,
            accepts_urgent=False,
            requires_geo_scope=False,
        )

        response = self.client.get(self.url)

        self.assertEqual(response.status_code, 200, response.json())
        settings_by_id = {
            item["subcategory_id"]: item
            for item in response.json()["subcategory_settings"]
        }
        self.assertTrue(settings_by_id[local_subcategory.id]["requires_geo_scope"])
        self.assertFalse(settings_by_id[remote_subcategory.id]["requires_geo_scope"])


class MyProviderServicesListCreateViewTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            phone="0503300110",
            password="StrongPass123!",
            username="provider.my.services.owner",
            role_state=UserRole.PROVIDER,
            first_name="مزود",
        )
        self.provider = ProviderProfile.objects.create(
            user=self.user,
            provider_type="individual",
            display_name="مزود خدماتي",
            bio="-",
            city="الرياض",
        )
        self.list_url = reverse("providers:my_services")

    def test_create_service_persists_requires_geo_scope_on_provider_category(self):
        self.client.force_login(self.user)
        category = Category.objects.create(name="الخدمات الرقمية")
        subcategory = SubCategory.objects.create(category=category, name="تصميم واجهات")

        response = self.client.post(
            self.list_url,
            data=json.dumps(
                {
                    "subcategory_id": subcategory.id,
                    "title": "تصميم واجهات احترافي",
                    "description": "-",
                    "price_unit": "fixed",
                    "price_from": 100,
                    "price_to": 200,
                    "is_active": True,
                    "accepts_urgent": False,
                    "requires_geo_scope": False,
                }
            ),
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 201, response.json())
        relation = self.provider.providercategory_set.get(subcategory=subcategory)
        self.assertFalse(relation.requires_geo_scope)
        self.assertFalse(response.json()["requires_geo_scope"])

    def test_patch_service_updates_requires_geo_scope_for_existing_service(self):
        self.client.force_login(self.user)
        category = Category.objects.create(name="الخدمات الرقمية")
        subcategory = SubCategory.objects.create(category=category, name="تصميم صفحات هبوط")
        self.provider.providercategory_set.create(
            subcategory=subcategory,
            accepts_urgent=False,
            requires_geo_scope=True,
        )
        service = ProviderService.objects.create(
            provider=self.provider,
            subcategory=subcategory,
            title="تصميم صفحات هبوط",
            is_active=True,
        )

        response = self.client.patch(
            reverse("providers:my_service_detail", kwargs={"pk": service.id}),
            data=json.dumps({"requires_geo_scope": False}),
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 200, response.json())
        relation = self.provider.providercategory_set.get(subcategory=subcategory)
        self.assertFalse(relation.requires_geo_scope)
        self.assertFalse(response.json()["requires_geo_scope"])


class ProviderServicesPublicListViewTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            phone="0503300109",
            password="StrongPass123!",
            username="provider.public.services.owner",
            role_state=UserRole.PROVIDER,
            first_name="مزود",
        )
        self.provider = ProviderProfile.objects.create(
            user=self.user,
            provider_type="individual",
            display_name="مزود خدمات عام",
            bio="-",
            city="الرياض",
        )
        self.url = reverse("providers:provider_services", kwargs={"provider_id": self.provider.id})

    def test_public_services_return_requires_geo_scope_per_subcategory_setting(self):
        category = Category.objects.create(name="الخدمات الإبداعية")
        local_subcategory = SubCategory.objects.create(category=category, name="تصوير")
        remote_subcategory = SubCategory.objects.create(category=category, name="ترجمة")

        self.provider.providercategory_set.create(
            subcategory=local_subcategory,
            accepts_urgent=True,
            requires_geo_scope=True,
        )
        self.provider.providercategory_set.create(
            subcategory=remote_subcategory,
            accepts_urgent=False,
            requires_geo_scope=False,
        )

        local_service = ProviderService.objects.create(
            provider=self.provider,
            subcategory=local_subcategory,
            title="تصوير مناسبات",
            is_active=True,
        )
        remote_service = ProviderService.objects.create(
            provider=self.provider,
            subcategory=remote_subcategory,
            title="ترجمة مستندات",
            is_active=True,
        )

        response = self.client.get(self.url)

        self.assertEqual(response.status_code, 200, response.json())
        items_by_id = {item["id"]: item for item in response.json()}
        self.assertTrue(items_by_id[local_service.id]["requires_geo_scope"])
        self.assertFalse(items_by_id[remote_service.id]["requires_geo_scope"])

    def test_provider_detail_selected_subcategories_include_scope_and_urgent_flags(self):
        category = Category.objects.create(name="الخدمات الإبداعية")
        remote_subcategory = SubCategory.objects.create(category=category, name="تصميم واجهات")

        self.provider.providercategory_set.create(
            subcategory=remote_subcategory,
            accepts_urgent=True,
            requires_geo_scope=False,
        )

        response = self.client.get(reverse("providers:provider_detail", kwargs={"pk": self.provider.id}))

        self.assertEqual(response.status_code, 200, response.json())
        selected = {
            item["id"]: item
            for item in response.json()["selected_subcategories"]
        }
        self.assertTrue(selected[remote_subcategory.id]["accepts_urgent"])
        self.assertFalse(selected[remote_subcategory.id]["requires_geo_scope"])

    def test_provider_detail_includes_additional_info_fields(self):
        self.provider.about_details = "شرح تفصيلي للخدمة"
        self.provider.qualifications = [{"title": "بكالوريوس"}, {"title": "شهادة مهنية"}]
        self.provider.experiences = ["خبرة أولى", {"title": "خبرة ثانية"}]
        self.provider.save(update_fields=["about_details", "qualifications", "experiences"])

        response = self.client.get(reverse("providers:provider_detail", kwargs={"pk": self.provider.id}))

        self.assertEqual(response.status_code, 200, response.json())
        body = response.json()
        self.assertEqual(body["about_details"], "شرح تفصيلي للخدمة")
        self.assertEqual(body["qualifications"], [{"title": "بكالوريوس"}, {"title": "شهادة مهنية"}])
        self.assertEqual(body["experiences"], ["خبرة أولى", {"title": "خبرة ثانية"}])

    def test_provider_rating_summary_includes_review_category_averages(self):
        category = Category.objects.create(name="الخدمات الإبداعية")
        subcategory = SubCategory.objects.create(category=category, name="تصميم واجهات")
        client_user = User.objects.create_user(
            phone="0503300111",
            password="StrongPass123!",
            username="provider.public.reviews.client",
            role_state=UserRole.CLIENT,
        )
        service_request = ServiceRequest.objects.create(
            client=client_user,
            provider=self.provider,
            subcategory=subcategory,
            title="طلب تقييم",
            description="-",
            request_type=RequestType.NORMAL,
            status=RequestStatus.COMPLETED,
            city="الرياض",
        )
        Review.objects.create(
            request=service_request,
            provider=self.provider,
            client=client_user,
            rating=5,
            response_speed=4,
            cost_value=3,
            quality=5,
            credibility=4,
            on_time=2,
            moderation_status=ReviewModerationStatus.APPROVED,
        )

        response = self.client.get(reverse("reviews:provider_rating", kwargs={"provider_id": self.provider.id}))

        self.assertEqual(response.status_code, 200, response.json())
        payload = response.json()
        self.assertEqual(payload["response_speed_avg"], "4.00")
        self.assertEqual(payload["cost_value_avg"], "3.00")
        self.assertEqual(payload["quality_avg"], "5.00")
        self.assertEqual(payload["credibility_avg"], "4.00")
        self.assertEqual(payload["on_time_avg"], "2.00")
