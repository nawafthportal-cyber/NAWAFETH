from types import SimpleNamespace

from django.contrib.auth import get_user_model
from django.test import TestCase

from apps.accounts.models import UserRole
from apps.notifications.models import Notification, NotificationPreference, NotificationTier
from apps.providers.models import ProviderProfile

from .models import SupportTicket, SupportTicketStatus, SupportTicketType
from .services import change_ticket_status, notify_ticket_requester_about_comment


class SupportNotificationPreferencesTests(TestCase):
    def setUp(self):
        self.User = get_user_model()
        self.agent = self.User.objects.create_user(
            phone="+966500000910",
            password="test-pass",
            role_state=UserRole.STAFF,
        )

    def _create_user(self, *, phone: str, role_state: str):
        return self.User.objects.create_user(
            phone=phone,
            password="test-pass",
            role_state=role_state,
        )

    def _create_provider_profile(self, *, user):
        return ProviderProfile.objects.create(
            user=user,
            provider_type="individual",
            display_name="Provider",
            bio="Provider bio",
        )

    def _create_ticket(self, *, requester):
        return SupportTicket.objects.create(
            requester=requester,
            ticket_type=SupportTicketType.TECH,
            description="مشكلة في الطلب",
        )

    def test_comment_notification_uses_client_audience_mode(self):
        requester = self._create_user(phone="+966500000911", role_state=UserRole.CLIENT)
        ticket = self._create_ticket(requester=requester)

        notification = notify_ticket_requester_about_comment(
            ticket=ticket,
            comment=SimpleNamespace(id=1, is_internal=False, text="تم الرد على البلاغ"),
            by_user=self.agent,
        )

        self.assertIsNotNone(notification)
        self.assertEqual(notification.audience_mode, Notification.AudienceMode.CLIENT)
        self.assertEqual(Notification.objects.filter(user=requester).count(), 1)

    def test_comment_notification_uses_provider_audience_mode(self):
        requester = self._create_user(phone="+966500000912", role_state=UserRole.PROVIDER)
        self._create_provider_profile(user=requester)
        ticket = self._create_ticket(requester=requester)

        notification = notify_ticket_requester_about_comment(
            ticket=ticket,
            comment=SimpleNamespace(id=2, is_internal=False, text="تحديث من فريق الدعم"),
            by_user=self.agent,
        )

        self.assertIsNotNone(notification)
        self.assertEqual(notification.audience_mode, Notification.AudienceMode.PROVIDER)
        self.assertEqual(Notification.objects.filter(user=requester).count(), 1)

    def test_comment_notification_respects_disabled_client_preference(self):
        requester = self._create_user(phone="+966500000913", role_state=UserRole.CLIENT)
        ticket = self._create_ticket(requester=requester)
        NotificationPreference.objects.create(
            user=requester,
            key="report_status_change",
            audience_mode=NotificationPreference.AudienceMode.CLIENT,
            enabled=False,
            tier=NotificationTier.BASIC,
        )

        notification = notify_ticket_requester_about_comment(
            ticket=ticket,
            comment=SimpleNamespace(id=3, is_internal=False, text="تحديث"),
            by_user=self.agent,
        )

        self.assertIsNone(notification)
        self.assertEqual(Notification.objects.filter(user=requester).count(), 0)

    def test_status_change_respects_disabled_provider_preference(self):
        requester = self._create_user(phone="+966500000914", role_state=UserRole.PROVIDER)
        self._create_provider_profile(user=requester)
        ticket = self._create_ticket(requester=requester)
        NotificationPreference.objects.create(
            user=requester,
            key="report_status_change",
            audience_mode=NotificationPreference.AudienceMode.PROVIDER,
            enabled=False,
            tier=NotificationTier.BASIC,
        )

        change_ticket_status(
            ticket=ticket,
            new_status=SupportTicketStatus.IN_PROGRESS,
            by_user=self.agent,
            note="بدء المعالجة",
        )

        self.assertEqual(Notification.objects.filter(user=requester).count(), 0)