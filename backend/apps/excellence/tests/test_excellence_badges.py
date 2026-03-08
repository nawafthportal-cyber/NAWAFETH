from __future__ import annotations

from datetime import timedelta

import pytest
from django.db.models import Q
from django.test import Client
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole
from apps.backoffice.models import AccessLevel, Dashboard, UserAccessProfile
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.excellence.models import ExcellenceBadgeAward, ExcellenceBadgeCandidate, ExcellenceBadgeCandidateStatus
from apps.excellence.selectors import FEATURED_SERVICE_BADGE_CODE, HIGH_ACHIEVEMENT_BADGE_CODE, TOP_100_CLUB_BADGE_CODE, current_review_window
from apps.excellence.services import approve_candidate, expire_excellence_awards, refresh_excellence_candidates, sync_badge_type_catalog
from apps.marketplace.models import RequestStatus, RequestType, ServiceRequest
from apps.messaging.models import Message, Thread
from apps.notifications.models import Notification
from apps.providers.models import Category, ProviderCategory, ProviderFollow, ProviderProfile, SubCategory
from apps.reviews.models import Review


pytestmark = pytest.mark.django_db


def _make_provider(phone: str, subcategory: SubCategory, display_name: str) -> ProviderProfile:
    user = User.objects.create_user(phone=phone, password="Pass12345!", role_state=UserRole.PROVIDER)
    provider = ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name=display_name,
        bio="bio",
        city="الرياض",
        years_experience=5,
    )
    ProviderCategory.objects.create(provider=provider, subcategory=subcategory)
    return provider


def _make_staff(phone: str, *, dashboard_codes: list[str]) -> User:
    user = User.objects.create_user(
        phone=phone,
        password="Pass12345!",
        is_staff=True,
        role_state=UserRole.STAFF,
    )
    dashboards = [
        Dashboard.objects.get_or_create(code=code, defaults={"name_ar": code, "sort_order": idx * 10})[0]
        for idx, code in enumerate(dashboard_codes, start=1)
    ]
    access = UserAccessProfile.objects.create(user=user, level=AccessLevel.USER)
    access.allowed_dashboards.set(dashboards)
    return user


def _dashboard_client(user: User) -> Client:
    client = Client()
    assert client.login(phone=user.phone, password="Pass12345!")
    session = client.session
    session[SESSION_OTP_VERIFIED_KEY] = True
    session.save()
    return client


def _add_followers(provider: ProviderProfile, count: int):
    for index in range(count):
        follower = User.objects.create_user(phone=f"0519{provider.id:02d}{index:04d}")
        ProviderFollow.objects.create(user=follower, provider=provider, role_context="client")


def _add_completed_requests(provider: ProviderProfile, subcategory: SubCategory, ratings: list[int]):
    for index, rating in enumerate(ratings, start=1):
        client_user = User.objects.create_user(phone=f"0529{provider.id:02d}{index:04d}")
        request = ServiceRequest.objects.create(
            client=client_user,
            provider=provider,
            subcategory=subcategory,
            title=f"طلب {provider.id}-{index}",
            description="وصف",
            request_type=RequestType.NORMAL,
            status=RequestStatus.COMPLETED,
            city="الرياض",
        )
        Review.objects.create(
            request=request,
            provider=provider,
            client=client_user,
            rating=rating,
            created_at=timezone.now() - timedelta(days=1),
        )


def _make_candidate(badge_code: str = FEATURED_SERVICE_BADGE_CODE) -> ExcellenceBadgeCandidate:
    sync_badge_type_catalog()
    category = Category.objects.create(name="الاستشارات", is_active=True)
    subcategory = SubCategory.objects.create(category=category, name="قانوني", is_active=True)
    provider = _make_provider("0507000001", subcategory, "مزود تميز")
    period_start, period_end = current_review_window()
    badge_type = {item.code: item for item in sync_badge_type_catalog()}[badge_code]
    return ExcellenceBadgeCandidate.objects.create(
        badge_type=badge_type,
        provider=provider,
        category=category,
        subcategory=subcategory,
        evaluation_period_start=period_start,
        evaluation_period_end=period_end,
        metric_value="4.90" if badge_code == FEATURED_SERVICE_BADGE_CODE else "12.00",
        rank_position=1,
        followers_count=120,
        completed_orders_count=12,
        rating_avg="4.90",
        rating_count=8,
    )


def test_refresh_excellence_candidates_is_idempotent_for_same_cycle():
    sync_badge_type_catalog()
    category = Category.objects.create(name="الخدمات المهنية", is_active=True)
    subcategory = SubCategory.objects.create(category=category, name="استشارات", is_active=True)
    provider_a = _make_provider("0507100001", subcategory, "الأول")
    provider_b = _make_provider("0507100002", subcategory, "الثاني")

    _add_followers(provider_a, 12)
    _add_followers(provider_b, 8)
    _add_completed_requests(provider_a, subcategory, [5, 5, 5, 5, 5, 5])
    _add_completed_requests(provider_b, subcategory, [5, 5, 4, 5, 4])

    first = refresh_excellence_candidates()
    second = refresh_excellence_candidates()

    assert first["created"] == 6
    assert second["created"] == 0
    assert ExcellenceBadgeCandidate.objects.count() == 6
    assert ExcellenceBadgeCandidate.objects.filter(badge_type__code=FEATURED_SERVICE_BADGE_CODE).count() == 2
    assert ExcellenceBadgeCandidate.objects.filter(badge_type__code=HIGH_ACHIEVEMENT_BADGE_CODE).count() == 2
    assert ExcellenceBadgeCandidate.objects.filter(badge_type__code=TOP_100_CLUB_BADGE_CODE).count() == 2


