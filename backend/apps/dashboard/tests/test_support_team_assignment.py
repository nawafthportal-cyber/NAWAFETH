import pytest
from django.test import Client
from django.urls import reverse

from apps.accounts.models import User, UserRole
from apps.backoffice.models import AccessLevel, Dashboard, UserAccessProfile
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.support.models import SupportPriority, SupportTeam, SupportTicket, SupportTicketEntrypoint, SupportTicketStatus, SupportTicketType


pytestmark = pytest.mark.django_db


def _dashboard_client() -> Client:
    user = User.objects.create_user(
        phone="0554100001",
        password="Pass12345!",
        is_staff=True,
        is_superuser=True,
        role_state=UserRole.STAFF,
    )
    client = Client()
    assert client.login(phone=user.phone, password="Pass12345!")
    session = client.session
    session[SESSION_OTP_VERIFIED_KEY] = True
    session.save()
    return client


def _create_dashboard_operator(*, phone: str, dashboard_code: str, dashboard_name: str) -> User:
    dashboard, _ = Dashboard.objects.get_or_create(
        code=dashboard_code,
        defaults={"name_ar": dashboard_name, "is_active": True, "sort_order": 50},
    )
    user = User.objects.create_user(
        phone=phone,
        password="Pass12345!",
        is_staff=True,
        role_state=UserRole.STAFF,
    )
    profile = UserAccessProfile.objects.create(user=user, level=AccessLevel.USER)
    profile.allowed_dashboards.add(dashboard)
    return user


def _create_support_team(*, code: str, name_ar: str, sort_order: int) -> SupportTeam:
    team, _ = SupportTeam.objects.get_or_create(
        code=code,
        defaults={"name_ar": name_ar, "is_active": True, "sort_order": sort_order},
    )
    return team


def _create_ticket(*, ticket_type: str = SupportTicketType.ADS, description: str = "طلب محول") -> SupportTicket:
    requester = User.objects.create_user(
        phone="0554100099",
        password="Pass12345!",
        role_state=UserRole.PROVIDER,
    )
    return SupportTicket.objects.create(
        requester=requester,
        ticket_type=ticket_type,
        status=SupportTicketStatus.NEW,
        priority=SupportPriority.NORMAL,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        description=description,
    )


@pytest.mark.parametrize(
    ("team_code", "team_name", "dashboard_code", "dashboard_name", "phone"),
    [
        ("promo", "فريق إدارة الإعلانات والترويج", "promo", "لوحة الترويج", "0554100002"),
        ("content", "فريق إدارة المحتوى", "content", "لوحة المحتوى", "0554100003"),
    ],
)
def test_support_assignment_accepts_operator_from_selected_team_dashboard(
    team_code,
    team_name,
    dashboard_code,
    dashboard_name,
    phone,
):
    client = _dashboard_client()
    operator = _create_dashboard_operator(phone=phone, dashboard_code=dashboard_code, dashboard_name=dashboard_name)
    team = _create_support_team(code=team_code, name_ar=team_name, sort_order=20)
    ticket = _create_ticket(description=f"تحويل إلى {team_name}")

    response = client.post(
        reverse("dashboard:support_ticket_detail", kwargs={"ticket_id": ticket.id}),
        {
            "ticket_id": str(ticket.id),
            "status": SupportTicketStatus.IN_PROGRESS,
            "assigned_team": str(team.id),
            "assigned_to": str(operator.id),
            "description": ticket.description,
            "assignee_comment": f"تحويل إلى {team_name}",
            "action": "save_ticket",
        },
    )

    assert response.status_code == 302
    ticket.refresh_from_db()
    assert ticket.assigned_team_id == team.id
    assert ticket.assigned_to_id == operator.id


def test_support_assignment_rejects_operator_without_selected_team_dashboard_access():
    client = _dashboard_client()
    promo_team = _create_support_team(code="promo", name_ar="فريق إدارة الإعلانات والترويج", sort_order=20)
    wrong_operator = _create_dashboard_operator(
        phone="0554100004",
        dashboard_code="content",
        dashboard_name="لوحة المحتوى",
    )
    ticket = _create_ticket(description="تحويل إلى فريق الترويج")

    response = client.post(
        reverse("dashboard:support_ticket_detail", kwargs={"ticket_id": ticket.id}),
        {
            "ticket_id": str(ticket.id),
            "status": SupportTicketStatus.IN_PROGRESS,
            "assigned_team": str(promo_team.id),
            "assigned_to": str(wrong_operator.id),
            "description": ticket.description,
            "assignee_comment": "محاولة إسناد غير صحيحة",
            "action": "save_ticket",
        },
        follow=True,
    )

    assert response.status_code == 200
    ticket.refresh_from_db()
    assert ticket.assigned_team_id is None
    assert ticket.assigned_to_id is None
    messages = list(response.context["messages"])
    assert any("غير مرتبط بفريق الدعم المحدد" in str(message) for message in messages)