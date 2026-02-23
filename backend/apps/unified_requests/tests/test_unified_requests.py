import pytest

from apps.accounts.models import User
from apps.unified_requests.models import (
    UnifiedRequest,
    UnifiedRequestStatus,
    UnifiedRequestType,
)
from apps.unified_requests.services import upsert_unified_request


pytestmark = pytest.mark.django_db


def test_unified_request_code_prefix_generation():
    user = User.objects.create_user(phone="0531111111", password="Pass12345!")

    ur_helpdesk = UnifiedRequest.objects.create(
        request_type=UnifiedRequestType.HELPDESK,
        requester=user,
        status=UnifiedRequestStatus.NEW,
    )
    ur_subs = UnifiedRequest.objects.create(
        request_type=UnifiedRequestType.SUBSCRIPTION,
        requester=user,
        status=UnifiedRequestStatus.PENDING_PAYMENT,
    )
    ur_extras = UnifiedRequest.objects.create(
        request_type=UnifiedRequestType.EXTRAS,
        requester=user,
        status=UnifiedRequestStatus.ACTIVE,
    )

    assert ur_helpdesk.code.startswith("HD")
    assert ur_subs.code.startswith("SD")
    assert ur_extras.code.startswith("P")


def test_upsert_unified_request_creates_logs_and_metadata_then_updates():
    requester = User.objects.create_user(phone="0532222222", password="Pass12345!")
    operator = User.objects.create_user(phone="0532222223", password="Pass12345!")

    ur = upsert_unified_request(
        request_type=UnifiedRequestType.PROMO,
        requester=requester,
        source_app="promo",
        source_model="PromoRequest",
        source_object_id=15,
        status=UnifiedRequestStatus.NEW,
        priority="professional",
        summary="طلب ترويج",
        metadata={"ad_type": "banner_home"},
        assigned_team_code="promo",
        assigned_team_name="الترويج",
        assigned_user=operator,
        changed_by=operator,
    )

    assert ur.code.startswith("MD")
    assert ur.status_logs.count() == 1
    assert ur.assignment_logs.count() == 1
    assert ur.metadata_record.payload["ad_type"] == "banner_home"

    ur2 = upsert_unified_request(
        request_type=UnifiedRequestType.PROMO,
        requester=requester,
        source_app="promo",
        source_model="PromoRequest",
        source_object_id=15,
        status=UnifiedRequestStatus.PENDING_PAYMENT,
        priority="professional",
        summary="تم التسعير",
        metadata={"ad_type": "banner_home", "quoted": True},
        assigned_team_code="promo",
        assigned_team_name="الترويج",
        assigned_user=operator,
        changed_by=operator,
    )

    assert ur2.id == ur.id
    assert ur2.status == UnifiedRequestStatus.PENDING_PAYMENT
    assert ur2.status_logs.count() == 2
    assert ur2.assignment_logs.count() == 1  # no assignment change
    assert ur2.metadata_record.payload["quoted"] is True
