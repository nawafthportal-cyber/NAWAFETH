import pytest
from datetime import timedelta
from io import StringIO
from django.core.management import call_command
from rest_framework.test import APIClient
from django.core.files.uploadedfile import SimpleUploadedFile

from django.utils import timezone

from apps.accounts.models import User
from apps.backoffice.models import UserAccessProfile
from apps.backoffice.models import Dashboard
from apps.promo.models import PromoRequest
from apps.promo.models import PromoAsset, PromoRequestStatus
from apps.promo.models import PromoAdPrice
from apps.notifications.models import EventLog, Notification
from apps.providers.models import ProviderProfile
from apps.subscriptions.models import SubscriptionPlan, Subscription, SubscriptionStatus
from apps.promo.services import quote_and_create_invoice
from apps.promo.services import calc_promo_quote
from apps.promo.services import reject_request, activate_after_payment
from apps.unified_requests.models import UnifiedRequest


pytestmark = pytest.mark.django_db


@pytest.fixture
def api():
    return APIClient()


@pytest.fixture
def user():
    return User.objects.create_user(phone="0566666666", password="Pass12345!")


@pytest.fixture
def admin_user():
    u = User.objects.create_user(phone="0577777777", password="Pass12345!")
    UserAccessProfile.objects.create(user=u, level="admin")
    return u


@pytest.fixture
def promo_dashboard():
    Dashboard.objects.get_or_create(code="promo", defaults={"name_ar": "الترويج", "sort_order": 40})
    return Dashboard.objects.get(code="promo")


@pytest.fixture
def promo_operator_user(promo_dashboard):
    u = User.objects.create_user(phone="0588888888", password="Pass12345!")
    u.is_staff = True
    u.save(update_fields=["is_staff"])
    ap = UserAccessProfile.objects.create(user=u, level="user")
    ap.allowed_dashboards.add(promo_dashboard)
    return u


@pytest.fixture
def other_staff_user():
    u = User.objects.create_user(phone="0599999999", password="Pass12345!")
    u.is_staff = True
    u.save(update_fields=["is_staff"])
    return u


def test_create_promo_request(api, user):
    plan = SubscriptionPlan.objects.create(code="PRO", title="Pro", features=["promo_ads"])
    Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
        end_at=timezone.now(),
    )

    start_at = timezone.now() + timedelta(days=1)
    end_at = timezone.now() + timedelta(days=5)
    api.force_authenticate(user=user)
    r = api.post("/api/promo/requests/create/", data={
        "title": "test",
        "ad_type": "banner_home",
        "start_at": start_at.isoformat(),
        "end_at": end_at.isoformat(),
        "frequency": "60s",
        "position": "normal",
        "target_city": "Riyadh",
        "redirect_url": "",
    }, format="json")
    assert r.status_code == 201
    assert r.data["code"].startswith("MD")
    pr = PromoRequest.objects.get(pk=r.data["id"])
    ur = UnifiedRequest.objects.get(source_app="promo", source_model="PromoRequest", source_object_id=str(pr.id))
    assert ur.request_type == "promo"
    assert ur.code.startswith("MD")
    assert ur.status == "new"


def test_create_promo_request_rejects_duration_less_than_24h(api, user):
    plan = SubscriptionPlan.objects.create(code="PRO24", title="Pro", features=["promo_ads"])
    Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
        end_at=timezone.now(),
    )

    start_at = timezone.now() + timedelta(days=1)
    end_at = start_at + timedelta(hours=23)
    api.force_authenticate(user=user)
    r = api.post(
        "/api/promo/requests/create/",
        data={
            "title": "short-campaign",
            "ad_type": "banner_home",
            "start_at": start_at.isoformat(),
            "end_at": end_at.isoformat(),
            "frequency": "60s",
            "position": "normal",
            "target_city": "Riyadh",
            "redirect_url": "",
        },
        format="json",
    )
    assert r.status_code == 400


def test_backoffice_list(api, admin_user, user):
    PromoRequest.objects.create(
        requester=user,
        title="x",
        ad_type="banner_home",
        start_at="2026-02-01T10:00:00Z",
        end_at="2026-02-05T10:00:00Z",
        frequency="60s",
        position="normal",
    )
    api.force_authenticate(user=admin_user)
    r = api.get("/api/promo/backoffice/requests/")
    assert r.status_code == 200
    assert len(r.data) >= 1


