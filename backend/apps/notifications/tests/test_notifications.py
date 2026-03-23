import json
from datetime import timedelta
from pathlib import Path
from unittest.mock import patch

import pytest
from django.core.cache import cache
from django.db import OperationalError
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole
from apps.core import unread_badges as unread_badges_module
from apps.extras.models import ExtraPurchase, ExtraPurchaseStatus, ExtraType
from apps.extras_portal.models import ExtrasPortalSubscription, ExtrasPortalSubscriptionStatus
from apps.providers.models import Category, SubCategory, ProviderProfile, ProviderCategory
from apps.marketplace.models import ServiceRequest, RequestType, RequestStatus, Offer, RequestStatusLog
from apps.messaging.models import Thread, Message
from apps.notifications.models import Notification, NotificationPreference
from apps.notifications.services import create_notification
from apps.subscriptions.models import PlanPeriod, Subscription, SubscriptionPlan, SubscriptionStatus


def _active_subscription(*, user, tier="basic", code="BASIC_TEST", notifications_enabled=True, promo_notifications=False):
    plan = SubscriptionPlan.objects.create(
        code=code,
        tier=tier,
        title=code,
        period=PlanPeriod.MONTH,
        price="0.00",
        notifications_enabled=notifications_enabled,
        promotional_notification_messages_enabled=promo_notifications,
    )
    return Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
    )


@pytest.mark.django_db
def test_notifications_created_on_offer_and_message():
    client_user = User.objects.create_user(phone="0509000001")
    provider_user = User.objects.create_user(phone="0509000002")

    provider = ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )

    cat = Category.objects.create(name="تصميم")
    sub = SubCategory.objects.create(category=cat, name="شعار")
    ProviderCategory.objects.create(provider=provider, subcategory=sub)

    sr = ServiceRequest.objects.create(
        client=client_user,
        provider=provider,
        subcategory=sub,
        title="طلب",
        description="وصف",
        request_type=RequestType.COMPETITIVE,
        status=RequestStatus.NEW,
        city="الرياض",
    )

    # إنشاء Offer => إشعار للعميل
    Offer.objects.create(request=sr, provider=provider, price="100.00", duration_days=3, note="عرض")
    offer_notif = Notification.objects.filter(user=client_user).order_by("-id").first()
    assert offer_notif is not None
    assert offer_notif.kind == "offer_created"
    assert offer_notif.url == f"/requests/{sr.id}"
    assert offer_notif.audience_mode == "client"

    # رسالة جديدة => إشعار للطرف الآخر
    thread, _ = Thread.objects.get_or_create(request=sr)
    Message.objects.create(thread=thread, sender=client_user, body="مرحبا")
    msg_notif = Notification.objects.filter(user=provider_user).order_by("-id").first()
    assert msg_notif is not None
    assert msg_notif.kind == "message_new"
    assert f"/requests/{sr.id}/chat" in (msg_notif.url or "")
    assert msg_notif.audience_mode == "provider"


@pytest.mark.django_db
def test_notifications_api_list_and_unread():
    # Notifications API is restricted to CLIENT+ per permissions table
    u = User.objects.create_user(phone="0509000011", role_state=UserRole.CLIENT)
    Notification.objects.create(user=u, title="t", body="b", kind="info")

    api = APIClient()
    api.force_authenticate(user=u)

    r1 = api.get("/api/notifications/")
    assert r1.status_code == 200

    r2 = api.get("/api/notifications/unread-count/")
    assert r2.status_code == 200
    assert r2.data["unread"] == 1


@pytest.mark.django_db
def test_notification_preferences_api_exposes_canonical_tier_compatibly():
    u = User.objects.create_user(phone="0509000012", role_state=UserRole.CLIENT)

    api = APIClient()
    api.force_authenticate(user=u)

    response = api.get("/api/notifications/preferences/")

    assert response.status_code == 200
    rows = response.data["results"]
    assert any(row["tier"] == "leading" and row["canonical_tier"] == "pioneer" for row in rows)
    assert any(row["tier"] == "professional" and row["canonical_tier"] == "professional" for row in rows)


