import pytest
from datetime import timedelta
from django.test import Client, override_settings
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import User
from apps.backoffice.models import AccessLevel, AccessPermission, Dashboard, UserAccessProfile
from apps.backoffice.policies import PermissionCode
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.moderation.models import ModerationCase, ModerationSeverity, ModerationStatus


pytestmark = pytest.mark.django_db


def _login_dashboard_user(phone: str, level: str, dashboards: list[str], *, permission_codes: list[str] | None = None):
    user = User.objects.create_user(phone=phone, password="Pass12345!", is_staff=True)
    access_profile = UserAccessProfile.objects.create(user=user, level=level)
    dashboard_objs = []
    for i, code in enumerate(dashboards, start=1):
        dashboard, _ = Dashboard.objects.get_or_create(
            code=code,
            defaults={"name_ar": code, "sort_order": i},
        )
        dashboard_objs.append(dashboard)
    access_profile.allowed_dashboards.set(dashboard_objs)

    for index, permission_code in enumerate(permission_codes or [], start=1):
        permission, _ = AccessPermission.objects.get_or_create(
            code=permission_code,
            defaults={
                "dashboard_code": "moderation",
                "name_ar": permission_code,
                "sort_order": index * 10,
            },
        )
        access_profile.granted_permissions.add(permission)

    client = Client()
    assert client.login(phone=phone, password="Pass12345!")
    session = client.session
    session[SESSION_OTP_VERIFIED_KEY] = True
    session.save()
    return user, client


@override_settings(FEATURE_MODERATION_CENTER=True)
def test_moderation_dashboard_list_detail_and_filters():
    reporter = User.objects.create_user(phone="0500011601", password="Pass12345!")
    case = ModerationCase.objects.create(
        reporter=reporter,
        source_app="support",
        source_model="SupportTicket",
        source_object_id="77",
        source_label="SupportTicket #77",
        reason="بلاغ",
        severity=ModerationSeverity.HIGH,
        status=ModerationStatus.NEW,
    )
    ModerationCase.objects.filter(id=case.id).update(sla_due_at=timezone.now() - timedelta(hours=2), category="complaint")
    _admin_user, dashboard_client = _login_dashboard_user("0500011600", AccessLevel.ADMIN, ["moderation"])

    list_response = dashboard_client.get(
        reverse("dashboard:moderation_cases_list"),
        data={"status": "new", "source_kind": "support", "severity": "high", "category": "complaint", "sla_state": "overdue"},
    )
    detail_response = dashboard_client.get(reverse("dashboard:moderation_case_detail", args=[case.id]))

    assert list_response.status_code == 200
    assert detail_response.status_code == 200
    html = list_response.content.decode("utf-8")
    assert case.code in html
    assert "مركز الإشراف" in html
    assert "متأخرة" in html
    detail_html = detail_response.content.decode("utf-8")
    assert "Snapshot المصدر" in detail_html or "الملخص" in detail_html


@override_settings(FEATURE_MODERATION_CENTER=True, FEATURE_RBAC_ENFORCE=True, RBAC_AUDIT_ONLY=False)
def test_moderation_dashboard_actions_apply_when_permissions_granted():
    reporter = User.objects.create_user(phone="0500011602", password="Pass12345!")
    operator, dashboard_client = _login_dashboard_user(
        "0500011603",
        AccessLevel.USER,
        ["moderation"],
        permission_codes=[PermissionCode.MODERATION_ASSIGN, PermissionCode.MODERATION_RESOLVE],
    )
    case = ModerationCase.objects.create(reporter=reporter, reason="test", details="x")

    assign_response = dashboard_client.post(
        reverse("dashboard:moderation_case_assign_action", args=[case.id]),
        data={
            "assigned_team_code": "moderation",
            "assigned_team_name": "الإشراف",
            "assigned_to": operator.id,
            "note": "claim",
        },
    )
    status_response = dashboard_client.post(
        reverse("dashboard:moderation_case_status_action", args=[case.id]),
        data={"status": "escalated", "note": "needs escalation"},
    )
    decision_response = dashboard_client.post(
        reverse("dashboard:moderation_case_decision_action", args=[case.id]),
        data={"decision_code": "no_action", "note": "resolved"},
    )

    assert assign_response.status_code == 302
    assert status_response.status_code == 302
    assert decision_response.status_code == 302
    case.refresh_from_db()
    assert case.assigned_to_id == operator.id
    assert case.decisions.filter(decision_code="no_action").exists()
    assert case.status == "dismissed"


@override_settings(FEATURE_MODERATION_CENTER=True, FEATURE_RBAC_ENFORCE=True, RBAC_AUDIT_ONLY=False)
def test_moderation_dashboard_assign_forbidden_without_permission():
    reporter = User.objects.create_user(phone="0500011604", password="Pass12345!")
    operator, dashboard_client = _login_dashboard_user(
        "0500011605",
        AccessLevel.USER,
        ["moderation"],
    )
    case = ModerationCase.objects.create(reporter=reporter, reason="test", details="x")

    response = dashboard_client.post(
        reverse("dashboard:moderation_case_assign_action", args=[case.id]),
        data={
            "assigned_team_code": "moderation",
            "assigned_to": operator.id,
        },
    )

    assert response.status_code == 302
    case.refresh_from_db()
    assert case.assigned_to_id is None