def test_backoffice_list_forbidden_without_access_profile(api, user):
    PromoRequest.objects.create(
        requester=user,
        title="x",
        ad_type="banner_home",
        start_at="2026-02-01T10:00:00Z",
        end_at="2026-02-05T10:00:00Z",
        frequency="60s",
        position="normal",
    )
    api.force_authenticate(user=user)
    r = api.get("/api/promo/backoffice/requests/")
    assert r.status_code == 403


def test_user_operator_cannot_assign_to_other(api, promo_operator_user, other_staff_user, user):
    pr = PromoRequest.objects.create(
        requester=user,
        title="x",
        ad_type="banner_home",
        start_at="2026-02-01T10:00:00Z",
        end_at="2026-02-05T10:00:00Z",
        frequency="60s",
        position="normal",
    )

    api.force_authenticate(user=promo_operator_user)

    r = api.patch(f"/api/promo/backoffice/requests/{pr.id}/assign/", data={"assigned_to": other_staff_user.id}, format="json")
    assert r.status_code == 403

    r2 = api.patch(f"/api/promo/backoffice/requests/{pr.id}/assign/", data={"assigned_to": promo_operator_user.id}, format="json")
    assert r2.status_code == 200
    assert r2.data.get("assigned_to") in (promo_operator_user.id, None)
    ur = UnifiedRequest.objects.get(source_app="promo", source_model="PromoRequest", source_object_id=str(pr.id))
    assert ur.assigned_user_id == promo_operator_user.id


def test_public_home_banners_only_from_active_promo(api, user):
    # Create provider profile for the requester to populate provider fields.
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مزود تجريبي",
        bio="bio",
        city="الرياض",
        years_experience=0,
    )

    now = timezone.now()
    pr_inactive = PromoRequest.objects.create(
        requester=user,
        title="inactive",
        ad_type="banner_home",
        start_at=now - timedelta(days=1),
        end_at=now + timedelta(days=1),
        frequency="60s",
        position="normal",
        status=PromoRequestStatus.NEW,
    )
    PromoAsset.objects.create(
        request=pr_inactive,
        asset_type="image",
        title="should not show",
        file=SimpleUploadedFile(
            "x.png",
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
            content_type="image/png",
        ),
        uploaded_by=user,
    )

    pr_active = PromoRequest.objects.create(
        requester=user,
        title="active banner",
        ad_type="banner_home",
        start_at=now - timedelta(days=1),
        end_at=now + timedelta(days=1),
        frequency="60s",
        position="normal",
        redirect_url="https://example.com/promo",
        status=PromoRequestStatus.ACTIVE,
        activated_at=now,
    )
    asset = PromoAsset.objects.create(
        request=pr_active,
        asset_type="image",
        title="",
        file=SimpleUploadedFile(
            "banner.png",
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
            content_type="image/png",
        ),
        uploaded_by=user,
    )

    r = api.get("/api/promo/banners/home/?limit=10")
    assert r.status_code == 200
    assert isinstance(r.data, list)
    assert any(item["id"] == asset.id for item in r.data)
    active_item = next(item for item in r.data if item["id"] == asset.id)
    assert active_item.get("redirect_url") == "https://example.com/promo"
    # Ensure inactive request assets are not included.
    assert all(item.get("caption") != "should not show" for item in r.data)


def test_public_home_banners_respect_position_order(api, user):
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مزود",
        bio="bio",
        city="الرياض",
        years_experience=0,
    )
    now = timezone.now()

    def _create_banner(title: str, position: str):
        pr = PromoRequest.objects.create(
            requester=user,
            title=title,
            ad_type="banner_home",
            start_at=now - timedelta(hours=1),
            end_at=now + timedelta(days=1),
            frequency="60s",
            position=position,
            status=PromoRequestStatus.ACTIVE,
            activated_at=now,
        )
        return PromoAsset.objects.create(
            request=pr,
            asset_type="image",
            title=title,
            file=SimpleUploadedFile(
                f"{title}.png",
                b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
                content_type="image/png",
            ),
            uploaded_by=user,
        )

    first_asset = _create_banner("first", "first")
    normal_asset = _create_banner("normal", "normal")
    second_asset = _create_banner("second", "second")

    r = api.get("/api/promo/banners/home/?limit=10")
    assert r.status_code == 200

    ids = [item["id"] for item in r.data]
    assert ids.index(first_asset.id) < ids.index(second_asset.id) < ids.index(normal_asset.id)


