import pytest
from django.test import Client

from apps.accounts.models import User, UserRole
from apps.providers.models import ProviderProfile


@pytest.mark.django_db
def test_promotion_new_request_renders_provider_name_and_hides_manual_banner_scaling():
    user = User.objects.create_user(
        phone="0551234567",
        password="Pass12345!",
        username="promo_provider",
        first_name="محمد",
        last_name="التصميم",
        role_state=UserRole.PROVIDER,
    )
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="محمد التصميم",
        bio="bio",
        city="الرياض",
        years_experience=4,
    )

    client = Client()
    client.force_login(user)
    res = client.get("/mobile-web/promotion/new/")

    assert res.status_code == 200
    html = res.content.decode("utf-8", errors="ignore")

    assert 'data-provider-display-name="محمد التصميم"' in html
    assert 'id="promo-provider-display">محمد التصميم<' in html
    assert 'id="home-banner-scale-range"' not in html
    assert 'id="home-banner-device-tabs"' not in html
