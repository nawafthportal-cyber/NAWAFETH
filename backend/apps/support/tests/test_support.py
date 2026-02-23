import pytest
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.backoffice.models import UserAccessProfile
from apps.backoffice.models import Dashboard
from apps.support.models import SupportTeam, SupportTicket
from apps.unified_requests.models import UnifiedRequest


pytestmark = pytest.mark.django_db


@pytest.fixture
def api():
    return APIClient()


@pytest.fixture
def client_user():
    return User.objects.create_user(phone="0511111111", password="Pass12345!")


@pytest.fixture
def staff_user():
    u = User.objects.create_user(phone="0522222222", password="Pass12345!")
    UserAccessProfile.objects.create(user=u, level="admin")
    return u


@pytest.fixture
def support_dashboard():
    Dashboard.objects.get_or_create(code="support", defaults={"name_ar": "الدعم", "sort_order": 10})
    return Dashboard.objects.get(code="support")


@pytest.fixture
def support_operator_user(support_dashboard):
    u = User.objects.create_user(phone="0533333333", password="Pass12345!")
    u.is_staff = True
    u.save(update_fields=["is_staff"])
    ap = UserAccessProfile.objects.create(user=u, level="user")
    ap.allowed_dashboards.add(support_dashboard)
    return u


@pytest.fixture
def other_staff_user():
    u = User.objects.create_user(phone="0533333334", password="Pass12345!")
    u.is_staff = True
    u.save(update_fields=["is_staff"])
    return u


@pytest.fixture
def teams():
    SupportTeam.objects.get_or_create(code="tech", defaults={"name_ar": "الدعم الفني", "sort_order": 10})
    return SupportTeam.objects.all()


def test_create_ticket(api, client_user):
    api.force_authenticate(user=client_user)
    r = api.post("/api/support/tickets/create/", data={
        "ticket_type": "tech",
        "description": "مشكلة في الدخول",
        "priority": "normal",
    }, format="json")
    assert r.status_code == 201
    assert r.data["code"].startswith("HD")
    t = SupportTicket.objects.get(pk=r.data["id"])
    ur = UnifiedRequest.objects.get(source_app="support", source_model="SupportTicket", source_object_id=str(t.id))
    assert ur.code.startswith("HD")
    assert ur.status == t.status
    assert ur.request_type == "helpdesk"


def test_create_complaint_ticket_accepts_reported_target(api, client_user):
    reported_user = User.objects.create_user(phone="0599999999", password="Pass12345!")

    api.force_authenticate(user=client_user)
    r = api.post(
        "/api/support/tickets/create/",
        data={
            "ticket_type": "complaint",
            "description": "بلاغ اختبار",
            "reported_kind": "review",
            "reported_object_id": "123",
            "reported_user": reported_user.id,
        },
        format="json",
    )
    assert r.status_code == 201
    t = SupportTicket.objects.get(pk=r.data["id"])
    assert t.ticket_type == "complaint"
    assert (t.reported_kind or "").strip() == "review"
    assert (t.reported_object_id or "").strip() == "123"
    assert t.reported_user_id == reported_user.id


def test_backoffice_list(api, staff_user, client_user):
    SupportTicket.objects.create(requester=client_user, ticket_type="tech", description="test")
    api.force_authenticate(user=staff_user)
    r = api.get("/api/support/backoffice/tickets/")
    assert r.status_code == 200
    assert len(r.data) >= 1


def test_backoffice_list_forbidden_without_access_profile(api, client_user):
    SupportTicket.objects.create(requester=client_user, ticket_type="tech", description="test")
    api.force_authenticate(user=client_user)
    r = api.get("/api/support/backoffice/tickets/")
    assert r.status_code == 403


def test_user_operator_cannot_assign_to_other(api, support_operator_user, other_staff_user, client_user):
    t = SupportTicket.objects.create(requester=client_user, ticket_type="tech", description="test")
    api.force_authenticate(user=support_operator_user)
    r = api.patch(f"/api/support/backoffice/tickets/{t.id}/assign/", data={"assigned_to": other_staff_user.id}, format="json")
    assert r.status_code == 403

    r2 = api.patch(f"/api/support/backoffice/tickets/{t.id}/assign/", data={"assigned_to": support_operator_user.id}, format="json")
    assert r2.status_code == 200


def test_support_ticket_syncs_to_unified_on_assign_and_status(api, support_operator_user, client_user, teams):
    t = SupportTicket.objects.create(requester=client_user, ticket_type="tech", description="test sync")
    api.force_authenticate(user=support_operator_user)

    team = SupportTeam.objects.get(code="tech")
    r_assign = api.patch(
        f"/api/support/backoffice/tickets/{t.id}/assign/",
        data={"assigned_team": team.id, "assigned_to": support_operator_user.id, "note": "claim"},
        format="json",
    )
    assert r_assign.status_code == 200

    ur = UnifiedRequest.objects.get(source_app="support", source_model="SupportTicket", source_object_id=str(t.id))
    assert ur.assigned_user_id == support_operator_user.id
    assert ur.assigned_team_code == "tech"
    # assign on NEW auto-transitions to in_progress
    assert ur.status == "in_progress"

    r_status = api.patch(
        f"/api/support/backoffice/tickets/{t.id}/status/",
        data={"status": "closed", "note": "done"},
        format="json",
    )
    assert r_status.status_code == 200

    ur.refresh_from_db()
    assert ur.status == "closed"
    assert ur.status_logs.count() >= 2
    assert ur.assignment_logs.count() >= 1
