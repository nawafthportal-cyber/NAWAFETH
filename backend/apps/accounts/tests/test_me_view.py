import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient

from apps.accounts.models import OTP, User


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