def test_management_command_expires_due_active_promos(user):
    now = timezone.now()
    due = PromoRequest.objects.create(
        requester=user,
        title="due",
        ad_type="banner_home",
        start_at=now - timedelta(days=2),
        end_at=now - timedelta(minutes=1),
        frequency="60s",
        position="normal",
        status=PromoRequestStatus.ACTIVE,
        activated_at=now - timedelta(days=1),
    )
    still_active = PromoRequest.objects.create(
        requester=user,
        title="still active",
        ad_type="banner_home",
        start_at=now - timedelta(hours=1),
        end_at=now + timedelta(hours=10),
        frequency="60s",
        position="normal",
        status=PromoRequestStatus.ACTIVE,
        activated_at=now - timedelta(hours=1),
    )

    out = StringIO()
    call_command("expire_promo_requests", stdout=out)

    due.refresh_from_db()
    still_active.refresh_from_db()
    assert due.status == PromoRequestStatus.EXPIRED
    assert still_active.status == PromoRequestStatus.ACTIVE
    assert "Expired promo requests: 1" in out.getvalue()
    due_ur = UnifiedRequest.objects.get(source_app="promo", source_model="PromoRequest", source_object_id=str(due.id))
    assert due_ur.status == "completed"
    assert Notification.objects.filter(user=user, kind="promo_status_change").exists()
    event = EventLog.objects.filter(target_user=user, request_id=due.id).order_by("-id").first()
    assert event is not None
    assert event.meta.get("payload", {}).get("status") == PromoRequestStatus.EXPIRED


def test_quote_updates_unified_request_quoted(user):
    pr = PromoRequest.objects.create(
        requester=user,
        title="quote me",
        ad_type="banner_home",
        start_at=timezone.now() + timedelta(days=1),
        end_at=timezone.now() + timedelta(days=3),
        frequency="60s",
        position="normal",
        status=PromoRequestStatus.NEW,
    )
    # Create initial unified record by syncing via create path equivalent.
    from apps.promo.services import _sync_promo_to_unified

    _sync_promo_to_unified(pr=pr, changed_by=user)
    PromoAsset.objects.create(
        request=pr,
        asset_type="image",
        title="asset",
        file=SimpleUploadedFile(
            "quote.png",
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
            content_type="image/png",
        ),
        uploaded_by=user,
    )

    pr = quote_and_create_invoice(pr=pr, by_user=user, quote_note="ok")
    ur = UnifiedRequest.objects.get(source_app="promo", source_model="PromoRequest", source_object_id=str(pr.id))
    assert pr.status == PromoRequestStatus.QUOTED
    assert ur.status == "new"
    assert ur.metadata_record.payload.get("invoice_id") == pr.invoice_id
    assert Notification.objects.filter(user=user, kind="promo_status_change").exists()
    event = EventLog.objects.filter(target_user=user, request_id=pr.id).order_by("-id").first()
    assert event is not None
    assert event.meta.get("payload", {}).get("status") == PromoRequestStatus.QUOTED


def test_reject_and_activate_send_promo_status_notifications(user):
    pr = PromoRequest.objects.create(
        requester=user,
        title="state flow",
        ad_type="banner_home",
        start_at=timezone.now() + timedelta(days=1),
        end_at=timezone.now() + timedelta(days=3),
        frequency="60s",
        position="normal",
        status=PromoRequestStatus.NEW,
    )
    PromoAsset.objects.create(
        request=pr,
        asset_type="image",
        title="asset",
        file=SimpleUploadedFile(
            "state.png",
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
            content_type="image/png",
        ),
        uploaded_by=user,
    )

    reject_request(pr=pr, reason="not suitable", by_user=user)
    assert Notification.objects.filter(user=user, kind="promo_status_change").exists()
    reject_event = EventLog.objects.filter(target_user=user, request_id=pr.id).order_by("-id").first()
    assert reject_event is not None
    assert reject_event.meta.get("payload", {}).get("status") == PromoRequestStatus.REJECTED

    pr = PromoRequest.objects.create(
        requester=user,
        title="activate me",
        ad_type="banner_home",
        start_at=timezone.now() - timedelta(hours=1),
        end_at=timezone.now() + timedelta(days=2),
        frequency="60s",
        position="normal",
        status=PromoRequestStatus.NEW,
    )
    PromoAsset.objects.create(
        request=pr,
        asset_type="image",
        title="asset2",
        file=SimpleUploadedFile(
            "state2.png",
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
            content_type="image/png",
        ),
        uploaded_by=user,
    )
    pr = quote_and_create_invoice(pr=pr, by_user=user, quote_note="activate")
    pr.invoice.status = "paid"
    pr.invoice.save(update_fields=["status"])
    activate_after_payment(pr=pr)
    assert Notification.objects.filter(user=user, kind="promo_status_change").exists()
    activate_event = EventLog.objects.filter(target_user=user, request_id=pr.id).order_by("-id").first()
    assert activate_event is not None
    assert activate_event.meta.get("payload", {}).get("status") == PromoRequestStatus.ACTIVE


