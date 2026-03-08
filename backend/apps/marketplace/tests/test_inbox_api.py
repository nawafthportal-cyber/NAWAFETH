import pytest
from datetime import timedelta
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import OTP
from apps.marketplace.models import RequestStatus, RequestType, ServiceRequest
from apps.providers.models import Category, ProviderCategory, ProviderProfile, SubCategory


@pytest.mark.django_db
def test_available_urgent_excludes_expired_requests():
    # Arrange: category/subcategory
    cat = Category.objects.create(name="خدمات", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="كهرباء", is_active=True)

    # Arrange: login as provider via OTP
    client = APIClient()
    send = client.post("/api/accounts/otp/send/", {"phone": "0500000101"}, format="json")
    assert send.status_code == 200
    payload = send.json()
    code = payload.get("dev_code") or OTP.objects.filter(phone="0500000101").order_by("-id").values_list(
        "code", flat=True
    ).first()
    assert code

    verify = client.post(
        "/api/accounts/otp/verify/",
        {"phone": "0500000101", "code": code},
        format="json",
    )
    assert verify.status_code == 200
    access = verify.json()["access"]
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

    # Complete registration (level 3) before registering provider
    complete = client.post(
        "/api/accounts/complete/",
        {
            "first_name": "مزود",
            "last_name": "اختبار",
            "username": "user_0500000101",
            "email": "0500000101@example.com",
            "password": "StrongPass123!",
            "password_confirm": "StrongPass123!",
            "accept_terms": True,
        },
        format="json",
    )
    assert complete.status_code == 200

    # Create provider profile
    reg = client.post(
        "/api/providers/register/",
        {
            "provider_type": "individual",
            "display_name": "مزود",
            "bio": "bio",
            "years_experience": 1,
            "city": "Riyadh",
            "accepts_urgent": True,
        },
        format="json",
    )
    assert reg.status_code in (201, 400)

    provider = ProviderProfile.objects.get(user_id=verify.json()["user_id"])
    ProviderCategory.objects.get_or_create(provider=provider, subcategory=sub)

    # Arrange: create an expired urgent request in matching city/subcategory
    expired = ServiceRequest.objects.create(
        client=provider.user,
        subcategory=sub,
        title="عاجل منتهي",
        description="desc",
        request_type=RequestType.URGENT,
        status=RequestStatus.NEW,
        city="Riyadh",
        is_urgent=True,
        expires_at=timezone.now() - timedelta(minutes=1),
    )

    # Arrange: create a valid urgent request in matching city/subcategory
    active = ServiceRequest.objects.create(
        client=provider.user,
        subcategory=sub,
        title="عاجل فعال",
        description="desc",
        request_type=RequestType.URGENT,
        status=RequestStatus.NEW,
        city="Riyadh",
        is_urgent=True,
        expires_at=timezone.now() + timedelta(minutes=10),
    )

    # Act
    res = client.get("/api/marketplace/provider/urgent/available/")

    # Assert
    assert res.status_code == 200
    ids = {item["id"] for item in res.json()}
    assert expired.id not in ids
    assert active.id in ids


@pytest.mark.django_db
def test_client_requests_lists_current_user_requests():
    # Arrange: category/subcategory
    cat = Category.objects.create(name="خدمات", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="نقاشة", is_active=True)

    client = APIClient()

    # Arrange: get JWT via OTP flow (as client)
    send = client.post("/api/accounts/otp/send/", {"phone": "0500000202"}, format="json")
    assert send.status_code == 200
    payload = send.json()
    dev_code = payload.get("dev_code") or OTP.objects.filter(phone="0500000202").order_by("-id").values_list(
        "code", flat=True
    ).first()
    assert dev_code

    verify = client.post(
        "/api/accounts/otp/verify/",
        {"phone": "0500000202", "code": dev_code},
        format="json",
    )
    assert verify.status_code == 200
    access = verify.json()["access"]

    # Create two requests for this client
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

    # Complete registration (level 3) before creating requests
    complete = client.post(
        "/api/accounts/complete/",
        {
            "first_name": "عميل",
            "last_name": "اختبار",
            "username": "user_0500000202",
            "email": "0500000202@example.com",
            "password": "StrongPass123!",
            "password_confirm": "StrongPass123!",
            "accept_terms": True,
        },
        format="json",
    )
    assert complete.status_code == 200

    r1 = client.post(
        "/api/marketplace/requests/create/",
        {
            "subcategory": sub.id,
            "title": "طلب 1",
            "description": "desc",
            "request_type": "competitive",
            "city": "الرياض",
        },
        format="json",
    )
    assert r1.status_code == 201

    r2 = client.post(
        "/api/marketplace/requests/create/",
        {
            "subcategory": sub.id,
            "title": "طلب 2",
            "description": "desc",
            "request_type": "urgent",
            "city": "الرياض",
        },
        format="json",
    )
    assert r2.status_code == 201

    # Act
    res = client.get("/api/marketplace/client/requests/")

    # Assert
    assert res.status_code == 200
    ids = [item["id"] for item in res.json()]
    assert r1.json()["id"] in ids
    assert r2.json()["id"] in ids


