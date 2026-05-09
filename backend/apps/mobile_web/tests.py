from datetime import timedelta

from django.test import TestCase
from django.urls import reverse
from django.utils.html import escape
from django.utils import timezone

from apps.accounts.models import User, UserRole
from apps.providers.models import ProviderProfile
from apps.subscriptions.configuration import canonical_subscription_plan_for_tier
from apps.subscriptions.models import Subscription, SubscriptionStatus
from apps.subscriptions.tiering import CanonicalPlanTier


class ProviderModeRequestAccessTests(TestCase):
    def setUp(self):
        self.provider_user = User.objects.create_user(
            phone="0502000001",
            username="provider.mobileweb",
            role_state=UserRole.PROVIDER,
        )
        self.provider_profile = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود الجوال",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.client.force_login(self.provider_user)

    def test_provider_mode_blocks_request_entry_points(self):
        self.client.cookies["nw_account_mode"] = "provider"
        scenarios = [
            (
                reverse("mobile_web:add_service"),
                "إنشاء الطلبات متاح في وضع العميل",
            ),
            (
                reverse("mobile_web:urgent_request"),
                "الطلب العاجل متاح في وضع العميل فقط",
            ),
            (
                reverse("mobile_web:request_quote"),
                "طلب عروض الأسعار متاح في وضع العميل فقط",
            ),
            (
                reverse("mobile_web:service_request_form"),
                "إنشاء الطلبات متاح في وضع العميل فقط",
            ),
        ]

        for path, title in scenarios:
            with self.subTest(path=path):
                response = self.client.get(path)

                self.assertEqual(response.status_code, 200)
                self.assertTrue(response.context["provider_mode_blocked"])
                self.assertEqual(response.context["provider_mode_target"], path)
                self.assertContains(response, title)
                self.assertContains(response, 'data-provider-request-switch="client"')
                self.assertContains(response, 'data-provider-request-target="{}"'.format(path))

    def test_service_request_target_strips_mode_and_keeps_other_query_values(self):
        path = reverse("mobile_web:service_request_form")
        response = self.client.get(
            path,
            {
                "provider_id": str(self.provider_profile.id),
                "return_to": "/mobile-web/search/?q=test",
                "mode": "provider",
            },
        )
        expected_target = (
            f"{path}?provider_id={self.provider_profile.id}"
            "&return_to=%2Fmobile-web%2Fsearch%2F%3Fq%3Dtest"
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.context["provider_mode_blocked"])
        self.assertEqual(response.context["provider_mode_target"], expected_target)
        self.assertEqual(response.context["provider_mode_block"]["target"], expected_target)
        self.assertContains(response, 'data-provider-request-target="{}"'.format(escape(expected_target)))

    def test_provider_account_in_client_mode_is_not_blocked(self):
        self.client.cookies["nw_account_mode"] = "client"
        response = self.client.get(reverse("mobile_web:add_service"))

        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.context["provider_mode_blocked"])


class ProfileCompletionRedirectTests(TestCase):
    def test_legacy_profile_completion_route_redirects_to_provider_profile_edit(self):
        response = self.client.get(reverse("mobile_web:profile_completion"))

        self.assertEqual(response.status_code, 302)
        self.assertEqual(response["Location"], "/provider-profile-edit/")


class ProviderDashboardCompletionLinkTests(TestCase):
    def setUp(self):
        self.provider_user = User.objects.create_user(
            phone="0502000099",
            username="provider.dashboard",
            role_state=UserRole.PROVIDER,
        )
        ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود لوحة التحكم",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.client.force_login(self.provider_user)

    def test_completion_card_points_to_basic_profile_section(self):
        response = self.client.get(reverse("mobile_web:provider_dashboard"))

        self.assertEqual(response.status_code, 200)
        self.assertContains(
            response,
            'href="/provider-profile-edit/?tab=account&amp;focus=fullName&amp;section=basic"',
        )


class PromotionNewRequestCapabilityTests(TestCase):
    def setUp(self):
        self.provider_user = User.objects.create_user(
            phone="0502000101",
            username="provider.promo",
            role_state=UserRole.PROVIDER,
        )
        ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود الترويج",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.client.force_login(self.provider_user)

    def _activate_professional_subscription(self):
        now = timezone.now()
        Subscription.objects.create(
            user=self.provider_user,
            plan=canonical_subscription_plan_for_tier(CanonicalPlanTier.PROFESSIONAL),
            status=SubscriptionStatus.ACTIVE,
            start_at=now - timedelta(days=1),
            end_at=now + timedelta(days=30),
            grace_end_at=now + timedelta(days=35),
        )

    def test_promo_messages_are_locked_without_professional_subscription(self):
        response = self.client.get(reverse("mobile_web:promotion_new_request"))

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'data-promo-messages-enabled="0"')
        self.assertContains(response, 'data-service-toggle="promo_messages" disabled')
        self.assertContains(response, "الرسائل الدعائية متاحة فقط للمشتركين في الباقة الاحترافية.")

    def test_promo_messages_are_enabled_for_professional_subscription(self):
        self._activate_professional_subscription()

        response = self.client.get(reverse("mobile_web:promotion_new_request"))

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'data-promo-messages-enabled="1"')
        self.assertNotContains(response, 'data-service-toggle="promo_messages" disabled')
        self.assertNotContains(response, "الرسائل الدعائية متاحة فقط للمشتركين في الباقة الاحترافية.")
