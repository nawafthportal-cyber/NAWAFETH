import pytest

from django.test import Client
from django.urls import reverse

from apps.accounts.models import User
from apps.backoffice.models import Dashboard, UserAccessProfile
from apps.providers.models import Category, ProviderCategory, ProviderProfile, SubCategory
from apps.marketplace.models import RequestStatus, RequestType, ServiceRequest
from apps.reviews.models import Review, ReviewModerationStatus
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.support.models import (
    SupportPriority,
    SupportTeam,
    SupportTicket,
    SupportTicketEntrypoint,
    SupportTicketStatus,
    SupportTicketType,
)
from apps.dashboard.views import _content_review_detail_payload, _content_review_queryset_for_user


pytestmark = pytest.mark.django_db


def _dashboard_client() -> Client:
    user = User.objects.create_user(
        phone="0551000099",
        password="Pass12345!",
        is_staff=True,
        is_superuser=True,
    )
    Dashboard.objects.get_or_create(
        code="content",
        defaults={"name_ar": "لوحة المحتوى", "is_active": True, "sort_order": 20},
    )
    UserAccessProfile.objects.get_or_create(user=user, defaults={"level": "admin"})
    client = Client()
    assert client.login(phone=user.phone, password="Pass12345!")
    session = client.session
    session[SESSION_OTP_VERIFIED_KEY] = True
    session.save()
    return client


def _create_provider(user: User) -> ProviderProfile:
    provider = ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مزود اختبار",
        bio="bio",
        years_experience=1,
        city="الرياض",
        accepts_urgent=True,
    )
    cat = Category.objects.create(name="اختبار")
    sub = SubCategory.objects.create(category=cat, name="فرعي")
    ProviderCategory.objects.create(provider=provider, subcategory=sub)
    return provider


def test_content_reviews_dashboard_queryset_includes_content_inquiries_and_transfers():
    requester = User.objects.create_user(phone="0551000001", password="Pass12345!")
    provider_user = User.objects.create_user(phone="0551000002", password="Pass12345!")
    reported_user = User.objects.create_user(phone="0551000003", password="Pass12345!")
    content_team, _ = SupportTeam.objects.get_or_create(
        code="content",
        defaults={"name_ar": "فريق إدارة المحتوى", "is_active": True, "sort_order": 20},
    )

    provider = _create_provider(provider_user)
    sr = ServiceRequest.objects.create(
        client=requester,
        provider=provider,
        subcategory=provider.providercategory_set.first().subcategory,
        title="طلب تجريبي",
        description="وصف",
        request_type=RequestType.NORMAL,
        status=RequestStatus.COMPLETED,
        city="الرياض",
    )
    review = Review.objects.create(
        request=sr,
        provider=provider,
        client=requester,
        rating=4,
        comment="تعليق التقييم",
        moderation_status=ReviewModerationStatus.APPROVED,
    )

    review_ticket = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.COMPLAINT,
        status=SupportTicketStatus.NEW,
        priority=SupportPriority.NORMAL,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        description="بلاغ على تقييم",
        reported_kind="review",
        reported_object_id=str(review.id),
        reported_user=reported_user,
    )

    suggest_ticket = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.SUGGEST,
        status=SupportTicketStatus.NEW,
        priority=SupportPriority.NORMAL,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        description="استفسار مباشر لفريق المحتوى",
    )

    transferred_ticket = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.TECH,
        status=SupportTicketStatus.NEW,
        priority=SupportPriority.NORMAL,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        description="طلب حُوّل من لوحة الدعم إلى فريق المحتوى",
        assigned_team=content_team,
    )

    SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.ADS,
        status=SupportTicketStatus.NEW,
        priority=SupportPriority.NORMAL,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        description="استفسار ترويج يجب ألا يظهر في لوحة المحتوى",
    )

    qs = _content_review_queryset_for_user(requester)
    ids = list(qs.values_list("id", flat=True))
    assert set(ids) == {review_ticket.id, suggest_ticket.id, transferred_ticket.id}


