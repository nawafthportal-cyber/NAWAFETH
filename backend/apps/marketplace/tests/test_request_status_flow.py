"""
Tests for the unified request status lifecycle.

Covers:
  1. Client cancel (NEW → CANCELLED)  ✓
  2. Client cancel (IN_PROGRESS → rejected)  ✓
  3. Provider cancel (IN_PROGRESS → CANCELLED)  ✓
  4. Provider cancel (NEW → CANCELLED)  ✓
  5. Client reopen (CANCELLED → NEW)  ✓
  6. Provider reopen → rejected  ✓
  7. Client approve provider inputs  ✓
  8. Client reject provider inputs  ✓
"""
import pytest
from django.utils import timezone
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole
from apps.marketplace.models import (
    RequestStatus,
    RequestStatusLog,
    RequestType,
    ServiceRequest,
    ServiceRequestAttachment,
)
from apps.providers.models import Category, ProviderCategory, ProviderProfile, SubCategory


# ── helpers ──────────────────────────────────────
def _make_fixtures(
    client_phone: str,
    provider_phone: str,
    *,
    cat_name: str = "صيانة",
    sub_name: str = "سباكة",
    request_status: str = RequestStatus.NEW,
    request_type: str = RequestType.NORMAL,
    assign_provider: bool = True,
):
    """Create a client user, provider user, provider profile, category chain
    and a ServiceRequest in the desired state."""
    client_user = User.objects.create_user(phone=client_phone, role_state=UserRole.CLIENT)
    provider_user = User.objects.create_user(phone=provider_phone, role_state=UserRole.PROVIDER)
    provider = ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود اختبار",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    cat = Category.objects.create(name=cat_name)
    sub = SubCategory.objects.create(category=cat, name=sub_name)
    ProviderCategory.objects.create(provider=provider, subcategory=sub)

    sr = ServiceRequest.objects.create(
        client=client_user,
        provider=provider if assign_provider else None,
        subcategory=sub,
        title="طلب اختبار",
        description="وصف اختبار",
        request_type=request_type,
        status=request_status,
        city="الرياض",
    )
    return client_user, provider_user, provider, sr


# ── 1. Client cancel NEW → OK ───────────────────
@pytest.mark.django_db
def test_client_cancel_new_request():
    """العميل يلغي طلبًا بحالة NEW → يتحول إلى CANCELLED."""
    client_user, provider_user, provider, sr = _make_fixtures(
        "0510000001", "0510000002",
        request_status=RequestStatus.NEW,
    )

    api = APIClient()
    api.force_authenticate(user=client_user)
    res = api.post(f"/api/marketplace/requests/{sr.id}/cancel/", format="json")

    assert res.status_code == 200, res.data
    sr.refresh_from_db()
    assert sr.status == RequestStatus.CANCELLED


# ── 2. Client cancel IN_PROGRESS → rejected ─────
@pytest.mark.django_db
def test_client_cannot_cancel_in_progress_request():
    """العميل لا يستطيع إلغاء طلب بحالة IN_PROGRESS."""
    client_user, provider_user, provider, sr = _make_fixtures(
        "0510000003", "0510000004",
        request_status=RequestStatus.IN_PROGRESS,
    )

    api = APIClient()
    api.force_authenticate(user=client_user)
    res = api.post(f"/api/marketplace/requests/{sr.id}/cancel/", format="json")

    assert res.status_code == 400
    sr.refresh_from_db()
    assert sr.status == RequestStatus.IN_PROGRESS


# ── 3. Provider cancel IN_PROGRESS → OK ─────────
@pytest.mark.django_db
def test_provider_cancel_in_progress_request():
    """المزود يلغي طلبًا بحالة IN_PROGRESS → يتحول إلى CANCELLED."""
    client_user, provider_user, provider, sr = _make_fixtures(
        "0510000005", "0510000006",
        request_status=RequestStatus.IN_PROGRESS,
    )

    # Test via the service layer (the provider reject API view checks NEW only;
    # for IN_PROGRESS cancellation the service layer is authoritative).
    from apps.marketplace.services.actions import execute_action
    result = execute_action(
        user=provider_user,
        request_id=sr.id,
        action="cancel",
    )
    assert result.ok is True
    sr.refresh_from_db()
    assert sr.status == RequestStatus.CANCELLED


