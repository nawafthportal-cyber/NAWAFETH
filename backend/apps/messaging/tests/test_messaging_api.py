from unittest.mock import patch

import pytest
from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.db import OperationalError
from django.test import override_settings
from rest_framework.test import APIClient
from decimal import Decimal

from apps.accounts.models import User, UserRole
from apps.core import unread_badges as unread_badges_module
from apps.marketplace.models import RequestStatus, RequestType, ServiceRequest
from apps.messaging.models import Message, Thread, ThreadUserState
from apps.moderation.models import ModerationCase
from apps.providers.models import Category, ProviderCategory, ProviderProfile, SubCategory
from apps.subscriptions.models import PlanPeriod, Subscription, SubscriptionPlan, SubscriptionStatus


@pytest.mark.django_db
def test_messaging_flow_participants_only():
    client_user = User.objects.create_user(phone="0501000001", role_state=UserRole.PHONE_ONLY)
    provider_user = User.objects.create_user(phone="0501000002", role_state=UserRole.PROVIDER)
    other_user = User.objects.create_user(phone="0501000003", role_state=UserRole.PHONE_ONLY)

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
        status=RequestStatus.ACCEPTED,
        city="الرياض",
    )

    api = APIClient()

    # غير مشارك ممنوع
    api.force_authenticate(user=other_user)
    r0 = api.post(f"/api/messaging/requests/{sr.id}/thread/", {}, format="json")
    assert r0.status_code == 403

    # عميل ينشئ/يجلب الثريد
    api.force_authenticate(user=client_user)
    r1 = api.post(f"/api/messaging/requests/{sr.id}/thread/", {}, format="json")
    assert r1.status_code == 200

    # يرسل رسالة
    r2 = api.post(
        f"/api/messaging/requests/{sr.id}/messages/send/",
        {"body": "مرحبا"},
        format="json",
    )
    assert r2.status_code == 201
    sent_message_id = r2.data.get("message_id")
    assert sent_message_id is not None

    # مزود يقرأ الرسائل
    api.force_authenticate(user=provider_user)
    r3 = api.get(f"/api/messaging/requests/{sr.id}/messages/")
    assert r3.status_code == 200
    results = r3.data.get("results", []) if isinstance(r3.data, dict) else r3.data
    assert len(results) >= 1
    first = results[0]
    assert "read_by_ids" in first
    assert provider_user.id not in first.get("read_by_ids", [])

    r4 = api.post(f"/api/messaging/requests/{sr.id}/messages/read/", {}, format="json")
    assert r4.status_code == 200
    assert r4.data.get("marked", 0) >= 1
    assert sent_message_id in r4.data.get("message_ids", [])

    # بعد التعليم كمقروء يجب أن يظهر provider ضمن read_by_ids
    r5 = api.get(f"/api/messaging/requests/{sr.id}/messages/")
    assert r5.status_code == 200
    results_after = r5.data.get("results", []) if isinstance(r5.data, dict) else r5.data
    target = next((m for m in results_after if m.get("id") == sent_message_id), None)
    assert target is not None
    assert provider_user.id in target.get("read_by_ids", [])


@pytest.mark.django_db
def test_direct_thread_requires_phone_only_or_higher():
    visitor_user = User.objects.create_user(phone="0501000011", role_state=UserRole.VISITOR)
    phone_only_user = User.objects.create_user(phone="0501000012", role_state=UserRole.PHONE_ONLY)
    provider_user = User.objects.create_user(phone="0501000013", role_state=UserRole.PROVIDER)

    ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود مباشر",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )

    api = APIClient()

    api.force_authenticate(user=visitor_user)
    forbidden = api.post(
        "/api/messaging/direct/thread/",
        {"provider_id": provider_user.provider_profile.id},
        format="json",
    )
    assert forbidden.status_code == 403

    api.force_authenticate(user=phone_only_user)
    ok = api.post(
        "/api/messaging/direct/thread/",
        {"provider_id": provider_user.provider_profile.id},
        format="json",
    )
    assert ok.status_code == 200


