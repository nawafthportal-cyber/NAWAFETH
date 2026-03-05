import pytest
from datetime import timedelta
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import OTP, User
from apps.marketplace.models import RequestStatus, ServiceRequest
from apps.notifications.models import Notification
from apps.providers.models import Category, ProviderCategory, ProviderProfile, SubCategory
from apps.subscriptions.models import PlanPeriod, PlanTier, Subscription, SubscriptionPlan, SubscriptionStatus


@pytest.mark.django_db
def test_create_urgent_service_request_auto_sends_and_sets_expiry():
    cat = Category.objects.create(name="تصميم", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="شعارات", is_active=True)

    client = APIClient()

    send = client.post(
        "/api/accounts/otp/send/",
        {"phone": "0500000001"},
        format="json",
    )
    assert send.status_code == 200
    payload = send.json()
    dev_code = payload.get("dev_code") or OTP.objects.filter(phone="0500000001").order_by("-id").values_list(
        "code", flat=True
    ).first()
    assert dev_code

    verify = client.post(
        "/api/accounts/otp/verify/",
        {"phone": "0500000001", "code": dev_code},
        format="json",
    )
    assert verify.status_code == 200
    access = verify.json()["access"]

    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

    complete = client.post(
        "/api/accounts/complete/",
        {
            "first_name": "عميل",
            "last_name": "اختبار",
            "username": "user_0500000001",
            "email": "0500000001@example.com",
            "password": "StrongPass123!",
            "password_confirm": "StrongPass123!",
            "accept_terms": True,
        },
        format="json",
    )
    assert complete.status_code == 200

    res = client.post(
        "/api/marketplace/requests/create/",
        {
            "subcategory": sub.id,
            "title": "تصميم شعار",
            "description": "أحتاج تصميم شعار احترافي",
            "request_type": "urgent",
            "city": "الرياض",
        },
        format="json",
    )
    assert res.status_code == 201

    sr = ServiceRequest.objects.get(id=res.json()["id"])
    assert sr.status == RequestStatus.NEW
    assert sr.is_urgent is True
    assert sr.expires_at is not None


