from __future__ import annotations

import pytest
from django.test import Client
from django.urls import reverse

from apps.accounts.models import User
from apps.backoffice.models import AccessLevel, Dashboard, UserAccessProfile
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.support.models import SupportPriority, SupportTicket, SupportTicketStatus, SupportTicketType
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
def test_dashboard_v2_access_basics():
    support_dashboard = _dashboard("support", "الدعم")
    _dashboard("analytics", "التحليلات")
    _dashboard("admin_control", "الإدارة")

    support_user = User.objects.create_user(phone="0500100001", password="Pass12345!", is_staff=True)
    _access_profile(support_user, level=AccessLevel.USER, dashboards=[support_dashboard])

    no_access_user = User.objects.create_user(phone="0500100002", password="Pass12345!", is_staff=True)
    UserAccessProfile.objects.create(user=no_access_user, level=AccessLevel.USER)

    support_client = Client()
    _login_dashboard_v2(support_client, user=support_user)
    assert support_client.get(reverse("dashboard_v2:support_list")).status_code == 200
    # requests list allowed for support dashboard scope in V2.
    assert support_client.get(reverse("dashboard_v2:requests_list")).status_code == 200
    # admin panel should be denied for non-admin scope.
    assert support_client.get(reverse("dashboard_v2:users_list")).status_code in (302, 403)

    no_access_client = Client()
    _login_dashboard_v2(no_access_client, user=no_access_user)
    assert no_access_client.get(reverse("dashboard_v2:support_list")).status_code == 403


@pytest.mark.django_db
def test_dashboard_v2_requests_visibility_scoped_for_user_level():
    analytics_dashboard = _dashboard("analytics", "التحليلات")
    support_dashboard = _dashboard("support", "الدعم")

    operator = User.objects.create_user(phone="0500100011", password="Pass12345!", is_staff=True)
    other_staff = User.objects.create_user(phone="0500100012", password="Pass12345!", is_staff=True)
    owner_user = User.objects.create_user(phone="0500100013", password="Pass12345!")
    foreign_requester = User.objects.create_user(phone="0500100014", password="Pass12345!")

    _access_profile(operator, level=AccessLevel.USER, dashboards=[analytics_dashboard, support_dashboard])
    _access_profile(other_staff, level=AccessLevel.USER, dashboards=[support_dashboard])

    assigned_visible = UnifiedRequest.objects.create(
        request_type=UnifiedRequestType.HELPDESK,
        requester=owner_user,
        status=UnifiedRequestStatus.NEW,
        summary="assigned-visible",
        assigned_user=operator,
        assigned_team_code="support",
        assigned_team_name="الدعم",
    )
    owned_visible = UnifiedRequest.objects.create(
        request_type=UnifiedRequestType.HELPDESK,
        requester=operator,
        status=UnifiedRequestStatus.IN_PROGRESS,
        summary="owned-visible",
        assigned_user=other_staff,
        assigned_team_code="support",
        assigned_team_name="الدعم",
    )
    hidden_foreign = UnifiedRequest.objects.create(
        request_type=UnifiedRequestType.HELPDESK,
        requester=foreign_requester,
        status=UnifiedRequestStatus.NEW,
        summary="hidden-foreign",
        assigned_user=other_staff,
        assigned_team_code="support",
        assigned_team_name="الدعم",
    )

    client = Client()
    _login_dashboard_v2(client, user=operator)

    list_response = client.get(reverse("dashboard_v2:requests_list"))
    assert list_response.status_code == 200
    html = list_response.content.decode("utf-8")
    assert "assigned-visible" in html
    assert "owned-visible" in html
    assert "hidden-foreign" not in html

    assert client.get(reverse("dashboard_v2:request_detail", args=[assigned_visible.id])).status_code == 200
    assert client.get(reverse("dashboard_v2:request_detail", args=[owned_visible.id])).status_code == 200
    assert client.get(reverse("dashboard_v2:request_detail", args=[hidden_foreign.id])).status_code == 403


@pytest.mark.django_db
def test_dashboard_v2_role_based_rendering_support_detail():
    support_dashboard = _dashboard("support", "الدعم")

    qa_user = User.objects.create_user(phone="0500100021", password="Pass12345!", is_staff=True)
    admin_user = User.objects.create_user(phone="0500100022", password="Pass12345!", is_staff=True)
    requester = User.objects.create_user(phone="0500100023", password="Pass12345!")

    _access_profile(qa_user, level=AccessLevel.QA, dashboards=[support_dashboard])
    UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN)

    ticket = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.TECH,
        status=SupportTicketStatus.NEW,
        priority=SupportPriority.NORMAL,
        description="qa-render-check",
    )

    status_action_url = reverse("dashboard_v2:support_status_action", args=[ticket.id])
    assign_action_url = reverse("dashboard_v2:support_assign_action", args=[ticket.id])

    qa_client = Client()
    _login_dashboard_v2(qa_client, user=qa_user)
    qa_response = qa_client.get(reverse("dashboard_v2:support_detail", args=[ticket.id]))
    assert qa_response.status_code == 200
    qa_html = qa_response.content.decode("utf-8")
    assert status_action_url not in qa_html
    assert assign_action_url not in qa_html

    admin_client = Client()
    _login_dashboard_v2(admin_client, user=admin_user)
    admin_response = admin_client.get(reverse("dashboard_v2:support_detail", args=[ticket.id]))
    assert admin_response.status_code == 200
    admin_html = admin_response.content.decode("utf-8")
    assert status_action_url in admin_html
    assert assign_action_url in admin_html

