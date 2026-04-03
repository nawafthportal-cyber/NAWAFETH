from decimal import Decimal

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient

from django.utils import timezone

from apps.accounts.models import User, UserRole
from apps.backoffice.models import UserAccessProfile
from apps.backoffice.models import Dashboard
from apps.core.models import PlatformConfig
from apps.providers.models import ProviderProfile
from apps.support.models import SupportTeam, SupportTicket, SupportTicketEntrypoint, SupportTicketType
from apps.verification.models import VerifiedBadge
from apps.verification.models import VerificationBadgeType
from apps.verification.models import VerificationBlueProfile
from apps.verification.models import VerificationInquiryProfile
from apps.verification.models import VerificationRequest
from apps.verification.models import VerificationDocument
from apps.verification.models import VerificationRequirement
from apps.verification.models import VerificationStatus
from apps.unified_requests.models import UnifiedRequest
from apps.subscriptions.models import SubscriptionPlan, Subscription, SubscriptionStatus
from apps.verification.services import (
    activate_after_payment,
    decide_document,
    finalize_request_and_create_invoice,
    verification_billing_policy,
    verification_pricing_for_user,
)


pytestmark = pytest.mark.django_db


@pytest.fixture
def api():
    return APIClient()


@pytest.fixture
def user():
    return User.objects.create_user(phone="0544444444", password="Pass12345!")


def _make_provider(user, *, sync_role: bool = True):
    if sync_role:
        user.role_state = UserRole.PROVIDER
        user.save(update_fields=["role_state"])
    return ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name=f"Provider {user.phone}",
        bio="bio",
    )


def test_verification_billing_policy_uses_platform_config_currency():
    config = PlatformConfig.load()
    config.verification_currency = "USD"
    config.save()

    policy = verification_billing_policy()

    assert policy["currency"] == "USD"


def test_verification_activation_window_uses_platform_config_days(user):
    config = PlatformConfig.load()
    config.verification_validity_days = 120
    config.save()

    request = VerificationRequest.objects.create(requester=user)

    assert request.activation_window().days == 120


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


def _create_ready_requirement_request(*, user, badge_type="green", codes=None):
    codes = list(codes or (["G1"] if badge_type == "green" else ["B1"]))
    vr = VerificationRequest.objects.create(requester=user, badge_type=badge_type)
    for idx, code in enumerate(codes):
        req = VerificationRequirement.objects.create(
            request=vr,
            badge_type=badge_type,
            code=code,
            title=f"Requirement {code}",
            is_approved=True,
            sort_order=idx,
        )
        req.attachments.create(
            file=SimpleUploadedFile(f"{code.lower()}.png", b"evidence", content_type="image/png"),
            uploaded_by=user,
        )
    return vr


def test_create_verification_request(api, user):
    _make_provider(user)
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


def test_blue_preview_endpoint_returns_provider_based_reference_name(api, user):
    provider_profile = _make_provider(user)
    provider_profile.display_name = "مؤسسة المثال"
    provider_profile.save(update_fields=["display_name"])
    api.force_authenticate(user=user)

    response = api.post(
        "/api/verification/blue-preview/",
        data={
            "subject_type": "business",
            "official_number": "1010123456",
            "official_date": "2026-04-03",
        },
        format="json",
    )

    assert response.status_code == 200
    assert response.data["subject_type"] == "business"
    assert response.data["subject_type_label"] == "منشأة"
    assert response.data["official_number_label"] == "رقم السجل التجاري"
    assert response.data["official_date_label"] == "تاريخه"
    assert response.data["verified_name"] == "مؤسسة المثال"
    assert response.data["verification_source"] == "elm"
    assert response.data["verification_source_label"] == "من خدمات علم"


