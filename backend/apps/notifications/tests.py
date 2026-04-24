from datetime import timedelta

import re
from pathlib import Path

from django.test import TestCase
from django.utils import timezone

from apps.accounts.models import User, UserRole
from apps.extras.models import ExtraPurchase, ExtraPurchaseStatus, ExtraType
from apps.extras_portal.models import ExtrasPortalSubscription, ExtrasPortalSubscriptionStatus
from apps.notifications.models import Notification, NotificationPreference
from apps.notifications.services import (
    EVENT_TO_PREF_KEY,
    NOTIFICATION_CATALOG,
    create_notification,
    get_or_create_notification_preferences,
)
from apps.providers.models import ProviderProfile
from apps.subscriptions.configuration import canonical_subscription_plan_for_tier
from apps.subscriptions.models import Subscription, SubscriptionStatus
from apps.subscriptions.tiering import CanonicalPlanTier


BASIC_PROVIDER_KEYS = {
    "new_request",
    "request_status_change",
    "urgent_request",
    "report_status_change",
    "new_chat_message",
    "subscription_expiry",
    "verification_expiry",
    "service_reply",
}

PIONEER_PROVIDER_KEYS = {
    "new_follow",
    "new_comment_services",
    "new_like_profile",
    "new_like_services",
    "competitive_offer_request",
}

PROFESSIONAL_PROVIDER_KEYS = {
    "review_update",
    "positive_review",
    "negative_review",
    "new_provider_same_category",
    "highlight_same_category",
    "ads_and_offers",
}

EXTRA_ALWAYS_KEYS = {
    "new_payment",
    "verification_completed",
    "paid_subscription_completed",
}

EXTRA_PROMO_KEYS = {"new_ad_visit"}

EXTRA_PORTAL_KEYS = {
    "report_completed",
    "customer_service_package_completed",
    "finance_package_completed",
    "scheduled_ticket_reminder",
}

ALL_PROVIDER_EXPOSED_KEYS = {
    key
    for key, cfg in NOTIFICATION_CATALOG.items()
    if cfg.get("expose_in_settings", True)
    and "provider" in tuple(cfg.get("audience_modes") or ())
}


