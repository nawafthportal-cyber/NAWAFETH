from types import SimpleNamespace
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.test import SimpleTestCase

from apps.accounts.models import UserRole
from apps.marketplace.models import OfferStatus
from apps.providers.models import ProviderProfile

from .models import EventType
from .signals import notify_offer_selected
from .services import get_or_create_notification_preferences


def _offer_instance(*, status: str = OfferStatus.SELECTED):
    provider_user = SimpleNamespace(id=11)
    provider = SimpleNamespace(user=provider_user, user_id=provider_user.id)
    client = SimpleNamespace(id=21)
    request = SimpleNamespace(id=31, title="طلب تجريبي", client=client)
    return SimpleNamespace(
        id=41,
        status=status,
        provider=provider,
        request=request,
    )


class OfferSelectedNotificationSignalTests(SimpleTestCase):
    @patch("apps.notifications.signals.create_notification")
    @patch("apps.notifications.signals.EventLog.objects.filter")
    def test_skips_duplicate_offer_selected_notification(self, event_filter_mock, create_notification_mock):
        event_filter_mock.return_value.exists.return_value = True

        notify_offer_selected(
            sender=None,
            instance=_offer_instance(),
            created=False,
        )

        create_notification_mock.assert_not_called()
        event_filter_mock.assert_called_once_with(
            event_type=EventType.OFFER_SELECTED,
            target_user_id=11,
            offer_id=41,
        )

    @patch("apps.notifications.signals.create_notification")
    @patch("apps.notifications.signals.EventLog.objects.filter")
    def test_sends_notification_once_when_no_previous_event(self, event_filter_mock, create_notification_mock):
        event_filter_mock.return_value.exists.return_value = False
        instance = _offer_instance()

        notify_offer_selected(
            sender=None,
            instance=instance,
            created=False,
        )

        create_notification_mock.assert_called_once()
        kwargs = create_notification_mock.call_args.kwargs
        self.assertEqual(kwargs["event_type"], EventType.OFFER_SELECTED)
        self.assertEqual(kwargs["offer_id"], instance.id)
        self.assertEqual(kwargs["request_id"], instance.request.id)
        self.assertEqual(kwargs["audience_mode"], "provider")
        self.assertEqual(kwargs["pref_key"], "service_reply")
        self.assertEqual(kwargs["user"], instance.provider.user)
        self.assertEqual(kwargs["actor"], instance.request.client)

    @patch("apps.notifications.signals.create_notification")
    @patch("apps.notifications.signals.EventLog.objects.filter")
    def test_ignores_non_selected_status(self, event_filter_mock, create_notification_mock):
        notify_offer_selected(
            sender=None,
            instance=_offer_instance(status=OfferStatus.PENDING),
            created=False,
        )

        event_filter_mock.assert_not_called()
        create_notification_mock.assert_not_called()


class NotificationPreferenceExposureTests(TestCase):
    def setUp(self):
        user_model = get_user_model()
        self.provider_user = user_model.objects.create_user(
            phone="+966500001111",
            password="test-pass",
            role_state=UserRole.PROVIDER,
        )
        ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="Provider",
            bio="Provider bio",
        )

    def test_provider_preferences_hide_unimplemented_catalog_entries(self):
        prefs = get_or_create_notification_preferences(
            self.provider_user,
            mode="provider",
            exposed_only=True,
        )

        keys = {pref.key for pref in prefs}

        self.assertIn("new_request", keys)
        self.assertIn("request_status_change", keys)
        self.assertIn("new_chat_message", keys)
        self.assertIn("new_follow", keys)
        self.assertIn("new_comment_services", keys)
        self.assertIn("new_like_profile", keys)
        self.assertIn("new_like_services", keys)
        self.assertIn("competitive_offer_request", keys)
        self.assertIn("ads_and_offers", keys)
        self.assertIn("positive_review", keys)
        self.assertIn("negative_review", keys)
        self.assertIn("new_provider_same_category", keys)
        self.assertIn("highlight_same_category", keys)
        self.assertIn("new_payment", keys)
        self.assertIn("new_ad_visit", keys)
        self.assertIn("report_completed", keys)
        self.assertIn("verification_completed", keys)
        self.assertIn("paid_subscription_completed", keys)
        self.assertIn("customer_service_package_completed", keys)
        self.assertIn("finance_package_completed", keys)
        self.assertIn("scheduled_ticket_reminder", keys)