def test_create_blue_request_persists_blue_profile_and_exposes_it_in_detail(api, user):
    _make_provider(user)
    user.first_name = "سارة"
    user.last_name = "محمد"
    user.save(update_fields=["first_name", "last_name"])
    api.force_authenticate(user=user)

    response = api.post(
        "/api/verification/requests/create/",
        data={
            "badge_type": "blue",
            "requirements": [{"badge_type": "blue", "code": "B1"}],
            "blue_profile": {
                "subject_type": "individual",
                "official_number": "1020304050",
                "official_date": "1992-02-14",
                "verified_name": "سارة محمد",
                "is_name_approved": True,
            },
        },
        format="json",
    )

    assert response.status_code == 201
    vr = VerificationRequest.objects.get(pk=response.data["id"])
    blue_profile = VerificationBlueProfile.objects.get(request=vr)
    assert blue_profile.subject_type == "individual"
    assert blue_profile.official_number == "1020304050"
    assert blue_profile.verified_name == "سارة محمد"
    assert blue_profile.is_name_approved is True

    detail_response = api.get(f"/api/verification/requests/{vr.id}/")
    assert detail_response.status_code == 200
    assert detail_response.data["blue_profile"]["subject_type"] == "individual"
    assert detail_response.data["blue_profile"]["official_number_label"] == "رقم الهوية / الإقامة"
    assert detail_response.data["blue_profile"]["official_date_label"] == "تاريخ الميلاد"
    assert detail_response.data["blue_profile"]["verified_name"] == "سارة محمد"


def test_verification_pricing_endpoint_reflects_subscription_tier(api, user):
    _make_provider(user)
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
    assert response.data["tier"] == "pioneer"
    assert response.data["tier_legacy"] == "riyadi"
    assert response.data["billing_cycle"] == "yearly"
    assert response.data["tax_policy"] == "inclusive"
    assert response.data["additional_vat_percent"] == "0.00"
    assert response.data["prices"]["blue"]["amount"] == "50.00"
    assert response.data["prices"]["green"]["amount"] == "50.00"
    assert response.data["prices"]["blue"]["final_amount"] == "50.00"
    assert response.data["prices"]["blue"]["requires_payment"] is True


def test_create_verification_request_rejects_non_provider(api, user):
    user.role_state = UserRole.CLIENT
    user.save(update_fields=["role_state"])
    api.force_authenticate(user=user)

    response = api.post("/api/verification/requests/create/", data={"badge_type": "blue"}, format="json")

    assert response.status_code == 403
    assert "مقدمي الخدمات" in str(response.data.get("detail", ""))


def test_create_verification_request_rejects_provider_role_without_profile(api, user):
    user.role_state = UserRole.PROVIDER
    user.save(update_fields=["role_state"])
    api.force_authenticate(user=user)

    response = api.post("/api/verification/requests/create/", data={"badge_type": "blue"}, format="json")

    assert response.status_code == 403
    assert "ملف مقدم الخدمة" in str(response.data.get("detail", ""))


def test_verification_pricing_rejects_non_provider(api, user):
    user.role_state = UserRole.CLIENT
    user.save(update_fields=["role_state"])
    api.force_authenticate(user=user)

    response = api.get("/api/verification/pricing/my/")

    assert response.status_code == 403
    assert "مقدمي الخدمات" in str(response.data.get("detail", ""))


def test_legacy_provider_profile_user_can_create_verification_request(api, user):
    _make_provider(user, sync_role=False)
    api.force_authenticate(user=user)

    response = api.post("/api/verification/requests/create/", data={"badge_type": "blue"}, format="json")

    assert response.status_code == 201


def test_blue_flow_document_upload_moves_request_to_in_review_and_mirrors_authoritative_attachment(api, user):
    _make_provider(user)
    api.force_authenticate(user=user)

    create_response = api.post(
        "/api/verification/requests/create/",
        data={"badge_type": "blue", "requirements": [{"badge_type": "blue", "code": "B1"}]},
        format="json",
    )
    assert create_response.status_code == 201

    request_id = create_response.data["id"]
    upload_response = api.post(
        f"/api/verification/requests/{request_id}/documents/",
        data={
            "doc_type": "id",
            "title": "هوية",
            "file": SimpleUploadedFile("id.png", b"evidence", content_type="image/png"),
        },
    )
    assert upload_response.status_code == 201

    vr = VerificationRequest.objects.get(pk=request_id)
    req = vr.requirements.get(code="B1")
    vr.refresh_from_db()

    assert vr.status == VerificationStatus.IN_REVIEW
    assert vr.documents.count() == 1
    assert req.attachments.count() == 1


