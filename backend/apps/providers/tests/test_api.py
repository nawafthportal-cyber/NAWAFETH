import pytest
from rest_framework.test import APIClient

from apps.accounts.models import OTP
from apps.providers.models import Category, ProviderCategory, ProviderProfile, SubCategory
from django.core.files.uploadedfile import SimpleUploadedFile


@pytest.mark.django_db
def test_get_categories_returns_active_with_subcategories():
    active = Category.objects.create(name="تصميم", is_active=True)
    SubCategory.objects.create(category=active, name="شعارات", is_active=True)

    Category.objects.create(name="غير نشط", is_active=False)

    client = APIClient()
    res = client.get("/api/providers/categories/")

    assert res.status_code == 200
    assert isinstance(res.json(), list)

    payload = res.json()
    assert len(payload) == 1
    assert payload[0]["name"] == "تصميم"
    assert payload[0]["subcategories"][0]["name"] == "شعارات"


@pytest.mark.django_db
def test_provider_register_flow_via_otp_and_jwt():
    client = APIClient()

    # 1) OTP send
    send = client.post(
        "/api/accounts/otp/send/",
        {"phone": "0500000000"},
        format="json",
    )
    assert send.status_code == 200
    payload = send.json()
    dev_code = payload.get("dev_code") or OTP.objects.filter(phone="0500000000").order_by("-id").values_list(
        "code", flat=True
    ).first()
    assert dev_code

    # 2) OTP verify -> JWT
    verify = client.post(
        "/api/accounts/otp/verify/",
        {"phone": "0500000000", "code": dev_code},
        format="json",
    )
    assert verify.status_code == 200
    access = verify.json()["access"]

    # 3) Authenticated register provider
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

    # 2.5) Complete registration (level 3)
    complete = client.post(
        "/api/accounts/complete/",
        {
            "first_name": "Test",
            "last_name": "Provider",
            "username": "user_0500000000",
            "email": "0500000000@example.com",
            "password": "StrongPass123!",
            "password_confirm": "StrongPass123!",
            "accept_terms": True,
        },
        format="json",
    )
    assert complete.status_code == 200

    reg = client.post(
        "/api/providers/register/",
        {
            "provider_type": "individual",
            "display_name": "محمد التصميم",
            "bio": "مصمم جرافيك محترف",
            "years_experience": 5,
            "city": "الرياض",
            "accepts_urgent": True,
        },
        format="json",
    )

    assert reg.status_code == 201
    assert ProviderProfile.objects.count() == 1
    profile = ProviderProfile.objects.first()
    assert profile is not None
    assert profile.display_name == "محمد التصميم"
    assert profile.city == "الرياض"


def _register_and_auth_provider(client: APIClient, phone: str = "0500000000") -> str:
    send = client.post(
        "/api/accounts/otp/send/",
        {"phone": phone},
        format="json",
    )
    assert send.status_code == 200
    payload = send.json()
    dev_code = payload.get("dev_code") or OTP.objects.filter(phone=phone).order_by("-id").values_list(
        "code", flat=True
    ).first()
    assert dev_code

    verify = client.post(
        "/api/accounts/otp/verify/",
        {"phone": phone, "code": dev_code},
        format="json",
    )
    assert verify.status_code == 200
    access = verify.json()["access"]

    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

    complete = client.post(
        "/api/accounts/complete/",
        {
            "first_name": "Test",
            "last_name": "Provider",
            "username": f"user_{phone}",
            "email": f"{phone}@example.com",
            "password": "StrongPass123!",
            "password_confirm": "StrongPass123!",
            "accept_terms": True,
        },
        format="json",
    )
    assert complete.status_code == 200

    reg = client.post(
        "/api/providers/register/",
        {
            "provider_type": "individual",
            "display_name": "محمد التصميم",
            "bio": "مصمم جرافيك محترف",
            "years_experience": 5,
            "city": "الرياض",
            "accepts_urgent": True,
        },
        format="json",
    )
    assert reg.status_code == 201
    return access


@pytest.mark.django_db
def test_provider_services_requires_auth():
    client = APIClient()
    res = client.get("/api/providers/me/services/")
    assert res.status_code in (401, 403)