@pytest.mark.django_db
def test_thread_user_state_favorite_archive_and_unarchive_on_message():
    client_user = User.objects.create_user(phone="0502000001", role_state=UserRole.PHONE_ONLY)
    provider_user = User.objects.create_user(phone="0502000002", role_state=UserRole.PROVIDER)

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
        status=RequestStatus.ACCEPTED,
        city="الرياض",
    )

    api = APIClient()
    api.force_authenticate(user=client_user)

    r1 = api.post(f"/api/messaging/requests/{sr.id}/thread/", {}, format="json")
    assert r1.status_code == 200
    thread_id = r1.data.get("id")
    assert thread_id is not None

    fav = api.post(f"/api/messaging/thread/{thread_id}/favorite/", {}, format="json")
    assert fav.status_code == 200
    assert fav.data.get("is_favorite") is True

    states = api.get("/api/messaging/threads/states/")
    assert states.status_code == 200
    assert any(s.get("thread") == thread_id and s.get("is_favorite") is True for s in states.data)

    arch = api.post(f"/api/messaging/thread/{thread_id}/archive/", {}, format="json")
    assert arch.status_code == 200
    assert arch.data.get("is_archived") is True

    # Sending a message should unarchive for participants
    send = api.post(
        f"/api/messaging/requests/{sr.id}/messages/send/",
        {"body": "مرحبا"},
        format="json",
    )
    assert send.status_code == 201

    state_after = api.get(f"/api/messaging/thread/{thread_id}/state/")
    assert state_after.status_code == 200
    assert state_after.data.get("is_archived") is False


@pytest.mark.django_db
def test_block_prevents_peer_sending_request_and_direct():
    client_user = User.objects.create_user(phone="0503000001", role_state=UserRole.PHONE_ONLY)
    provider_user = User.objects.create_user(phone="0503000002", role_state=UserRole.PROVIDER)

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
        status=RequestStatus.ACCEPTED,
        city="الرياض",
    )

    api = APIClient()

    # Request thread block
    api.force_authenticate(user=client_user)
    r1 = api.post(f"/api/messaging/requests/{sr.id}/thread/", {}, format="json")
    assert r1.status_code == 200
    thread_id = r1.data.get("id")
    assert thread_id is not None

    b1 = api.post(f"/api/messaging/thread/{thread_id}/block/", {}, format="json")
    assert b1.status_code == 200
    assert b1.data.get("is_blocked") is True

    api.force_authenticate(user=provider_user)
    blocked_send = api.post(
        f"/api/messaging/requests/{sr.id}/messages/send/",
        {"body": "رسالة"},
        format="json",
    )
    assert blocked_send.status_code == 403

    # Direct thread block
    api.force_authenticate(user=client_user)
    d1 = api.post(
        "/api/messaging/direct/thread/",
        {"provider_id": provider.id},
        format="json",
    )
    assert d1.status_code == 200
    direct_thread_id = d1.data.get("id")
    assert direct_thread_id is not None

    b2 = api.post(f"/api/messaging/thread/{direct_thread_id}/block/", {}, format="json")
    assert b2.status_code == 200
    assert b2.data.get("is_blocked") is True

    api.force_authenticate(user=provider_user)
    blocked_direct_send = api.post(
        f"/api/messaging/direct/thread/{direct_thread_id}/messages/send/",
        {"body": "رسالة"},
        format="json",
    )
    assert blocked_direct_send.status_code == 403


