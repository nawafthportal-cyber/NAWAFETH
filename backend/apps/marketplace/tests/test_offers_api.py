from datetime import timedelta

import pytest
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import OTP
from apps.marketplace.models import Offer, OfferStatus, RequestStatus, RequestType, ServiceRequest
from apps.providers.models import Category, ProviderCategory, ProviderProfile, SubCategory


def _login_via_otp(client: APIClient, phone: str) -> str:
    send = client.post("/api/accounts/otp/send/", {"phone": phone}, format="json")
    assert send.status_code == 200
    payload = send.json()
    code = payload.get("dev_code") or OTP.objects.filter(phone=phone).order_by("-id").values_list(
        "code", flat=True
    ).first()
    assert code

    verify = client.post(
        "/api/accounts/otp/verify/",
        {"phone": phone, "code": code},
        format="json",
    )
    assert verify.status_code == 200
    return verify.json()["access"]


def _complete_registration(client: APIClient, access: str, phone: str) -> None:
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
    res = client.post(
        "/api/accounts/complete/",
        {
            "first_name": "Test",
            "last_name": "User",
            "username": f"user_{phone}",
            "email": f"{phone}@example.com",
            "password": "StrongPass123!",
            "password_confirm": "StrongPass123!",
            "accept_terms": True,
        },
        format="json",
    )
    assert res.status_code == 200


def _ensure_provider_profile(client: APIClient, access: str, phone: str, city: str = "Riyadh") -> ProviderProfile:
    # Provider registration requires CLIENT+; complete registration first.
    _complete_registration(client, access, phone)

    res = client.post(
        "/api/providers/register/",
        {
            "provider_type": "individual",
            "display_name": "مزود",
            "bio": "bio",
            "years_experience": 1,
            "city": city,
            "accepts_urgent": True,
        },
        format="json",
    )
    assert res.status_code in (201, 400)
    return ProviderProfile.objects.get(user__phone=res.wsgi_request.user.phone)


def _make_request_visible_to_basic_providers(service_request: ServiceRequest) -> None:
    ServiceRequest.objects.filter(id=service_request.id).update(
        created_at=timezone.now() - timedelta(hours=73),
    )
    service_request.refresh_from_db(fields=["created_at"])


@pytest.mark.django_db
def test_provider_can_create_offer_once_for_competitive_sent_request():
    cat = Category.objects.create(name="خدمات", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="سباكة", is_active=True)

    client_api = APIClient()

    # Client creates a competitive request; set it SENT (system/admin step)
    client_phone = "0500000303"
    client_access = _login_via_otp(client_api, client_phone)
    _complete_registration(client_api, client_access, client_phone)
    create = client_api.post(
        "/api/marketplace/requests/create/",
        {
            "subcategory": sub.id,
            "title": "طلب تنافسي",
            "description": "desc",
            "request_type": "competitive",
            "city": "Riyadh",
        },
        format="json",
    )
    assert create.status_code == 201
    service_request = ServiceRequest.objects.get(id=create.json()["id"])
    service_request.status = RequestStatus.NEW
    service_request.save(update_fields=["status"])
    _make_request_visible_to_basic_providers(service_request)

    # Provider posts an offer
    provider_api = APIClient()
    provider_phone = "0500000404"
    provider_access = _login_via_otp(provider_api, provider_phone)
    provider_profile = _ensure_provider_profile(provider_api, provider_access, provider_phone, city="Riyadh")
    ProviderCategory.objects.get_or_create(provider=provider_profile, subcategory=sub)

    res1 = provider_api.post(
        f"/api/marketplace/requests/{service_request.id}/offers/create/",
        {"price": "250.00", "duration_days": 3, "note": "جاهز"},
        format="json",
    )
    assert res1.status_code == 201

    # Second offer attempt should conflict
    res2 = provider_api.post(
        f"/api/marketplace/requests/{service_request.id}/offers/create/",
        {"price": "300.00", "duration_days": 5, "note": "محاولة ثانية"},
        format="json",
    )
    assert res2.status_code == 409

    assert Offer.objects.filter(request=service_request, provider=provider_profile).count() == 1