def test_calc_quote_uses_db_price_override(user):
    PromoAdPrice.objects.update_or_create(ad_type="banner_home", defaults={"price_per_day": "123.45", "is_active": True})

    start_at = timezone.now() + timedelta(days=2)
    end_at = start_at + timedelta(days=2)
    pr = PromoRequest.objects.create(
        requester=user,
        title="priced",
        ad_type="banner_home",
        start_at=start_at,
        end_at=end_at,
        frequency="60s",
        position="normal",
        status=PromoRequestStatus.NEW,
    )

    q = calc_promo_quote(pr=pr)
    assert q["days"] == 2
    assert str(q["subtotal"]) == "246.90"


def test_calc_quote_ignores_zero_db_price(user):
    # price_per_day=0 should not accidentally override to free pricing.
    PromoAdPrice.objects.update_or_create(ad_type="banner_home", defaults={"price_per_day": "0", "is_active": True})

    start_at = timezone.now() + timedelta(days=2)
    end_at = start_at + timedelta(days=2)
    pr = PromoRequest.objects.create(
        requester=user,
        title="priced",
        ad_type="banner_home",
        start_at=start_at,
        end_at=end_at,
        frequency="60s",
        position="normal",
        status=PromoRequestStatus.NEW,
    )

    from django.conf import settings

    settings.PROMO_BASE_PRICES = {"banner_home": 300}
    settings.PROMO_POSITION_MULTIPLIER = {"normal": 1.0}
    settings.PROMO_FREQUENCY_MULTIPLIER = {"60s": 1.0}

    q = calc_promo_quote(pr=pr)
    assert q["days"] == 2
    # Falls back to default base price (300) when settings has no override.
    assert str(q["subtotal"]) == "600.00"


def test_public_active_promos_returns_targeting_and_assets(api, user):
    pp = ProviderProfile.objects.create(
        user=user,
        provider_type="company",
        display_name="متجر تجريبي",
        bio="bio",
        city="الرياض",
        years_experience=0,
    )

    now = timezone.now()
    pr_active = PromoRequest.objects.create(
        requester=user,
        title="active placement",
        ad_type="banner_home",
        start_at=now - timedelta(days=1),
        end_at=now + timedelta(days=1),
        frequency="60s",
        position="normal",
        status=PromoRequestStatus.ACTIVE,
        activated_at=now,
        target_provider=pp,
        message_title="",
        message_body="",
    )
    PromoAsset.objects.create(
        request=pr_active,
        asset_type="image",
        title="",
        file=SimpleUploadedFile(
            "banner.png",
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
            content_type="image/png",
        ),
        uploaded_by=user,
    )

    r = api.get("/api/promo/active/?ad_type=banner_home&limit=10")
    assert r.status_code == 200
    assert isinstance(r.data, list)
    assert any(item.get("id") == pr_active.id for item in r.data)
    item = next(x for x in r.data if x.get("id") == pr_active.id)
    assert item.get("target_provider_id") == pp.id
    assert isinstance(item.get("assets"), list)


