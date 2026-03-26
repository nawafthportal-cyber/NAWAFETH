import pytest

from apps.accounts.models import User
from apps.providers.models import Category, ProviderCategory, ProviderProfile, SubCategory
from apps.marketplace.models import RequestStatus, RequestType, ServiceRequest
from apps.reviews.models import Review, ReviewModerationStatus
from apps.support.models import (
    SupportPriority,
    SupportTicket,
    SupportTicketEntrypoint,
    SupportTicketStatus,
    SupportTicketType,
)
from apps.dashboard.views import _content_review_detail_payload, _content_review_queryset_for_user


pytestmark = pytest.mark.django_db


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


def test_content_reviews_dashboard_queryset_includes_review_reports_only():
    requester = User.objects.create_user(phone="0551000001", password="Pass12345!")
    provider_user = User.objects.create_user(phone="0551000002", password="Pass12345!")
    reported_user = User.objects.create_user(phone="0551000003", password="Pass12345!")

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

    # Should be included: complaint + reported_kind=review + contact_platform.
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

    # Should be excluded: wrong kind.
    SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.COMPLAINT,
        status=SupportTicketStatus.NEW,
        priority=SupportPriority.NORMAL,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        description="بلاغ محادثة",
        reported_kind="thread",
        reported_object_id="99",
        reported_user=reported_user,
    )

    # Should be excluded: wrong ticket type.
    SupportTicket.objects.create(
        requester=requester,
        ticket_type=SupportTicketType.SUGGEST,
        status=SupportTicketStatus.NEW,
        priority=SupportPriority.NORMAL,
        entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM,
        description="اقتراح",
        reported_kind="review",
        reported_object_id=str(review.id),
        reported_user=reported_user,
    )

    qs = _content_review_queryset_for_user(requester)
    ids = list(qs.values_list("id", flat=True))
    assert ids == [review_ticket.id]


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
