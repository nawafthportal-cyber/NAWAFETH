import pytest
from django.test import override_settings
from rest_framework.test import APIClient

from apps.accounts.models import OTP


@pytest.mark.django_db
@override_settings(
    DEBUG=False,
    OTP_APP_BYPASS=True,
    OTP_APP_BYPASS_ALLOWLIST=[],
)
def test_otp_app_bypass_in_production_accepts_any_number_when_enabled():
    client = APIClient()

    for phone in ("0555967209", "0500000901"):
        send = client.post(
            "/api/accounts/otp/send/",
            {"phone": phone},
            format="json",
        )
        assert send.status_code == 200

        verify = client.post(
            "/api/accounts/otp/verify/",
            {"phone": phone, "code": "1234"},
            format="json",
        )
        assert verify.status_code == 200
        assert verify.json()["ok"] is True


@pytest.mark.django_db
@override_settings(
    DEBUG=False,
    OTP_APP_BYPASS=False,
    OTP_APP_BYPASS_ALLOWLIST=[],
)
def test_otp_app_bypass_disabled_requires_real_code():
    client = APIClient()

    send = client.post(
        "/api/accounts/otp/send/",
        {"phone": "0555967209"},
        format="json",
    )
    assert send.status_code == 200

    bypass_attempt = client.post(
        "/api/accounts/otp/verify/",
        {"phone": "0555967209", "code": "1234"},
        format="json",
    )
    assert bypass_attempt.status_code == 400
    assert bypass_attempt.json()["detail"] == "الكود غير صحيح"

    actual_code = OTP.objects.filter(phone="0555967209").order_by("-id").values_list("code", flat=True).first()
    assert actual_code

    real_verify = client.post(
        "/api/accounts/otp/verify/",
        {"phone": "0555967209", "code": actual_code},
        format="json",
    )
    assert real_verify.status_code == 200
    assert real_verify.json()["ok"] is True