@pytest.mark.django_db
def test_notification_preferences_require_client_or_higher():
    phone_only_user = User.objects.create_user(phone="0509000091", role_state=UserRole.PHONE_ONLY)
    client_user = User.objects.create_user(phone="0509000092", role_state=UserRole.CLIENT)

    api = APIClient()

    api.force_authenticate(user=phone_only_user)
    denied_get = api.get("/api/notifications/preferences/")
    denied_patch = api.patch(
        "/api/notifications/preferences/",
        {"updates": []},
        format="json",
    )
    assert denied_get.status_code == 403
    assert denied_patch.status_code == 403

    api.force_authenticate(user=client_user)
    allowed_get = api.get("/api/notifications/preferences/")
    allowed_patch = api.patch(
        "/api/notifications/preferences/",
        {"updates": []},
        format="json",
    )
    assert allowed_get.status_code == 200
    assert allowed_patch.status_code == 200


@pytest.mark.django_db
def test_notification_preferences_are_filtered_by_requested_mode():
    user = User.objects.create_user(phone="0509000013", role_state=UserRole.CLIENT)

    api = APIClient()
    api.force_authenticate(user=user)

    provider_response = api.get("/api/notifications/preferences/", {"mode": "provider"})
    assert provider_response.status_code == 200
    provider_rows = provider_response.data["results"]
    provider_keys = {row["key"] for row in provider_rows}
    provider_modes = {row["key"]: row["audience_mode"] for row in provider_rows}

    assert len(provider_rows) == len(provider_keys)
    assert "new_request" in provider_keys
    assert "new_follow" in provider_keys
    assert "new_chat_message" in provider_keys
    assert provider_modes["new_request"] == "provider"
    assert provider_modes["new_chat_message"] == "provider"

    client_response = api.get("/api/notifications/preferences/", {"mode": "client"})
    assert client_response.status_code == 200
    client_rows = client_response.data["results"]
    client_keys = {row["key"] for row in client_rows}
    client_modes = {row["key"]: row["audience_mode"] for row in client_rows}

    assert len(client_rows) == len(client_keys)
    assert "new_request" not in client_keys
    assert "new_follow" not in client_keys
    assert "new_chat_message" in client_keys
    assert client_modes["new_chat_message"] == "client"
    assert all(row["key"] != "promo_status_change" for row in client_rows)


@pytest.mark.django_db
def test_notification_preferences_patch_isolated_per_mode():
    user = User.objects.create_user(phone="0509000014", role_state=UserRole.CLIENT)
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مزود/عميل",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )

    api = APIClient()
    api.force_authenticate(user=user)

    initial_provider = api.get("/api/notifications/preferences/", {"mode": "provider"})
    assert initial_provider.status_code == 200
    assert any(row["key"] == "new_chat_message" and row["enabled"] is True for row in initial_provider.data["results"])

    patch_response = api.patch(
        "/api/notifications/preferences/?mode=provider",
        {"updates": [{"key": "new_chat_message", "enabled": False}]},
        format="json",
    )
    assert patch_response.status_code == 200
    assert patch_response.data["changed"] == 1

    provider_pref = NotificationPreference.objects.get(
        user=user,
        key="new_chat_message",
        audience_mode="provider",
    )
    shared_pref = NotificationPreference.objects.get(
        user=user,
        key="new_chat_message",
        audience_mode="shared",
    )

    assert provider_pref.enabled is False
    assert shared_pref.enabled is True

    client_response = api.get("/api/notifications/preferences/", {"mode": "client"})
    assert client_response.status_code == 200
    client_row = next(row for row in client_response.data["results"] if row["key"] == "new_chat_message")
    assert client_row["enabled"] is True
    assert client_row["audience_mode"] == "client"

    client_pref = NotificationPreference.objects.get(
        user=user,
        key="new_chat_message",
        audience_mode="client",
    )
    assert client_pref.enabled is True