@pytest.mark.django_db
def test_direct_unread_count_respects_mode_for_same_user():
    cache.clear()
    dual_user = User.objects.create_user(phone="0501000091", role_state=UserRole.CLIENT)
    peer_provider_user = User.objects.create_user(phone="0501000092", role_state=UserRole.PROVIDER)
    ProviderProfile.objects.create(
        user=peer_provider_user,
        provider_type="individual",
        display_name="مزود",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    peer_client_user = User.objects.create_user(phone="0501000093", role_state=UserRole.CLIENT)
    shared_peer_user = User.objects.create_user(phone="0501000094", role_state=UserRole.PROVIDER)
    ProviderProfile.objects.create(
        user=shared_peer_user,
        provider_type="individual",
        display_name="مزود مشترك",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
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
    shared_thread = Thread.objects.create(
        is_direct=True,
        context_mode=Thread.ContextMode.SHARED,
        participant_1=dual_user,
        participant_2=shared_peer_user,
    )

    Message.objects.create(thread=client_thread, sender=peer_provider_user, body="client unread")
    Message.objects.create(thread=provider_thread, sender=peer_client_user, body="provider unread")
    Message.objects.create(thread=shared_thread, sender=shared_peer_user, body="shared unread")

    api = APIClient()
    api.force_authenticate(user=dual_user)

    client_response = api.get("/api/messaging/direct/unread-count/", {"mode": "client"})
    provider_response = api.get("/api/messaging/direct/unread-count/", {"mode": "provider"})

    assert client_response.status_code == 200
    assert client_response.data["mode"] == "client"
    assert client_response.data["unread"] == 2

    assert provider_response.status_code == 200
    assert provider_response.data["mode"] == "provider"
    assert provider_response.data["unread"] == 2


@pytest.mark.django_db
def test_direct_unread_count_returns_controlled_503_when_database_is_unavailable():
    cache.clear()
    user = User.objects.create_user(phone="0501000095", role_state=UserRole.CLIENT)
    cache.delete(unread_badges_module._combined_cache_key(user.id, "client"))

    api = APIClient()
    api.force_authenticate(user=user)

    with patch(
        "apps.core.unread_badges._compute_unread_badges",
        side_effect=OperationalError("database unavailable"),
    ):
        response = api.get("/api/messaging/direct/unread-count/", {"mode": "client"})

    assert response.status_code == 503
    assert response.data["unread"] == 0
    assert response.data["degraded"] is True
    assert response.data["stale"] is False
    assert "detail" in response.data


@pytest.mark.django_db
def test_send_request_message_with_attachment():
    client_user = User.objects.create_user(phone="0504000001", role_state=UserRole.PHONE_ONLY)
    provider_user = User.objects.create_user(phone="0504000002", role_state=UserRole.PROVIDER)

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
        title="طلب",
        description="وصف",
        request_type=RequestType.COMPETITIVE,
        status=RequestStatus.ACCEPTED,
        city="الرياض",
    )

    api = APIClient()
    api.force_authenticate(user=client_user)
    f = SimpleUploadedFile("voice.aac", b"fake-audio-bytes", content_type="audio/aac")
    r = api.post(
        f"/api/messaging/requests/{sr.id}/messages/send/",
        {"body": "رسالة صوتية", "attachment": f, "attachment_type": "audio"},
        format="multipart",
    )
    assert r.status_code == 201

    api.force_authenticate(user=provider_user)
    list_r = api.get(f"/api/messaging/requests/{sr.id}/messages/")
    assert list_r.status_code == 200
    results = list_r.data.get("results", []) if isinstance(list_r.data, dict) else list_r.data
    assert results
    latest = results[0]
    assert latest.get("attachment_url")
    assert latest.get("attachment_type") == "audio"


@pytest.mark.django_db
def test_send_direct_message_with_attachment():
    client_user = User.objects.create_user(phone="0505000001", role_state=UserRole.PHONE_ONLY)
    provider_user = User.objects.create_user(phone="0505000002", role_state=UserRole.PROVIDER)

    provider = ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود مباشر",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )

    api = APIClient()
    api.force_authenticate(user=client_user)
    thread_r = api.post(
        "/api/messaging/direct/thread/",
        {"provider_id": provider.id},
        format="json",
    )
    assert thread_r.status_code == 200
    thread_id = thread_r.data["id"]

    f = SimpleUploadedFile("sample.txt", b"hello", content_type="text/plain")
    send_r = api.post(
        f"/api/messaging/direct/thread/{thread_id}/messages/send/",
        {"body": "", "attachment": f, "attachment_type": "file"},
        format="multipart",
    )
    assert send_r.status_code == 201

    api.force_authenticate(user=provider_user)
    list_r = api.get(f"/api/messaging/direct/thread/{thread_id}/messages/")
    assert list_r.status_code == 200
    results = list_r.data.get("results", []) if isinstance(list_r.data, dict) else list_r.data
    assert results
    latest = results[0]
    assert latest.get("attachment_url")
    assert latest.get("attachment_type") == "file"


@pytest.mark.django_db
def test_sender_can_delete_own_request_message_for_both_participants():
    client_user = User.objects.create_user(phone="0505100001", role_state=UserRole.PHONE_ONLY)
    provider_user = User.objects.create_user(phone="0505100002", role_state=UserRole.PROVIDER)

    provider = ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود حذف",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    cat = Category.objects.create(name="نقل")
    sub = SubCategory.objects.create(category=cat, name="داخل المدينة")
    ProviderCategory.objects.create(provider=provider, subcategory=sub)

    sr = ServiceRequest.objects.create(
        client=client_user,
        provider=provider,
        subcategory=sub,
        title="طلب حذف",
        description="وصف",
        request_type=RequestType.COMPETITIVE,
        status=RequestStatus.ACCEPTED,
        city="الرياض",
    )

    api = APIClient()
    api.force_authenticate(user=client_user)
    thread_res = api.post(f"/api/messaging/requests/{sr.id}/thread/", {}, format="json")
    assert thread_res.status_code == 200
    thread_id = thread_res.data["id"]

    send_res = api.post(
        f"/api/messaging/requests/{sr.id}/messages/send/",
        {"body": "رسالة غير مناسبة"},
        format="json",
    )
    assert send_res.status_code == 201
    message_id = send_res.data["message_id"]

    # Receiver cannot delete peer message
    api.force_authenticate(user=provider_user)
    forbidden = api.post(
        f"/api/messaging/thread/{thread_id}/messages/{message_id}/delete/",
        {},
        format="json",
    )
    assert forbidden.status_code == 403

    # Sender can delete it for both
    api.force_authenticate(user=client_user)
    ok = api.post(
        f"/api/messaging/thread/{thread_id}/messages/{message_id}/delete/",
        {},
        format="json",
    )
    assert ok.status_code == 200

    api.force_authenticate(user=provider_user)
    list_res = api.get(f"/api/messaging/requests/{sr.id}/messages/")
    assert list_res.status_code == 200
    results = list_res.data.get("results", []) if isinstance(list_res.data, dict) else list_res.data
    assert all(item.get("id") != message_id for item in results)


@pytest.mark.django_db
def test_sender_can_delete_own_direct_message_for_both_participants():
    client_user = User.objects.create_user(phone="0505100011", role_state=UserRole.PHONE_ONLY)
    provider_user = User.objects.create_user(phone="0505100012", role_state=UserRole.PROVIDER)

    provider = ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود مباشر حذف",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )

    api = APIClient()
    api.force_authenticate(user=client_user)
    thread_res = api.post(
        "/api/messaging/direct/thread/",
        {"provider_id": provider.id},
        format="json",
    )
    assert thread_res.status_code == 200
    thread_id = thread_res.data["id"]

    send_res = api.post(
        f"/api/messaging/direct/thread/{thread_id}/messages/send/",
        {"body": "رسالة مباشرة غير مناسبة"},
        format="json",
    )
    assert send_res.status_code == 201
    message_id = send_res.data["message_id"]

    ok = api.post(
        f"/api/messaging/thread/{thread_id}/messages/{message_id}/delete/",
        {},
        format="json",
    )
    assert ok.status_code == 200

    api.force_authenticate(user=provider_user)
    list_res = api.get(f"/api/messaging/direct/thread/{thread_id}/messages/")
    assert list_res.status_code == 200
    results = list_res.data.get("results", []) if isinstance(list_res.data, dict) else list_res.data
    assert all(item.get("id") != message_id for item in results)


@pytest.mark.django_db
def test_thread_report_accepts_reason_and_details():
    client_user = User.objects.create_user(phone="0506000001", role_state=UserRole.PHONE_ONLY)
    provider_user = User.objects.create_user(phone="0506000002", role_state=UserRole.PROVIDER)

    provider = ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود بلاغ",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    cat = Category.objects.create(name="نظافة")
    sub = SubCategory.objects.create(category=cat, name="تنظيف")
    ProviderCategory.objects.create(provider=provider, subcategory=sub)

    sr = ServiceRequest.objects.create(
        client=client_user,
        provider=provider,
        subcategory=sub,
        title="طلب",
        description="وصف",
        request_type=RequestType.COMPETITIVE,
        status=RequestStatus.ACCEPTED,
        city="الرياض",
    )

    api = APIClient()
    api.force_authenticate(user=client_user)
    thread_res = api.post(f"/api/messaging/requests/{sr.id}/thread/", {}, format="json")
    assert thread_res.status_code == 200
    thread_id = thread_res.data["id"]

    report_res = api.post(
        f"/api/messaging/thread/{thread_id}/report/",
        {
            "reason": "محتوى غير لائق",
            "details": "تفاصيل اختبار",
            "reported_label": "مزود بلاغ",
        },
        format="json",
    )
    assert report_res.status_code == 201
    assert report_res.data.get("ticket_id") is not None


@pytest.mark.django_db
@override_settings(FEATURE_MODERATION_DUAL_WRITE=True)
def test_thread_report_dual_writes_to_moderation_case():
    client_user = User.objects.create_user(phone="0506000011", role_state=UserRole.PHONE_ONLY)
    provider_user = User.objects.create_user(phone="0506000012", role_state=UserRole.PROVIDER)

    provider = ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود بلاغ مزدوج",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    cat = Category.objects.create(name="نظافة 2")
    sub = SubCategory.objects.create(category=cat, name="تنظيف 2")
    ProviderCategory.objects.create(provider=provider, subcategory=sub)

    sr = ServiceRequest.objects.create(
        client=client_user,
        provider=provider,
        subcategory=sub,
        title="طلب",
        description="وصف",
        request_type=RequestType.COMPETITIVE,
        status=RequestStatus.ACCEPTED,
        city="الرياض",
    )

    api = APIClient()
    api.force_authenticate(user=client_user)
    thread_res = api.post(f"/api/messaging/requests/{sr.id}/thread/", {}, format="json")
    thread_id = thread_res.data["id"]

    report_res = api.post(
        f"/api/messaging/thread/{thread_id}/report/",
        {"reason": "إساءة", "details": "تفاصيل", "reported_label": "مزود"},
        format="json",
    )

    assert report_res.status_code == 201
    ticket_id = report_res.data["ticket_id"]
    case = ModerationCase.objects.get(linked_support_ticket_id=str(ticket_id))
    assert case.source_app == "messaging"
    assert case.source_model == "Thread"
    assert case.source_object_id == str(thread_id)
    assert case.reported_user_id == provider_user.id


@pytest.mark.django_db
def test_mode_filters_direct_threads_and_thread_states_for_same_user():
    dual_user = User.objects.create_user(phone="0507000001", role_state=UserRole.PROVIDER)
    other_client = User.objects.create_user(phone="0507000002", role_state=UserRole.CLIENT)
    other_provider_user = User.objects.create_user(phone="0507000003", role_state=UserRole.PROVIDER)

    dual_provider = ProviderProfile.objects.create(
        user=dual_user,
        provider_type="individual",
        display_name="ثنائي",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    other_provider = ProviderProfile.objects.create(
        user=other_provider_user,
        provider_type="individual",
        display_name="مزود آخر",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )

    cat = Category.objects.create(name="تقنية")
    sub = SubCategory.objects.create(category=cat, name="ويب")
    ProviderCategory.objects.create(provider=dual_provider, subcategory=sub)
    ProviderCategory.objects.create(provider=other_provider, subcategory=sub)

    api = APIClient()
    api.force_authenticate(user=dual_user)

    # Direct thread created in client context
    r_direct = api.post(
        "/api/messaging/direct/thread/",
        {"provider_id": other_provider.id, "mode": "client"},
        format="json",
    )
    assert r_direct.status_code == 200
    direct_thread_id = r_direct.data["id"]
    assert r_direct.data["context_mode"] == "client"

    # Request where dual_user is provider -> provider-context thread state
    sr_provider = ServiceRequest.objects.create(
        client=other_client,
        provider=dual_provider,
        subcategory=sub,
        title="طلب كمزود",
        description="وصف",
        request_type=RequestType.NORMAL,
        status=RequestStatus.ACCEPTED,
        city="الرياض",
    )
    r_req_thread = api.post(f"/api/messaging/requests/{sr_provider.id}/thread/", {}, format="json")
    assert r_req_thread.status_code == 200
    provider_thread_id = r_req_thread.data["id"]
    api.post(f"/api/messaging/thread/{provider_thread_id}/favorite/", {}, format="json")

    # Request where dual_user is client -> client-context thread state
    sr_client = ServiceRequest.objects.create(
        client=dual_user,
        provider=other_provider,
        subcategory=sub,
        title="طلب كعميل",
        description="وصف",
        request_type=RequestType.NORMAL,
        status=RequestStatus.ACCEPTED,
        city="الرياض",
    )
    r_req_thread2 = api.post(f"/api/messaging/requests/{sr_client.id}/thread/", {}, format="json")
    assert r_req_thread2.status_code == 200
    client_thread_id = r_req_thread2.data["id"]
    api.post(f"/api/messaging/thread/{client_thread_id}/archive/", {}, format="json")

    # Direct threads list: visible in client mode, hidden in provider mode
    direct_client = api.get("/api/messaging/direct/threads/", {"mode": "client"})
    assert direct_client.status_code == 200
    assert any((row.get("thread_id") == direct_thread_id) for row in direct_client.data)

    direct_provider = api.get("/api/messaging/direct/threads/", {"mode": "provider"})
    assert direct_provider.status_code == 200
    assert all((row.get("thread_id") != direct_thread_id) for row in direct_provider.data)

    # Thread states list: split by active mode
    states_client = api.get("/api/messaging/threads/states/", {"mode": "client"})
    assert states_client.status_code == 200
    ids_client = {row.get("thread") for row in states_client.data}
    assert client_thread_id in ids_client
    assert provider_thread_id not in ids_client

    states_provider = api.get("/api/messaging/threads/states/", {"mode": "provider"})
    assert states_provider.status_code == 200
    ids_provider = {row.get("thread") for row in states_provider.data}
    assert provider_thread_id in ids_provider
    assert client_thread_id not in ids_provider

    # Sanity: states exist in DB for both threads
    assert ThreadUserState.objects.filter(user=dual_user, thread_id=provider_thread_id).exists()
    assert ThreadUserState.objects.filter(user=dual_user, thread_id=client_thread_id).exists()


@pytest.mark.django_db
def test_direct_thread_creation_respects_provider_chat_quota():
    provider_user = User.objects.create_user(phone="0508000001", role_state=UserRole.PROVIDER)
    provider = ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود محدود",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    plan = SubscriptionPlan.objects.create(
        code="basic_chat_limit",
        title="الأساسية",
        tier="basic",
        period=PlanPeriod.YEAR,
        price=Decimal("0.00"),
        is_active=True,
    )
    Subscription.objects.create(
        user=provider_user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
    )

    api = APIClient()
    for idx in range(3):
        client_user = User.objects.create_user(phone=f"050800001{idx}", role_state=UserRole.PHONE_ONLY)
        api.force_authenticate(user=client_user)
        created = api.post(
            "/api/messaging/direct/thread/",
            {"provider_id": provider.id},
            format="json",
        )
        assert created.status_code == 200

    blocked_user = User.objects.create_user(phone="0508000099", role_state=UserRole.PHONE_ONLY)
    api.force_authenticate(user=blocked_user)
    blocked = api.post(
        "/api/messaging/direct/thread/",
        {"provider_id": provider.id},
        format="json",
    )
    assert blocked.status_code == 403
    assert "الحد الأقصى" in str(blocked.data.get("error", ""))


@pytest.mark.django_db
def test_existing_direct_thread_remains_accessible_after_quota_reached():
    client_user = User.objects.create_user(phone="0508000101", role_state=UserRole.PHONE_ONLY)
    provider_user = User.objects.create_user(phone="0508000102", role_state=UserRole.PROVIDER)
    provider = ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود مباشر",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    plan = SubscriptionPlan.objects.create(
        code="basic_chat_existing",
        title="الأساسية",
        tier="basic",
        period=PlanPeriod.YEAR,
        price=Decimal("0.00"),
        is_active=True,
    )
    Subscription.objects.create(
        user=provider_user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
    )

    api = APIClient()
    api.force_authenticate(user=client_user)
    first = api.post(
        "/api/messaging/direct/thread/",
        {"provider_id": provider.id},
        format="json",
    )
    assert first.status_code == 200
    thread_id = first.data["id"]

    for idx in range(2):
        other_client = User.objects.create_user(phone=f"050800011{idx}", role_state=UserRole.PHONE_ONLY)
        api.force_authenticate(user=other_client)
        created = api.post(
            "/api/messaging/direct/thread/",
            {"provider_id": provider.id},
            format="json",
        )
        assert created.status_code == 200

    api.force_authenticate(user=client_user)
    existing = api.post(
        "/api/messaging/direct/thread/",
        {"provider_id": provider.id},
        format="json",
    )
    assert existing.status_code == 200
    assert existing.data["id"] == thread_id