def test_content_dashboard_home_lists_content_inquiries_and_support_transfers():
    client = _dashboard_client()
    requester = User.objects.create_user(phone="0551000041", password="Pass12345!")
    content_team, _ = SupportTeam.objects.get_or_create(
        code="content",
        defaults={"name_ar": "فريق إدارة المحتوى", "is_active": True, "sort_order": 20},
    )

    direct_content_ticket = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.SUGGEST,
        status=SupportTicketStatus.NEW,
        priority=SupportPriority.NORMAL,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        description="استفسار محتوى مباشر من تواصل مع نوافذ",
    )

    transferred_to_content = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.TECH,
        status=SupportTicketStatus.IN_PROGRESS,
        priority=SupportPriority.NORMAL,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        description="طلب دعم محوّل إلى فريق إدارة المحتوى",
        assigned_team=content_team,
    )

    excluded_ticket = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.ADS,
        status=SupportTicketStatus.NEW,
        priority=SupportPriority.NORMAL,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        description="استفسار ترويج غير تابع لإدارة المحتوى",
    )

    response = client.get(reverse("dashboard:content_dashboard_home"))

    assert response.status_code == 200
    ids = [row["id"] for row in response.context["content_inquiries"]]
    assert direct_content_ticket.id in ids
    assert transferred_to_content.id in ids
    assert excluded_ticket.id not in ids
    assert response.context["content_inquiry_summary"]["total"] == 2


def test_content_dashboard_home_csv_export_contains_inquiries_rows():
    client = _dashboard_client()
    requester = User.objects.create_user(phone="0551000042", password="Pass12345!")
    ticket = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.SUGGEST,
        status=SupportTicketStatus.NEW,
        priority=SupportPriority.NORMAL,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        description="استفسار محتوى لاختبار تصدير CSV",
    )

    response = client.get(reverse("dashboard:content_dashboard_home"), {"export": "csv"})

    assert response.status_code == 200
    assert response["Content-Disposition"] == 'attachment; filename="content_inquiries.csv"'
    content = response.content.decode("utf-8")
    assert "رقم الطلب" in content
    assert ticket.code in content


def test_content_review_detail_payload_contains_report_and_review_details():
    requester = User.objects.create_user(phone="0551000011", password="Pass12345!")
    provider_user = User.objects.create_user(phone="0551000012", password="Pass12345!")
    reported_user = User.objects.create_user(phone="0551000013", password="Pass12345!")

    provider = _create_provider(provider_user)
    sr = ServiceRequest.objects.create(
        client=requester,
        provider=provider,
        subcategory=provider.providercategory_set.first().subcategory,
        title="طلب اختبار",
        description="وصف",
        request_type=RequestType.NORMAL,
        status=RequestStatus.COMPLETED,
        city="الرياض",
    )
    review = Review.objects.create(
        request=sr,
        provider=provider,
        client=requester,
        rating=5,
        comment="هذا نص التقييم",
        provider_reply="رد مقدم الخدمة",
        management_reply="رد الإدارة",
        moderation_status=ReviewModerationStatus.APPROVED,
    )

    ticket = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.COMPLAINT,
        status=SupportTicketStatus.NEW,
        priority=SupportPriority.NORMAL,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        description="تفاصيل الشكوى النصية",
        reported_kind="review",
        reported_object_id=str(review.id),
        reported_user=reported_user,
    )

    payload = _content_review_detail_payload(ticket)

    assert payload["review_id"] == review.id
    assert payload["request_id"] == sr.id
    assert payload["review_rating"] == 5
    assert payload["complaint_details"] == "تفاصيل الشكوى النصية"
    assert payload["review_comment"] == "هذا نص التقييم"
    assert payload["review_provider_reply"] == "رد مقدم الخدمة"
    assert payload["review_management_reply"] == "رد الإدارة"
    assert payload["reporter_account"].startswith("@")
    assert payload["reported_account"].startswith("@")


def test_content_reviews_dashboard_closes_direct_content_inquiry_without_delete_target_error():
    client = _dashboard_client()
    requester = User.objects.create_user(phone="0551000021", password="Pass12345!")
    ticket = SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.SUGGEST,
        status=SupportTicketStatus.NEW,
        priority=SupportPriority.NORMAL,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        description="استفسار محتوى مباشر",
    )

    response = client.post(
        reverse("dashboard:content_reviews_ticket_detail", args=[ticket.id]),
        data={
            "ticket_id": str(ticket.id),
            "status": SupportTicketStatus.NEW,
            "assigned_team": "",
            "assigned_to": "",
            "description": ticket.description,
            "assignee_comment": "إغلاق الاستفسار بعد المعالجة",
            "management_reply": "",
            "moderation_action": "none",
            "action": "close_ticket",
        },
    )

    assert response.status_code == 302
    ticket.refresh_from_db()
    assert ticket.status == SupportTicketStatus.CLOSED