@pytest.mark.django_db
def test_client_can_list_offers_and_accept_one_updates_statuses():
    cat = Category.objects.create(name="خدمات", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="تنظيف", is_active=True)

    # Client user
    client_api = APIClient()
    client_phone = "0500000505"
    client_access = _login_via_otp(client_api, client_phone)
    _complete_registration(client_api, client_access, client_phone)

    create = client_api.post(
        "/api/marketplace/requests/create/",
        {
            "subcategory": sub.id,
            "title": "طلب تنافسي",
            "description": "desc",
            "request_type": "competitive",
            "city": "Riyadh",
        },
        format="json",
    )
    assert create.status_code == 201
    service_request = ServiceRequest.objects.get(id=create.json()["id"])
    service_request.status = RequestStatus.NEW
    service_request.save(update_fields=["status"])
    _make_request_visible_to_basic_providers(service_request)

    # Two providers create offers
    p1_api = APIClient()
    p1_phone = "0500000606"
    p1_access = _login_via_otp(p1_api, p1_phone)
    p1 = _ensure_provider_profile(p1_api, p1_access, p1_phone)
    ProviderCategory.objects.get_or_create(provider=p1, subcategory=sub)

    p2_api = APIClient()
    p2_phone = "0500000707"
    p2_access = _login_via_otp(p2_api, p2_phone)
    p2 = _ensure_provider_profile(p2_api, p2_access, p2_phone)
    ProviderCategory.objects.get_or_create(provider=p2, subcategory=sub)

    o1 = p1_api.post(
        f"/api/marketplace/requests/{service_request.id}/offers/create/",
        {"price": "200.00", "duration_days": 2, "note": "عرض1"},
        format="json",
    )
    assert o1.status_code == 201
    offer1_id = o1.json()["offer_id"]

    o2 = p2_api.post(
        f"/api/marketplace/requests/{service_request.id}/offers/create/",
        {"price": "180.00", "duration_days": 4, "note": "عرض2"},
        format="json",
    )
    assert o2.status_code == 201
    offer2_id = o2.json()["offer_id"]

    # Client lists offers
    offers_list = client_api.get(f"/api/marketplace/requests/{service_request.id}/offers/")
    assert offers_list.status_code == 200
    assert len(offers_list.json()) == 2

    # Client accepts one offer
    accept = client_api.post(f"/api/marketplace/offers/{offer2_id}/accept/", {}, format="json")
    assert accept.status_code == 200

    service_request.refresh_from_db()
    assert service_request.status == RequestStatus.NEW
    assert service_request.provider_id == p2.id

    offer1 = Offer.objects.get(id=offer1_id)
    offer2 = Offer.objects.get(id=offer2_id)
    assert offer2.status == OfferStatus.SELECTED
    assert offer1.status == OfferStatus.REJECTED


@pytest.mark.django_db
def test_accept_offer_forbidden_for_non_owner():
    cat = Category.objects.create(name="خدمات", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="دهان", is_active=True)

    # Owner client
    owner_api = APIClient()
    owner_phone = "0500000808"
    owner_access = _login_via_otp(owner_api, owner_phone)
    _complete_registration(owner_api, owner_access, owner_phone)

    create = owner_api.post(
        "/api/marketplace/requests/create/",
        {
            "subcategory": sub.id,
            "title": "طلب تنافسي",
            "description": "desc",
            "request_type": "competitive",
            "city": "Riyadh",
        },
        format="json",
    )
    assert create.status_code == 201
    service_request = ServiceRequest.objects.get(id=create.json()["id"])
    service_request.status = RequestStatus.NEW
    service_request.save(update_fields=["status"])
    _make_request_visible_to_basic_providers(service_request)

    # Provider offer
    provider_api = APIClient()
    provider_phone = "0500000909"
    provider_access = _login_via_otp(provider_api, provider_phone)
    _ensure_provider_profile(provider_api, provider_access, provider_phone)
    ProviderCategory.objects.get_or_create(
        provider=ProviderProfile.objects.get(user__phone=provider_phone),
        subcategory=sub,
    )

    created = provider_api.post(
        f"/api/marketplace/requests/{service_request.id}/offers/create/",
        {"price": "100.00", "duration_days": 1, "note": "عرض"},
        format="json",
    )
    assert created.status_code == 201
    offer_id = created.json()["offer_id"]

    # Another client attempts to accept
    other_api = APIClient()
    other_phone = "0500001010"
    other_access = _login_via_otp(other_api, other_phone)
    _complete_registration(other_api, other_access, other_phone)

    res = other_api.post(f"/api/marketplace/offers/{offer_id}/accept/", {}, format="json")
    assert res.status_code == 403


