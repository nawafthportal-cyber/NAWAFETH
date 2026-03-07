import pytest
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole
from apps.providers.models import Category, SubCategory, ProviderProfile, ProviderCategory
from apps.marketplace.models import ServiceRequest, RequestType, RequestStatus, Offer, RequestStatusLog
from apps.messaging.models import Thread, Message
from apps.notifications.models import Notification


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
def test_status_log_creates_notification_for_both_parties_with_request_title():
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
        note="تم إكمال الطلب",
    )

    client_notif = Notification.objects.filter(
        user=client_user,
        kind="request_status_change",
    ).order_by("-id").first()
    provider_notif = Notification.objects.filter(
        user=provider_user,
        kind="request_status_change",
    ).order_by("-id").first()

    assert client_notif is not None
    assert provider_notif is not None

    assert client_notif.title == f"تحديث الطلب: {sr.title}"
    assert provider_notif.title == f"تحديث الطلب: {sr.title}"

    assert "مكتمل" in client_notif.body
    assert "مكتمل" in provider_notif.body

    assert client_notif.url == f"/requests/{sr.id}"
    assert provider_notif.url == f"/requests/{sr.id}"
    assert client_notif.audience_mode == "client"
    assert provider_notif.audience_mode == "provider"


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
