from django.test import TestCase
from django.urls import reverse
from django.utils.html import escape

from apps.accounts.models import User, UserRole
from apps.providers.models import ProviderProfile


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
