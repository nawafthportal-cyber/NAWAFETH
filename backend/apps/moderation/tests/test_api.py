import pytest
from django.test import override_settings
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole
from apps.backoffice.models import AccessLevel, AccessPermission, Dashboard, UserAccessProfile
from apps.backoffice.policies import PermissionCode
from apps.moderation.models import ModerationCase


pytestmark = pytest.mark.django_db


@pytest.fixture
def api():
    return APIClient()


@pytest.fixture
def moderation_dashboard():
    dash, _ = Dashboard.objects.get_or_create(
        code="moderation",
        defaults={"name_ar": "مركز الإشراف", "sort_order": 25},
    )
    return dash


@pytest.fixture
def reporter_user():
    return User.objects.create_user(phone="0581000001", password="Pass12345!", role_state=UserRole.PHONE_ONLY)


@pytest.fixture
def other_user():
    return User.objects.create_user(phone="0581000002", password="Pass12345!", role_state=UserRole.PHONE_ONLY)


@pytest.fixture
def moderation_operator(moderation_dashboard):
    user = User.objects.create_user(phone="0581000003", password="Pass12345!", role_state=UserRole.STAFF)
    ap = UserAccessProfile.objects.create(user=user, level=AccessLevel.USER)
    ap.allowed_dashboards.add(moderation_dashboard)
    return user


def _ensure_permission(code: str, dashboard_code: str, name_ar: str):
    perm, _ = AccessPermission.objects.get_or_create(
        code=code,
        defaults={"dashboard_code": dashboard_code, "name_ar": name_ar, "sort_order": 10},
    )
    return perm


@override_settings(FEATURE_MODERATION_CENTER=True)
def test_create_report_happy_path(api, reporter_user):
    api.force_authenticate(user=reporter_user)
    response = api.post(
        "/api/moderation/reports/",
        data={
            "source_app": "messaging",
            "source_model": "Thread",
            "source_object_id": "9",
            "source_label": "محادثة",
            "reason": "إساءة لفظية",
            "details": "تفاصيل البلاغ",
            "severity": "normal",
        },
        format="json",
    )

    assert response.status_code == 201
    assert response.data["code"].startswith("MC")
    assert ModerationCase.objects.count() == 1


@override_settings(FEATURE_MODERATION_CENTER=True)
def test_create_report_validation_path(api, reporter_user):
    api.force_authenticate(user=reporter_user)
    response = api.post(
        "/api/moderation/reports/",
        data={"source_app": "messaging", "reason": ""},
        format="json",
    )
    assert response.status_code == 400
    assert "reason" in response.data


def test_feature_flag_hides_endpoints(api, reporter_user):
    api.force_authenticate(user=reporter_user)
    response = api.get("/api/moderation/cases/my/")
    assert response.status_code == 404


@override_settings(FEATURE_MODERATION_CENTER=True)
def test_reporter_can_list_and_view_own_cases(api, reporter_user):
    case = ModerationCase.objects.create(reporter=reporter_user, reason="test", details="x")
    api.force_authenticate(user=reporter_user)

    list_response = api.get("/api/moderation/cases/my/")
    detail_response = api.get(f"/api/moderation/cases/{case.id}/")

    assert list_response.status_code == 200
    assert len(list_response.data) == 1
    assert detail_response.status_code == 200
    assert detail_response.data["id"] == case.id


@override_settings(FEATURE_MODERATION_CENTER=True)
def test_other_user_cannot_view_case_detail(api, reporter_user, other_user):
    case = ModerationCase.objects.create(reporter=reporter_user, reason="test", details="x")
    api.force_authenticate(user=other_user)
    response = api.get(f"/api/moderation/cases/{case.id}/")
    assert response.status_code == 403


@override_settings(FEATURE_MODERATION_CENTER=True, FEATURE_RBAC_ENFORCE=True)
def test_backoffice_assign_forbidden_without_permission(api, moderation_operator):
    case = ModerationCase.objects.create(reporter=moderation_operator, reason="test", details="x")
    api.force_authenticate(user=moderation_operator)
    response = api.patch(
        f"/api/moderation/backoffice/cases/{case.id}/assign/",
        data={"assigned_team_code": "moderation", "assigned_team_name": "الإشراف"},
        format="json",
    )
    assert response.status_code == 403


@override_settings(FEATURE_MODERATION_CENTER=True, FEATURE_RBAC_ENFORCE=True)
def test_backoffice_assign_happy_path_with_permission(api, moderation_operator):
    case = ModerationCase.objects.create(reporter=moderation_operator, reason="test", details="x")
    perm = _ensure_permission(PermissionCode.MODERATION_ASSIGN, "moderation", "إسناد حالات الإشراف")
    moderation_operator.access_profile.granted_permissions.add(perm)
    api.force_authenticate(user=moderation_operator)

    response = api.patch(
        f"/api/moderation/backoffice/cases/{case.id}/assign/",
        data={
            "assigned_team_code": "moderation",
            "assigned_team_name": "الإشراف",
            "assigned_to": moderation_operator.id,
        },
        format="json",
    )

    assert response.status_code == 200
    case.refresh_from_db()
    assert case.assigned_to_id == moderation_operator.id
    assert case.status == "under_review"


@override_settings(FEATURE_MODERATION_CENTER=True, FEATURE_RBAC_ENFORCE=True)
def test_backoffice_status_and_decision_require_resolve_permission(api, moderation_operator):
    case = ModerationCase.objects.create(reporter=moderation_operator, reason="test", details="x")
    resolve_perm = _ensure_permission(PermissionCode.MODERATION_RESOLVE, "moderation", "معالجة حالات الإشراف")
    moderation_operator.access_profile.granted_permissions.add(resolve_perm)
    api.force_authenticate(user=moderation_operator)

    status_response = api.patch(
        f"/api/moderation/backoffice/cases/{case.id}/status/",
        data={"status": "under_review", "note": "بدء المعالجة"},
        format="json",
    )
    decision_response = api.post(
        f"/api/moderation/backoffice/cases/{case.id}/decision/",
        data={"decision_code": "no_action", "note": "لا يوجد إجراء"},
        format="json",
    )

    assert status_response.status_code == 200
    assert decision_response.status_code == 200
    case.refresh_from_db()
    assert case.status == "dismissed"
