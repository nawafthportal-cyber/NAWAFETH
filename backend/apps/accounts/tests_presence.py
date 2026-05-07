"""Tests for the provider presence (online/offline) feature."""
from datetime import timedelta

from django.core.cache import cache
from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from .models import User, UserRole
from .presence import effective_last_seen, is_online, is_online_value, mark_seen


class PresenceHelperTests(TestCase):
    def setUp(self):
        cache.clear()
        self.user = User.objects.create_user(phone="+966500000001", role_state=UserRole.PROVIDER)

    def test_anonymous_is_never_online(self):
        self.assertFalse(is_online(None))

    def test_user_without_last_seen_is_offline(self):
        self.assertFalse(is_online(self.user))

    def test_recent_last_seen_is_online(self):
        self.user.last_seen = timezone.now()
        self.assertTrue(is_online(self.user))

    def test_old_last_seen_is_offline(self):
        self.user.last_seen = timezone.now() - timedelta(minutes=10)
        self.assertFalse(is_online(self.user))

    def test_is_online_value_window_boundary(self):
        # Default window is 120s.
        self.assertTrue(is_online_value(timezone.now() - timedelta(seconds=30)))
        self.assertFalse(is_online_value(timezone.now() - timedelta(seconds=300)))

    def test_mark_seen_updates_db(self):
        mark_seen(self.user)
        self.user.refresh_from_db()
        self.assertIsNotNone(self.user.last_seen)
        self.assertTrue(is_online(self.user))

    def test_mark_seen_throttle_skips_repeated_writes(self):
        mark_seen(self.user)
        self.user.refresh_from_db()
        first_ts = self.user.last_seen
        # Second call within the throttle window must NOT update the DB.
        mark_seen(self.user)
        self.user.refresh_from_db()
        self.assertEqual(self.user.last_seen, first_ts)

    def test_repeated_mark_seen_keeps_effective_presence_fresh_while_db_write_is_throttled(self):
        mark_seen(self.user)
        self.user.refresh_from_db()
        first_db_ts = self.user.last_seen

        stale_db_ts = timezone.now() - timedelta(seconds=300)
        User.objects.filter(pk=self.user.pk).update(last_seen=stale_db_ts)
        self.user.refresh_from_db()

        mark_seen(self.user)

        self.user.refresh_from_db()
        self.assertEqual(self.user.last_seen, stale_db_ts)
        self.assertGreater(effective_last_seen(self.user), first_db_ts)
        self.assertTrue(is_online(self.user))


class HeartbeatEndpointTests(TestCase):
    def setUp(self):
        cache.clear()
        self.client = APIClient()
        self.user = User.objects.create_user(
            phone="+966500000002", password="pw", role_state=UserRole.PROVIDER
        )
        self.client.force_authenticate(self.user)

    def test_heartbeat_marks_user_online(self):
        url = reverse("accounts:heartbeat")
        resp = self.client.post(url)
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.data["is_online"])
        self.assertIsNotNone(resp.data["last_seen"])
        self.user.refresh_from_db()
        self.assertIsNotNone(self.user.last_seen)

    def test_heartbeat_requires_auth(self):
        anon = APIClient()
        resp = anon.post(reverse("accounts:heartbeat"))
        self.assertIn(resp.status_code, (401, 403))


class LastSeenMiddlewareTests(TestCase):
    """The middleware should auto-update last_seen on any authenticated call."""

    def setUp(self):
        cache.clear()
        self.client = APIClient()
        self.user = User.objects.create_user(
            phone="+966500000003", password="pw", role_state=UserRole.PROVIDER
        )
        self.client.force_authenticate(self.user)

    def test_authenticated_request_updates_last_seen(self):
        self.assertIsNone(self.user.last_seen)
        # Hit any authenticated endpoint.
        self.client.get(reverse("accounts:wallet"))
        self.user.refresh_from_db()
        self.assertIsNotNone(self.user.last_seen)
