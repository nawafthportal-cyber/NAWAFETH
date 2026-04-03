import pytest

from django.test import Client
from django.urls import reverse
from django.utils import timezone
from django.core.files.uploadedfile import SimpleUploadedFile

from apps.accounts.models import User, UserRole
from apps.backoffice.models import Dashboard, UserAccessProfile
from apps.billing.models import Invoice
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.support.models import SupportTeam, SupportTicket, SupportTicketEntrypoint, SupportTicketType
from apps.verification.models import (
    VerifiedBadge,
    VerificationBadgeType,
    VerificationBlueProfile,
    VerificationInquiryProfile,
    VerificationRequirement,
    VerificationRequest,
)


pytestmark = pytest.mark.django_db


def _dashboard_client() -> Client:
    user = User.objects.create_user(
        phone="0556000001",
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


def test_verification_dashboard_renders_main_and_verified_accounts_views():
    requester = User.objects.create_user(phone="0556001001", password="Pass12345!", username="verify-client")
    verification_team, _ = SupportTeam.objects.get_or_create(
        code="verification",
        defaults={"name_ar": "فريق التوثيق", "is_active": True, "sort_order": 40},
    )
    ticket = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.VERIFY,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        assigned_team=verification_team,
        description="استفسار توثيق",
    )
    verification_request = VerificationRequest.objects.create(requester=requester, badge_type=VerificationBadgeType.BLUE)
    VerifiedBadge.objects.create(
        user=requester,
        request=verification_request,
        badge_type=VerificationBadgeType.BLUE,
        verification_code="B1",
        verification_title="توثيق هوية",
        activated_at=timezone.now(),
        expires_at=timezone.now() + timezone.timedelta(days=30),
        is_active=True,
    )

    client = _dashboard_client()

    response = client.get(reverse("dashboard:verification_dashboard"))
    assert response.status_code == 200
    html = response.content.decode("utf-8", errors="ignore")
    assert ticket.code in html
    assert verification_request.code in html
    assert "قائمة استفسارات التوثيق" in html
    assert "قائمة طلبات التوثيق" in html

    accounts_response = client.get(reverse("dashboard:verification_dashboard"), {"tab": "verified_accounts"})
    assert accounts_response.status_code == 200
    accounts_html = accounts_response.content.decode("utf-8", errors="ignore")
    assert "بيانات الحسابات الموثقة" in accounts_html
    assert requester.username in accounts_html
    assert "B1" in accounts_html


def test_verification_dashboard_inquiry_details_follow_requested_layout():
    requester = User.objects.create_user(phone="0556001004", password="Pass12345!", username="verify-detail")
    verification_team, _ = SupportTeam.objects.get_or_create(
        code="verification",
        defaults={"name_ar": "فريق التوثيق", "is_active": True, "sort_order": 40},
    )
    ticket = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.VERIFY,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        assigned_team=verification_team,
        description="أحتاج متابعة بخصوص التوثيق",
    )

    client = _dashboard_client()
    response = client.get(reverse("dashboard:verification_dashboard"), {"inquiry": ticket.id})

    assert response.status_code == 200
    html = response.content.decode("utf-8", errors="ignore")
    assert "تفاصيل الطلب" in html
    assert "المرفقات" in html
    assert "حالة الطلب" in html
    assert "الفريق المكلف" in html
    assert "المكلف بالطلب" in html
    assert "تعليق المكلف بالطلب" in html
    assert 'id="closeInquiryDetailLink"' in html
    assert 'data-toggle-state="close"' in html
    assert "ربط بطلب توثيق" not in html
    assert "رابط صفحة الطلب التفصيلي" not in html


def test_verification_dashboard_save_inquiry_creates_profile_and_links_request():
    requester = User.objects.create_user(phone="0556001002", password="Pass12345!", username="verify-link")
    verification_team, _ = SupportTeam.objects.get_or_create(
        code="verification",
        defaults={"name_ar": "فريق التوثيق", "is_active": True, "sort_order": 40},
    )
    ticket = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.VERIFY,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        assigned_team=verification_team,
        description="طلب ربط استفسار بطلب توثيق",
    )
    verification_request = VerificationRequest.objects.create(requester=requester, badge_type=VerificationBadgeType.GREEN)

    client = _dashboard_client()
    response = client.post(
        reverse("dashboard:verification_dashboard"),
        data={
            "action": "save_inquiry",
            "ticket_id": ticket.id,
            "status": "in_progress",
            "assigned_team": str(verification_team.id),
            "assigned_to": "",
            "description": "تمت مراجعة الاستفسار وتحويله",
            "operator_comment": "يرجى استكمال نموذج التوثيق عبر الرابط https://example.com/verification/request/42",
            "detailed_request_url": "",
            "linked_request_id": str(verification_request.id),
            "redirect_query": f"inquiry={ticket.id}",
        },
        follow=True,
    )

    assert response.status_code == 200
    profile = VerificationInquiryProfile.objects.get(ticket=ticket)
    assert profile.linked_request_id == verification_request.id
    assert profile.detailed_request_url == "https://example.com/verification/request/42"
    assert "يرجى استكمال" in profile.operator_comment


