"""
Phase 2 tests — PlatformConfig, Client RBAC scope, Celery reminder tasks.
"""

from datetime import timedelta
from decimal import Decimal
from unittest.mock import patch

import pytest
from django.test import TestCase, override_settings
from django.utils import timezone

from apps.accounts.models import User
from apps.backoffice.models import AccessLevel, Dashboard, UserAccessProfile
from apps.core.models import PlatformConfig, ReminderLog


# ────────────────────────────────────────────
# PlatformConfig singleton tests
# ────────────────────────────────────────────


class PlatformConfigTests(TestCase):

    def setUp(self):
        from django.core.cache import cache
        cache.clear()

    def test_load_creates_default_instance(self):
        self.assertEqual(PlatformConfig.objects.count(), 0)
        config = PlatformConfig.load()
        self.assertEqual(PlatformConfig.objects.count(), 1)
        self.assertEqual(config.pk, 1)
        self.assertEqual(config.vat_percent, Decimal("15.00"))
        self.assertEqual(config.subscription_grace_days, 7)

    def test_singleton_enforced(self):
        PlatformConfig.load()
        # Creating another with different pk still results in pk=1
        c2 = PlatformConfig(pk=99, vat_percent=Decimal("10.00"))
        c2.save()
        self.assertEqual(PlatformConfig.objects.count(), 1)
        self.assertEqual(PlatformConfig.objects.first().pk, 1)

    def test_delete_prevented(self):
        config = PlatformConfig.load()
        config.delete()
        self.assertTrue(PlatformConfig.objects.filter(pk=1).exists())

    def test_cache_cleared_on_save(self):
        from django.core.cache import cache
        from apps.core.models import PLATFORM_CONFIG_CACHE_KEY

        config = PlatformConfig.load()
        # Cache should be populated
        self.assertIsNotNone(cache.get(PLATFORM_CONFIG_CACHE_KEY))
        # Saving should clear cache
        config.vat_percent = Decimal("20.00")
        config.save()
        self.assertIsNone(cache.get(PLATFORM_CONFIG_CACHE_KEY))

    def test_subscription_reminder_days_parsing(self):
        config = PlatformConfig.load()
        config.subscription_reminder_days_before = "7,3,1"
        config.save()
        config = PlatformConfig.load()
        self.assertEqual(config.get_subscription_reminder_days(), [7, 3, 1])

    def test_subscription_reminder_days_handles_empty(self):
        config = PlatformConfig.load()
        config.subscription_reminder_days_before = ""
        config.save()
        config = PlatformConfig.load()
        self.assertEqual(config.get_subscription_reminder_days(), [])


# ────────────────────────────────────────────
# Client RBAC scope tests
# ────────────────────────────────────────────


class ClientRBACTests(TestCase):

    def setUp(self):
        self.extras_dash = Dashboard.objects.create(code="extras", name_ar="إضافية", is_active=True)
        self.subs_dash = Dashboard.objects.create(code="subs", name_ar="اشتراكات", is_active=True)
        self.analytics_dash = Dashboard.objects.create(code="analytics", name_ar="تحليلات", is_active=True)

        self.client_user = User.objects.create_user(phone="0501000001", password="Pass12345!")

        self.profile = UserAccessProfile.objects.create(
            user=self.client_user,
            level=AccessLevel.CLIENT,
        )
        # Even if we add non-extras dashboards to M2M, Client should be restricted
        self.profile.allowed_dashboards.add(self.extras_dash, self.subs_dash, self.analytics_dash)

    def test_client_allowed_extras(self):
        self.assertTrue(self.profile.is_allowed("extras"))

    def test_client_denied_subs(self):
        self.assertFalse(self.profile.is_allowed("subs"))

    def test_client_denied_analytics(self):
        self.assertFalse(self.profile.is_allowed("analytics"))

    def test_dashboard_allowed_function_client_scope(self):
        from apps.dashboard.access import dashboard_allowed

        self.assertTrue(dashboard_allowed(self.client_user, "extras"))
        self.assertFalse(dashboard_allowed(self.client_user, "subs"))
        self.assertFalse(dashboard_allowed(self.client_user, "analytics"))

    def test_client_profile_sync_keeps_role_non_staff(self):
        from apps.accounts.models import UserRole
        from apps.dashboard.access import sync_dashboard_user_access

        self.client_user.role_state = UserRole.CLIENT
        self.client_user.save(update_fields=["role_state"])
        changed_fields = sync_dashboard_user_access(
            self.client_user,
            access_profile=self.profile,
            force_staff_role_state=True,
        )
        if changed_fields:
            self.client_user.save(update_fields=changed_fields)
        self.client_user.refresh_from_db()

        self.assertFalse(self.client_user.is_staff)
        self.assertEqual(self.client_user.role_state, UserRole.CLIENT)

    def test_admin_level_not_restricted(self):
        admin_user = User.objects.create_user(phone="0501000002", password="Pass12345!")
        admin_user.is_staff = True
        admin_user.save()
        admin_profile = UserAccessProfile.objects.create(
            user=admin_user,
            level=AccessLevel.ADMIN,
        )
        self.assertTrue(admin_profile.is_allowed("extras"))
        self.assertTrue(admin_profile.is_allowed("subs"))
        self.assertTrue(admin_profile.is_allowed("analytics"))


