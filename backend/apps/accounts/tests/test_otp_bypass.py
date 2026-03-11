import pytest
from django.test import override_settings
from rest_framework.test import APIClient

from apps.accounts.models import OTP


@pytest.mark.django_db
@override_settings(
    DEBUG=False,
    OTP_APP_BYPASS=True,
    OTP_APP_BYPASS_ALLOWLIST=["0555967209", "0546868209"],
)
def test_otp_app_bypass_in_production_only_allows_allowlisted_numbers():
    client = APIClient()

    allowed_send = client.post(
        "/api/accounts/otp/send/",
        {"phone": "0555967209"},
        format="json",
    )
    assert allowed_send.status_code == 200

    allowed_verify = client.post(
        "/api/accounts/otp/verify/",
        {"phone": "0555967209", "code": "1234"},
        format="json",
    )
    assert allowed_verify.status_code == 200
    assert allowed_verify.json()["ok"] is True

    blocked_send = client.post(
        "/api/accounts/otp/send/",
        {"phone": "0500000901"},
        format="json",
    )
    assert blocked_send.status_code == 200

    blocked_verify = client.post(
        "/api/accounts/otp/verify/",
        {"phone": "0500000901", "code": "1234"},
        format="json",
    )
    assert blocked_verify.status_code == 400
    assert blocked_verify.json()["detail"] == "الكود غير صحيح"


@pytest.mark.django_db
@override_settings(
    DEBUG=False,
    OTP_APP_BYPASS=True,
    OTP_APP_BYPASS_ALLOWLIST=[],
)
def test_otp_app_bypass_in_production_requires_explicit_allowlist():
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