def test_verification_dashboard_request_review_and_summary_follow_requested_flow():
    requester = User.objects.create_user(phone="0556001005", password="Pass12345!", username="verify-request-flow")
    verification_request = VerificationRequest.objects.create(requester=requester, badge_type=VerificationBadgeType.BLUE)
    VerificationBlueProfile.objects.create(
        request=verification_request,
        subject_type="individual",
        official_number="1020304050",
        official_date=timezone.now().date(),
        verified_name="أحمد علي",
        is_name_approved=True,
    )
    blue_req = VerificationRequirement.objects.create(
        request=verification_request,
        badge_type=VerificationBadgeType.BLUE,
        code="B1",
        title="توثيق الهوية الشخصية",
        sort_order=0,
    )
    blue_req.attachments.create(
        file=SimpleUploadedFile("blue.png", b"blue-evidence", content_type="image/png"),
        uploaded_by=requester,
    )
    green_req = VerificationRequirement.objects.create(
        request=verification_request,
        badge_type=VerificationBadgeType.GREEN,
        code="G2",
        title="توثيق الرخص التنظيمية",
        sort_order=1,
    )
    green_req.attachments.create(
        file=SimpleUploadedFile("green.png", b"green-evidence", content_type="image/png"),
        uploaded_by=requester,
    )

    client = _dashboard_client()

    review_response = client.get(
        reverse("dashboard:verification_dashboard"),
        {"request": verification_request.id, "request_stage": "review"},
    )
    assert review_response.status_code == 200
    review_html = review_response.content.decode("utf-8", errors="ignore")
    assert "مراجعة بنود طلب التوثيق" in review_html
    assert "الشارة الزرقاء" in review_html
    assert "الشارة الخضراء" in review_html
    assert f'name="decision_{blue_req.id}"' in review_html
    assert f'name="evidence_expires_at_{green_req.id}"' in review_html

    summary_response = client.post(
        reverse("dashboard:verification_dashboard"),
        data={
            "action": "continue_request_review",
            "verification_request_id": verification_request.id,
            "assigned_to": "",
            "admin_note": "تمت مراجعة البنود",
            "request_stage": "review",
            "decision_%s" % blue_req.id: "approve",
            "decision_%s" % green_req.id: "reject",
            "evidence_expires_at_%s" % green_req.id: "2026-12-31T09:30",
            "redirect_query": f"request={verification_request.id}&request_stage=review",
        },
        follow=True,
    )
    assert summary_response.status_code == 200
    summary_html = summary_response.content.decode("utf-8", errors="ignore")
    assert "بنود التوثيق المعتمدة" in summary_html
    assert "بنود التوثيق المرفوضة" in summary_html
    assert f'name="reject_reason_{green_req.id}"' in summary_html

    verification_request.refresh_from_db()
    green_req.refresh_from_db()
    assert verification_request.status == "in_review"
    assert green_req.is_approved is False
    assert green_req.evidence_expires_at is not None