# ────────────────────────────────────────────
# Celery reminder tasks tests
# ────────────────────────────────────────────


class SubscriptionReminderTaskTests(TestCase):

    def setUp(self):
        from apps.subscriptions.models import SubscriptionPlan, SubscriptionStatus, Subscription

        self.user = User.objects.create_user(phone="0502000001", password="Pass12345!")
        self.plan = SubscriptionPlan.objects.create(
            code="TEST_PLAN", title="Test Plan", price=Decimal("100.00"),
        )
        # Subscription expiring in 3 days
        self.sub = Subscription.objects.create(
            user=self.user,
            plan=self.plan,
            status=SubscriptionStatus.ACTIVE,
            start_at=timezone.now() - timedelta(days=27),
            end_at=timezone.now() + timedelta(days=3),
        )
        # Configure to remind at 3 days
        config = PlatformConfig.load()
        config.subscription_reminder_days_before = "7,3,1"
        config.save()

    @patch("apps.notifications.services.create_notification")
    def test_sends_reminder_for_expiring_subscription(self, mock_notify):
        from apps.core.tasks import send_subscription_renewal_reminders

        count = send_subscription_renewal_reminders()
        self.assertEqual(count, 1)
        mock_notify.assert_called_once()
        # ReminderLog created
        self.assertTrue(ReminderLog.objects.filter(
            user=self.user,
            reminder_type=ReminderLog.ReminderType.SUBSCRIPTION_EXPIRY,
            reference_id=self.sub.pk,
            days_before=3,
        ).exists())

    @patch("apps.notifications.services.create_notification")
    def test_no_duplicate_reminder(self, mock_notify):
        from apps.core.tasks import send_subscription_renewal_reminders

        # First run
        send_subscription_renewal_reminders()
        # Second run should not create another
        count = send_subscription_renewal_reminders()
        self.assertEqual(count, 0)
        self.assertEqual(mock_notify.call_count, 1)


class VerificationReminderTaskTests(TestCase):

    def setUp(self):
        from apps.verification.models import VerificationRequest, VerificationStatus

        self.user = User.objects.create_user(phone="0503000001", password="Pass12345!")
        config = PlatformConfig.load()
        config.verification_reminder_days_before = 30
        config.save()

        self.badge = VerificationRequest.objects.create(
            requester=self.user,
            status=VerificationStatus.ACTIVE,
            expires_at=timezone.now() + timedelta(days=30),
        )

    @patch("apps.notifications.services.create_notification")
    def test_sends_verification_reminder(self, mock_notify):
        from apps.core.tasks import send_verification_expiry_reminders

        count = send_verification_expiry_reminders()
        self.assertEqual(count, 1)
        mock_notify.assert_called_once()


class PromoAutoCompleteTaskTests(TestCase):

    def setUp(self):
        from apps.promo.models import PromoRequest, PromoRequestStatus, PromoAdType

        self.user = User.objects.create_user(phone="0504000001", password="Pass12345!")
        now = timezone.now()
        self.promo = PromoRequest.objects.create(
            requester=self.user,
            title="حملة تجريبية",
            ad_type=PromoAdType.BUNDLE,
            start_at=now - timedelta(days=7),
            end_at=now - timedelta(hours=1),  # already ended
            status=PromoRequestStatus.ACTIVE,
        )

    def test_auto_marks_expired_promos(self):
        from apps.core.tasks import auto_complete_expired_promos
        from apps.promo.models import PromoRequestStatus

        count = auto_complete_expired_promos()
        self.assertEqual(count, 1)
        self.promo.refresh_from_db()
        self.assertEqual(self.promo.status, PromoRequestStatus.EXPIRED)


class PromoScheduledMessageTaskTests(TestCase):

    @patch("apps.promo.services.send_due_promo_messages")
    def test_delegates_to_promo_service(self, mock_send_due):
        from apps.core.tasks import send_due_promo_messages

        mock_send_due.return_value = 3

        count = send_due_promo_messages()

        self.assertEqual(count, 3)
        mock_send_due.assert_called_once()
        _, kwargs = mock_send_due.call_args
        self.assertEqual(kwargs["limit"], 100)
        self.assertIsNotNone(kwargs["now"])