@pytest.mark.django_db
def test_notification_preferences_respect_subscription_notification_flag():
    user = User.objects.create_user(phone="0509000015", role_state=UserRole.PROVIDER)
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مزود",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    _active_subscription(
        user=user,
        tier="pro",
        code="PRO_NOTIFS_OFF",
        notifications_enabled=False,
        promo_notifications=True,
    )

    api = APIClient()
    api.force_authenticate(user=user)

    response = api.get("/api/notifications/preferences/", {"mode": "provider"})
    assert response.status_code == 200
    rows = response.data["results"]
    new_request = next(row for row in rows if row["key"] == "new_request")
    ads_and_offers = next(row for row in rows if row["key"] == "ads_and_offers")

    assert new_request["locked"] is True
    assert "معطلة" in new_request["locked_reason"]
    assert ads_and_offers["locked"] is True

    created = create_notification(
        user=user,
        title="طلب جديد",
        body="تفاصيل",
        kind="request_created",
        pref_key="new_request",
        audience_mode="provider",
    )
    assert created is None


@pytest.mark.django_db
def test_basic_provider_sees_paid_tiers_as_locked_with_subscription_message():
    user = User.objects.create_user(phone="0509000017", role_state=UserRole.PROVIDER)
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مزود أساسي",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    _active_subscription(
        user=user,
        tier="basic",
        code="BASIC_PROVIDER_PLAN",
        notifications_enabled=True,
    )

    api = APIClient()
    api.force_authenticate(user=user)

    response = api.get("/api/notifications/preferences/", {"mode": "provider"})
    assert response.status_code == 200

    rows = response.data["results"]
    new_follow = next(row for row in rows if row["key"] == "new_follow")
    positive_review = next(row for row in rows if row["key"] == "positive_review")
    new_request = next(row for row in rows if row["key"] == "new_request")

    assert new_request["locked"] is False
    assert new_follow["locked"] is True
    assert positive_review["locked"] is True
    assert "يلزم الاشتراك في الباقة" in new_follow["locked_reason"]
    assert "يلزم الاشتراك في الباقة" in positive_review["locked_reason"]


@pytest.mark.django_db
def test_notification_preferences_respect_promotional_capability_and_extras_entitlements():
    user = User.objects.create_user(phone="0509000016", role_state=UserRole.PROVIDER)
    provider = ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مزود متقدم",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    _active_subscription(
        user=user,
        tier="pro",
        code="PRO_NO_PROMO_NOTIFS",
        notifications_enabled=True,
        promo_notifications=False,
    )

    api = APIClient()
    api.force_authenticate(user=user)

    initial = api.get("/api/notifications/preferences/", {"mode": "provider"})
    assert initial.status_code == 200
    initial_rows = initial.data["results"]

    ads_and_offers = next(row for row in initial_rows if row["key"] == "ads_and_offers")
    new_ad_visit = next(row for row in initial_rows if row["key"] == "new_ad_visit")
    finance_package = next(row for row in initial_rows if row["key"] == "finance_package_completed")

    assert ads_and_offers["locked"] is True
    assert "الدعائية" in ads_and_offers["locked_reason"]
    assert new_ad_visit["locked"] is True
    assert "ترويج" in new_ad_visit["locked_reason"]
    assert finance_package["locked"] is True
    assert "الإدارة المالية" in finance_package["locked_reason"]

    ExtraPurchase.objects.create(
        user=user,
        sku="promo_boost_7d",
        title="Boost",
        extra_type=ExtraType.TIME_BASED,
        status=ExtraPurchaseStatus.ACTIVE,
        start_at=timezone.now(),
        end_at=timezone.now() + timedelta(days=7),
    )
    ExtrasPortalSubscription.objects.create(
        provider=provider,
        status=ExtrasPortalSubscriptionStatus.ACTIVE,
        plan_title="بوابة الخدمات الإضافية",
    )

    updated = api.get("/api/notifications/preferences/", {"mode": "provider"})
    assert updated.status_code == 200
    updated_rows = updated.data["results"]

    updated_new_ad_visit = next(row for row in updated_rows if row["key"] == "new_ad_visit")
    updated_finance_package = next(row for row in updated_rows if row["key"] == "finance_package_completed")

    assert updated_new_ad_visit["locked"] is False
    assert updated_finance_package["locked"] is False


