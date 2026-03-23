import pytest
from datetime import timedelta
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import Client
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import User
from apps.backoffice.models import AccessLevel, Dashboard, UserAccessProfile
from apps.dashboard.access import sync_dashboard_user_access
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.promo.models import PromoAdType, PromoAsset, PromoAssetType, PromoFrequency, PromoOpsStatus, PromoPosition, PromoRequest


pytestmark = pytest.mark.django_db


@pytest.fixture
def otp_client():
    return Client()


def _login_with_dashboard_otp(client: Client, user: User) -> None:
    client.force_login(user)
    session = client.session
    session[SESSION_OTP_VERIFIED_KEY] = True
    session.save()


def test_promo_request_detail_shows_provider_uploaded_assets(otp_client):
    Dashboard.objects.get_or_create(code="promo", defaults={"name_ar": "إدارة الترويج", "is_active": True, "sort_order": 4})

    operator = User.objects.create_user(phone="0557111001", username="promo-operator", password="Pass12345!")
    profile = UserAccessProfile.objects.create(user=operator, level=AccessLevel.POWER)
    profile.allowed_dashboards.set(Dashboard.objects.filter(code="promo"))

    changed_fields = sync_dashboard_user_access(operator, access_profile=profile, force_staff_role_state=True)
    if changed_fields:
        operator.save(update_fields=changed_fields)

    requester = User.objects.create_user(phone="0557111002", username="provider-user", password="Pass12345!")

    now = timezone.now()
    promo_request = PromoRequest.objects.create(
        requester=requester,
        title="طلب ترويج مرفق",
        ad_type=PromoAdType.BANNER_HOME,
        start_at=now,
        end_at=now + timedelta(days=2),
        frequency=PromoFrequency.S60,
        position=PromoPosition.NORMAL,
        ops_status=PromoOpsStatus.NEW,
    )

    uploaded = SimpleUploadedFile("creative.jpg", b"fake-image-bytes", content_type="image/jpeg")
    PromoAsset.objects.create(
        request=promo_request,
        asset_type=PromoAssetType.IMAGE,
        title="تصميم الحملة",
        file=uploaded,
        uploaded_by=requester,
    )
    uploaded_pdf = SimpleUploadedFile("brief.pdf", b"%PDF-1.4 test", content_type="application/pdf")
    PromoAsset.objects.create(
        request=promo_request,
        asset_type=PromoAssetType.PDF,
        title="مستند الحملة",
        file=uploaded_pdf,
        uploaded_by=requester,
    )

    _login_with_dashboard_otp(otp_client, operator)

    response = otp_client.get(reverse("dashboard:promo_request_detail", args=[promo_request.id]))
    assert response.status_code == 200

    html = response.content.decode("utf-8", errors="ignore")
    assert "الملفات المرفقة من مزود الخدمة" in html
    assert "تصميم الحملة" in html
    assert "مستند الحملة" in html
    assert "فتح الملف" in html
    assert '<img src="' in html
    assert 'promo-asset-pdf-preview' in html
    assert 'class="promo-asset-lightbox-trigger"' in html
