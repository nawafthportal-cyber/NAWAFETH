import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient

from apps.accounts.models import OTP, User, UserRole
from apps.providers.models import (
    ProviderFollow,
    ProviderLike,
    ProviderPortfolioItem,
    ProviderPortfolioLike,
    ProviderPortfolioSave,
    ProviderProfile,
    ProviderSpotlightItem,
    ProviderSpotlightLike,
    ProviderSpotlightSave,
    RoleContext,
)


def _login_via_otp(client: APIClient, phone: str) -> str:
    send = client.post("/api/accounts/otp/send/", {"phone": phone}, format="json")
    assert send.status_code == 200
    payload = send.json()
    code = payload.get("dev_code") or OTP.objects.filter(phone=phone).order_by("-id").values_list("code", flat=True).first()
    assert code

    verify = client.post("/api/accounts/otp/verify/", {"phone": phone, "code": code}, format="json")
    assert verify.status_code == 200
    return verify.json()["access"]


def _complete_registration(client: APIClient, phone: str, username: str) -> None:
    res = client.post(
        "/api/accounts/complete/",
        {
            "first_name": "Test",
            "last_name": "User",
            "username": username,
            "email": f"{phone}@example.com",
            "password": "StrongPass123!",
            "password_confirm": "StrongPass123!",
            "accept_terms": True,
        },
        format="json",
    )
    assert res.status_code == 200


@pytest.mark.django_db
def test_me_view_blocks_username_change_after_registration():
    client = APIClient()
    phone = "0500000811"
    access = _login_via_otp(client, phone)
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
    _complete_registration(client, phone, "fixed_username")

    change = client.patch("/api/accounts/me/", {"username": "new_username"}, format="json")
    assert change.status_code == 400
    body = change.json()
    assert "username" in body

    user = User.objects.get(phone=phone)
    assert user.username == "fixed_username"


@pytest.mark.django_db
def test_me_view_allows_other_fields_update_while_username_locked():
    client = APIClient()
    phone = "0500000812"
    access = _login_via_otp(client, phone)
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
    _complete_registration(client, phone, "fixed_username_2")

    res = client.patch(
        "/api/accounts/me/",
        {
            "first_name": "Updated",
            "last_name": "Name",
            "email": "updated@example.com",
        },
        format="json",
    )
    assert res.status_code == 200
    payload = res.json()
    assert payload["first_name"] == "Updated"
    assert payload["last_name"] == "Name"
    assert payload["email"] == "updated@example.com"

    user = User.objects.get(phone=phone)
    assert user.username == "fixed_username_2"


@pytest.mark.django_db
def test_me_view_uploads_profile_and_cover_images(settings, tmp_path):
    settings.MEDIA_ROOT = str(tmp_path)
    settings.STORAGES = {
        "default": {
            "BACKEND": "django.core.files.storage.FileSystemStorage",
        },
        "staticfiles": {
            "BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage",
        },
    }

    client = APIClient()
    phone = "0500000813"
    access = _login_via_otp(client, phone)
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
    _complete_registration(client, phone, "fixed_username_3")

    profile_upload = SimpleUploadedFile("profile.jpg", b"profile-bytes", content_type="image/jpeg")
    cover_upload = SimpleUploadedFile("cover.jpg", b"cover-bytes", content_type="image/jpeg")

    res = client.patch(
        "/api/accounts/me/",
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

    user = User.objects.get(phone=phone)
    assert bool(user.profile_image)
    assert bool(user.cover_image)


@pytest.mark.django_db
def test_me_view_scopes_social_counts_by_mode(settings, tmp_path):
    settings.MEDIA_ROOT = str(tmp_path)
    settings.STORAGES = {
        "default": {
            "BACKEND": "django.core.files.storage.FileSystemStorage",
        },
        "staticfiles": {
            "BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage",
        },
    }

    actor_client = APIClient()
    actor_phone = "0500000814"
    access = _login_via_otp(actor_client, actor_phone)
    actor_client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
    _complete_registration(actor_client, actor_phone, "dual_mode_user")
    actor = User.objects.get(phone=actor_phone)

    provider_user_1 = User.objects.create(
        phone="0500000815",
        username="provider_ctx_1",
        role_state=UserRole.PROVIDER,
    )
    provider_user_2 = User.objects.create(
        phone="0500000816",
        username="provider_ctx_2",
        role_state=UserRole.PROVIDER,
    )
    provider_1 = ProviderProfile.objects.create(
        user=provider_user_1,
        provider_type="individual",
        display_name="Provider One",
        bio="bio",
        years_experience=2,
        city="الرياض",
    )
    provider_2 = ProviderProfile.objects.create(
        user=provider_user_2,
        provider_type="individual",
        display_name="Provider Two",
        bio="bio",
        years_experience=2,
        city="جدة",
    )

    png_bytes = (
        b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89"
        b"\x00\x00\x00\x0cIDATx\x9cc\xf8\xff\xff?\x00\x05\xfe\x02\xfeA\x89\x1e\x1b\x00\x00\x00\x00IEND\xaeB`\x82"
    )
    portfolio_item = ProviderPortfolioItem.objects.create(
        provider=provider_1,
        file_type="image",
        file=SimpleUploadedFile("ctx_portfolio.png", png_bytes, content_type="image/png"),
        caption="portfolio",
    )
    spotlight_item = ProviderSpotlightItem.objects.create(
        provider=provider_1,
        file_type="image",
        file=SimpleUploadedFile("ctx_spotlight.png", png_bytes, content_type="image/png"),
        caption="spotlight",
    )

    ProviderFollow.objects.create(user=actor, provider=provider_1, role_context=RoleContext.CLIENT)
    ProviderFollow.objects.create(user=actor, provider=provider_2, role_context=RoleContext.PROVIDER)

    ProviderLike.objects.create(user=actor, provider=provider_1, role_context=RoleContext.CLIENT)
    ProviderLike.objects.create(user=actor, provider=provider_2, role_context=RoleContext.PROVIDER)

    ProviderPortfolioLike.objects.create(
        user=actor,
        item=portfolio_item,
        role_context=RoleContext.CLIENT,
    )
    ProviderPortfolioSave.objects.create(
        user=actor,
        item=portfolio_item,
        role_context=RoleContext.PROVIDER,
    )

    ProviderSpotlightSave.objects.create(
        user=actor,
        item=spotlight_item,
        role_context=RoleContext.CLIENT,
    )
    ProviderSpotlightLike.objects.create(
        user=actor,
        item=spotlight_item,
        role_context=RoleContext.PROVIDER,
    )

    me_client = actor_client.get("/api/accounts/me/?mode=client")
    assert me_client.status_code == 200
    client_payload = me_client.json()
    assert client_payload["following_count"] == 1
    assert client_payload["likes_count"] == 1
    assert client_payload["favorites_media_count"] == 2

    me_provider = actor_client.get("/api/accounts/me/?mode=provider")
    assert me_provider.status_code == 200
    provider_payload = me_provider.json()
    assert provider_payload["following_count"] == 1
    assert provider_payload["likes_count"] == 1
    assert provider_payload["favorites_media_count"] == 2
