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
        status=RequestStatus.SENT,
        city="الرياض",
    )

    # إنشاء Offer => إشعار للعميل
    Offer.objects.create(request=sr, provider=provider, price="100.00", duration_days=3, note="عرض")
    offer_notif = Notification.objects.filter(user=client_user).order_by("-id").first()
    assert offer_notif is not None
    assert offer_notif.kind == "offer_created"
    assert offer_notif.url == f"/requests/{sr.id}"

    # رسالة جديدة => إشعار للطرف الآخر
    thread, _ = Thread.objects.get_or_create(request=sr)
    Message.objects.create(thread=thread, sender=client_user, body="مرحبا")
    msg_notif = Notification.objects.filter(user=provider_user).order_by("-id").first()
    assert msg_notif is not None
    assert msg_notif.kind == "message_new"
    assert f"/requests/{sr.id}/chat" in (msg_notif.url or "")


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
def test_status_log_creates_notification_for_counterparty():
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
        status=RequestStatus.ACCEPTED,
        city="الرياض",
    )

    RequestStatusLog.objects.create(
        request=sr,
        actor=provider_user,
        from_status=RequestStatus.ACCEPTED,
        to_status=RequestStatus.IN_PROGRESS,
        note="بدء التنفيذ",
    )

    notif = Notification.objects.filter(user=client_user, title="تحديث على الطلب").first()
    assert notif is not None
    assert "تحت التنفيذ" in notif.body
    assert notif.kind == "request_status_change"
    assert notif.url == f"/requests/{sr.id}"


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