def test_verification_dashboard_finalize_request_creates_invoice_from_approved_codes():
    requester = User.objects.create_user(phone="0556001006", password="Pass12345!", username="verify-finalize")
    verification_request = VerificationRequest.objects.create(requester=requester, badge_type=VerificationBadgeType.GREEN)
    approved_req = VerificationRequirement.objects.create(
        request=verification_request,
        badge_type=VerificationBadgeType.GREEN,
        code="G1",
        title="توثيق الاعتماد المهني",
        is_approved=True,
        sort_order=0,
    )
    approved_req.attachments.create(
        file=SimpleUploadedFile("verify-dashboard-g1-finalize.png", b"g1-evidence", content_type="image/png"),
        uploaded_by=requester,
    )
    rejected_req = VerificationRequirement.objects.create(
        request=verification_request,
        badge_type=VerificationBadgeType.GREEN,
        code="G4",
        title="توثيق الدرجة العلمية",
        is_approved=False,
        sort_order=1,
    )
    rejected_req.attachments.create(
        file=SimpleUploadedFile("verify-dashboard-g4-finalize.png", b"g4-evidence", content_type="image/png"),
        uploaded_by=requester,
    )

    client = _dashboard_client()
    response = client.post(
        reverse("dashboard:verification_dashboard"),
        data={
            "action": "finalize_request",
            "verification_request_id": verification_request.id,
            "assigned_to": "",
            "admin_note": "اعتماد نهائي",
            "request_stage": "summary",
            "reject_reason_%s" % rejected_req.id: "تعذر التحقق من صحة المستند المرفوع.",
            "redirect_query": f"request={verification_request.id}&request_stage=summary",
        },
        follow=True,
    )

    assert response.status_code == 200
    verification_request.refresh_from_db()
    rejected_req.refresh_from_db()
    assert verification_request.invoice is not None
    assert verification_request.status == "pending_payment"
    assert verification_request.invoice.lines.count() == 1
    assert verification_request.invoice.lines.get().item_code == "G1"
    assert "تعذر التحقق" in rejected_req.decision_note


def test_verification_dashboard_verified_account_detail_matches_requested_layout():
    requester = User.objects.create_user(phone="0556001007", password="Pass12345!", username="verified-account-user")
    verification_request = VerificationRequest.objects.create(requester=requester, badge_type=VerificationBadgeType.BLUE)
    VerificationBlueProfile.objects.create(
        request=verification_request,
        subject_type="individual",
        official_number="1020304050",
        official_date=timezone.now().date(),
        verified_name="اسم العميل الموثق",
        is_name_approved=True,
    )
    requirement = VerificationRequirement.objects.create(
        request=verification_request,
        badge_type=VerificationBadgeType.BLUE,
        code="B1",
        title="توثيق الهوية الشخصية",
        is_approved=True,
        sort_order=0,
    )
    requirement.attachments.create(
        file=SimpleUploadedFile("verified-b1.pdf", b"verified-b1", content_type="application/pdf"),
        uploaded_by=requester,
    )
    verification_request.documents.create(
        doc_type="id",
        title="هوية وطنية",
        file=SimpleUploadedFile("verified-id.pdf", b"verified-id", content_type="application/pdf"),
        uploaded_by=requester,
    )
    invoice = Invoice.objects.create(
        user=requester,
        title="فاتورة توثيق",
        reference_type="verify_request",
        reference_id=verification_request.code,
    )
    invoice.lines.create(item_code="B1", title="توثيق الهوية الشخصية", amount="100.00")
    invoice.mark_payment_confirmed(
        provider="manual",
        provider_reference="manual-1",
        event_id="evt-verified-1",
        amount="100.00",
        currency="SAR",
    )
    invoice.save()
    verification_request.invoice = invoice
    verification_request.save(update_fields=["invoice", "updated_at"])
    badge = VerifiedBadge.objects.create(
        user=requester,
        request=verification_request,
        badge_type=VerificationBadgeType.BLUE,
        verification_code="B1",
        verification_title="توثيق الهوية الشخصية",
        activated_at=timezone.now(),
        expires_at=timezone.now() + timezone.timedelta(days=30),
        is_active=True,
    )

    client = _dashboard_client()
    response = client.get(
        reverse("dashboard:verification_dashboard"),
        {"tab": "verified_accounts", "verified_badge": badge.id},
    )

    assert response.status_code == 200
    html = response.content.decode("utf-8", errors="ignore")
    assert "تفاصيل التوثيق" in html
    assert "مستندات التوثيق المرفوعة" in html
    assert "اسم العميل أو المنشأة الموثق" in html
    assert "تمت عملية سداد الرسوم بنجاح" in html
    assert invoice.code in html


