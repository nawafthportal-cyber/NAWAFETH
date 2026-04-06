from django.test import TestCase
from django.urls import resolve

from .views import MobileWebSubscriptionPaymentView


class MobileWebRootRoutesTests(TestCase):
    def test_subscription_payment_page_is_available_at_root_path(self):
        match = resolve("/plans/payment/")

        self.assertEqual(match.func.view_class, MobileWebSubscriptionPaymentView)