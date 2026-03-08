from decimal import Decimal

import pytest
from django.urls import reverse

from apps.accounts.models import User
from apps.subscriptions.models import PlanPeriod, PlanTier, SubscriptionPlan


pytestmark = pytest.mark.django_db


def test_subscription_plan_admin_updates_managed_configuration(client):
    admin_user = User.objects.create_superuser(phone="0505555555", password="Pass12345!")
    plan = SubscriptionPlan.objects.create(
        code="riyadi_admin_test",
        tier=PlanTier.RIYADI,
        title="الخطة الحالية",
        period=PlanPeriod.YEAR,
        price=Decimal("199.00"),
        is_active=True,
    )

    client.force_login(admin_user)
    response = client.post(
        reverse("admin:subscriptions_subscriptionplan_change", args=[plan.pk]),
        {
            "code": "riyadi_admin_test",
            "tier": PlanTier.RIYADI,
            "title": "الخطة الريادية المحدثة",
            "description": "وصف جديد من لوحة الإدارة",
            "period": PlanPeriod.MONTH,
            "price": "149.00",
            "is_active": "on",
            "features_text": "promo_ads\npriority_support",
            "feature_bullets_text": "ميزة أولى\nميزة ثانية",
            "notifications_enabled": "on",
            "competitive_visibility_delay_hours": "8",
            "competitive_visibility_label": "بعد 8 ساعات",
            "banner_images_limit": "4",
            "banner_images_label": "4 صور",
            "direct_chat_quota": "14",
            "direct_chat_label": "14 محادثة مباشرة",
            "promotional_chat_messages_enabled": "on",
            "promotional_notification_messages_enabled": "on",
            "reminder_schedule_hours_text": "24, 72",
            "reminder_policy_label": "تذكير أول ثم ثان",
            "support_priority": "high",
            "support_is_priority": "on",
            "support_sla_hours": "18",
            "support_sla_label": "خلال 18 ساعة",
            "storage_policy": "custom",
            "storage_label": "سعة موسعة",
            "storage_multiplier": "3",
            "storage_upload_max_mb": "40",
            "verification_blue_fee": "25.00",
            "verification_green_fee": "15.00",
            "_save": "Save",
        },
    )

    assert response.status_code == 302

    plan.refresh_from_db()
    assert plan.title == "الخطة الريادية المحدثة"
    assert plan.description == "وصف جديد من لوحة الإدارة"
    assert plan.period == PlanPeriod.MONTH
    assert plan.price == Decimal("149.00")
    assert plan.features == ["promo_ads", "priority_support"]
    assert plan.feature_bullets == ["ميزة أولى", "ميزة ثانية"]
    assert plan.notifications_enabled is True
    assert plan.competitive_visibility_delay_hours == 8
    assert plan.banner_images_limit == 4
    assert plan.direct_chat_quota == 14
    assert plan.promotional_chat_messages_enabled is True
    assert plan.promotional_notification_messages_enabled is True
    assert plan.reminder_schedule_hours == [24, 72]
    assert plan.support_sla_hours == 18
    assert plan.storage_upload_max_mb == 40
    assert plan.verification_blue_fee == Decimal("25.00")
    assert plan.verification_green_fee == Decimal("15.00")