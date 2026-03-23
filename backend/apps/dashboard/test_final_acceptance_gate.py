from __future__ import annotations

import pytest
from django.test import Client
from django.urls import reverse

from apps.accounts.models import User
from apps.backoffice.models import AccessLevel, Dashboard, UserAccessProfile
from apps.dashboard.access import can_access_dashboard, can_access_object, has_action_permission
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.support.models import SupportPriority, SupportTicket, SupportTicketStatus, SupportTicketType


def _login_with_dashboard_otp(client: Client, *, user: User, password: str = "Pass12345!") -> None:
    assert client.login(phone=user.phone, password=password)
    session = client.session
    session[SESSION_OTP_VERIFIED_KEY] = True
    session.save()


@pytest.mark.django_db
def test_final_acceptance_role_smoke_matrix_dashboard_action_object():
    support_dashboard, _ = Dashboard.objects.get_or_create(
        code="support",
        defaults={"name_ar": "الدعم والمساعدة", "sort_order": 10},
    )
    Dashboard.objects.get_or_create(
        code="client_extras",
        defaults={"name_ar": "بوابة العميل", "sort_order": 90},
    )

    admin_user = User.objects.create_user(phone="0500091001", password="Pass12345!", is_staff=True)
    power_user = User.objects.create_user(phone="0500091002", password="Pass12345!", is_staff=True)
    user_level = User.objects.create_user(phone="0500091003", password="Pass12345!", is_staff=True)
    qa_user = User.objects.create_user(phone="0500091004", password="Pass12345!", is_staff=True)
    client_user = User.objects.create_user(phone="0500091005", password="Pass12345!")
    assignee_user = User.objects.create_user(phone="0500091006", password="Pass12345!", is_staff=True)
    requester = User.objects.create_user(phone="0500091007", password="Pass12345!")

    UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN)
    UserAccessProfile.objects.create(user=power_user, level=AccessLevel.POWER)
    UserAccessProfile.objects.create(user=client_user, level=AccessLevel.CLIENT)

    user_ap = UserAccessProfile.objects.create(user=user_level, level=AccessLevel.USER)
    user_ap.allowed_dashboards.set([support_dashboard])
    qa_ap = UserAccessProfile.objects.create(user=qa_user, level=AccessLevel.QA)
    qa_ap.allowed_dashboards.set([support_dashboard])
    assignee_ap = UserAccessProfile.objects.create(user=assignee_user, level=AccessLevel.USER)
    assignee_ap.allowed_dashboards.set([support_dashboard])

    foreign_ticket = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.TECH,
        status=SupportTicketStatus.NEW,
        priority=SupportPriority.NORMAL,
        description="foreign object",
        assigned_to=assignee_user,
    )
    own_ticket = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.TECH,
        status=SupportTicketStatus.NEW,
        priority=SupportPriority.NORMAL,
        description="own object",
        assigned_to=user_level,
    )

    role_matrix = {
        "admin": {
            "user": admin_user,
            "support_read": True,
            "support_write": True,
            "action_manage_access": True,
            "foreign_object": True,
        },
        "power": {
            "user": power_user,
            "support_read": True,
            "support_write": True,
            "action_manage_access": True,
            "foreign_object": True,
        },
        "user": {
            "user": user_level,
            "support_read": True,
            "support_write": True,
            "action_manage_access": False,
            "foreign_object": False,
        },
        "qa": {
            "user": qa_user,
            "support_read": True,
            "support_write": False,
            "action_manage_access": False,
            "foreign_object": True,
        },
        "client": {
            "user": client_user,
            "support_read": False,
            "support_write": False,
            "action_manage_access": False,
            "foreign_object": False,
        },
    }

    for expected in role_matrix.values():
        subject = expected["user"]
        assert can_access_dashboard(subject, "support", write=False) is expected["support_read"]
        assert can_access_dashboard(subject, "support", write=True) is expected["support_write"]
        assert has_action_permission(subject, "admin_control.manage_access") is expected["action_manage_access"]
        assert (
            can_access_object(
                subject,
                foreign_ticket,
                assigned_field="assigned_to",
                allow_unassigned_for_user_level=True,
            )
            is expected["foreign_object"]
        )

    assert can_access_object(
        user_level,
        own_ticket,
        assigned_field="assigned_to",
        allow_unassigned_for_user_level=True,
    )
    assert can_access_dashboard(client_user, "client_extras", write=False) is True