# ── 4. Provider cancel NEW → OK ─────────────────
@pytest.mark.django_db
def test_provider_cancel_new_request():
    """المزود يلغي طلبًا بحالة NEW → يتحول إلى CANCELLED."""
    client_user, provider_user, provider, sr = _make_fixtures(
        "0510000007", "0510000008",
        request_status=RequestStatus.NEW,
    )

    api = APIClient()
    api.force_authenticate(user=provider_user)
    res = api.post(
        f"/api/marketplace/provider/requests/{sr.id}/reject/",
        {
            "canceled_at": "2026-03-01T10:00:00Z",
            "cancel_reason": "لا أستطيع التنفيذ",
        },
        format="json",
    )

    assert res.status_code == 200, res.data
    sr.refresh_from_db()
    assert sr.status == RequestStatus.CANCELLED


# ── 5. Client reopen CANCELLED → NEW ────────────
@pytest.mark.django_db
def test_client_reopen_cancelled_request():
    """العميل يعيد فتح طلب ملغي → يتحول إلى NEW."""
    client_user, provider_user, provider, sr = _make_fixtures(
        "0510000009", "0510000010",
        request_status=RequestStatus.CANCELLED,
    )

    api = APIClient()
    api.force_authenticate(user=client_user)
    res = api.post(f"/api/marketplace/requests/{sr.id}/reopen/", format="json")

    assert res.status_code == 200, res.data
    sr.refresh_from_db()
    assert sr.status == RequestStatus.NEW
    assert sr.provider is None  # provider cleared on reopen

    # Verify a status log was created
    log = RequestStatusLog.objects.filter(
        request=sr,
        from_status=RequestStatus.CANCELLED,
        to_status=RequestStatus.NEW,
    ).first()
    assert log is not None
    assert log.actor_id == client_user.id


# ── 6. Provider reopen → rejected ───────────────
@pytest.mark.django_db
def test_provider_cannot_reopen_cancelled_request():
    """المزود لا يستطيع إعادة فتح طلب ملغي."""
    client_user, provider_user, provider, sr = _make_fixtures(
        "0510000011", "0510000012",
        request_status=RequestStatus.CANCELLED,
    )

    api = APIClient()
    api.force_authenticate(user=provider_user)
    res = api.post(f"/api/marketplace/requests/{sr.id}/reopen/", format="json")

    assert res.status_code == 403
    sr.refresh_from_db()
    assert sr.status == RequestStatus.CANCELLED


# ── 7. Client approve provider inputs ────────────
@pytest.mark.django_db
def test_client_approve_provider_inputs():
    """العميل يوافق على مدخلات المزود أثناء NEW فيتحول الطلب إلى IN_PROGRESS."""
    client_user, provider_user, provider, sr = _make_fixtures(
        "0510000013", "0510000014",
        request_status=RequestStatus.NEW,
    )
    # Simulate provider submitted inputs (start flow)
    sr.expected_delivery_at = timezone.now()
    sr.estimated_service_amount = 1000
    sr.received_amount = 300
    sr.remaining_amount = 700
    sr.save()

    api = APIClient()
    api.force_authenticate(user=client_user)
    res = api.post(
        f"/api/marketplace/requests/{sr.id}/provider-inputs/decision/",
        {"approved": True, "note": "أوافق على المدخلات"},
        format="json",
    )

    assert res.status_code == 200, res.data
    sr.refresh_from_db()
    assert sr.provider_inputs_approved is True
    assert sr.provider_inputs_decided_at is not None
    assert sr.provider_inputs_decision_note == "أوافق على المدخلات"
    assert sr.status == RequestStatus.IN_PROGRESS


# ── 8. Client reject provider inputs ─────────────
@pytest.mark.django_db
def test_client_reject_provider_inputs():
    """العميل يرفض مدخلات المزود أثناء NEW ويبقى الطلب NEW."""
    client_user, provider_user, provider, sr = _make_fixtures(
        "0510000015", "0510000016",
        request_status=RequestStatus.NEW,
    )
    sr.expected_delivery_at = timezone.now()
    sr.estimated_service_amount = 2000
    sr.received_amount = 500
    sr.remaining_amount = 1500
    sr.save()

    api = APIClient()
    api.force_authenticate(user=client_user)
    res = api.post(
        f"/api/marketplace/requests/{sr.id}/provider-inputs/decision/",
        {"approved": False, "note": "المبلغ مبالغ فيه"},
        format="json",
    )

    assert res.status_code == 200, res.data
    sr.refresh_from_db()
    assert sr.provider_inputs_approved is False
    assert sr.provider_inputs_decided_at is not None
    assert sr.provider_inputs_decision_note == "المبلغ مبالغ فيه"
    assert sr.status == RequestStatus.NEW


