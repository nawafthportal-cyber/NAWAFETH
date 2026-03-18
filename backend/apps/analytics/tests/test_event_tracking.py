import json
from pathlib import Path

import pytest
from django.test import override_settings
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole
from apps.analytics.models import AnalyticsEvent
from apps.marketplace.models import ServiceRequest
from apps.providers.models import Category, ProviderCategory, ProviderProfile, SubCategory


pytestmark = pytest.mark.django_db


@pytest.fixture
def api():
    return APIClient()


@override_settings(FEATURE_ANALYTICS_EVENTS=True)
def test_event_ingest_accepts_event_and_dedupes(api):
    payload = {
        "event_name": "provider.profile_view",
        "channel": "mobile_web",
        "surface": "mobile_web.provider_profile",
        "source_app": "providers",
        "object_type": "ProviderProfile",
        "object_id": "55",
        "dedupe_key": "provider.profile_view:test:55",
        "payload": {"role_state": "client"},
    }

    first = api.post("/api/analytics/events/", payload, format="json")
    second = api.post("/api/analytics/events/", payload, format="json")

    assert first.status_code == 202
    assert second.status_code == 202
    assert first.data["accepted"] is True
    assert second.data["deduped"] is True
    assert AnalyticsEvent.objects.filter(dedupe_key="provider.profile_view:test:55").count() == 1


def test_analytics_events_endpoint_hidden_when_flag_off(api):
    response = api.post(
        "/api/analytics/events/",
        {"event_name": "provider.profile_view", "object_type": "ProviderProfile", "object_id": "99"},
        format="json",
    )

    assert response.status_code == 404


def test_contract_fixture_docs_are_valid_json():
    repo_root = Path(__file__).resolve().parents[4]
    fixture_sets = {
        "sprint2": [
            "auth_me_response.json",
            "profile_provider_detail.json",
            "orders_list.json",
            "chat_thread_messages.json",
            "subscriptions_plans.json",
            "verification_request_detail.json",
            "promo_active_items.json",
            "support_ticket_detail.json",
        ],
        "sprint3": [
            "notifications_list.json",
            "notifications_unread_count.json",
        ],
    }

    for folder_name, fixture_names in fixture_sets.items():
        fixture_dir = repo_root / "docs" / "contracts" / folder_name
        for fixture_name in fixture_names:
            data = json.loads((fixture_dir / fixture_name).read_text(encoding="utf-8"))
            assert data


@override_settings(FEATURE_ANALYTICS_EVENTS=True)
def test_marketplace_request_create_emits_analytics_event(api):
    category = Category.objects.create(name="تصميم", is_active=True)
    subcategory = SubCategory.objects.create(category=category, name="هوية", is_active=True)
    client_user = User.objects.create_user(phone="0510101001", password="Pass12345!", role_state=UserRole.CLIENT)
    provider_user = User.objects.create_user(phone="0510101002", password="Pass12345!", role_state=UserRole.PROVIDER)
    provider = ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود تحليلات",
        bio="bio",
        city="الرياض",
        years_experience=1,
    )
    ProviderCategory.objects.create(provider=provider, subcategory=subcategory)

    api.force_authenticate(user=client_user)
    response = api.post(
        "/api/marketplace/requests/create/",
        {
            "subcategory": subcategory.id,
            "title": "طلب تحليلات",
            "description": "اختبار إنشاء طلب",
            "request_type": "competitive",
            "city": "الرياض",
        },
        format="json",
    )

    assert response.status_code == 201
    request_id = str(response.data["id"])
    assert ServiceRequest.objects.filter(id=response.data["id"]).exists()
    assert AnalyticsEvent.objects.filter(
        event_name="marketplace.request_created",
        object_type="ServiceRequest",
        object_id=request_id,
    ).exists()


@override_settings(FEATURE_ANALYTICS_EVENTS=True)
def test_direct_thread_create_emits_analytics_event(api):
    client_user = User.objects.create_user(phone="0510101003", password="Pass12345!", role_state=UserRole.PHONE_ONLY)
    provider_user = User.objects.create_user(phone="0510101004", password="Pass12345!", role_state=UserRole.PROVIDER)
    provider = ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود رسائل",
        bio="bio",
        city="الرياض",
        years_experience=1,
    )

    api.force_authenticate(user=client_user)
    response = api.post(
        "/api/messaging/direct/thread/",
        {"provider_id": provider.id},
        format="json",
    )

    assert response.status_code == 200
    assert AnalyticsEvent.objects.filter(
        event_name="messaging.direct_thread_created",
        object_type="Thread",
        object_id=str(response.data["id"]),
    ).exists()