def test_duplicate_prevention_blocks_existing_requirement_based_request(api, user):
    _make_provider(user)
    existing = VerificationRequest.objects.create(requester=user, badge_type=None, status=VerificationStatus.IN_REVIEW)
    VerificationRequirement.objects.create(
        request=existing,
        badge_type=VerificationBadgeType.BLUE,
        code="B1",
        title="Blue requirement",
    )

    api.force_authenticate(user=user)
    response = api.post(
        "/api/verification/requests/create/",
        data={"badge_type": "blue", "requirements": [{"badge_type": "blue", "code": "B1"}]},
        format="json",
    )

    assert response.status_code == 400
    assert "يوجد طلب توثيق قائم" in str(response.data)


def test_duplicate_prevention_rejects_duplicate_requirement_codes_in_same_request(api, user):
    _make_provider(user)
    api.force_authenticate(user=user)

    response = api.post(
        "/api/verification/requests/create/",
        data={
            "badge_type": "green",
            "requirements": [
                {"badge_type": "green", "code": "G1"},
                {"badge_type": "green", "code": "G1"},
            ],
        },
        format="json",
    )

    assert response.status_code == 400
    assert "لا يمكن تكرار" in str(response.data)


def test_green_flow_requirement_attachment_moves_request_to_in_review(api, user):
    _make_provider(user)
    api.force_authenticate(user=user)

    create_response = api.post(
        "/api/verification/requests/create/",
        data={"badge_type": "green", "requirements": [{"badge_type": "green", "code": "G1"}]},
        format="json",
    )
    assert create_response.status_code == 201

    request_id = create_response.data["id"]
    req_id = VerificationRequest.objects.get(pk=request_id).requirements.get(code="G1").id
    upload_response = api.post(
        f"/api/verification/requests/{request_id}/requirements/{req_id}/attachments/",
        data={
            "file": SimpleUploadedFile("g1.png", b"evidence", content_type="image/png"),
        },
    )
    assert upload_response.status_code == 201

    vr = VerificationRequest.objects.get(pk=request_id)
    assert vr.status == VerificationStatus.IN_REVIEW
    assert vr.requirements.get(pk=req_id).attachments.count() == 1


def test_green_flow_shared_document_upload_mirrors_to_all_selected_requirements(api, user):
    _make_provider(user)
    api.force_authenticate(user=user)

    create_response = api.post(
        "/api/verification/requests/create/",
        data={
            "badge_type": "green",
            "requirements": [
                {"badge_type": "green", "code": "G1"},
                {"badge_type": "green", "code": "G2"},
            ],
        },
        format="json",
    )
    assert create_response.status_code == 201

    request_id = create_response.data["id"]
    upload_response = api.post(
        f"/api/verification/requests/{request_id}/documents/",
        data={
            "doc_type": "other",
            "title": "مرفقات داعمة للشارة الخضراء",
            "file": SimpleUploadedFile("green.pdf", b"evidence", content_type="application/pdf"),
        },
    )
    assert upload_response.status_code == 201

    vr = VerificationRequest.objects.get(pk=request_id)
    requirements = list(vr.requirements.order_by("code"))
    assert vr.status == VerificationStatus.IN_REVIEW
    assert vr.documents.count() == 1
    assert [req.code for req in requirements] == ["G1", "G2"]
    assert all(req.attachments.count() == 1 for req in requirements)