@pytest.mark.django_db
def test_notifications_are_filtered_by_active_mode_query_param():
    user = User.objects.create_user(phone="0509000041", role_state=UserRole.CLIENT)
    provider = ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مزود/عميل",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    other_client = User.objects.create_user(phone="0509000042", role_state=UserRole.CLIENT)
    other_provider_user = User.objects.create_user(phone="0509000043", role_state=UserRole.PROVIDER)
    other_provider = ProviderProfile.objects.create(
        user=other_provider_user,
        provider_type="individual",
        display_name="مزود آخر",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )

    cat = Category.objects.create(name="نجارة")
    sub = SubCategory.objects.create(category=cat, name="أبواب")
    ProviderCategory.objects.create(provider=provider, subcategory=sub)
    ProviderCategory.objects.create(provider=other_provider, subcategory=sub)

    # طلب العميل -> إشعار عميل عند وصول عرض
    sr_client = ServiceRequest.objects.create(
        client=user,
        provider=other_provider,
        subcategory=sub,
        title="طلب كعميل",
        description="وصف",
        request_type=RequestType.NORMAL,
        status=RequestStatus.NEW,
        city="الرياض",
    )
    Offer.objects.create(request=sr_client, provider=other_provider, price="120.00", duration_days=2, note="عرض")

    # طلب أنا فيه مزود -> إشعار مزود عند تغيير الحالة بواسطة العميل
    sr_provider = ServiceRequest.objects.create(
        client=other_client,
        provider=provider,
        subcategory=sub,
        title="طلب كمزود",
        description="وصف",
        request_type=RequestType.NORMAL,
        status=RequestStatus.IN_PROGRESS,
        city="الرياض",
    )
    RequestStatusLog.objects.create(
        request=sr_provider,
        actor=other_client,
        from_status=RequestStatus.IN_PROGRESS,
        to_status=RequestStatus.COMPLETED,
        note="تم إكمال الطلب",
    )

    api = APIClient()
    api.force_authenticate(user=user)

    r_client = api.get("/api/notifications/", {"mode": "client"})
    assert r_client.status_code == 200
    client_kinds = [row["kind"] for row in r_client.data["results"]]
    assert "offer_created" in client_kinds
    assert "request_status_change" not in client_kinds

    r_provider = api.get("/api/notifications/", {"mode": "provider"})
    assert r_provider.status_code == 200
    provider_kinds = [row["kind"] for row in r_provider.data["results"]]
    assert "request_status_change" in provider_kinds
    assert "offer_created" not in provider_kinds

    r_unread_client = api.get("/api/notifications/unread-count/", {"mode": "client"})
    r_unread_provider = api.get("/api/notifications/unread-count/", {"mode": "provider"})
    assert r_unread_client.status_code == 200
    assert r_unread_provider.status_code == 200
    assert r_unread_client.data["unread"] == 1
    assert r_unread_provider.data["unread"] == 1


@pytest.mark.django_db
def test_status_log_completion_notifies_client_only_with_review_prompt():
    client_user = User.objects.create_user(phone="0509000021")
    provider_user = User.objects.create_user(phone="0509000022")

    provider = ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )

    cat = Category.objects.create(name="صيانة")
    sub = SubCategory.objects.create(category=cat, name="كهرباء")
    ProviderCategory.objects.create(provider=provider, subcategory=sub)

    sr = ServiceRequest.objects.create(
        client=client_user,
        provider=provider,
        subcategory=sub,
        title="طلب تحديث حالة",
        description="وصف",
        request_type=RequestType.NORMAL,
        status=RequestStatus.IN_PROGRESS,
        city="الرياض",
    )

    RequestStatusLog.objects.create(
        request=sr,
        actor=provider_user,
        from_status=RequestStatus.IN_PROGRESS,
        to_status=RequestStatus.COMPLETED,
        note="تم الإكمال. يرجى مراجعة الطلب وتقييم الخدمة.",
    )

    client_notif = Notification.objects.filter(
        user=client_user,
        kind="request_status_change",
    ).order_by("-id").first()
    assert client_notif is not None
    assert client_notif.title == f"تحديث الطلب: {sr.title}"
    assert "تقييم الخدمة" in client_notif.body
    assert "اكتمل طلبك" in client_notif.body

    assert client_notif.url == f"/requests/{sr.id}"
    assert client_notif.audience_mode == "client"
    assert not Notification.objects.filter(
        user=provider_user,
        kind="request_status_change",
    ).exists()