@pytest.mark.django_db
def test_provider_competitive_available_lists_matching_sent_requests():
    cat = Category.objects.create(name="خدمات", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="تنظيف", is_active=True)

    provider_user = ProviderProfile.objects.create(
        user=ProviderProfile._meta.get_field("user").related_model.objects.create(
            phone="0500002001", username="prov_2001"
        ),
        provider_type="individual",
        display_name="مزود",
        bio="bio",
        years_experience=1,
        city="Riyadh",
        accepts_urgent=True,
    )
    ProviderCategory.objects.get_or_create(provider=provider_user, subcategory=sub)

    # Login as provider via OTP
    client = APIClient()
    send = client.post("/api/accounts/otp/send/", {"phone": "0500002001"}, format="json")
    assert send.status_code == 200
    code = send.json().get("dev_code") or OTP.objects.filter(phone="0500002001").order_by("-id").values_list(
        "code", flat=True
    ).first()
    assert code
    verify = client.post("/api/accounts/otp/verify/", {"phone": "0500002001", "code": code}, format="json")
    assert verify.status_code == 200
    access = verify.json()["access"]
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

    # Complete registration so role is CLIENT+ (required by register endpoints in other tests)
    complete = client.post(
        "/api/accounts/complete/",
        {
            "first_name": "مزود",
            "last_name": "اختبار",
            "username": "user_0500002001",
            "email": "0500002001@example.com",
            "password": "StrongPass123!",
            "password_confirm": "StrongPass123!",
            "accept_terms": True,
        },
        format="json",
    )
    assert complete.status_code == 200

    # Create a matching competitive request (SENT)
    sr = ServiceRequest.objects.create(
        client=provider_user.user,
        subcategory=sub,
        title="طلب تنافسي",
        description="desc",
        request_type=RequestType.COMPETITIVE,
        status=RequestStatus.NEW,
        city="Riyadh",
        is_urgent=False,
    )
    ServiceRequest.objects.filter(id=sr.id).update(
        created_at=timezone.now() - timedelta(hours=73),
    )

    res = client.get("/api/marketplace/provider/competitive/available/")
    assert res.status_code == 200
    ids = {item["id"] for item in res.json()}
    assert sr.id in ids


@pytest.mark.django_db
def test_provider_can_accept_assigned_normal_request():
    cat = Category.objects.create(name="خدمات", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="دهان", is_active=True)

    # Create provider user + profile
    from apps.accounts.models import User

    u = User.objects.create(phone="0500003001", username="prov_3001")
    provider = ProviderProfile.objects.create(
        user=u,
        provider_type="individual",
        display_name="مزود",
        bio="bio",
        years_experience=1,
        city="Riyadh",
        accepts_urgent=True,
    )

    # OTP login as that provider
    client = APIClient()
    send = client.post("/api/accounts/otp/send/", {"phone": "0500003001"}, format="json")
    assert send.status_code == 200
    code = send.json().get("dev_code") or OTP.objects.filter(phone="0500003001").order_by("-id").values_list(
        "code", flat=True
    ).first()
    assert code
    verify = client.post("/api/accounts/otp/verify/", {"phone": "0500003001", "code": code}, format="json")
    assert verify.status_code == 200
    access = verify.json()["access"]
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

    complete = client.post(
        "/api/accounts/complete/",
        {
            "first_name": "مزود",
            "last_name": "اختبار",
            "username": "user_0500003001",
            "email": "0500003001@example.com",
            "password": "StrongPass123!",
            "password_confirm": "StrongPass123!",
            "accept_terms": True,
        },
        format="json",
    )
    assert complete.status_code == 200

    # Create assigned normal request in SENT
    sr = ServiceRequest.objects.create(
        client=u,
        provider=provider,
        subcategory=sub,
        title="طلب عادي",
        description="desc",
        request_type=RequestType.NORMAL,
        status=RequestStatus.NEW,
        city="Riyadh",
        is_urgent=False,
    )

    accept = client.post(f"/api/marketplace/provider/requests/{sr.id}/accept/", {}, format="json")
    assert accept.status_code == 200
    sr.refresh_from_db()
    assert sr.status == RequestStatus.NEW