@pytest.mark.parametrize(
    ("tier", "expected_amount", "expected_request_status", "expected_invoice_status"),
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
    expected_amount,
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
    assert str(vr.invoice.subtotal) == expected_amount
    assert str(vr.invoice.total) == expected_amount
    assert str(vr.invoice.vat_percent) == "0.00"
    assert str(vr.invoice.vat_amount) == "0.00"
    assert vr.status == expected_request_status
    assert vr.invoice.status == expected_invoice_status
    if tier == "pro":
        assert vr.activated_at is not None
        assert vr.expires_at is not None


@pytest.mark.parametrize(
    ("tier", "expected_amount"),
    [
        ("basic", "100.00"),
        ("riyadi", "50.00"),
        ("pro", "0.00"),
    ],
)
def test_verification_pricing_has_blue_green_parity_by_tier(user, tier, expected_amount):
    plan = SubscriptionPlan.objects.create(code=f"{tier.upper()}_PARITY", tier=tier, title=tier.title(), features=[])
    Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
        end_at=timezone.now(),
    )

    pricing = verification_pricing_for_user(user)

    assert pricing["prices"]["blue"]["amount"] == expected_amount
    assert pricing["prices"]["green"]["amount"] == expected_amount
    assert pricing["prices"]["blue"]["final_amount"] == expected_amount
    assert pricing["prices"]["green"]["final_amount"] == expected_amount


def test_multi_requirement_verification_is_billed_per_approved_requirement(user):
    plan = SubscriptionPlan.objects.create(code="RIYADI_MULTI", tier="riyadi", title="Riyadi", features=[])
    Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
        end_at=timezone.now(),
    )

    vr = _create_ready_requirement_request(user=user, badge_type="green", codes=["G1", "G2", "G3"])
    vr = finalize_request_and_create_invoice(vr=vr, by_user=user)

    assert vr.invoice is not None
    assert vr.invoice.lines.count() == 3
    assert [line.item_code for line in vr.invoice.lines.order_by("sort_order", "id")] == ["G1", "G2", "G3"]
    assert all(str(line.amount) == "50.00" for line in vr.invoice.lines.all())
    assert str(vr.invoice.subtotal) == "150.00"
    assert str(vr.invoice.total) == "150.00"
    assert str(vr.invoice.vat_percent) == "0.00"
    assert vr.status == VerificationStatus.PENDING_PAYMENT


def test_finalize_rejects_approved_requirement_without_evidence(user):
    vr = VerificationRequest.objects.create(requester=user, badge_type=VerificationBadgeType.BLUE)
    VerificationRequirement.objects.create(
        request=vr,
        badge_type=VerificationBadgeType.BLUE,
        code="B1",
        title="Blue requirement",
        is_approved=True,
    )

    with pytest.raises(ValueError, match="مرفقات إثبات"):
        finalize_request_and_create_invoice(vr=vr, by_user=user)


def test_activate_after_payment_requires_approval_before_activation(user):
    vr = VerificationRequest.objects.create(requester=user, badge_type=VerificationBadgeType.BLUE, status=VerificationStatus.NEW)
    req = VerificationRequirement.objects.create(
        request=vr,
        badge_type=VerificationBadgeType.BLUE,
        code="B1",
        title="Blue requirement",
        is_approved=True,
    )
    req.attachments.create(
        file=SimpleUploadedFile("b1.png", b"evidence", content_type="image/png"),
        uploaded_by=user,
    )
    from apps.billing.models import Invoice

    invoice = Invoice.objects.create(
        user=user,
        title="رسوم التوثيق",
        subtotal=Decimal("0.00"),
        vat_percent=Decimal("0.00"),
        reference_type="verify_request",
        reference_id=vr.code,
        status="draft",
    )
    invoice.mark_paid(when=timezone.now())
    invoice.save(update_fields=["status", "paid_at", "subtotal", "vat_percent", "vat_amount", "total", "updated_at"])
    vr.invoice = invoice
    vr.save(update_fields=["invoice", "updated_at"])

    with pytest.raises(ValueError, match="قبل اعتماد الطلب"):
        activate_after_payment(vr=vr)


