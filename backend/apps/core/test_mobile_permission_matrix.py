import pytest
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole
from apps.providers.models import Category, ProviderProfile, SubCategory


@pytest.mark.django_db
def test_visitor_denied_level2_social_actions():
    provider_user = User.objects.create_user(phone="0511000001", role_state=UserRole.PROVIDER)
    provider = ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="Provider One",
        bio="bio",
        years_experience=1,
        city="Riyadh",
        accepts_urgent=True,
    )

    visitor_user = User.objects.create_user(phone="0511000002", role_state=UserRole.VISITOR)
    api = APIClient()
    api.force_authenticate(user=visitor_user)

    follow_res = api.post(f"/api/providers/{provider.id}/follow/", {}, format="json")
    direct_chat_res = api.post(
        "/api/messaging/direct/thread/",
        {"provider_id": provider.id},
        format="json",
    )

    assert follow_res.status_code == 403
    assert direct_chat_res.status_code == 403


@pytest.mark.django_db
def test_phone_only_denied_level3_actions():
    cat = Category.objects.create(name="Design", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="Logo", is_active=True)

    phone_only_user = User.objects.create_user(phone="0511000011", role_state=UserRole.PHONE_ONLY)
    api = APIClient()
    api.force_authenticate(user=phone_only_user)

    request_res = api.post(
        "/api/marketplace/requests/create/",
        {
            "subcategory": sub.id,
            "title": "Need design",
            "description": "Need logo design",
            "request_type": "competitive",
            "city": "Riyadh",
        },
        format="json",
    )

    provider_register_res = api.post(
        "/api/providers/register/",
        {
            "provider_type": "individual",
            "display_name": "Provider Candidate",
            "bio": "bio",
            "years_experience": 2,
            "city": "Riyadh",
            "accepts_urgent": True,
        },
        format="json",
    )

    notification_pref_res = api.patch(
        "/api/notifications/preferences/",
        {"updates": []},
        format="json",
    )

    assert request_res.status_code == 403
    assert provider_register_res.status_code == 403
    assert notification_pref_res.status_code == 403


@pytest.mark.django_db
def test_client_and_provider_boundary_actions():
    cat = Category.objects.create(name="Dev", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="Web", is_active=True)

    client_user = User.objects.create_user(phone="0511000021", role_state=UserRole.CLIENT)
    client_api = APIClient()
    client_api.force_authenticate(user=client_user)

    request_res = client_api.post(
        "/api/marketplace/requests/create/",
        {
            "subcategory": sub.id,
            "title": "Build website",
            "description": "Need a landing page",
            "request_type": "competitive",
            "city": "Riyadh",
        },
        format="json",
    )
    provider_only_res = client_api.get("/api/providers/me/subcategories/")

    provider_user = User.objects.create_user(phone="0511000022", role_state=UserRole.PROVIDER)
    ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="Provider Two",
        bio="bio",
        years_experience=3,
        city="Riyadh",
        accepts_urgent=True,
    )
    provider_api = APIClient()
    provider_api.force_authenticate(user=provider_user)
    provider_subcategories_res = provider_api.get("/api/providers/me/subcategories/")

    assert request_res.status_code == 201
    assert provider_only_res.status_code == 403
    assert provider_subcategories_res.status_code == 200