@pytest.mark.django_db
def test_available_urgent_blank_city_matches_any_provider_city_with_same_subcategory():
    cat = Category.objects.create(name="خدمات", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="نجارة", is_active=True)

    from apps.accounts.models import User

    user_riyadh = User.objects.create(phone="0500004011", username="prov_4011")
    provider_riyadh = ProviderProfile.objects.create(
        user=user_riyadh,
        provider_type="individual",
        display_name="مزود الرياض",
        bio="bio",
        years_experience=1,
        city="Riyadh",
        accepts_urgent=True,
    )
    ProviderCategory.objects.get_or_create(provider=provider_riyadh, subcategory=sub)

    user_jeddah = User.objects.create(phone="0500004012", username="prov_4012")
    provider_jeddah = ProviderProfile.objects.create(
        user=user_jeddah,
        provider_type="individual",
        display_name="مزود جدة",
        bio="bio",
        years_experience=1,
        city="Jeddah",
        accepts_urgent=True,
    )
    ProviderCategory.objects.get_or_create(provider=provider_jeddah, subcategory=sub)

    urgent_any_city = ServiceRequest.objects.create(
        client=user_riyadh,
        subcategory=sub,
        title="عاجل بدون مدينة",
        description="desc",
        request_type=RequestType.URGENT,
        status=RequestStatus.NEW,
        city="",
        is_urgent=True,
        expires_at=timezone.now() + timedelta(minutes=10),
    )

    client = APIClient()
    send = client.post("/api/accounts/otp/send/", {"phone": "0500004011"}, format="json")
    assert send.status_code == 200
    code = send.json().get("dev_code") or OTP.objects.filter(phone="0500004011").order_by("-id").values_list(
        "code", flat=True
    ).first()
    assert code
    verify = client.post("/api/accounts/otp/verify/", {"phone": "0500004011", "code": code}, format="json")
    assert verify.status_code == 200
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {verify.json()['access']}")
    res_riyadh = client.get("/api/marketplace/provider/urgent/available/")
    assert res_riyadh.status_code == 200
    ids_riyadh = {item["id"] for item in res_riyadh.json()}
    assert urgent_any_city.id in ids_riyadh

    client2 = APIClient()
    send2 = client2.post("/api/accounts/otp/send/", {"phone": "0500004012"}, format="json")
    assert send2.status_code == 200
    code2 = send2.json().get("dev_code") or OTP.objects.filter(phone="0500004012").order_by("-id").values_list(
        "code", flat=True
    ).first()
    assert code2
    verify2 = client2.post("/api/accounts/otp/verify/", {"phone": "0500004012", "code": code2}, format="json")
    assert verify2.status_code == 200
    client2.credentials(HTTP_AUTHORIZATION=f"Bearer {verify2.json()['access']}")
    res_jeddah = client2.get("/api/marketplace/provider/urgent/available/")
    assert res_jeddah.status_code == 200
    ids_jeddah = {item["id"] for item in res_jeddah.json()}
    assert urgent_any_city.id in ids_jeddah


@pytest.mark.django_db
def test_available_urgent_with_city_only_matches_same_city_and_subcategory():
    cat = Category.objects.create(name="خدمات", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="سباكة", is_active=True)

    from apps.accounts.models import User

    user_riyadh = User.objects.create(phone="0500004021", username="prov_4021")
    provider_riyadh = ProviderProfile.objects.create(
        user=user_riyadh,
        provider_type="individual",
        display_name="مزود الرياض",
        bio="bio",
        years_experience=1,
        city="Riyadh",
        accepts_urgent=True,
    )
    ProviderCategory.objects.get_or_create(provider=provider_riyadh, subcategory=sub)

    user_jeddah = User.objects.create(phone="0500004022", username="prov_4022")
    provider_jeddah = ProviderProfile.objects.create(
        user=user_jeddah,
        provider_type="individual",
        display_name="مزود جدة",
        bio="bio",
        years_experience=1,
        city="Jeddah",
        accepts_urgent=True,
    )
    ProviderCategory.objects.get_or_create(provider=provider_jeddah, subcategory=sub)

    urgent_riyadh = ServiceRequest.objects.create(
        client=user_riyadh,
        subcategory=sub,
        title="عاجل في الرياض",
        description="desc",
        request_type=RequestType.URGENT,
        status=RequestStatus.NEW,
        city="Riyadh",
        is_urgent=True,
        expires_at=timezone.now() + timedelta(minutes=10),
    )

    client = APIClient()
    send = client.post("/api/accounts/otp/send/", {"phone": "0500004021"}, format="json")
    assert send.status_code == 200
    code = send.json().get("dev_code") or OTP.objects.filter(phone="0500004021").order_by("-id").values_list(
        "code", flat=True
    ).first()
    assert code
    verify = client.post("/api/accounts/otp/verify/", {"phone": "0500004021", "code": code}, format="json")
    assert verify.status_code == 200
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {verify.json()['access']}")
    res_riyadh = client.get("/api/marketplace/provider/urgent/available/")
    assert res_riyadh.status_code == 200
    ids_riyadh = {item["id"] for item in res_riyadh.json()}
    assert urgent_riyadh.id in ids_riyadh

    client2 = APIClient()
    send2 = client2.post("/api/accounts/otp/send/", {"phone": "0500004022"}, format="json")
    assert send2.status_code == 200
    code2 = send2.json().get("dev_code") or OTP.objects.filter(phone="0500004022").order_by("-id").values_list(
        "code", flat=True
    ).first()
    assert code2
    verify2 = client2.post("/api/accounts/otp/verify/", {"phone": "0500004022", "code": code2}, format="json")
    assert verify2.status_code == 200
    client2.credentials(HTTP_AUTHORIZATION=f"Bearer {verify2.json()['access']}")
    res_jeddah = client2.get("/api/marketplace/provider/urgent/available/")
    assert res_jeddah.status_code == 200
    ids_jeddah = {item["id"] for item in res_jeddah.json()}
    assert urgent_riyadh.id not in ids_jeddah

