import pytest
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
def test_change_username_endpoint_updates_username():
    client = APIClient()
    phone = "0500000921"
    access = _login_via_otp(client, phone)
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
    _complete_registration(client, phone, "old_user_name")

    res = client.post("/api/accounts/change-username/", {"username": "new_user_name"}, format="json")

    assert res.status_code == 200
    body = res.json()
    assert body.get("ok") is True
    assert body.get("username") == "new_user_name"
    assert User.objects.get(phone=phone).username == "new_user_name"


@pytest.mark.django_db
def test_change_password_endpoint_updates_password_hash():
    client = APIClient()
    phone = "0500000922"
    access = _login_via_otp(client, phone)
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
    _complete_registration(client, phone, "password_user")

    res = client.post(
        "/api/accounts/change-password/",
        {
            "current_password": "StrongPass123!",
            "new_password": "NewStrongPass456!",
            "new_password_confirm": "NewStrongPass456!",
        },
        format="json",
    )

    assert res.status_code == 200
    assert res.json().get("ok") is True

    user = User.objects.get(phone=phone)
    assert user.check_password("NewStrongPass456!")


@pytest.mark.django_db
def test_change_password_endpoint_rejects_wrong_current_password():
    client = APIClient()
    phone = "0500000923"
    access = _login_via_otp(client, phone)
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
    _complete_registration(client, phone, "password_user_2")

    res = client.post(
        "/api/accounts/change-password/",
        {
            "current_password": "WrongPass111!",
            "new_password": "NewStrongPass456!",
            "new_password_confirm": "NewStrongPass456!",
        },
        format="json",
    )

    assert res.status_code == 400
    body = res.json()
    assert "current_password" in body