@pytest.mark.django_db
def test_provider_services_crud_and_public_list():
    cat = Category.objects.create(name="تصميم", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="شعارات", is_active=True)

    client = APIClient()
    _register_and_auth_provider(client, phone="0500000001")

    create = client.post(
        "/api/providers/me/services/",
        {
            "title": "تصميم شعار احترافي",
            "description": "3 نماذج + تسليم الملفات المفتوحة",
            "price_from": "250.00",
            "price_to": "500.00",
            "price_unit": "fixed",
            "is_active": True,
            "subcategory_id": sub.id,
        },
        format="json",
    )
    assert create.status_code == 201
    service = create.json()
    assert service["title"] == "تصميم شعار احترافي"
    assert service["subcategory"]["id"] == sub.id
    service_id = service["id"]

    me_list = client.get("/api/providers/me/services/")
    assert me_list.status_code == 200
    assert isinstance(me_list.json(), list)
    assert len(me_list.json()) == 1

    patch = client.patch(
        f"/api/providers/me/services/{service_id}/",
        {"title": "تصميم شعار (محدث)"},
        format="json",
    )
    assert patch.status_code == 200
    assert patch.json()["title"] == "تصميم شعار (محدث)"

    provider_id = ProviderProfile.objects.first().id
    public_list = client.get(f"/api/providers/{provider_id}/services/")
    assert public_list.status_code == 200
    assert len(public_list.json()) == 1

    delete = client.delete(f"/api/providers/me/services/{service_id}/")
    assert delete.status_code in (200, 204)

    public_list2 = client.get(f"/api/providers/{provider_id}/services/")
    assert public_list2.status_code == 200
    assert len(public_list2.json()) == 0


@pytest.mark.django_db
def test_provider_list_supports_urgent_and_location_filters():
    cat = Category.objects.create(name="خدمات منزلية", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="سباكة", is_active=True)

    from apps.accounts.models import User

    p1_user = User.objects.create(phone="0501111111", username="provider_a")
    p1 = ProviderProfile.objects.create(
        user=p1_user,
        provider_type="individual",
        display_name="مزود عاجل مع موقع",
        bio="bio",
        years_experience=2,
        city="الرياض",
        accepts_urgent=True,
        lat=24.7136,
        lng=46.6753,
    )
    ProviderCategory.objects.get_or_create(provider=p1, subcategory=sub)

    p2_user = User.objects.create(phone="0502222222", username="provider_b")
    p2 = ProviderProfile.objects.create(
        user=p2_user,
        provider_type="individual",
        display_name="مزود بدون موقع",
        bio="bio",
        years_experience=2,
        city="الرياض",
        accepts_urgent=True,
    )
    ProviderCategory.objects.get_or_create(provider=p2, subcategory=sub)

    p3_user = User.objects.create(phone="0503333333", username="provider_c")
    p3 = ProviderProfile.objects.create(
        user=p3_user,
        provider_type="individual",
        display_name="مزود غير عاجل",
        bio="bio",
        years_experience=2,
        city="الرياض",
        accepts_urgent=False,
        lat=24.7200,
        lng=46.6800,
    )
    ProviderCategory.objects.get_or_create(provider=p3, subcategory=sub)

    client = APIClient()
    res = client.get(
        "/api/providers/list/",
        {
            "subcategory_id": sub.id,
            "city": "الرياض",
            "has_location": "true",
            "accepts_urgent": "true",
        },
    )

    assert res.status_code == 200
    payload = res.json()
    assert len(payload) == 1
    assert payload[0]["display_name"] == "مزود عاجل مع موقع"


@pytest.mark.django_db
def test_provider_can_upload_profile_and_cover_images(settings, tmp_path):
    settings.MEDIA_ROOT = tmp_path
    settings.STORAGES = {
        "default": {
            "BACKEND": "django.core.files.storage.FileSystemStorage",
        },
        "staticfiles": {
            "BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage",
        },
    }

    client = APIClient()
    _register_and_auth_provider(client, phone="0500000099")

    png_bytes = (
        b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89"
        b"\x00\x00\x00\x0cIDATx\x9cc\xf8\xff\xff?\x00\x05\xfe\x02\xfeA\x89\x1e\x1b\x00\x00\x00\x00IEND\xaeB`\x82"
    )
    profile_upload = SimpleUploadedFile("profile.png", png_bytes, content_type="image/png")
    cover_upload = SimpleUploadedFile("cover.png", png_bytes, content_type="image/png")

    res = client.patch(
        "/api/providers/me/profile/",
        {
            "profile_image": profile_upload,
            "cover_image": cover_upload,
        },
        format="multipart",
    )
    assert res.status_code == 200
    payload = res.json()
    assert payload.get("profile_image")
    assert payload.get("cover_image")

    profile = ProviderProfile.objects.get(user__phone="0500000099")
    assert bool(profile.profile_image)
    assert bool(profile.cover_image)