@pytest.mark.django_db
def test_create_normal_request_can_target_provider():
    cat = Category.objects.create(name="تصميم", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="شعارات", is_active=True)

    client = APIClient()

    send = client.post(
        "/api/accounts/otp/send/",
        {"phone": "0500000002"},
        format="json",
    )
    assert send.status_code == 200
    payload = send.json()
    dev_code = payload.get("dev_code") or OTP.objects.filter(phone="0500000002").order_by("-id").values_list(
        "code", flat=True
    ).first()
    assert dev_code

    verify = client.post(
        "/api/accounts/otp/verify/",
        {"phone": "0500000002", "code": dev_code},
        format="json",
    )
    assert verify.status_code == 200
    access = verify.json()["access"]
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

    complete = client.post(
        "/api/accounts/complete/",
        {
            "first_name": "عميل",
            "last_name": "اختبار",
            "username": "user_0500000002",
            "email": "0500000002@example.com",
            "password": "StrongPass123!",
            "password_confirm": "StrongPass123!",
            "accept_terms": True,
        },
        format="json",
    )
    assert complete.status_code == 200

    from apps.accounts.models import User  # local import

    p_user = User.objects.create(phone="0500000099", username="provider_99")
    provider = ProviderProfile.objects.create(
        user=p_user,
        provider_type="individual",
        display_name="مزود تجريبي",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    ProviderCategory.objects.get_or_create(provider=provider, subcategory=sub)

    res = client.post(
        "/api/marketplace/requests/create/",
        {
            "provider": provider.id,
            "subcategory": sub.id,
            "title": "تصميم شعار لمزود محدد",
            "description": "طلب خاص",
            "request_type": "normal",
            "city": "الرياض",
        },
        format="json",
    )

    assert res.status_code == 201
    sr = ServiceRequest.objects.get(id=res.json()["id"])
    assert sr.provider_id == provider.id
    assert sr.request_type == "normal"
    n = Notification.objects.filter(user=p_user, kind="request_created").order_by("-id").first()
    assert n is not None
    assert n.kind == "request_created"
    assert n.audience_mode == "provider"
    assert f"/requests/{sr.id}" in (n.url or "")


@pytest.mark.django_db
def test_create_competitive_request_rejects_target_provider():
    cat = Category.objects.create(name="تصميم", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="شعارات", is_active=True)

    client = APIClient()

    send = client.post(
        "/api/accounts/otp/send/",
        {"phone": "0500000004"},
        format="json",
    )
    assert send.status_code == 200
    payload = send.json()
    dev_code = payload.get("dev_code") or OTP.objects.filter(phone="0500000004").order_by("-id").values_list(
        "code", flat=True
    ).first()
    assert dev_code

    verify = client.post(
        "/api/accounts/otp/verify/",
        {"phone": "0500000004", "code": dev_code},
        format="json",
    )
    assert verify.status_code == 200
    access = verify.json()["access"]
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

    complete = client.post(
        "/api/accounts/complete/",
        {
            "first_name": "عميل",
            "last_name": "اختبار",
            "username": "user_0500000004",
            "email": "0500000004@example.com",
            "password": "StrongPass123!",
            "password_confirm": "StrongPass123!",
            "accept_terms": True,
        },
        format="json",
    )
    assert complete.status_code == 200

    from apps.accounts.models import User  # local import

    p_user = User.objects.create(phone="0500000199", username="provider_199")
    provider = ProviderProfile.objects.create(
        user=p_user,
        provider_type="individual",
        display_name="مزود تنافسي مستهدف",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    ProviderCategory.objects.get_or_create(provider=provider, subcategory=sub)

    res = client.post(
        "/api/marketplace/requests/create/",
        {
            "provider": provider.id,
            "subcategory": sub.id,
            "title": "طلب تنافسي لمزود محدد",
            "description": "desc",
            "request_type": "competitive",
            "city": "الرياض",
        },
        format="json",
    )

    assert res.status_code == 400


@pytest.mark.django_db
def test_create_normal_request_requires_provider():
    cat = Category.objects.create(name="خدمات", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="سباكة", is_active=True)

    client = APIClient()

    send = client.post(
        "/api/accounts/otp/send/",
        {"phone": "0500000003"},
        format="json",
    )
    assert send.status_code == 200
    payload = send.json()
    dev_code = payload.get("dev_code") or OTP.objects.filter(phone="0500000003").order_by("-id").values_list(
        "code", flat=True
    ).first()
    assert dev_code

    verify = client.post(
        "/api/accounts/otp/verify/",
        {"phone": "0500000003", "code": dev_code},
        format="json",
    )
    assert verify.status_code == 200


@pytest.mark.django_db
def test_create_normal_request_allows_blank_city():
    cat = Category.objects.create(name="خدمات", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="سباكة", is_active=True)

    client = APIClient()

    send = client.post(
        "/api/accounts/otp/send/",
        {"phone": "0500000991"},
        format="json",
    )
    assert send.status_code == 200
    payload = send.json()
    dev_code = payload.get("dev_code") or OTP.objects.filter(phone="0500000991").order_by("-id").values_list(
        "code", flat=True
    ).first()
    assert dev_code

    verify = client.post(
        "/api/accounts/otp/verify/",
        {"phone": "0500000991", "code": dev_code},
        format="json",
    )
    assert verify.status_code == 200
    access = verify.json()["access"]
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

    complete = client.post(
        "/api/accounts/complete/",
        {
            "first_name": "عميل",
            "last_name": "اختبار",
            "username": "user_0500000991",
            "email": "0500000991@example.com",
            "password": "StrongPass123!",
            "password_confirm": "StrongPass123!",
            "accept_terms": True,
        },
        format="json",
    )
    assert complete.status_code == 200

    p_user = User.objects.create(phone="0500000992", username="provider_992")
    provider = ProviderProfile.objects.create(
        user=p_user,
        provider_type="individual",
        display_name="مزود تجريبي",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    ProviderCategory.objects.get_or_create(provider=provider, subcategory=sub)

    res = client.post(
        "/api/marketplace/requests/create/",
        {
            "provider": provider.id,
            "subcategory": sub.id,
            "title": "طلب بدون مدينة",
            "description": "طلب عادي والمدينة اختيارية",
            "request_type": "normal",
            "city": "",
        },
        format="json",
    )

    assert res.status_code == 201
    sr = ServiceRequest.objects.get(id=res.json()["id"])
    assert sr.request_type == "normal"
    assert sr.city == ""
    access = verify.json()["access"]
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

    complete = client.post(
        "/api/accounts/complete/",
        {
            "first_name": "عميل",
            "last_name": "اختبار",
            "username": "user_0500000003",
            "email": "0500000003@example.com",
            "password": "StrongPass123!",
            "password_confirm": "StrongPass123!",
            "accept_terms": True,
        },
        format="json",
    )
    assert complete.status_code == 200

    res = client.post(
        "/api/marketplace/requests/create/",
        {
            "subcategory": sub.id,
            "title": "طلب عادي بدون مزود",
            "description": "desc",
            "request_type": "normal",
            "city": "الرياض",
        },
        format="json",
    )

    assert res.status_code == 400


@pytest.mark.django_db
def test_create_urgent_allows_blank_city_when_dispatch_all():
    cat = Category.objects.create(name="خدمات", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="كهرباء", is_active=True)

    client = APIClient()
    send = client.post("/api/accounts/otp/send/", {"phone": "0500000005"}, format="json")
    assert send.status_code == 200
    payload = send.json()
    dev_code = payload.get("dev_code") or OTP.objects.filter(phone="0500000005").order_by("-id").values_list(
        "code", flat=True
    ).first()
    assert dev_code

    verify = client.post(
        "/api/accounts/otp/verify/",
        {"phone": "0500000005", "code": dev_code},
        format="json",
    )
    assert verify.status_code == 200
    access = verify.json()["access"]
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

    complete = client.post(
        "/api/accounts/complete/",
        {
            "first_name": "عميل",
            "last_name": "بدون مدينة",
            "username": "user_0500000005",
            "email": "0500000005@example.com",
            "password": "StrongPass123!",
            "password_confirm": "StrongPass123!",
            "accept_terms": True,
        },
        format="json",
    )
    assert complete.status_code == 200

    res = client.post(
        "/api/marketplace/requests/create/",
        {
            "subcategory": sub.id,
            "title": "طلب عاجل بدون مدينة",
            "description": "desc",
            "request_type": "urgent",
            "dispatch_mode": "all",
            "city": "",
        },
        format="json",
    )

    assert res.status_code == 201
    sr = ServiceRequest.objects.get(id=res.json()["id"])
    assert sr.city == ""
    assert sr.request_type == "urgent"


@pytest.mark.django_db
def test_create_urgent_creates_urgent_notifications_for_matching_providers_only():
    from apps.accounts.models import User

    cat = Category.objects.create(name="خدمات", is_active=True)
    sub_match = SubCategory.objects.create(category=cat, name="كهرباء", is_active=True)
    sub_other = SubCategory.objects.create(category=cat, name="سباكة", is_active=True)

    provider_user_match = User.objects.create(phone="0507777001", username="prov_match")
    provider_match = ProviderProfile.objects.create(
        user=provider_user_match,
        provider_type="individual",
        display_name="مزود مطابق",
        bio="bio",
        years_experience=2,
        city="الرياض",
        accepts_urgent=True,
    )
    ProviderCategory.objects.get_or_create(provider=provider_match, subcategory=sub_match)

    pro_plan = SubscriptionPlan.objects.create(
        code="pro_notify",
        tier=PlanTier.PRO,
        title="احترافية",
        period=PlanPeriod.MONTH,
        price="99.00",
        features=["verify_blue"],
    )
    Subscription.objects.create(
        user=provider_user_match,
        plan=pro_plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
        end_at=timezone.now() + timedelta(days=30),
    )

    provider_user_other = User.objects.create(phone="0507777002", username="prov_other")
    provider_other = ProviderProfile.objects.create(
        user=provider_user_other,
        provider_type="individual",
        display_name="مزود غير مطابق",
        bio="bio",
        years_experience=2,
        city="جدة",
        accepts_urgent=True,
    )
    ProviderCategory.objects.get_or_create(provider=provider_other, subcategory=sub_other)

    basic_plan = SubscriptionPlan.objects.create(
        code="basic_notify",
        tier=PlanTier.BASIC,
        title="أساسية",
        period=PlanPeriod.MONTH,
        price="49.00",
        features=["verify_green"],
    )
    Subscription.objects.create(
        user=provider_user_other,
        plan=basic_plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
        end_at=timezone.now() + timedelta(days=30),
    )

    client = APIClient()
    send = client.post("/api/accounts/otp/send/", {"phone": "0507777000"}, format="json")
    assert send.status_code == 200
    payload = send.json()
    dev_code = payload.get("dev_code") or OTP.objects.filter(phone="0507777000").order_by("-id").values_list(
        "code", flat=True
    ).first()
    assert dev_code

    verify = client.post(
        "/api/accounts/otp/verify/",
        {"phone": "0507777000", "code": dev_code},
        format="json",
    )
    assert verify.status_code == 200
    access = verify.json()["access"]
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

    complete = client.post(
        "/api/accounts/complete/",
        {
            "first_name": "عميل",
            "last_name": "عاجل",
            "username": "user_0507777000",
            "email": "0507777000@example.com",
            "password": "StrongPass123!",
            "password_confirm": "StrongPass123!",
            "accept_terms": True,
        },
        format="json",
    )
    assert complete.status_code == 200

    res = client.post(
        "/api/marketplace/requests/create/",
        {
            "subcategory": sub_match.id,
            "title": "عاجل كهرباء",
            "description": "أحتاج كهربائي الآن",
            "request_type": "urgent",
            "city": "الرياض",
        },
        format="json",
    )
    assert res.status_code == 201

    n_match = Notification.objects.filter(user=provider_user_match, kind="urgent_request").first()
    assert n_match is not None
    assert n_match.is_urgent is True
    assert "عاجل" in n_match.title

    n_other = Notification.objects.filter(user=provider_user_other, kind="urgent_request").first()
    assert n_other is None

