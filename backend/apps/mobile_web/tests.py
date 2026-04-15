from django.contrib.auth import get_user_model
from django.test import TestCase
from django.urls import resolve

from apps.providers.models import ProviderProfile

from .views import (
    MobileWebAdditionalServicesPaymentView,
    MobileWebLegacyLoginRedirectView,
    MobileWebLegacyRequestRedirectView,
    MobileWebPromotionPaymentView,
    MobileWebSearchProvidersView,
    MobileWebSubscriptionPaymentView,
)


class MobileWebRootRoutesTests(TestCase):
    def test_subscription_payment_page_is_available_at_root_path(self):
        match = resolve("/plans/payment/")

        self.assertEqual(match.func.view_class, MobileWebSubscriptionPaymentView)

    def test_promotion_payment_page_is_available_at_root_path(self):
        match = resolve("/promotion/payment/")

        self.assertEqual(match.func.view_class, MobileWebPromotionPaymentView)

    def test_additional_services_payment_page_is_available_at_root_path(self):
        match = resolve("/additional-services/payment/")

        self.assertEqual(match.func.view_class, MobileWebAdditionalServicesPaymentView)

    def test_legacy_request_detail_redirect_is_available_without_trailing_slash(self):
        match = resolve("/requests/1")

        self.assertEqual(match.func.view_class, MobileWebLegacyRequestRedirectView)

    def test_legacy_request_detail_redirect_is_available_with_trailing_slash(self):
        match = resolve("/requests/1/")

        self.assertEqual(match.func.view_class, MobileWebLegacyRequestRedirectView)

    def test_legacy_request_detail_redirects_client_mode_to_orders_page(self):
        response = self.client.get("/requests/1?mode=client")

        self.assertEqual(response.status_code, 302)
        self.assertEqual(response["Location"], "/orders/1/?mode=client")

    def test_legacy_request_detail_redirects_provider_mode_to_provider_orders_page(self):
        response = self.client.get("/requests/1?mode=provider")

        self.assertEqual(response.status_code, 302)
        self.assertEqual(response["Location"], "/provider-orders/1/?mode=provider")

    def test_search_providers_route_is_available(self):
        match = resolve("/search-providers/")

        self.assertEqual(match.func.view_class, MobileWebSearchProvidersView)

    def test_mobile_web_login_route_redirect_is_available(self):
        match = resolve("/mobile-web/login/")

        self.assertEqual(match.func.view_class, MobileWebLegacyLoginRedirectView)

    def test_mobile_web_login_redirects_to_canonical_login_with_query_params(self):
        response = self.client.get("/mobile-web/login/?next=/chats/&source=legacy")

        self.assertEqual(response.status_code, 302)
        self.assertEqual(response["Location"], "/login/?next=/chats/&source=legacy")

    def test_search_providers_redirects_to_search_with_query_params(self):
        response = self.client.get("/search-providers/?q=plumber&city=riyadh&sort=rating")

        self.assertEqual(response.status_code, 302)
        self.assertEqual(response["Location"], "/search/?q=plumber&city=riyadh&sort=rating")


class MobileWebAdditionalServicesViewContextTests(TestCase):
    def test_additional_services_uses_provider_profile_display_name(self):
        user_model = get_user_model()
        user = user_model.objects.create_user(
            phone="0501112233",
            username="extra_provider_name_test",
            password="P@ssw0rd!123",
            first_name="اسم",
            last_name="المستخدم",
        )
        ProviderProfile.objects.create(
            user=user,
            provider_type="individual",
            display_name="اسم المختص المعتمد",
            bio="نبذة اختبار",
        )

        self.client.force_login(user)
        response = self.client.get("/additional-services/")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.context["additional_services_provider_display_name"], "اسم المختص المعتمد")
