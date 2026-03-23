import pytest

from apps.accounts.models import User
from apps.support.models import SupportPriority, SupportTicket, SupportTicketStatus, SupportTicketType
from apps.support.services import _sync_ticket_to_unified, change_ticket_status
from apps.unified_requests.models import UnifiedRequestStatus, UnifiedRequestType
from apps.unified_requests.services import upsert_unified_request
from apps.unified_requests.workflows import canonical_status_for_workflow, is_valid_transition


pytestmark = pytest.mark.django_db


def test_subscription_operational_status_is_canonicalized():
    assert (
        canonical_status_for_workflow(
            request_type=UnifiedRequestType.SUBSCRIPTION,
            status=UnifiedRequestStatus.PENDING_PAYMENT,
        )
        == UnifiedRequestStatus.NEW
    )
    assert (
        canonical_status_for_workflow(
            request_type=UnifiedRequestType.SUBSCRIPTION,
            status=UnifiedRequestStatus.ACTIVE,
        )
        == UnifiedRequestStatus.IN_PROGRESS
    )
    assert (
        canonical_status_for_workflow(
            request_type=UnifiedRequestType.SUBSCRIPTION,
            status=UnifiedRequestStatus.COMPLETED,
        )
        == UnifiedRequestStatus.CLOSED
    )


def test_subscription_transition_accepts_legacy_state_aliases():
    assert is_valid_transition(
        request_type=UnifiedRequestType.SUBSCRIPTION,
        from_status=UnifiedRequestStatus.PENDING_PAYMENT,
        to_status=UnifiedRequestStatus.IN_PROGRESS,
    )
    assert not is_valid_transition(
        request_type=UnifiedRequestType.SUBSCRIPTION,
        from_status=UnifiedRequestStatus.PENDING_PAYMENT,
        to_status=UnifiedRequestStatus.CLOSED,
    )


def test_upsert_normalizes_subscription_status_and_sets_closed_at():
    requester = User.objects.create_user(phone="0540000001", password="Pass12345!")

    ur = upsert_unified_request(
        request_type=UnifiedRequestType.SUBSCRIPTION,
        requester=requester,
        source_app="subscriptions",
        source_model="Subscription",
        source_object_id=9001,
        status=UnifiedRequestStatus.PENDING_PAYMENT,
        summary="pending subscription",
    )
    assert ur.status == UnifiedRequestStatus.NEW
    assert ur.closed_at is None

    ur = upsert_unified_request(
        request_type=UnifiedRequestType.SUBSCRIPTION,
        requester=requester,
        source_app="subscriptions",
        source_model="Subscription",
        source_object_id=9001,
        status=UnifiedRequestStatus.COMPLETED,
        summary="finished subscription",
    )
    assert ur.status == UnifiedRequestStatus.CLOSED
    assert ur.closed_at is not None


def test_unified_request_remains_aggregation_layer_not_business_source():
    requester = User.objects.create_user(phone="0540000011", password="Pass12345!")
    operator = User.objects.create_user(phone="0540000012", password="Pass12345!", is_staff=True)

    ticket = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.TECH,
        status=SupportTicketStatus.NEW,
        priority=SupportPriority.NORMAL,
        description="aggregation boundary check",
        assigned_to=operator,
    )
    _sync_ticket_to_unified(ticket=ticket, changed_by=operator)
    ur = upsert_unified_request(
        request_type=UnifiedRequestType.HELPDESK,
        requester=requester,
        source_app="support",
        source_model="SupportTicket",
        source_object_id=ticket.id,
        status=SupportTicketStatus.NEW,
        summary="support sync",
        changed_by=operator,
    )
    assert ur.status == UnifiedRequestStatus.NEW

    change_ticket_status(ticket=ticket, new_status=SupportTicketStatus.IN_PROGRESS, by_user=operator, note="progress")
    change_ticket_status(ticket=ticket, new_status=SupportTicketStatus.CLOSED, by_user=operator, note="close")
    ur.refresh_from_db()
    assert ur.status == UnifiedRequestStatus.CLOSED

    # Updating aggregation status directly must not rewrite business status.
    ur.status = UnifiedRequestStatus.IN_PROGRESS
    ur.save(update_fields=["status", "updated_at"])
    ticket.refresh_from_db()
    assert ticket.status == SupportTicketStatus.CLOSED
