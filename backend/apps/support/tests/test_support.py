import pytest
from decimal import Decimal
from django.test import override_settings
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.audit.models import AuditAction, AuditLog
from apps.backoffice.models import UserAccessProfile
from apps.backoffice.models import Dashboard
from apps.moderation.models import ModerationCase
from apps.providers.models import ProviderProfile
from apps.subscriptions.models import PlanPeriod, Subscription, SubscriptionPlan, SubscriptionStatus
from apps.support.models import SupportTeam, SupportTicket, SupportTicketStatus
from apps.support.services import change_ticket_status
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


@override_settings(FEATURE_MODERATION_DUAL_WRITE=True)
def test_complaint_ticket_dual_writes_to_moderation_case(api, client_user):
    reported_user = User.objects.create_user(phone="0598888888", password="Pass12345!")

    api.force_authenticate(user=client_user)
    response = api.post(
        "/api/support/tickets/create/",
        data={
            "ticket_type": "complaint",
            "description": "بلاغ يحتاج إشرافًا",
            "reported_kind": "review",
            "reported_object_id": "321",
            "reported_user": reported_user.id,
        },
        format="json",
    )

    assert response.status_code == 201
    ticket = SupportTicket.objects.get(pk=response.data["id"])
    case = ModerationCase.objects.get(linked_support_ticket_id=str(ticket.id))
    assert case.reporter_id == client_user.id
    assert case.reported_user_id == reported_user.id
    assert case.source_app == "reviews"
    assert case.source_model == "Review"
    assert case.source_object_id == "321"
    assert case.status == "new"


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


@override_settings(FEATURE_RBAC_ENFORCE=False, RBAC_AUDIT_ONLY=True)
def test_support_assign_audit_only_mode_allows_fallback_and_logs(api, support_operator_user, client_user, teams):
    ticket = SupportTicket.objects.create(requester=client_user, ticket_type="tech", description="audit only assign")
    api.force_authenticate(user=support_operator_user)

    team = SupportTeam.objects.get(code="tech")
    response = api.patch(
        f"/api/support/backoffice/tickets/{ticket.id}/assign/",
        data={"assigned_team": team.id, "assigned_to": support_operator_user.id, "note": "audit_only"},
        format="json",
    )

    assert response.status_code == 200
    assert AuditLog.objects.filter(
        action=AuditAction.RBAC_POLICY_AUDIT_ONLY,
        reference_type="support.ticket",
        reference_id=str(ticket.id),
    ).exists()


@override_settings(FEATURE_RBAC_ENFORCE=True, RBAC_AUDIT_ONLY=False)
def test_support_assign_enforced_mode_denies_without_permission_and_logs(api, support_operator_user, client_user):
    ticket = SupportTicket.objects.create(requester=client_user, ticket_type="tech", description="enforced assign")
    api.force_authenticate(user=support_operator_user)

    response = api.patch(
        f"/api/support/backoffice/tickets/{ticket.id}/assign/",
        data={"assigned_to": support_operator_user.id, "note": "should_fail"},
        format="json",
    )

    assert response.status_code == 403
    assert AuditLog.objects.filter(
        action=AuditAction.RBAC_POLICY_DENIED,
        reference_type="support.ticket",
        reference_id=str(ticket.id),
    ).exists()


def test_provider_pioneer_ticket_gets_normal_priority(api):
    provider_user = User.objects.create_user(phone="0511111122", password="Pass12345!")
    ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود ريادي",
        bio="bio",
    )
    plan = SubscriptionPlan.objects.create(
        code="riyadi_support",
        title="الريادية",
        tier="riyadi",
        period=PlanPeriod.YEAR,
        price=Decimal("199.00"),
        is_active=True,
    )
    Subscription.objects.create(
        user=provider_user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
    )

    api.force_authenticate(user=provider_user)
    response = api.post(
        "/api/support/tickets/create/",
        data={
            "ticket_type": "tech",
            "description": "أولوية الدعم",
        },
        format="json",
    )

    assert response.status_code == 201
    ticket = SupportTicket.objects.get(pk=response.data["id"])
    assert ticket.priority == "normal"


def test_support_status_transition_blocks_reopen_after_closed(client_user, support_operator_user):
    ticket = SupportTicket.objects.create(
        requester=client_user,
        ticket_type="tech",
        description="closed ticket",
        status=SupportTicketStatus.CLOSED,
    )
    with pytest.raises(ValueError):
        change_ticket_status(
            ticket=ticket,
            new_status=SupportTicketStatus.IN_PROGRESS,
            by_user=support_operator_user,
            note="invalid reopen",
        )
