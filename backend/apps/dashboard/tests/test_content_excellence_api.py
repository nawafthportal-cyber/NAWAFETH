import pytest
from django.test import Client
from django.urls import reverse

from apps.accounts.models import User, UserRole
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.excellence.models import ExcellenceBadgeCandidate
from apps.excellence.selectors import (
    FEATURED_SERVICE_BADGE_CODE,
    TOP_100_CLUB_BADGE_CODE,
    current_review_window,
)
from apps.excellence.services import sync_badge_type_catalog
from apps.providers.models import Category, ProviderCategory, ProviderProfile, SubCategory


pytestmark = pytest.mark.django_db


def _dashboard_client() -> Client:
    user = User.objects.create_user(
        phone="0553000001",
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


def _create_provider(*, phone: str, display_name: str, category_name: str, subcategory_name: str) -> ProviderProfile:
    user = User.objects.create_user(phone=phone, password="Pass12345!", role_state=UserRole.PROVIDER)
    provider = ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name=display_name,
        bio="bio",
        years_experience=4,
        city="الرياض",
        accepts_urgent=True,
    )
    category = Category.objects.create(name=category_name)
    subcategory = SubCategory.objects.create(category=category, name=subcategory_name)
    ProviderCategory.objects.create(provider=provider, subcategory=subcategory)
    return provider


def _create_candidate(*, badge_code: str, provider: ProviderProfile, rank: int, followers: int, completed: int, rating: str):
    period_start, period_end = current_review_window()
    badge_map = {item.code: item for item in sync_badge_type_catalog()}
    category_row = provider.providercategory_set.select_related("subcategory", "subcategory__category").first()
    ExcellenceBadgeCandidate.objects.create(
        badge_type=badge_map[badge_code],
        provider=provider,
        category=category_row.subcategory.category if category_row else None,
        subcategory=category_row.subcategory if category_row else None,
        evaluation_period_start=period_start,
        evaluation_period_end=period_end,
        metric_value=rating,
        rank_position=rank,
        followers_count=followers,
        completed_orders_count=completed,
        rating_avg=rating,
        rating_count=7,
    )


def test_content_excellence_api_returns_rows_and_tabs():
    provider_top = _create_provider(
        phone="0553001001",
        display_name="مختص المتابعين",
        category_name="قانوني",
        subcategory_name="تجاري",
    )
    provider_featured = _create_provider(
        phone="0553001002",
        display_name="مختص التقييم",
        category_name="تقني",
        subcategory_name="شبكات",
    )
    _create_candidate(
        badge_code=TOP_100_CLUB_BADGE_CODE,
        provider=provider_top,
        rank=1,
        followers=220,
        completed=10,
        rating="4.70",
    )
    _create_candidate(
        badge_code=FEATURED_SERVICE_BADGE_CODE,
        provider=provider_featured,
        rank=2,
        followers=40,
        completed=8,
        rating="4.95",
    )

    client = _dashboard_client()
    response = client.get(reverse("dashboard:content_excellence_api"))

    assert response.status_code == 200
    payload = response.json()
    assert payload["ok"] is True
    assert payload["total_rows"] == 2
    assert len(payload["rows"]) == 2
    tab_codes = {item["code"] for item in payload["badge_tabs"]}
    assert TOP_100_CLUB_BADGE_CODE in tab_codes
    assert FEATURED_SERVICE_BADGE_CODE in tab_codes


def test_content_excellence_api_filters_by_badge_and_search():
    provider_top = _create_provider(
        phone="0553002001",
        display_name="نادي الكبار",
        category_name="استشارات",
        subcategory_name="أعمال",
    )
    provider_featured = _create_provider(
        phone="0553002002",
        display_name="خدمة متميزة",
        category_name="تعليم",
        subcategory_name="لغة",
    )
    _create_candidate(
        badge_code=TOP_100_CLUB_BADGE_CODE,
        provider=provider_top,
        rank=1,
        followers=310,
        completed=16,
        rating="4.80",
    )
    _create_candidate(
        badge_code=FEATURED_SERVICE_BADGE_CODE,
        provider=provider_featured,
        rank=1,
        followers=22,
        completed=9,
        rating="4.99",
    )

    client = _dashboard_client()
    response = client.get(
        reverse("dashboard:content_excellence_api"),
        {"badge": TOP_100_CLUB_BADGE_CODE, "q": "الكبار"},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["filters"]["badge"] == TOP_100_CLUB_BADGE_CODE
    assert payload["filters"]["q"] == "الكبار"
    assert payload["total_rows"] == 1
    assert payload["rows"][0]["provider_name"] == "نادي الكبار"
