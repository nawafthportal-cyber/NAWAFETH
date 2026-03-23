from __future__ import annotations

import pytest
from django.test import Client
from django.urls import reverse

from apps.accounts.models import User
from apps.backoffice.models import AccessLevel, AccessPermission, Dashboard, UserAccessProfile
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.unified_requests.models import UnifiedRequest, UnifiedRequestStatus, UnifiedRequestType


def _dashboard(code: str, name_ar: str) -> Dashboard:
    dashboard, _ = Dashboard.objects.get_or_create(
        code=code,
        defaults={"name_ar": name_ar, "sort_order": 10},
    )
    return dashboard


def _login_dashboard_v2(client: Client, *, user: User, password: str = "Pass12345!") -> None:
    assert client.login(phone=user.phone, password=password)
    session = client.session
    session[SESSION_OTP_VERIFIED_KEY] = True
    session.save()


def _access_profile(user: User, *, level: str, dashboards: list[Dashboard]) -> UserAccessProfile:
    access_profile = UserAccessProfile.objects.create(user=user, level=level)
    access_profile.allowed_dashboards.set(dashboards)
    return access_profile


@pytest.mark.django_db
def test_phase5_analytics_exports_hides_export_actions_without_permission():
    analytics_dashboard = _dashboard("analytics", "التحليلات")
    user = User.objects.create_user(phone="0500500001", password="Pass12345!", is_staff=True)
    _access_profile(user, level=AccessLevel.USER, dashboards=[analytics_dashboard])

    client = Client()
    _login_dashboard_v2(client, user=user)

    response = client.get(reverse("dashboard_v2:analytics_exports"))
    assert response.status_code == 200
    html = response.content.decode("utf-8")
    assert "يتطلب صلاحية تصدير" in html
    assert ">فتح<" not in html
    assert "?section=provider" not in html


@pytest.mark.django_db
def test_phase5_analytics_overview_hides_export_route_without_permission():
    analytics_dashboard = _dashboard("analytics", "التحليلات")
    user = User.objects.create_user(phone="0500500004", password="Pass12345!", is_staff=True)
    _access_profile(user, level=AccessLevel.USER, dashboards=[analytics_dashboard])

    client = Client()
    _login_dashboard_v2(client, user=user)

    response = client.get(reverse("dashboard_v2:analytics_overview"))
    assert response.status_code == 200
    html = response.content.decode("utf-8")
    assert "التصدير غير متاح" in html
    assert reverse("dashboard_v2:analytics_exports") not in html


@pytest.mark.django_db
def test_phase5_analytics_exports_shows_export_actions_with_permission():
    analytics_dashboard = _dashboard("analytics", "التحليلات")
    user = User.objects.create_user(phone="0500500002", password="Pass12345!", is_staff=True)
    profile = _access_profile(user, level=AccessLevel.USER, dashboards=[analytics_dashboard])

    permission, _ = AccessPermission.objects.get_or_create(
        code="analytics.export",
        defaults={
            "name_ar": "تصدير التحليلات",
            "dashboard_code": "analytics",
            "sort_order": 40,
            "is_active": True,
        },
    )
    profile.granted_permissions.add(permission)

    client = Client()
    _login_dashboard_v2(client, user=user)

    response = client.get(reverse("dashboard_v2:analytics_exports"))
    assert response.status_code == 200
    html = response.content.decode("utf-8")
    assert "يتطلب صلاحية تصدير" not in html
    assert html.count(">فتح<") >= 2
    assert "?section=provider" in html


@pytest.mark.django_db
def test_phase5_requests_list_contains_loading_and_skeleton_hooks():
    client_dashboard = _dashboard("client_extras", "بوابة العميل")
    user = User.objects.create_user(phone="0500500003", password="Pass12345!")
    _access_profile(user, level=AccessLevel.CLIENT, dashboards=[client_dashboard])

    UnifiedRequest.objects.create(
        request_type=UnifiedRequestType.EXTRAS,
        requester=user,
        status=UnifiedRequestStatus.NEW,
        summary="phase5-hook-check",
    )

    client = Client()
    _login_dashboard_v2(client, user=user)

    response = client.get(reverse("dashboard_v2:client_portal_requests_list"))
    assert response.status_code == 200
    html = response.content.decode("utf-8")
    assert "data-loading-form" in html
    assert "data-table-skeleton" in html