@pytest.mark.django_db
def test_direct_message_creates_notification_for_other_participant():
    client_user = User.objects.create_user(phone="0509000031")
    provider_user = User.objects.create_user(phone="0509000032")

    thread = Thread.objects.create(
        is_direct=True,
        participant_1=client_user,
        participant_2=provider_user,
    )

    Message.objects.create(thread=thread, sender=client_user, body="مرحبا مباشر")

    notif = Notification.objects.filter(user=provider_user, title="رسالة جديدة").first()
    assert notif is not None
    assert "/threads/" in (notif.url or "")


@pytest.mark.django_db
def test_combined_unread_badges_endpoint_returns_mode_specific_counts():
    cache.clear()
    dual_user = User.objects.create_user(phone="0509000061", role_state=UserRole.CLIENT)
    ProviderProfile.objects.create(
        user=dual_user,
        provider_type="individual",
        display_name="مستخدم مزدوج",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    peer_provider_user = User.objects.create_user(phone="0509000062", role_state=UserRole.PROVIDER)
    ProviderProfile.objects.create(
        user=peer_provider_user,
        provider_type="individual",
        display_name="مزود خارجي",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    peer_client_user = User.objects.create_user(phone="0509000063", role_state=UserRole.CLIENT)

    Notification.objects.create(
        user=dual_user,
        title="إشعار عميل",
        body="body",
        kind="info",
        audience_mode="client",
    )
    Notification.objects.create(
        user=dual_user,
        title="إشعار مزود",
        body="body",
        kind="info",
        audience_mode="provider",
    )

    client_thread = Thread.objects.create(
        is_direct=True,
        context_mode=Thread.ContextMode.CLIENT,
        participant_1=dual_user,
        participant_2=peer_provider_user,
    )
    provider_thread = Thread.objects.create(
        is_direct=True,
        context_mode=Thread.ContextMode.PROVIDER,
        participant_1=dual_user,
        participant_2=peer_client_user,
    )
    Message.objects.create(thread=client_thread, sender=peer_provider_user, body="client unread")
    Message.objects.create(thread=provider_thread, sender=peer_client_user, body="provider unread")
    Notification.objects.filter(user=dual_user, kind="message_new").delete()

    api = APIClient()
    api.force_authenticate(user=dual_user)

    client_response = api.get("/api/core/unread-badges/", {"mode": "client"})
    provider_response = api.get("/api/core/unread-badges/", {"mode": "provider"})

    assert client_response.status_code == 200
    assert client_response.data["mode"] == "client"
    assert client_response.data["notifications"] == 1
    assert client_response.data["chats"] == 1
    assert client_response.data["degraded"] is False
    assert client_response.data["stale"] is False

    assert provider_response.status_code == 200
    assert provider_response.data["mode"] == "provider"
    assert provider_response.data["notifications"] == 1
    assert provider_response.data["chats"] == 1
    assert provider_response.data["degraded"] is False
    assert provider_response.data["stale"] is False


@pytest.mark.django_db
def test_combined_unread_badges_returns_stale_payload_when_database_temporarily_fails():
    cache.clear()
    user = User.objects.create_user(phone="0509000064", role_state=UserRole.CLIENT)
    Notification.objects.create(
        user=user,
        title="إشعار",
        body="body",
        kind="info",
        audience_mode="client",
    )

    api = APIClient()
    api.force_authenticate(user=user)

    warm = api.get("/api/core/unread-badges/", {"mode": "client"})
    assert warm.status_code == 200
    assert warm.data["notifications"] == 1

    cache.delete(unread_badges_module._combined_cache_key(user.id, "client"))

    with patch(
        "apps.core.unread_badges._compute_unread_badges",
        side_effect=OperationalError("database unavailable"),
    ):
        degraded = api.get("/api/core/unread-badges/", {"mode": "client"})

    assert degraded.status_code == 200
    assert degraded.data["notifications"] == 1
    assert degraded.data["chats"] == 0
    assert degraded.data["degraded"] is True
    assert degraded.data["stale"] is True


@pytest.mark.django_db
def test_notifications_unread_count_returns_controlled_503_when_database_is_unavailable():
    cache.clear()
    user = User.objects.create_user(phone="0509000065", role_state=UserRole.CLIENT)

    api = APIClient()
    api.force_authenticate(user=user)

    with patch(
        "apps.core.unread_badges._compute_unread_badges",
        side_effect=OperationalError("database unavailable"),
    ):
        response = api.get("/api/notifications/unread-count/", {"mode": "client"})

    assert response.status_code == 503
    assert response.data["unread"] == 0
    assert response.data["degraded"] is True
    assert response.data["stale"] is False
    assert "detail" in response.data


@pytest.mark.django_db
def test_mark_all_read_is_scoped_to_mode_and_refreshes_combined_badges():
    cache.clear()
    user = User.objects.create_user(phone="0509000066", role_state=UserRole.CLIENT)
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مستخدم مزدوج",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    client_notification = Notification.objects.create(
        user=user,
        title="عميل",
        body="body",
        kind="info",
        audience_mode="client",
    )
    provider_notification = Notification.objects.create(
        user=user,
        title="مزود",
        body="body",
        kind="info",
        audience_mode="provider",
    )

    api = APIClient()
    api.force_authenticate(user=user)

    warm_client = api.get("/api/core/unread-badges/", {"mode": "client"})
    warm_provider = api.get("/api/core/unread-badges/", {"mode": "provider"})
    assert warm_client.status_code == 200
    assert warm_provider.status_code == 200
    assert warm_client.data["notifications"] == 1
    assert warm_provider.data["notifications"] == 1

    response = api.post("/api/notifications/mark-all-read/", {"mode": "provider"}, format="json")
    assert response.status_code == 200

    client_notification.refresh_from_db()
    provider_notification.refresh_from_db()
    assert client_notification.is_read is False
    assert provider_notification.is_read is True

    client_unread = api.get("/api/notifications/unread-count/", {"mode": "client"})
    provider_unread = api.get("/api/notifications/unread-count/", {"mode": "provider"})
    assert client_unread.status_code == 200
    assert provider_unread.status_code == 200
    assert client_unread.data["unread"] == 1
    assert provider_unread.data["unread"] == 0

    refreshed_client = api.get("/api/core/unread-badges/", {"mode": "client"})
    refreshed_provider = api.get("/api/core/unread-badges/", {"mode": "provider"})
    assert refreshed_client.status_code == 200
    assert refreshed_provider.status_code == 200
    assert refreshed_client.data["notifications"] == 1
    assert refreshed_provider.data["notifications"] == 0


@pytest.mark.django_db
def test_mark_single_read_updates_unread_count_and_combined_badges():
    cache.clear()
    user = User.objects.create_user(phone="0509000067", role_state=UserRole.CLIENT)
    notification = Notification.objects.create(
        user=user,
        title="مفرد",
        body="body",
        kind="info",
        audience_mode="client",
    )

    api = APIClient()
    api.force_authenticate(user=user)

    warm = api.get("/api/core/unread-badges/", {"mode": "client"})
    assert warm.status_code == 200
    assert warm.data["notifications"] == 1

    mark_read = api.post(f"/api/notifications/mark-read/{notification.id}/")
    assert mark_read.status_code == 200

    unread = api.get("/api/notifications/unread-count/", {"mode": "client"})
    badges = api.get("/api/core/unread-badges/", {"mode": "client"})
    assert unread.status_code == 200
    assert badges.status_code == 200
    assert unread.data["unread"] == 0
    assert badges.data["notifications"] == 0


def test_sprint4_unread_badge_contract_fixtures_are_valid():
    fixtures_dir = Path(__file__).resolve().parents[4] / "docs" / "contracts" / "sprint4"

    for fixture_name in ("unread_badges_client.json", "unread_badges_provider.json"):
        payload = json.loads((fixtures_dir / fixture_name).read_text(encoding="utf-8"))
        assert set(payload.keys()) == {"notifications", "chats", "degraded", "stale", "mode"}
        assert isinstance(payload["notifications"], int)
        assert isinstance(payload["chats"], int)
        assert isinstance(payload["degraded"], bool)
        assert isinstance(payload["stale"], bool)
        assert payload["mode"] in {"client", "provider"}