def test_unpaid_approved_request_has_no_active_badge(user):
    vr = _create_ready_requirement_request(user=user, badge_type="blue", codes=["B1"])
    vr = finalize_request_and_create_invoice(vr=vr, by_user=user)

    assert vr.status == VerificationStatus.PENDING_PAYMENT
    assert VerifiedBadge.objects.filter(request=vr, is_active=True).count() == 0


def test_professional_verification_flow_is_free_and_activates_immediately(user):
    plan = SubscriptionPlan.objects.create(code="PRO_FREE", tier="pro", title="Professional", features=[])
    Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
        end_at=timezone.now(),
    )

    vr = _create_ready_requirement_request(user=user, badge_type="green", codes=["G1", "G2"])
    vr = finalize_request_and_create_invoice(vr=vr, by_user=user)

    assert vr.invoice is not None
    assert vr.status == VerificationStatus.ACTIVE
    assert vr.invoice.status == "paid"
    assert str(vr.invoice.total) == "0.00"
    assert vr.activated_at is not None
    assert vr.expires_at is not None
    assert VerifiedBadge.objects.filter(request=vr, is_active=True).count() == 2


def test_pricing_endpoint_matches_invoice_total_and_invoice_summary(api, user):
    _make_provider(user)
    plan = SubscriptionPlan.objects.create(code="RIYADI_SUMMARY", tier="riyadi", title="Riyadi", features=[])
    Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
        end_at=timezone.now(),
    )
    api.force_authenticate(user=user)

    pricing_response = api.get("/api/verification/pricing/my/")
    assert pricing_response.status_code == 200
    expected_amount = pricing_response.data["prices"]["blue"]["amount"]

    vr = _create_ready_requirement_request(user=user, badge_type="blue", codes=["B1"])
    vr = finalize_request_and_create_invoice(vr=vr, by_user=user)

    assert vr.invoice is not None
    assert str(vr.invoice.total) == expected_amount

    detail_response = api.get(f"/api/verification/requests/{vr.id}/")
    assert detail_response.status_code == 200
    assert detail_response.data["invoice_summary"]["total"] == expected_amount
    assert detail_response.data["invoice_summary"]["vat_percent"] == "0.00"
    assert detail_response.data["invoice_summary"]["tax_policy"] == "inclusive"


def test_backoffice_list(api, admin_user, user):
    VerificationRequest.objects.create(requester=user, badge_type="blue")
    api.force_authenticate(user=admin_user)
    r = api.get("/api/verification/backoffice/requests/")
    assert r.status_code == 200
    assert len(r.data) >= 1


def test_provider_created_request_appears_in_backoffice_requests_list(api, admin_user, user):
    _make_provider(user)
    api.force_authenticate(user=user)
    create_response = api.post(
        "/api/verification/requests/create/",
        data={"badge_type": "green", "requirements": [{"badge_type": "green", "code": "G1"}]},
        format="json",
    )
    assert create_response.status_code == 201
    request_code = create_response.data["code"]

    api.force_authenticate(user=admin_user)
    list_response = api.get("/api/verification/backoffice/requests/")

    assert list_response.status_code == 200
    assert any(item["code"] == request_code for item in list_response.data)


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


def test_verification_fee_ignores_legacy_plan_matrix_override(settings, user):
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
    assert str(vr.invoice.subtotal) == "0.00"
    pricing = verification_pricing_for_user(user)
    assert pricing["prices"]["blue"]["amount"] == "0.00"
    assert pricing["prices"]["green"]["amount"] == "0.00"
    ur = UnifiedRequest.objects.get(
        source_app="verification",
        source_model="VerificationRequest",
        source_object_id=str(vr.id),
    )
    assert ur.status == "active"
    assert ur.metadata_record.payload.get("invoice_id") == vr.invoice_id