def test_verification_dashboard_delete_verified_badge_deactivates_selected_row_only():
    requester = User.objects.create_user(phone="0556001008", password="Pass12345!", username="verified-delete-user")
    verification_request = VerificationRequest.objects.create(requester=requester, badge_type=VerificationBadgeType.GREEN)
    first_badge = VerifiedBadge.objects.create(
        user=requester,
        request=verification_request,
        badge_type=VerificationBadgeType.GREEN,
        verification_code="G2",
        verification_title="توثيق الرخص التنظيمية",
        activated_at=timezone.now(),
        expires_at=timezone.now() + timezone.timedelta(days=30),
        is_active=True,
    )
    second_badge = VerifiedBadge.objects.create(
        user=requester,
        request=verification_request,
        badge_type=VerificationBadgeType.GREEN,
        verification_code="G5",
        verification_title="توثيق الشهادات الاحترافية",
        activated_at=timezone.now(),
        expires_at=timezone.now() + timezone.timedelta(days=45),
        is_active=True,
    )

    client = _dashboard_client()
    response = client.post(
        reverse("dashboard:verification_dashboard"),
        data={
            "action": "delete_verified_badge",
            "verified_badge_id": first_badge.id,
            "redirect_query": "tab=verified_accounts&verified_badge=%s" % first_badge.id,
        },
        follow=True,
    )

    assert response.status_code == 200
    first_badge.refresh_from_db()
    second_badge.refresh_from_db()
    assert first_badge.is_active is False
    assert second_badge.is_active is True


def test_verification_dashboard_renew_verified_badge_creates_new_request_and_opens_review():
    requester = User.objects.create_user(phone="0556001009", password="Pass12345!", username="verified-renew-user")
    source_request = VerificationRequest.objects.create(requester=requester, badge_type=VerificationBadgeType.BLUE)
    VerificationBlueProfile.objects.create(
        request=source_request,
        subject_type="individual",
        official_number="1020304050",
        official_date=timezone.now().date(),
        verified_name="عميل تجديد",
        is_name_approved=True,
    )
    source_requirement = VerificationRequirement.objects.create(
        request=source_request,
        badge_type=VerificationBadgeType.BLUE,
        code="B1",
        title="توثيق الهوية الشخصية",
        is_approved=True,
        sort_order=0,
    )
    source_requirement.attachments.create(
        file=SimpleUploadedFile("renew-b1.pdf", b"renew-b1", content_type="application/pdf"),
        uploaded_by=requester,
    )
    source_request.documents.create(
        doc_type="id",
        title="هوية وطنية",
        file=SimpleUploadedFile("renew-id.pdf", b"renew-id", content_type="application/pdf"),
        uploaded_by=requester,
    )
    badge = VerifiedBadge.objects.create(
        user=requester,
        request=source_request,
        badge_type=VerificationBadgeType.BLUE,
        verification_code="B1",
        verification_title="توثيق الهوية الشخصية",
        activated_at=timezone.now(),
        expires_at=timezone.now() + timezone.timedelta(days=30),
        is_active=True,
    )

    client = _dashboard_client()
    response = client.post(
        reverse("dashboard:verification_dashboard"),
        data={
            "action": "renew_verified_badge",
            "verified_badge_id": badge.id,
            "redirect_query": "tab=verified_accounts&verified_badge=%s" % badge.id,
        },
        follow=True,
    )

    assert response.status_code == 200
    renewal_request = VerificationRequest.objects.exclude(id=source_request.id).get()
    renewal_requirement = renewal_request.requirements.get()
    assert renewal_request.badge_type == VerificationBadgeType.BLUE
    assert renewal_request.assigned_to is not None
    assert renewal_requirement.code == "B1"
    assert renewal_requirement.attachments.count() == 1
    assert renewal_request.documents.count() == 1
    html = response.content.decode("utf-8", errors="ignore")
    assert "مراجعة بنود طلب التوثيق" in html
    assert renewal_request.code in html


def test_verification_dashboard_is_visible_in_main_nav_for_verify_operator():
    verify_dashboard, _ = Dashboard.objects.get_or_create(
        code="verify",
        defaults={"name_ar": "فريق التوثيق", "is_active": True, "sort_order": 40},
    )
    operator = User.objects.create_user(
        phone="0556001003",
        password="Pass12345!",
        is_staff=True,
        role_state=UserRole.STAFF,
    )
    access_profile = UserAccessProfile.objects.create(user=operator, level="user")
    access_profile.allowed_dashboards.add(verify_dashboard)

    client = Client()
    assert client.login(phone=operator.phone, password="Pass12345!")
    session = client.session
    session[SESSION_OTP_VERIFIED_KEY] = True
    session.save()

    response = client.get(reverse("dashboard:verification_dashboard"))
    assert response.status_code == 200
    html = response.content.decode("utf-8", errors="ignore")
    assert reverse("dashboard:verification_dashboard") in html