class ProviderNotificationPreferencesTests(TestCase):
    def setUp(self):
        self.provider_user = User.objects.create_user(
            phone="0504400001",
            username="provider.notifications",
            role_state=UserRole.PROVIDER,
        )
        self.provider_profile = ProviderProfile.objects.create(
            user=self.provider_user,
            provider_type="individual",
            display_name="مزود الإشعارات",
            bio="-",
            city="الرياض",
            region="منطقة الرياض",
            accepts_urgent=True,
        )
        self.client.force_login(self.provider_user)

    def _set_provider_state(
        self,
        *,
        canonical_tier: str | None,
        has_promo_boost: bool = False,
        has_extras_portal: bool = False,
    ):
        Subscription.objects.filter(user=self.provider_user).delete()
        ExtraPurchase.objects.filter(user=self.provider_user).delete()
        ExtrasPortalSubscription.objects.filter(provider=self.provider_profile).delete()

        if canonical_tier is not None:
            plan = canonical_subscription_plan_for_tier(canonical_tier)
            now = timezone.now()
            Subscription.objects.create(
                user=self.provider_user,
                plan=plan,
                status=SubscriptionStatus.ACTIVE,
                start_at=now - timedelta(days=1),
                end_at=now + timedelta(days=30),
                grace_end_at=now + timedelta(days=35),
            )

        if has_promo_boost:
            now = timezone.now()
            ExtraPurchase.objects.create(
                user=self.provider_user,
                sku="promo_boost_7d",
                title="Boost إعلان 7 أيام",
                extra_type=ExtraType.TIME_BASED,
                status=ExtraPurchaseStatus.ACTIVE,
                start_at=now - timedelta(days=1),
                end_at=now + timedelta(days=6),
            )

        if has_extras_portal:
            now = timezone.now()
            ExtrasPortalSubscription.objects.create(
                provider=self.provider_profile,
                status=ExtrasPortalSubscriptionStatus.ACTIVE,
                plan_title="بوابة الخدمات الإضافية",
                started_at=now - timedelta(days=1),
                ends_at=now + timedelta(days=30),
            )

    def _fetch_provider_preferences_payload(self):
        response = self.client.get("/api/notifications/preferences/?mode=provider")
        self.assertEqual(response.status_code, 200)
        return response.json()

    def _fetch_provider_preferences(self):
        payload = self._fetch_provider_preferences_payload()
        results = payload.get("results", [])
        by_key = {item["key"]: item for item in results}
        self.assertSetEqual(set(by_key), ALL_PROVIDER_EXPOSED_KEYS)
        return by_key

    def test_provider_preferences_api_exposes_locked_plan_bound_items(self):
        payload = self._fetch_provider_preferences_payload()
        sections = payload.get("sections", [])
        by_key = self._fetch_provider_preferences()

        self.assertEqual(
            [section["key"] for section in sections],
            ["basic", "pioneer", "professional", "extra"],
        )
        self.assertEqual(sections[0]["title"], "الباقة الأساسية")
        self.assertEqual(sections[-1]["title"], "الخدمات الإضافية")
        self.assertEqual(sections[-1]["note_title"], "إدارة العملاء")
        self.assertIn("مواعيد ورسائل تنبيه", sections[-1]["note_body"])
        self.assertIn("new_request", by_key)
        self.assertIn("ads_and_offers", by_key)
        self.assertNotIn("platform_recommendations", by_key)
        self.assertFalse(by_key["new_request"]["locked"])
        self.assertTrue(by_key["ads_and_offers"]["locked"])
        self.assertIn("يلزم الاشتراك في الباقة", by_key["ads_and_offers"]["locked_reason"])

    def test_provider_preferences_matrix_matches_plan_and_extra_entitlements(self):
        scenarios = [
            {
                "label": "provider_unsubscribed",
                "tier": None,
                "has_promo_boost": False,
                "has_extras_portal": False,
                "locked": PIONEER_PROVIDER_KEYS | PROFESSIONAL_PROVIDER_KEYS | EXTRA_PROMO_KEYS | EXTRA_PORTAL_KEYS,
            },
            {
                "label": "provider_basic",
                "tier": CanonicalPlanTier.BASIC,
                "has_promo_boost": False,
                "has_extras_portal": False,
                "locked": PIONEER_PROVIDER_KEYS | PROFESSIONAL_PROVIDER_KEYS | EXTRA_PROMO_KEYS | EXTRA_PORTAL_KEYS,
            },
            {
                "label": "provider_pioneer",
                "tier": CanonicalPlanTier.PIONEER,
                "has_promo_boost": False,
                "has_extras_portal": False,
                "locked": PROFESSIONAL_PROVIDER_KEYS | EXTRA_PROMO_KEYS | EXTRA_PORTAL_KEYS,
            },
            {
                "label": "provider_professional",
                "tier": CanonicalPlanTier.PROFESSIONAL,
                "has_promo_boost": False,
                "has_extras_portal": False,
                "locked": EXTRA_PROMO_KEYS | EXTRA_PORTAL_KEYS,
            },
            {
                "label": "provider_professional_with_boost",
                "tier": CanonicalPlanTier.PROFESSIONAL,
                "has_promo_boost": True,
                "has_extras_portal": False,
                "locked": EXTRA_PORTAL_KEYS,
            },
            {
                "label": "provider_professional_with_portal",
                "tier": CanonicalPlanTier.PROFESSIONAL,
                "has_promo_boost": False,
                "has_extras_portal": True,
                "locked": EXTRA_PROMO_KEYS,
            },
            {
                "label": "provider_professional_with_boost_and_portal",
                "tier": CanonicalPlanTier.PROFESSIONAL,
                "has_promo_boost": True,
                "has_extras_portal": True,
                "locked": set(),
            },
        ]

        always_unlocked = BASIC_PROVIDER_KEYS | EXTRA_ALWAYS_KEYS

        for scenario in scenarios:
            with self.subTest(scenario=scenario["label"]):
                self._set_provider_state(
                    canonical_tier=scenario["tier"],
                    has_promo_boost=scenario["has_promo_boost"],
                    has_extras_portal=scenario["has_extras_portal"],
                )
                by_key = self._fetch_provider_preferences()
                locked_keys = {key for key, item in by_key.items() if item["locked"]}
                self.assertSetEqual(locked_keys, scenario["locked"])

                for key in always_unlocked - scenario["locked"]:
                    self.assertFalse(by_key[key]["locked"], msg=f"{scenario['label']} should unlock {key}")

        self._set_provider_state(canonical_tier=CanonicalPlanTier.BASIC)
        basic_response = self._fetch_provider_preferences()
        self.assertIn("يلزم الاشتراك في الباقة", basic_response["new_follow"]["locked_reason"])
        self.assertIn("يلزم الاشتراك في الباقة", basic_response["ads_and_offers"]["locked_reason"])
        self.assertEqual(basic_response["new_ad_visit"]["locked_reason"], "يتطلب إضافة ترويج فعالة.")
        self.assertEqual(
            basic_response["report_completed"]["locked_reason"],
            "يتطلب اشتراكًا فعالًا في بوابة التقارير.",
        )

    def test_create_notification_respects_provider_lock_and_manual_toggle(self):
        get_or_create_notification_preferences(self.provider_user, mode="provider", exposed_only=True)

        locked_notification = create_notification(
            user=self.provider_user,
            title="إعلان جديد",
            body="هذه رسالة دعائية",
            pref_key="ads_and_offers",
            audience_mode="provider",
        )

        self.assertIsNone(locked_notification)
        self.assertEqual(Notification.objects.count(), 0)

        new_request_pref = NotificationPreference.objects.get(
            user=self.provider_user,
            key="new_request",
            audience_mode=NotificationPreference.AudienceMode.PROVIDER,
        )
        new_request_pref.enabled = False
        new_request_pref.save(update_fields=["enabled", "updated_at"])

        disabled_notification = create_notification(
            user=self.provider_user,
            title="طلب جديد",
            body="تم إنشاء طلب جديد",
            pref_key="new_request",
            audience_mode="provider",
        )

        self.assertIsNone(disabled_notification)
        self.assertEqual(Notification.objects.count(), 0)

    def test_provider_does_not_receive_client_only_platform_recommendations_pref(self):
        get_or_create_notification_preferences(self.provider_user, mode="provider", exposed_only=True)

        notification = create_notification(
            user=self.provider_user,
            title="توصية من المنصة",
            body="هذه توصية عامة من المنصة.",
            pref_key="platform_recommendations",
            audience_mode="provider",
        )

        self.assertIsNone(notification)
        self.assertFalse(
            NotificationPreference.objects.filter(
                user=self.provider_user,
                key="platform_recommendations",
                audience_mode=NotificationPreference.AudienceMode.PROVIDER,
            ).exists()
        )

    def test_all_provider_exposed_settings_have_backend_emitters(self):
        source_text = []
        apps_root = Path(__file__).resolve().parents[1]
        for path in apps_root.rglob("*.py"):
            source_text.append(path.read_text(encoding="utf-8"))
        full_source = "\n".join(source_text)

        emitter_pref_keys = set(
            re.findall(r"pref_key\s*=\s*['\"]([^'\"]+)['\"]", full_source)
        )
        emitter_pref_keys.update(
            re.findall(r"['\"]pref_key['\"]\s*:\s*['\"]([^'\"]+)['\"]", full_source)
        )
        emitter_pref_keys.update(EVENT_TO_PREF_KEY.values())

        provider_exposed_keys = {
            key
            for key, cfg in NOTIFICATION_CATALOG.items()
            if cfg.get("expose_in_settings", True)
            and NotificationPreference.AudienceMode.PROVIDER in tuple(cfg.get("audience_modes") or ())
        }

        self.assertSetEqual(provider_exposed_keys - emitter_pref_keys, set())