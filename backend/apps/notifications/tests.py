from types import SimpleNamespace
from unittest.mock import patch

from django.test import SimpleTestCase

from apps.marketplace.models import OfferStatus

from .models import EventType
from .signals import notify_offer_selected


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
