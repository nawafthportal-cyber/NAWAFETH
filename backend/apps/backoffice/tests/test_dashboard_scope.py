import pytest
from django.test import Client
from django.urls import reverse

from apps.accounts.models import User
from apps.backoffice.models import AccessLevel, Dashboard, UserAccessProfile
from apps.dashboard.access import sync_dashboard_user_access
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY


pytestmark = pytest.mark.django_db


@pytest.fixture
def dashboards():
    rows = [
        ("admin_control", "إدارة الصلاحيات", 1),
        ("support", "الدعم والمساعدة", 2),
        ("content", "إدارة المحتوى", 3),
        ("promo", "إدارة الترويج", 4),
        ("verify", "التوثيق", 5),
        ("analytics", "التحليلات", 6),
    ]
    for code, name_ar, order in rows:
        Dashboard.objects.get_or_create(
            code=code,
            defaults={"name_ar": name_ar, "is_active": True, "sort_order": order},
        )


@pytest.fixture
def otp_client():
    return Client()


def _login_with_dashboard_otp(client: Client, user: User) -> None:
    client.force_login(user)
    session = client.session
    session[SESSION_OTP_VERIFIED_KEY] = True
    session.save()


def test_power_user_is_scoped_to_allowed_dashboards(dashboards, otp_client):
    user = User.objects.create_user(phone="0557000001", username="power-scoped", password="Pass12345!")
    profile = UserAccessProfile.objects.create(user=user, level=AccessLevel.POWER)
    profile.allowed_dashboards.set(Dashboard.objects.filter(code__in=["support"]))

    changed_fields = sync_dashboard_user_access(user, access_profile=profile, force_staff_role_state=True)
    if changed_fields:
        user.save(update_fields=changed_fields)

    _login_with_dashboard_otp(otp_client, user)

    index_response = otp_client.get(reverse("dashboard:index"))
    assert index_response.status_code == 302
    assert index_response.url == reverse("dashboard:support_dashboard")

    support_response = otp_client.get(reverse("dashboard:support_dashboard"))
    assert support_response.status_code == 200

    assert otp_client.get(reverse("dashboard:admin_control_home")).status_code == 403
    assert otp_client.get(reverse("dashboard:content_dashboard_home")).status_code == 403
    assert otp_client.get(reverse("dashboard:promo_dashboard")).status_code == 403
    assert otp_client.get(reverse("dashboard:verification_dashboard")).status_code == 403
    assert otp_client.get(reverse("dashboard:analytics_insights")).status_code == 403

    html = support_response.content.decode("utf-8", errors="ignore")
    assert reverse("dashboard:admin_control_home") not in html
    assert reverse("dashboard:content_dashboard_home") not in html
    assert reverse("dashboard:promo_dashboard") not in html
    assert reverse("dashboard:verification_dashboard") not in html
    assert reverse("dashboard:analytics_insights") not in html


def test_admin_user_keeps_full_dashboard_access(dashboards, otp_client):
    user = User.objects.create_user(phone="0557000002", username="admin-full", password="Pass12345!")
    profile = UserAccessProfile.objects.create(user=user, level=AccessLevel.ADMIN)
    profile.allowed_dashboards.clear()

    changed_fields = sync_dashboard_user_access(user, access_profile=profile, force_staff_role_state=True)
    if changed_fields:
        user.save(update_fields=changed_fields)

    _login_with_dashboard_otp(otp_client, user)

    assert otp_client.get(reverse("dashboard:admin_control_home")).status_code == 200
    assert otp_client.get(reverse("dashboard:support_dashboard")).status_code == 200
    assert otp_client.get(reverse("dashboard:content_dashboard_home")).status_code == 200
    assert otp_client.get(reverse("dashboard:promo_dashboard")).status_code == 200
    assert otp_client.get(reverse("dashboard:verification_dashboard")).status_code == 200