@pytest.mark.django_db
def test_final_acceptance_role_smoke_enforced_in_views():
    support_dashboard, _ = Dashboard.objects.get_or_create(
        code="support",
        defaults={"name_ar": "الدعم والمساعدة", "sort_order": 10},
    )
    Dashboard.objects.get_or_create(
        code="client_extras",
        defaults={"name_ar": "بوابة العميل", "sort_order": 90},
    )

    admin_user = User.objects.create_user(phone="0500091011", password="Pass12345!", is_staff=True)
    power_user = User.objects.create_user(phone="0500091012", password="Pass12345!", is_staff=True)
    user_level = User.objects.create_user(phone="0500091013", password="Pass12345!", is_staff=True)
    qa_user = User.objects.create_user(phone="0500091014", password="Pass12345!", is_staff=True)
    client_user = User.objects.create_user(phone="0500091015", password="Pass12345!")
    assignee_user = User.objects.create_user(phone="0500091016", password="Pass12345!", is_staff=True)
    requester = User.objects.create_user(phone="0500091017", password="Pass12345!")

    UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN)
    UserAccessProfile.objects.create(user=power_user, level=AccessLevel.POWER)
    UserAccessProfile.objects.create(user=client_user, level=AccessLevel.CLIENT)

    user_ap = UserAccessProfile.objects.create(user=user_level, level=AccessLevel.USER)
    user_ap.allowed_dashboards.set([support_dashboard])
    qa_ap = UserAccessProfile.objects.create(user=qa_user, level=AccessLevel.QA)
    qa_ap.allowed_dashboards.set([support_dashboard])
    assignee_ap = UserAccessProfile.objects.create(user=assignee_user, level=AccessLevel.USER)
    assignee_ap.allowed_dashboards.set([support_dashboard])

    ticket = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.TECH,
        status=SupportTicketStatus.NEW,
        priority=SupportPriority.NORMAL,
        description="smoke object-level enforcement",
        assigned_to=assignee_user,
    )

    detail_url = reverse("dashboard:support_ticket_detail", args=[ticket.id])
    status_url = reverse("dashboard:support_ticket_status_action", args=[ticket.id])

    admin_client = Client()
    _login_with_dashboard_otp(admin_client, user=admin_user)
    assert admin_client.get(detail_url).status_code == 200
    assert admin_client.post(status_url, data={"status": SupportTicketStatus.IN_PROGRESS, "note": "admin"}).status_code == 302

    ticket.status = SupportTicketStatus.NEW
    ticket.save(update_fields=["status", "updated_at"])

    power_client = Client()
    _login_with_dashboard_otp(power_client, user=power_user)
    assert power_client.get(detail_url).status_code == 200
    assert power_client.post(status_url, data={"status": SupportTicketStatus.IN_PROGRESS, "note": "power"}).status_code == 302

    ticket.status = SupportTicketStatus.NEW
    ticket.save(update_fields=["status", "updated_at"])

    user_client = Client()
    _login_with_dashboard_otp(user_client, user=user_level)
    assert user_client.get(detail_url).status_code == 403
    assert user_client.post(status_url, data={"status": SupportTicketStatus.IN_PROGRESS, "note": "user"}).status_code == 403

    ticket.status = SupportTicketStatus.NEW
    ticket.save(update_fields=["status", "updated_at"])

    qa_client = Client()
    _login_with_dashboard_otp(qa_client, user=qa_user)
    assert qa_client.get(detail_url).status_code == 200
    # QA read-only: write action blocked by dashboard access (redirect).
    assert qa_client.post(status_url, data={"status": SupportTicketStatus.IN_PROGRESS, "note": "qa"}).status_code == 302

    client_portal_client = Client()
    _login_with_dashboard_otp(client_portal_client, user=client_user)
    assert client_portal_client.get(detail_url).status_code in (302, 403)
    assert client_portal_client.post(status_url, data={"status": SupportTicketStatus.IN_PROGRESS, "note": "client"}).status_code in (302, 403)
