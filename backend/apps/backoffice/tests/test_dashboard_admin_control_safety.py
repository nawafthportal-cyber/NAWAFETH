import pytest
from django.test import Client
from django.urls import reverse

from apps.accounts.models import User
from apps.backoffice.models import AccessLevel, AccessPermission, Dashboard, UserAccessProfile
from apps.dashboard.access import sync_dashboard_user_access
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY


pytestmark = pytest.mark.django_db


@pytest.fixture
def otp_client():
    return Client()


def _seed_dashboard_rows():
    rows = [
        ("admin_control", "Admin Control", 1),
        ("support", "Support", 2),
    ]
    for code, name_ar, order in rows:
        Dashboard.objects.get_or_create(
            code=code,
            defaults={"name_ar": name_ar, "is_active": True, "sort_order": order},
        )


def _login_with_dashboard_otp(client: Client, user: User) -> None:
    client.force_login(user)
    session = client.session
    session[SESSION_OTP_VERIFIED_KEY] = True
    session.save()


def _make_admin_user(phone: str, username: str) -> tuple[User, UserAccessProfile]:
    user = User.objects.create_user(phone=phone, username=username, password="Pass12345!")
    profile = UserAccessProfile.objects.create(user=user, level=AccessLevel.ADMIN)
    changed_fields = sync_dashboard_user_access(user, access_profile=profile, force_staff_role_state=True)
    if changed_fields:
        user.save(update_fields=changed_fields)
    return user, profile


def test_cannot_deactivate_last_active_admin_via_dashboard(otp_client):
    _seed_dashboard_rows()
    admin_user, admin_profile = _make_admin_user("0557200001", "last-admin-delete")
    _login_with_dashboard_otp(otp_client, admin_user)

    response = otp_client.post(
        reverse("dashboard:admin_control_home"),
        {"action": "delete_user", "profile_id": str(admin_profile.id)},
        follow=True,
    )

    admin_profile.refresh_from_db()
    assert admin_profile.revoked_at is None
    assert "لا يمكن تعطيل آخر Admin فع" in response.content.decode("utf-8", errors="ignore")


def test_cannot_revoke_last_active_admin_via_dashboard_toggle(otp_client):
    _seed_dashboard_rows()
    admin_user, admin_profile = _make_admin_user("0557200002", "last-admin-toggle")
    _login_with_dashboard_otp(otp_client, admin_user)

    response = otp_client.post(
        reverse("dashboard:admin_control_home"),
        {"action": "toggle_revoke", "profile_id": str(admin_profile.id)},
        follow=True,
    )

    admin_profile.refresh_from_db()
    assert admin_profile.revoked_at is None
    assert "لا يمكن سحب صلاحية آخر Admin فع" in response.content.decode("utf-8", errors="ignore")


def test_cannot_demote_last_active_admin_via_save_user(otp_client):
    _seed_dashboard_rows()
    admin_user, admin_profile = _make_admin_user("0557200003", "last-admin-demote")
    _login_with_dashboard_otp(otp_client, admin_user)

    response = otp_client.post(
        reverse("dashboard:admin_control_home"),
        {
            "action": "save_user",
            "profile_id": str(admin_profile.id),
            "username": admin_user.username,
            "mobile_number": admin_user.phone,
            "level": AccessLevel.USER,
            "password": "",
            "password_expiration_date": "",
            "account_revoke_date": "",
        },
        follow=True,
    )

    admin_profile.refresh_from_db()
    assert admin_profile.level == AccessLevel.ADMIN
    assert "لا يمكن خفض/تعطيل آخر Admin فع" in response.content.decode("utf-8", errors="ignore")


def test_save_user_persists_granted_permissions(otp_client):
    _seed_dashboard_rows()
    operator, _operator_profile = _make_admin_user("0557200004", "operator-admin")

    target_user = User.objects.create_user(phone="0557200005", username="target-user", password="Pass12345!")
    target_profile = UserAccessProfile.objects.create(user=target_user, level=AccessLevel.USER)

    support_permission, _ = AccessPermission.objects.get_or_create(
        code="support.resolve",
        defaults={
            "name_ar": "Resolve Support",
            "dashboard_code": "support",
            "is_active": True,
            "sort_order": 100,
        },
    )

    _login_with_dashboard_otp(otp_client, operator)
    response = otp_client.post(
        reverse("dashboard:admin_control_home"),
        {
            "action": "save_user",
            "profile_id": str(target_profile.id),
            "username": target_user.username,
            "mobile_number": target_user.phone,
            "level": AccessLevel.USER,
            "dashboards": ["support"],
            "permissions": [support_permission.code],
            "password": "",
            "password_expiration_date": "",
            "account_revoke_date": "",
        },
        follow=True,
    )

    target_profile.refresh_from_db()
    assert target_profile.granted_permissions.filter(code=support_permission.code).exists()
    assert response.status_code == 200


def test_new_query_takes_precedence_over_edit_query(otp_client):
    _seed_dashboard_rows()
    operator, _operator_profile = _make_admin_user("0557200006", "operator-admin-2")

    target_user = User.objects.create_user(phone="0557200007", username="target-user-2", password="Pass12345!")
    target_profile = UserAccessProfile.objects.create(user=target_user, level=AccessLevel.USER)

    _login_with_dashboard_otp(otp_client, operator)
    response = otp_client.get(
        f"{reverse('dashboard:admin_control_home')}?section=access&new=1&edit={target_profile.id}"
    )

    assert response.status_code == 200
    assert response.context["edit_profile"] is None
    assert response.context["access_form_open"] is True
    assert "إضافة حساب تشغيل جديد" in response.content.decode("utf-8", errors="ignore")