def test_verification_pricing_uses_canonical_db_row_not_settings_matrix(settings, user):
    canonical = SubscriptionPlan.objects.get(code="riyadi")
    canonical.verification_blue_fee = Decimal("12.00")
    canonical.verification_green_fee = Decimal("7.00")
    canonical.save(update_fields=["verification_blue_fee", "verification_green_fee"])

    plan = SubscriptionPlan.objects.create(code="RIYADI_DB_MATRIX", tier="riyadi", title="Riyadi", features=[])
    Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
        end_at=timezone.now(),
    )

    settings.VERIFY_FEES_BY_TIER = {
        "pioneer": {
            "blue": "88.00",
            "green": "44.00",
        }
    }

    pricing = verification_pricing_for_user(user)

    assert pricing["prices"]["blue"]["amount"] == "12.00"
    assert pricing["prices"]["green"]["amount"] == "7.00"


def test_create_verification_request_ignores_client_priority_and_uses_server_priority(api, user):
    _make_provider(user)
    api.force_authenticate(user=user)

    response = api.post(
        "/api/verification/requests/create/",
        data={"badge_type": "blue", "priority": 3},
        format="json",
    )

    assert response.status_code == 201
    vr = VerificationRequest.objects.get(pk=response.data["id"])
    assert vr.priority == 1


def test_create_verification_request_rejects_unknown_requirement_code(api, user):
    _make_provider(user)
    api.force_authenticate(user=user)

    response = api.post(
        "/api/verification/requests/create/",
        data={
            "badge_type": "green",
            "requirements": [{"badge_type": "green", "code": "G99"}],
        },
        format="json",
    )

    assert response.status_code == 400
    assert "code غير صالح" in str(response.data)


def test_backoffice_request_list_includes_requester_and_assignment_fields(api, admin_user, verify_operator_user, user):
    vr = VerificationRequest.objects.create(
        requester=user,
        badge_type="blue",
        assigned_to=verify_operator_user,
        assigned_at=timezone.now(),
    )

    api.force_authenticate(user=admin_user)
    response = api.get("/api/verification/backoffice/requests/")

    assert response.status_code == 200
    row = next(item for item in response.data if item["id"] == vr.id)
    assert row["requester_name"].startswith("@")
    assert row["assigned_to_name"].startswith("@") or verify_operator_user.phone in row["assigned_to_name"]
    assert row["assigned_at"] is not None


def test_backoffice_inquiries_list_returns_verification_tickets_with_profile_link(api, admin_user, user):
    verification_team, _ = SupportTeam.objects.get_or_create(
        code="verification",
        defaults={"name_ar": "فريق التوثيق", "is_active": True, "sort_order": 40},
    )
    ticket = SupportTicket.objects.create(
        requester=user,
        ticket_type=SupportTicketType.VERIFY,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        assigned_team=verification_team,
        description="استفسار توثيق",
    )
    vr = VerificationRequest.objects.create(requester=user, badge_type="green")
    VerificationInquiryProfile.objects.create(ticket=ticket, linked_request=vr, operator_comment="تم الربط")

    api.force_authenticate(user=admin_user)
    response = api.get("/api/verification/backoffice/inquiries/")

    assert response.status_code == 200
    row = next(item for item in response.data if item["id"] == ticket.id)
    assert row["code"] == ticket.code
    assert row["linked_request_code"] == vr.code
    assert row["operator_comment"] == "تم الربط"


def test_backoffice_verified_accounts_list_returns_active_badges(api, admin_user, user):
    vr = VerificationRequest.objects.create(requester=user, badge_type="blue")
    VerifiedBadge.objects.create(
        user=user,
        request=vr,
        badge_type=VerificationBadgeType.BLUE,
        verification_code="B1",
        verification_title="توثيق أساسي",
        activated_at=timezone.now(),
        expires_at=timezone.now() + timezone.timedelta(days=15),
        is_active=True,
    )

    api.force_authenticate(user=admin_user)
    response = api.get("/api/verification/backoffice/verified-accounts/")

    assert response.status_code == 200
    assert response.data
    row = next(item for item in response.data if item["badge_id"])
    assert row["user_id"] == user.id
    assert row["verification_code"] == "B1"
    assert row["badge_type"] == VerificationBadgeType.BLUE
    assert row["badge_type_label"]
    assert row["request_code"] == vr.code