# ── Extra: Double decision is rejected ────────────
@pytest.mark.django_db
def test_client_cannot_decide_inputs_twice():
    """العميل لا يستطيع اتخاذ قرار ثانٍ بشأن المدخلات."""
    client_user, provider_user, provider, sr = _make_fixtures(
        "0510000017", "0510000018",
        request_status=RequestStatus.NEW,
    )
    sr.provider_inputs_approved = True
    sr.provider_inputs_decided_at = timezone.now()
    sr.save()

    api = APIClient()
    api.force_authenticate(user=client_user)
    res = api.post(
        f"/api/marketplace/requests/{sr.id}/provider-inputs/decision/",
        {"approved": False},
        format="json",
    )

    assert res.status_code == 400  # already decided


# ── Extra: Reopen non-cancelled request → rejected ─
@pytest.mark.django_db
def test_reopen_new_request_rejected():
    """لا يمكن إعادة فتح طلب ليس بحالة CANCELLED."""
    client_user, provider_user, provider, sr = _make_fixtures(
        "0510000019", "0510000020",
        request_status=RequestStatus.NEW,
    )

    api = APIClient()
    api.force_authenticate(user=client_user)
    res = api.post(f"/api/marketplace/requests/{sr.id}/reopen/", format="json")

    assert res.status_code == 400
    sr.refresh_from_db()
    assert sr.status == RequestStatus.NEW


# ── Extra: Staff can reopen ──────────────────────
@pytest.mark.django_db
def test_staff_can_reopen_cancelled_request():
    """الموظف يستطيع إعادة فتح طلب ملغي."""
    client_user, provider_user, provider, sr = _make_fixtures(
        "0510000021", "0510000022",
        request_status=RequestStatus.CANCELLED,
    )
    staff_user = User.objects.create_user(phone="0510000023")
    staff_user.is_staff = True
    staff_user.save()

    api = APIClient()
    api.force_authenticate(user=staff_user)
    res = api.post(f"/api/marketplace/requests/{sr.id}/reopen/", format="json")

    assert res.status_code == 200, res.data
    sr.refresh_from_db()
    assert sr.status == RequestStatus.NEW


# ── Extra: Full start → inputs → complete flow ───
@pytest.mark.django_db
def test_full_start_approve_complete_flow():
    """دورة كاملة: إرسال مدخلات ← اعتماد مدخلات ← إكمال."""
    client_user, provider_user, provider, sr = _make_fixtures(
        "0510000025", "0510000026",
        request_status=RequestStatus.NEW,
    )

    api = APIClient()

    # Provider starts
    api.force_authenticate(user=provider_user)
    r = api.post(
        f"/api/marketplace/requests/{sr.id}/start/",
        {
            "expected_delivery_at": "2026-06-01T10:00:00Z",
            "estimated_service_amount": "500.00",
            "received_amount": "100.00",
        },
        format="json",
    )
    assert r.status_code == 200
    sr.refresh_from_db()
    assert sr.status == RequestStatus.NEW

    # Client approves inputs
    api.force_authenticate(user=client_user)
    r = api.post(
        f"/api/marketplace/requests/{sr.id}/provider-inputs/decision/",
        {"approved": True, "note": "موافق"},
        format="json",
    )
    assert r.status_code == 200
    sr.refresh_from_db()
    assert sr.status == RequestStatus.IN_PROGRESS

    # Provider completes
    api.force_authenticate(user=provider_user)
    invoice = SimpleUploadedFile(
        "invoice.pdf",
        b"%PDF-1.4 fake invoice content",
        content_type="application/pdf",
    )
    r = api.post(
        f"/api/marketplace/requests/{sr.id}/complete/",
        {
            "delivered_at": "2026-06-02T12:00:00Z",
            "actual_service_amount": "480.00",
            "attachments": [invoice],
        },
        format="multipart",
    )
    assert r.status_code == 200
    sr.refresh_from_db()
    assert sr.status == RequestStatus.COMPLETED
    assert ServiceRequestAttachment.objects.filter(request=sr).count() == 1



