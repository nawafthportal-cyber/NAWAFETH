from datetime import timedelta

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import User, UserRole
from apps.subscriptions.models import Subscription, SubscriptionPlan, SubscriptionStatus

from .models import ProviderCoverImage, ProviderProfile


class ProviderCoverGalleryTests(TestCase):
    def setUp(self):
        self.provider_user = User.objects.create_user(
            phone="0504400011",
            username="provider.cover.gallery",
            role_state=UserRole.PROVIDER,
        )
        self.provider = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود الخلفيات",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.plan = SubscriptionPlan.objects.create(
            code="cover-gallery-basic",
            tier="basic",
            title="الأساسية",
            description="باقة اختبار لخلفيات الملف",
            period="year",
            price="0.00",
            notifications_enabled=True,
            banner_images_limit=2,
            spotlight_quota=1,
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
        self.client.force_login(self.provider_user)
        self.list_url = reverse("providers:my_cover_gallery")

    def _upload_payload(self, name: str):
        return {
            "image": SimpleUploadedFile(name, b"img", content_type="image/jpeg"),
        }

    def test_create_cover_image_respects_plan_limit_and_updates_profile_payload(self):
        first = self.client.post(self.list_url, self._upload_payload("cover-1.jpg"))
        second = self.client.post(self.list_url, self._upload_payload("cover-2.jpg"))
        third = self.client.post(self.list_url, self._upload_payload("cover-3.jpg"))

        self.assertEqual(first.status_code, 201)
        self.assertEqual(second.status_code, 201)
        self.assertEqual(third.status_code, 400)
        self.assertEqual(third.json().get("error_code"), "cover_gallery_limit_exceeded")
        self.assertEqual(ProviderCoverImage.objects.filter(provider=self.provider).count(), 2)

        profile_response = self.client.get(reverse("providers:my_profile"))
        self.assertEqual(profile_response.status_code, 200)
        body = profile_response.json()
        gallery = body.get("cover_gallery") or []
        self.assertEqual(len(gallery), 2)
        self.assertEqual(len(body.get("cover_images") or []), 2)
        self.assertEqual(body.get("cover_image"), gallery[0]["image_url"])

    def test_delete_primary_cover_promotes_next_image(self):
        self.client.post(self.list_url, self._upload_payload("cover-1.jpg"))
        second = self.client.post(self.list_url, self._upload_payload("cover-2.jpg"))
        second_body = second.json()
        second_id = second_body["item"]["id"]
        second_url = second_body["item"]["image_url"]
        first_id = ProviderCoverImage.objects.filter(provider=self.provider).order_by("sort_order", "id").first().id

        delete_response = self.client.delete(reverse("providers:my_cover_gallery_detail", args=[first_id]))

        self.assertEqual(delete_response.status_code, 200)
        self.provider.refresh_from_db()
        self.assertEqual(self.provider.cover_image.url, second_url)
        self.assertEqual(ProviderCoverImage.objects.filter(provider=self.provider).count(), 1)
        remaining = ProviderCoverImage.objects.get(provider=self.provider)
        self.assertEqual(remaining.id, second_id)
        self.assertEqual(remaining.sort_order, 0)
        self.assertTrue(delete_response.json()["results"][0]["is_primary"])

    def test_provider_can_delete_one_cover_and_replace_it_after_reaching_limit(self):
        first = self.client.post(self.list_url, self._upload_payload("cover-1.jpg"))
        second = self.client.post(self.list_url, self._upload_payload("cover-2.jpg"))
        blocked = self.client.post(self.list_url, self._upload_payload("cover-3.jpg"))

        self.assertEqual(first.status_code, 201)
        self.assertEqual(second.status_code, 201)
        self.assertEqual(blocked.status_code, 400)
        self.assertEqual(blocked.json().get("error_code"), "cover_gallery_limit_exceeded")

        first_id = first.json()["item"]["id"]
        delete_response = self.client.delete(reverse("providers:my_cover_gallery_detail", args=[first_id]))
        self.assertEqual(delete_response.status_code, 200)
        self.assertEqual(delete_response.json().get("count"), 1)
        self.assertEqual(delete_response.json().get("remaining"), 1)

        replacement = self.client.post(self.list_url, self._upload_payload("cover-3.jpg"))
        self.assertEqual(replacement.status_code, 201)
        self.assertEqual(replacement.json().get("count"), 2)
        self.assertEqual(replacement.json().get("remaining"), 0)
        self.assertEqual(ProviderCoverImage.objects.filter(provider=self.provider).count(), 2)

        profile_response = self.client.get(reverse("providers:my_profile"))
        self.assertEqual(profile_response.status_code, 200)
        gallery = profile_response.json().get("cover_gallery") or []
        self.assertEqual(len(gallery), 2)

    def test_provider_without_cover_gallery_quota_cannot_upload_any_cover(self):
        self.plan.banner_images_limit = 0
        self.plan.save(update_fields=["banner_images_limit"])

        response = self.client.post(self.list_url, self._upload_payload("cover-blocked.jpg"))

        self.assertEqual(response.status_code, 400)
        body = response.json()
        self.assertEqual(body.get("error_code"), "cover_gallery_unavailable")
        self.assertEqual(body.get("cover_images_limit"), 0)
        self.assertEqual(ProviderCoverImage.objects.filter(provider=self.provider).count(), 0)