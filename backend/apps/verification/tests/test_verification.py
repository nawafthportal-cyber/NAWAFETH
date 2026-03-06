import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient

from django.utils import timezone

from apps.accounts.models import User
from apps.backoffice.models import UserAccessProfile
from apps.backoffice.models import Dashboard
from apps.verification.models import VerificationRequest
from apps.verification.models import VerificationDocument
from apps.verification.models import VerificationStatus
from apps.unified_requests.models import UnifiedRequest
from apps.subscriptions.models import SubscriptionPlan, Subscription, SubscriptionStatus
from apps.verification.services import decide_document, finalize_request_and_create_invoice


pytestmark = pytest.mark.django_db


@pytest.fixture
def api():
    return APIClient()


@pytest.fixture
def user():
    return User.objects.create_user(phone="0544444444", password="Pass12345!")


@pytest.fixture
def admin_user():
    u = User.objects.create_user(phone="0555555555", password="Pass12345!")
    UserAccessProfile.objects.create(user=u, level="admin")
    return u


@pytest.fixture
def verify_dashboard():
    Dashboard.objects.get_or_create(code="verify", defaults={"name_ar": "التوثيق", "sort_order": 50})
    return Dashboard.objects.get(code="verify")


@pytest.fixture
def verify_operator_user(verify_dashboard):
    u = User.objects.create_user(phone="0580000000", password="Pass12345!")
    u.is_staff = True
    u.save(update_fields=["is_staff"])
    ap = UserAccessProfile.objects.create(user=u, level="user")
    ap.allowed_dashboards.add(verify_dashboard)
    return u


@pytest.fixture
def other_staff_user():
    u = User.objects.create_user(phone="0580000001", password="Pass12345!")
    u.is_staff = True
    u.save(update_fields=["is_staff"])
    return u


def _create_ready_verification_request(*, user, badge_type="blue"):
    vr = VerificationRequest.objects.create(requester=user, badge_type=badge_type)
    doc = VerificationDocument.objects.create(
        request=vr,
        doc_type="id",
        title="هوية",
        file=SimpleUploadedFile("id.png", b"fake", content_type="image/png"),
        uploaded_by=user,
    )
    decide_document(doc=doc, is_approved=True, note="ok", by_user=user)
    return vr


def test_create_verification_request(api, user):
    api.force_authenticate(user=user)
    r = api.post("/api/verification/requests/create/", data={"badge_type": "blue"}, format="json")
    assert r.status_code == 201
    assert r.data["code"].startswith("AD")
    vr = VerificationRequest.objects.get(pk=r.data["id"])
    ur = UnifiedRequest.objects.get(
        source_app="verification",
        source_model="VerificationRequest",
        source_object_id=str(vr.id),
    )
    assert ur.request_type == "verification"
    assert ur.code.startswith("AD")
    assert ur.status == vr.status


def test_verification_pricing_endpoint_reflects_subscription_tier(api, user):
    plan = SubscriptionPlan.objects.create(code="RIYADI", tier="riyadi", title="Riyadi", features=[])
    Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
        end_at=timezone.now(),
    )
    api.force_authenticate(user=user)
    response = api.get("/api/verification/pricing/my/")
    assert response.status_code == 200
    assert response.data["tier"] == "riyadi"
    assert response.data["prices"]["blue"]["amount"] == "50.00"
    assert response.data["prices"]["green"]["amount"] == "50.00"
    assert response.data["prices"]["blue"]["requires_payment"] is True


@pytest.mark.parametrize(
    ("tier", "expected_subtotal", "expected_request_status", "expected_invoice_status"),
    [
        ("basic", "100.00", VerificationStatus.PENDING_PAYMENT, "pending"),
        ("riyadi", "50.00", VerificationStatus.PENDING_PAYMENT, "pending"),
        ("pro", "0.00", VerificationStatus.ACTIVE, "paid"),
    ],
)
def test_verification_fee_uses_subscription_tier_defaults(
    api,
    user,
    tier,
    expected_subtotal,
    expected_request_status,
    expected_invoice_status,
):
    plan = SubscriptionPlan.objects.create(code=tier.upper(), tier=tier, title=tier.title(), features=[])
    Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
        end_at=timezone.now(),
    )

    vr = _create_ready_verification_request(user=user)
    vr = finalize_request_and_create_invoice(vr=vr, by_user=user)

    assert vr.invoice is not None
    assert str(vr.invoice.subtotal) == expected_subtotal
    assert vr.status == expected_request_status
    assert vr.invoice.status == expected_invoice_status
    if tier == "pro":
        assert vr.activated_at is not None
        assert vr.expires_at is not None


def test_backoffice_list(api, admin_user, user):
    VerificationRequest.objects.create(requester=user, badge_type="blue")
    api.force_authenticate(user=admin_user)
    r = api.get("/api/verification/backoffice/requests/")
    assert r.status_code == 200
    assert len(r.data) >= 1


def test_backoffice_list_forbidden_without_access_profile(api, user):
    VerificationRequest.objects.create(requester=user, badge_type="blue")
    api.force_authenticate(user=user)
    r = api.get("/api/verification/backoffice/requests/")
    assert r.status_code == 403


def test_user_operator_cannot_assign_to_other(api, verify_operator_user, other_staff_user, user):
    vr = VerificationRequest.objects.create(requester=user, badge_type="blue")

    api.force_authenticate(user=verify_operator_user)

    r = api.patch(f"/api/verification/backoffice/requests/{vr.id}/assign/", data={"assigned_to": other_staff_user.id}, format="json")
    assert r.status_code == 403

    r2 = api.patch(f"/api/verification/backoffice/requests/{vr.id}/assign/", data={"assigned_to": verify_operator_user.id}, format="json")
    assert r2.status_code == 200
    ur = UnifiedRequest.objects.get(
        source_app="verification",
        source_model="VerificationRequest",
        source_object_id=str(vr.id),
    )
    assert ur.assigned_user_id == verify_operator_user.id


def test_verification_fee_uses_active_subscription_plan_matrix(settings, user):
    plan = SubscriptionPlan.objects.create(code="PRO", tier="pro", title="Pro", features=[])
    Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
        end_at=timezone.now(),
    )
    settings.VERIFY_FEES_BY_PLAN = {
        "PRO": {
            "blue": "77.00",
            "green": "33.00",
        }
    }

    vr = _create_ready_verification_request(user=user)
    vr = finalize_request_and_create_invoice(vr=vr, by_user=user)
    assert vr.invoice is not None
    assert str(vr.invoice.subtotal) == "77.00"
    ur = UnifiedRequest.objects.get(
        source_app="verification",
        source_model="VerificationRequest",
        source_object_id=str(vr.id),
    )
    assert ur.status == "pending_payment"
    assert ur.metadata_record.payload.get("invoice_id") == vr.invoice_id
