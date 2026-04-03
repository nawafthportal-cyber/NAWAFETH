import pytest
from django.test import Client

from apps.accounts.models import User, UserRole
from apps.providers.models import ProviderProfile


pytestmark = pytest.mark.django_db


def test_verification_page_renders_blue_green_flow_shell():
    client = Client()
    res = client.get("/verification/")

    assert res.status_code == 200
    html = res.content.decode("utf-8", errors="ignore")

    assert 'id="verifyBadgeBlueTab"' in html
    assert 'id="verifyBadgeGreenTab"' in html
    assert 'id="verifyGreenRequirements"' in html
    assert 'id="greenAttachmentsInput"' in html
    assert 'id="verifyPricingStrip"' in html
    assert 'id="verifySummaryStep"' in html
    assert 'id="verifySummaryRows"' in html
    assert 'id="verifySummaryProviderHandle"' in html
    assert 'id="verifySuccessRequestCode"' in html
    assert 'id="verifySuccessCloseBtn"' in html
    assert 'mobile_web/js/verificationPage.js' in html


def test_profile_page_contains_provider_verification_entry():
    user = User.objects.create_user(
        phone="0558887777",
        password="Pass12345!",
        username="verify_provider",
        role_state=UserRole.PROVIDER,
    )
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مزود التوثيق",
        bio="bio",
    )

    client = Client()
    client.force_login(user)
    res = client.get("/profile/")

    assert res.status_code == 200
    html = res.content.decode("utf-8", errors="ignore")

    assert 'id="btn-provider-verification"' in html
    assert 'href="/verification/"' in html
    assert "طلب الشارة الزرقاء أو الخضراء" in html