@pytest.mark.django_db
def test_accept_offer_assigns_request_and_removes_from_competitive_available():
    cat = Category.objects.create(name="خدمات", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="تبريد", is_active=True)

    # Client creates competitive request
    client_api = APIClient()
    client_phone = "0500001111"
    client_access = _login_via_otp(client_api, client_phone)
    _complete_registration(client_api, client_access, client_phone)
    created = client_api.post(
        "/api/marketplace/requests/create/",
        {
            "subcategory": sub.id,
            "title": "طلب تنافسي للإسناد",
            "description": "desc",
            "request_type": "competitive",
            "city": "Riyadh",
        },
        format="json",
    )
    assert created.status_code == 201
    request_id = created.json()["id"]
    sr = ServiceRequest.objects.get(id=request_id)
    sr.status = RequestStatus.NEW
    sr.save(update_fields=["status"])
    _make_request_visible_to_basic_providers(sr)

    # Provider #1
    p1_api = APIClient()
    p1_phone = "0500001112"
    p1_access = _login_via_otp(p1_api, p1_phone)
    p1 = _ensure_provider_profile(p1_api, p1_access, p1_phone, city="Riyadh")
    ProviderCategory.objects.get_or_create(provider=p1, subcategory=sub)

    # Provider #2
    p2_api = APIClient()
    p2_phone = "0500001113"
    p2_access = _login_via_otp(p2_api, p2_phone)
    p2 = _ensure_provider_profile(p2_api, p2_access, p2_phone, city="Riyadh")
    ProviderCategory.objects.get_or_create(provider=p2, subcategory=sub)

    # Both send offers
    o1 = p1_api.post(
        f"/api/marketplace/requests/{request_id}/offers/create/",
        {"price": "320.00", "duration_days": 3, "note": "عرض 1"},
        format="json",
    )
    assert o1.status_code == 201

    o2 = p2_api.post(
        f"/api/marketplace/requests/{request_id}/offers/create/",
        {"price": "300.00", "duration_days": 4, "note": "عرض 2"},
        format="json",
    )
    assert o2.status_code == 201
    offer2_id = o2.json()["offer_id"]

    # Client accepts provider #2 offer
    accepted = client_api.post(
        f"/api/marketplace/offers/{offer2_id}/accept/",
        {},
        format="json",
    )
    assert accepted.status_code == 200

    sr.refresh_from_db()
    assert sr.provider_id == p2.id
    assert sr.status == RequestStatus.NEW

    # Must disappear from competitive available list for all providers
    p1_available = p1_api.get("/api/marketplace/provider/competitive/available/")
    assert p1_available.status_code == 200
    assert request_id not in {item["id"] for item in p1_available.json()}

    p2_available = p2_api.get("/api/marketplace/provider/competitive/available/")
    assert p2_available.status_code == 200
    assert request_id not in {item["id"] for item in p2_available.json()}

    # Should appear only in selected provider assigned requests
    p2_assigned = p2_api.get("/api/marketplace/provider/requests/?status_group=new")
    assert p2_assigned.status_code == 200
    assert request_id in {item["id"] for item in p2_assigned.json()}

    p1_assigned = p1_api.get("/api/marketplace/provider/requests/?status_group=new")
    assert p1_assigned.status_code == 200
    assert request_id not in {item["id"] for item in p1_assigned.json()}