def test_basic_plan_can_create_banner_promo_without_professional_controls(api, user):
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مزود بانر",
        bio="bio",
        city="الرياض",
        years_experience=0,
    )
    plan = SubscriptionPlan.objects.create(
        code="basic_promo",
        title="الأساسية",
        tier="basic",
        features=[],
        is_active=True,
    )
    Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
        end_at=timezone.now() + timedelta(days=365),
    )

    start_at = timezone.now() + timedelta(days=1)
    end_at = timezone.now() + timedelta(days=3)
    api.force_authenticate(user=user)
    response = api.post(
        "/api/promo/requests/create/",
        data={
            "title": "banner-basic",
            "ad_type": "banner_home",
            "start_at": start_at.isoformat(),
            "end_at": end_at.isoformat(),
            "frequency": "60s",
            "position": "normal",
        },
        format="json",
    )

    assert response.status_code == 201


def test_non_professional_plan_blocks_promotional_message_controls(api, user):
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مزود غير احترافي",
        bio="bio",
        city="الرياض",
        years_experience=0,
    )
    plan = SubscriptionPlan.objects.create(
        code="riyadi_promo",
        title="الريادية",
        tier="riyadi",
        features=[],
        is_active=True,
    )
    Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
        end_at=timezone.now() + timedelta(days=365),
    )

    start_at = timezone.now() + timedelta(days=1)
    end_at = timezone.now() + timedelta(days=3)
    api.force_authenticate(user=user)

    push_response = api.post(
        "/api/promo/requests/create/",
        data={
            "title": "push-not-allowed",
            "ad_type": "push_notification",
            "start_at": start_at.isoformat(),
            "end_at": end_at.isoformat(),
            "frequency": "60s",
            "position": "normal",
        },
        format="json",
    )
    assert push_response.status_code == 400
    assert "الاحترافية" in str(push_response.data)

    message_response = api.post(
        "/api/promo/requests/create/",
        data={
            "title": "message-not-allowed",
            "ad_type": "banner_home",
            "start_at": start_at.isoformat(),
            "end_at": end_at.isoformat(),
            "frequency": "60s",
            "position": "normal",
            "message_title": "عرض خاص",
            "message_body": "تفاصيل العرض",
        },
        format="json",
    )
    assert message_response.status_code == 400
    assert "الاحترافية" in str(message_response.data)


def test_professional_plan_allows_promotional_notification_controls(api, user):
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مزود احترافي",
        bio="bio",
        city="الرياض",
        years_experience=0,
    )
    plan = SubscriptionPlan.objects.create(
        code="pro_promo_controls",
        title="الاحترافية",
        tier="pro",
        features=[],
        is_active=True,
    )
    Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
        end_at=timezone.now() + timedelta(days=365),
    )

    start_at = timezone.now() + timedelta(days=1)
    end_at = timezone.now() + timedelta(days=3)
    api.force_authenticate(user=user)

    response = api.post(
        "/api/promo/requests/create/",
        data={
            "title": "push-allowed",
            "ad_type": "push_notification",
            "start_at": start_at.isoformat(),
            "end_at": end_at.isoformat(),
            "frequency": "60s",
            "position": "normal",
            "message_title": "عرض خاص",
            "message_body": "تفاصيل العرض",
        },
        format="json",
    )

    assert response.status_code == 201


def test_banner_asset_limit_uses_subscription_capability(api, user):
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مزود بانر محدود",
        bio="bio",
        city="الرياض",
        years_experience=0,
    )
    plan = SubscriptionPlan.objects.create(
        code="basic_banner_limit",
        title="الأساسية",
        tier="basic",
        features=[],
        is_active=True,
    )
    Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
        end_at=timezone.now() + timedelta(days=365),
    )
    pr = PromoRequest.objects.create(
        requester=user,
        title="banner limit",
        ad_type="banner_home",
        start_at=timezone.now() + timedelta(days=1),
        end_at=timezone.now() + timedelta(days=3),
        frequency="60s",
        position="normal",
        status=PromoRequestStatus.NEW,
    )

    api.force_authenticate(user=user)
    first_upload = api.post(
        f"/api/promo/requests/{pr.id}/assets/",
        data={
            "asset_type": "image",
            "file": SimpleUploadedFile(
                "banner1.png",
                b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
                content_type="image/png",
            ),
        },
        format="multipart",
    )
    assert first_upload.status_code == 201

    second_upload = api.post(
        f"/api/promo/requests/{pr.id}/assets/",
        data={
            "asset_type": "image",
            "file": SimpleUploadedFile(
                "banner2.png",
                b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
                content_type="image/png",
            ),
        },
        format="multipart",
    )
    assert second_upload.status_code == 400
    assert "الحد الأقصى" in str(second_upload.data.get("detail", ""))