def test_approve_candidate_creates_award_cache_notification_and_message():
    candidate = _make_candidate(FEATURED_SERVICE_BADGE_CODE)
    reviewer = _make_staff("0507000091", dashboard_codes=["excellence"])

    award = approve_candidate(candidate=candidate, approved_by=reviewer, note="اعتماد الاختبار")

    candidate.refresh_from_db()
    candidate.provider.refresh_from_db()

    assert award.is_active is True
    assert candidate.status == ExcellenceBadgeCandidateStatus.APPROVED
    assert candidate.provider.excellence_badges_cache[0]["code"] == FEATURED_SERVICE_BADGE_CODE

    notification = Notification.objects.filter(
        user=candidate.provider.user,
        kind="excellence_badge_awarded",
    ).first()
    assert notification is not None
    assert candidate.badge_type.name_ar in notification.body

    thread = (
        Thread.objects.filter(is_direct=True)
        .filter(
            Q(participant_1=reviewer, participant_2=candidate.provider.user)
            | Q(participant_1=candidate.provider.user, participant_2=reviewer)
        )
        .first()
    )
    assert thread is not None
    assert Message.objects.filter(thread=thread, sender=reviewer).exists()


def test_expire_excellence_awards_marks_award_inactive_and_clears_payload_cache():
    candidate = _make_candidate(TOP_100_CLUB_BADGE_CODE)
    reviewer = _make_staff("0507000092", dashboard_codes=["excellence"])
    award = approve_candidate(candidate=candidate, approved_by=reviewer)

    award.valid_until = timezone.now() - timedelta(minutes=1)
    award.save(update_fields=["valid_until"])

    changed = expire_excellence_awards()

    award.refresh_from_db()
    candidate.refresh_from_db()
    candidate.provider.refresh_from_db()
    assert changed >= 1
    assert award.is_active is False
    assert candidate.status == ExcellenceBadgeCandidateStatus.EXPIRED
    assert candidate.provider.excellence_badges_cache == []


def test_provider_public_and_owner_api_include_excellence_badges():
    candidate = _make_candidate(HIGH_ACHIEVEMENT_BADGE_CODE)
    reviewer = _make_staff("0507000093", dashboard_codes=["excellence"])
    approve_candidate(candidate=candidate, approved_by=reviewer)

    anonymous = APIClient()
    detail = anonymous.get(f"/api/providers/{candidate.provider.id}/")
    assert detail.status_code == 200
    assert detail.data["excellence_badges"][0]["code"] == HIGH_ACHIEVEMENT_BADGE_CODE

    listing = anonymous.get("/api/providers/list/")
    assert listing.status_code == 200
    payload = listing.data[0] if isinstance(listing.data, list) else listing.data["results"][0]
    assert payload["excellence_badges"][0]["code"] == HIGH_ACHIEVEMENT_BADGE_CODE

    owner = APIClient()
    owner.force_authenticate(user=candidate.provider.user)
    profile = owner.get("/api/providers/me/profile/")
    assert profile.status_code == 200
    assert profile.data["excellence_badges"][0]["code"] == HIGH_ACHIEVEMENT_BADGE_CODE


def test_excellence_dashboard_requires_access_and_supports_approve_revoke_and_export():
    candidate = _make_candidate(FEATURED_SERVICE_BADGE_CODE)
    excellence_user = _make_staff("0507000094", dashboard_codes=["excellence"])
    content_user = _make_staff("0507000095", dashboard_codes=["content"])

    allowed = _dashboard_client(excellence_user)
    denied = _dashboard_client(content_user)

    page = allowed.get(reverse("dashboard:excellence_dashboard"))
    assert page.status_code == 200
    assert candidate.provider.display_name in page.content.decode("utf-8")

    export = allowed.get(reverse("dashboard:excellence_dashboard"), {"export": "xlsx"})
    assert export.status_code == 200
    assert export["Content-Type"] == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

    forbidden = denied.get(reverse("dashboard:excellence_dashboard"))
    assert forbidden.status_code in {302, 403}

    approve_response = allowed.post(
        reverse("dashboard:excellence_candidate_approve_action", args=[candidate.id]),
        data={},
    )
    assert approve_response.status_code == 302
    candidate.refresh_from_db()
    assert candidate.status == ExcellenceBadgeCandidateStatus.APPROVED

    award = ExcellenceBadgeAward.objects.get(candidate=candidate, is_active=True)
    revoke_response = allowed.post(
        reverse("dashboard:excellence_award_revoke_action", args=[award.id]),
        data={},
    )
    assert revoke_response.status_code == 302
    award.refresh_from_db()
    assert award.is_active is False
    candidate.refresh_from_db()
    assert candidate.status == ExcellenceBadgeCandidateStatus.REVOKED
