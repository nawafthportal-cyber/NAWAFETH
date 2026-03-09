from __future__ import annotations

from django.http import HttpResponse
from django.test import Client, override_settings
from django.urls import reverse

from apps.accounts.models import User, UserRole
from apps.core.models import PlatformConfig
from apps.extras_portal.auth import (
    SESSION_PORTAL_LOGIN_USER_ID_KEY,
    SESSION_PORTAL_OTP_VERIFIED_KEY,
)
from apps.marketplace.models import RequestStatus, RequestType, ServiceRequest
from apps.providers.models import Category, ProviderCategory, ProviderProfile, SubCategory


def _make_provider(phone: str) -> tuple[ProviderProfile, SubCategory]:
    user = User.objects.create_user(
        phone=phone,
        username=phone,
        password="Pass12345!",
        role_state=UserRole.PROVIDER,
    )
    provider = ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name=f"Provider {phone}",
        bio="bio",
        city="الرياض",
        years_experience=1,
        accepts_urgent=True,
    )
    category = Category.objects.create(name=f"Cat {phone}", is_active=True)
    subcategory = SubCategory.objects.create(category=category, name=f"Sub {phone}", is_active=True)
    ProviderCategory.objects.create(provider=provider, subcategory=subcategory)
    return provider, subcategory


def _portal_client(user: User) -> Client:
    client = Client()
    client.force_login(user)
    session = client.session
    session[SESSION_PORTAL_LOGIN_USER_ID_KEY] = user.id
    session[SESSION_PORTAL_OTP_VERIFIED_KEY] = True
    session.save()
    return client


@override_settings(DEBUG=True, OTP_DEV_BYPASS_ENABLED=True, OTP_DEV_ACCEPT_ANY_4_DIGITS=True)
def test_portal_otp_dev_mode_accepts_any_4_digits(db):
    provider, _ = _make_provider("0590000101")
    user = provider.user

    client = Client()
    login_res = client.post(
        reverse("extras_portal:login"),
        data={"username": user.phone, "password": "Pass12345!"},
    )
    assert login_res.status_code == 302
    assert login_res.url == reverse("extras_portal:otp")

    otp_res = client.post(reverse("extras_portal:otp"), data={"code": "4321"})
    assert otp_res.status_code == 302
    assert otp_res.url == reverse("extras_portal:reports")
    assert client.session.get(SESSION_PORTAL_OTP_VERIFIED_KEY) is True


@override_settings(DEBUG=False, OTP_DEV_BYPASS_ENABLED=False, OTP_DEV_ACCEPT_ANY_4_DIGITS=False)
def test_portal_otp_requires_real_code_when_dev_mode_disabled(db):
    provider, _ = _make_provider("0590000102")
    user = provider.user

    client = Client()
    login_res = client.post(
        reverse("extras_portal:login"),
        data={"username": user.phone, "password": "Pass12345!"},
    )
    assert login_res.status_code == 302
    assert login_res.url == reverse("extras_portal:otp")

    otp_res = client.post(reverse("extras_portal:otp"), data={"code": "1234"})
    assert otp_res.status_code == 200
    assert SESSION_PORTAL_OTP_VERIFIED_KEY not in client.session


def test_portal_reports_export_uses_platform_config_limit(mocker, db):
    provider, subcategory = _make_provider("0590000103")
    client_user = User.objects.create_user(phone="0590000999", password="Pass12345!")
    for idx in range(3):
        ServiceRequest.objects.create(
            client=client_user,
            provider=provider,
            subcategory=subcategory,
            title=f"طلب {idx}",
            description="وصف",
            request_type=RequestType.NORMAL,
            status=RequestStatus.COMPLETED,
            city="الرياض",
        )

    config = PlatformConfig.load()
    config.export_xlsx_max_rows = 1
    config.save()

    captured: dict[str, list] = {}

    def _fake_xlsx_response(filename, sheet_name, headers, rows):
        captured["rows"] = rows
        return HttpResponse(
            b"PK",
            content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )

    mocker.patch("apps.extras_portal.views.xlsx_response", side_effect=_fake_xlsx_response)

    client = _portal_client(provider.user)
    response = client.get(reverse("extras_portal:reports_export_xlsx"))

    assert response.status_code == 200
    assert len(captured["rows"]) == 1
