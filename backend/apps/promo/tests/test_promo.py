import pytest
from datetime import timedelta
from io import StringIO
from django.core.management import call_command
from django.db.models import Q
from django.test import override_settings
from rest_framework.test import APIClient
from django.core.files.uploadedfile import SimpleUploadedFile

from django.utils import timezone

from apps.accounts.models import User
from apps.backoffice.models import UserAccessProfile
from apps.backoffice.models import Dashboard
from apps.billing.models import InvoiceStatus
from apps.core.models import PlatformConfig
from apps.promo.models import HomeBanner, PromoAdType, PromoAsset, PromoOpsStatus, PromoRequest, PromoRequestItem, PromoRequestStatus, PromoServiceType
from apps.promo.models import PromoAdPrice
from apps.promo.serializers import PromoRequestCreateSerializer
from apps.notifications.models import EventLog, Notification
from apps.messaging.models import Message, Thread
from apps.providers.models import (
    Category,
    ProviderCategory,
    ProviderPortfolioItem,
    ProviderProfile,
    SubCategory,
)
from apps.subscriptions.models import (
    PlanPeriod,
    Subscription,
    SubscriptionPlan,
    SubscriptionStatus,
)
from apps.promo.services import quote_and_create_invoice
from apps.promo.services import calc_promo_quote
from apps.promo.services import (
    reject_request,
    send_due_promo_messages,
    set_promo_ops_status,
)
from apps.support.models import SupportTicket, SupportTicketType
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


def _active_pro_subscription(user, code: str):
    plan = SubscriptionPlan.objects.create(
        code=code,
        title=code,
        tier="pro",
        period=PlanPeriod.MONTH,
        price="0.00",
        notifications_enabled=True,
        promotional_chat_messages_enabled=True,
        promotional_notification_messages_enabled=True,
        is_active=True,
    )
    return Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
        end_at=timezone.now() + timedelta(days=30),
    )


def test_create_promo_request(api, user):
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مزود أساسي",
        bio="bio",
        city="الرياض",
        years_experience=1,
    )
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
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مزود مدة قصيرة",
        bio="bio",
        city="الرياض",
        years_experience=1,
    )
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
    assert active_item.get("file")
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


def test_public_home_banners_include_active_bundle_home_banner(api, user):
    pp = ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مزود بنر متعدد",
        bio="bio",
        city="الرياض",
        years_experience=0,
    )
    now = timezone.now()
    pr = PromoRequest.objects.create(
        requester=user,
        title="bundle banner",
        ad_type="bundle",
        start_at=now - timedelta(days=1),
        end_at=now + timedelta(days=1),
        frequency="60s",
        position="normal",
        status=PromoRequestStatus.ACTIVE,
        activated_at=now,
    )
    item = PromoRequestItem.objects.create(
        request=pr,
        service_type=PromoServiceType.HOME_BANNER,
        title="بنر رئيسي",
        start_at=now - timedelta(hours=2),
        end_at=now + timedelta(hours=20),
    )
    asset = PromoAsset.objects.create(
        request=pr,
        item=item,
        asset_type="image",
        title="bundle banner",
        file=SimpleUploadedFile(
            "bundle-home.png",
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
            content_type="image/png",
        ),
        uploaded_by=user,
    )

    r = api.get("/api/promo/banners/home/?limit=10")
    assert r.status_code == 200
    payload = next(row for row in r.data if row["id"] == asset.id)
    assert payload.get("provider_id") == pp.id
    assert payload.get("redirect_url") == ""


def test_public_home_carousel_includes_device_scales(api, user):
    provider = ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مزود بانر داشبورد",
        bio="bio",
        city="الرياض",
        years_experience=0,
    )
    banner = HomeBanner.objects.create(
        title="dashboard hero banner",
        media_type="image",
        media_file=SimpleUploadedFile(
            "dashboard-banner.png",
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
            content_type="image/png",
        ),
        provider=provider,
        display_order=3,
        mobile_scale=92,
        tablet_scale=108,
        desktop_scale=128,
        is_active=True,
        created_by=user,
    )

    response = api.get("/api/promo/home-carousel/?limit=10")

    assert response.status_code == 200
    payload = next(row for row in response.data if row["id"] == banner.id)
    assert payload["mobile_scale"] == 92
    assert payload["tablet_scale"] == 108
    assert payload["desktop_scale"] == 128
    assert payload["provider_id"] == provider.id


def test_public_home_banner_queryset_excludes_message_delivery_columns():
    from apps.promo.views import _public_home_banner_asset_queryset

    sql = str(_public_home_banner_asset_queryset(now=timezone.now()).query).lower()

    assert "message_sent_at" not in sql
    assert "message_recipients_count" not in sql
    assert "message_dispatch_error" not in sql


def test_invoice_paid_signal_activates_home_banner_and_exposes_it_publicly(api, user):
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مزود بعد الدفع",
        bio="bio",
        city="الرياض",
        years_experience=0,
    )
    PromoAdPrice.objects.update_or_create(
        ad_type=PromoAdType.BANNER_HOME,
        defaults={"price_per_day": "100.00", "is_active": True},
    )
    now = timezone.now()
    pr = PromoRequest.objects.create(
        requester=user,
        title="home banner after payment",
        ad_type=PromoAdType.BANNER_HOME,
        start_at=now - timedelta(hours=1),
        end_at=now + timedelta(days=2),
        frequency="60s",
        position="normal",
        status=PromoRequestStatus.NEW,
    )
    asset = PromoAsset.objects.create(
        request=pr,
        asset_type="image",
        title="paid-banner",
        file=SimpleUploadedFile(
            "paid-banner.png",
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
            content_type="image/png",
        ),
        uploaded_by=user,
    )

    pr = quote_and_create_invoice(pr=pr, by_user=user, quote_note="approve and pay")
    assert pr.status == PromoRequestStatus.PENDING_PAYMENT
    assert pr.invoice is not None
    assert pr.invoice.total > 0

    pr.invoice.mark_payment_confirmed(
        provider="mock",
        provider_reference="promo_ref_paid_banner",
        event_id="evt-promo-paid-banner",
        amount=pr.invoice.total,
        currency=pr.invoice.currency,
    )
    pr.invoice.save(
        update_fields=[
            "status",
            "paid_at",
            "cancelled_at",
            "payment_confirmed",
            "payment_confirmed_at",
            "payment_provider",
            "payment_reference",
            "payment_event_id",
            "payment_amount",
            "payment_currency",
            "updated_at",
        ]
    )
    pr.refresh_from_db()

    assert pr.status == PromoRequestStatus.ACTIVE
    assert pr.activated_at is not None

    response = api.get("/api/promo/banners/home/?limit=10")
    assert response.status_code == 200
    payload = next(row for row in response.data if row["id"] == asset.id)
    assert payload["provider_display_name"] == "مزود بعد الدفع"
    assert payload["caption"] == "paid-banner"


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
    assert due_ur.status == "expired"
    assert Notification.objects.filter(user=user, kind="promo_status_change").exists()
    event = EventLog.objects.filter(target_user=user, request_id=due.id).order_by("-id").first()
    assert event is not None
    assert event.meta.get("payload", {}).get("status") == PromoRequestStatus.EXPIRED


def test_quote_updates_unified_request_pending_payment(user):
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
    assert pr.status == PromoRequestStatus.PENDING_PAYMENT
    assert ur.status == "pending_payment"
    assert ur.metadata_record.payload.get("invoice_id") == pr.invoice_id
    assert Notification.objects.filter(user=user, kind="promo_status_change").exists()
    event = EventLog.objects.filter(target_user=user, request_id=pr.id).order_by("-id").first()
    assert event is not None
    assert event.meta.get("payload", {}).get("status") == PromoRequestStatus.PENDING_PAYMENT


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
    pr.invoice.mark_payment_confirmed(
        provider="mock",
        provider_reference="promo_ref_activate",
        event_id="evt-promo-activate",
        amount=pr.invoice.total,
        currency=pr.invoice.currency,
    )
    pr.invoice.save(
        update_fields=[
            "status",
            "paid_at",
            "cancelled_at",
            "payment_confirmed",
            "payment_confirmed_at",
            "payment_provider",
            "payment_reference",
            "payment_event_id",
            "payment_amount",
            "payment_currency",
            "updated_at",
        ]
    )
    pr.refresh_from_db()
    assert Notification.objects.filter(user=user, kind="promo_status_change").exists()
    activate_event = EventLog.objects.filter(target_user=user, request_id=pr.id).order_by("-id").first()
    assert activate_event is not None
    assert activate_event.meta.get("payload", {}).get("status") == PromoRequestStatus.ACTIVE


def test_ops_completion_does_not_end_active_home_banner_campaign(api, user):
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مزود بانر",
        bio="bio",
        city="الرياض",
        years_experience=0,
    )
    now = timezone.now()
    pr = PromoRequest.objects.create(
        requester=user,
        title="بنر الصفحة الرئيسية",
        ad_type="banner_home",
        start_at=now - timedelta(hours=1),
        end_at=now + timedelta(days=2),
        frequency="60s",
        position="normal",
        status=PromoRequestStatus.ACTIVE,
        ops_status=PromoOpsStatus.IN_PROGRESS,
        activated_at=now - timedelta(hours=1),
    )
    asset = PromoAsset.objects.create(
        request=pr,
        asset_type="image",
        title="banner asset",
        file=SimpleUploadedFile(
            "home-banner.png",
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
            content_type="image/png",
        ),
        uploaded_by=user,
    )

    set_promo_ops_status(pr=pr, new_status=PromoOpsStatus.COMPLETED, by_user=user)
    pr.refresh_from_db()

    assert pr.ops_status == PromoOpsStatus.COMPLETED
    assert pr.status == PromoRequestStatus.ACTIVE

    response = api.get("/api/promo/banners/home/?limit=10")
    assert response.status_code == 200
    assert any(item["id"] == asset.id for item in response.data)


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

    config = PlatformConfig.load()
    config.promo_base_prices = {"banner_home": 300}
    config.promo_position_multipliers = {"normal": 1.0}
    config.promo_frequency_multipliers = {"60s": 1.0}
    config.save()

    q = calc_promo_quote(pr=pr)
    assert q["days"] == 2
    # Falls back to default base price (300) when settings has no override.
    assert str(q["subtotal"]) == "600.00"


def test_promo_item_validation_uses_platform_config_min_campaign_hours(user):
    config = PlatformConfig.load()
    config.promo_min_campaign_hours = 48
    config.save()

    start_at = timezone.now() + timedelta(days=2)
    end_at = start_at + timedelta(hours=24)

    request_stub = type("RequestStub", (), {"user": user})()
    serializer = PromoRequestCreateSerializer(
        data={
            "title": "طلب متعدد",
            "items": [
                {
                    "service_type": PromoServiceType.HOME_BANNER,
                    "start_at": start_at.isoformat(),
                    "end_at": end_at.isoformat(),
                }
            ],
        },
        context={"request": request_stub},
    )

    assert serializer.is_valid() is False
    assert "48 ساعة" in str(serializer.errors)


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


def test_public_active_promos_returns_item_based_featured_placements(api, user):
    pp = ProviderProfile.objects.create(
        user=user,
        provider_type="company",
        display_name="مختص مميز",
        bio="bio",
        city="الرياض",
        years_experience=0,
    )
    now = timezone.now()
    pr = PromoRequest.objects.create(
        requester=user,
        title="featured bundle",
        ad_type="bundle",
        start_at=now - timedelta(days=1),
        end_at=now + timedelta(days=1),
        frequency="60s",
        position="normal",
        status=PromoRequestStatus.ACTIVE,
        activated_at=now,
    )
    item = PromoRequestItem.objects.create(
        request=pr,
        service_type=PromoServiceType.FEATURED_SPECIALISTS,
        title="شريط أبرز المختصين",
        start_at=now - timedelta(hours=2),
        end_at=now + timedelta(hours=20),
        frequency="60s",
    )

    service_r = api.get("/api/promo/active/?service_type=featured_specialists&limit=10")
    assert service_r.status_code == 200
    service_item = next(row for row in service_r.data if row.get("item_id") == item.id)
    assert service_item.get("target_provider_id") == pp.id
    assert service_item.get("service_type") == PromoServiceType.FEATURED_SPECIALISTS

    legacy_r = api.get("/api/promo/active/?ad_type=featured_top5&limit=10")
    assert legacy_r.status_code == 200
    assert any(row.get("item_id") == item.id for row in legacy_r.data)


def test_public_active_bundle_item_queryset_excludes_message_delivery_columns():
    from apps.promo.views import _public_active_bundle_item_queryset

    sql = str(_public_active_bundle_item_queryset().query).lower()

    assert "message_sent_at" not in sql
    assert "message_recipients_count" not in sql
    assert "message_dispatch_error" not in sql


def test_public_active_promos_orders_search_result_items_by_position(api, user):
    ProviderProfile.objects.create(
        user=user,
        provider_type="company",
        display_name="مزود بحث",
        bio="bio",
        city="الرياض",
        years_experience=0,
    )
    now = timezone.now()
    pr = PromoRequest.objects.create(
        requester=user,
        title="search bundle",
        ad_type="bundle",
        start_at=now - timedelta(days=1),
        end_at=now + timedelta(days=1),
        frequency="60s",
        position="normal",
        status=PromoRequestStatus.ACTIVE,
        activated_at=now,
    )
    top10_item = PromoRequestItem.objects.create(
        request=pr,
        service_type=PromoServiceType.SEARCH_RESULTS,
        title="top10",
        start_at=now - timedelta(hours=2),
        end_at=now + timedelta(hours=20),
        search_scope="main_results",
        search_position="top10",
        sort_order=20,
    )
    first_item = PromoRequestItem.objects.create(
        request=pr,
        service_type=PromoServiceType.SEARCH_RESULTS,
        title="first",
        start_at=now - timedelta(hours=2),
        end_at=now + timedelta(hours=20),
        search_scope="main_results",
        search_position="first",
        sort_order=10,
    )

    r = api.get("/api/promo/active/?service_type=search_results&limit=10")
    assert r.status_code == 200
    item_ids = [row.get("item_id") for row in r.data]
    assert item_ids[:2] == [first_item.id, top10_item.id]


def test_public_active_promos_return_portfolio_showcase_payload(api, user):
    provider = ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="استوديو ممول",
        bio="bio",
        city="الرياض",
        years_experience=3,
    )
    portfolio = ProviderPortfolioItem.objects.create(
        provider=provider,
        file_type="image",
        file=SimpleUploadedFile(
            "portfolio_showcase.png",
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
            content_type="image/png",
        ),
        caption="مشروع ممول",
    )
    now = timezone.now()
    pr = PromoRequest.objects.create(
        requester=user,
        title="شريط معرض الأعمال",
        ad_type="bundle",
        start_at=now - timedelta(hours=2),
        end_at=now + timedelta(days=2),
        frequency="60s",
        position="normal",
        status=PromoRequestStatus.ACTIVE,
    )
    PromoRequestItem.objects.create(
        request=pr,
        service_type=PromoServiceType.PORTFOLIO_SHOWCASE,
        title="معرض ممول",
        start_at=now - timedelta(hours=1),
        end_at=now + timedelta(days=1),
        frequency="60s",
        target_provider=provider,
        sort_order=10,
    )

    response = api.get("/api/promo/active/?service_type=portfolio_showcase&limit=10")

    assert response.status_code == 200
    payload = response.json()
    assert len(payload) == 1
    assert payload[0]["service_type"] == PromoServiceType.PORTFOLIO_SHOWCASE
    assert payload[0]["portfolio_item"]["id"] == portfolio.id
    assert payload[0]["portfolio_item"]["caption"] == "مشروع ممول"
    assert payload[0]["portfolio_item"]["file_url"]


def test_send_due_promo_messages_dispatches_campaign_once():
    sender = User.objects.create_user(
        phone="0501111111",
        password="Pass12345!",
        role_state="provider",
    )
    recipient = User.objects.create_user(
        phone="0502222222",
        password="Pass12345!",
        role_state="provider",
    )
    other_recipient = User.objects.create_user(
        phone="0503333333",
        password="Pass12345!",
        role_state="provider",
    )
    _active_pro_subscription(sender, "PROMO_SENDER")
    _active_pro_subscription(recipient, "PROMO_RECIPIENT")
    _active_pro_subscription(other_recipient, "PROMO_OTHER")

    ProviderProfile.objects.create(
        user=sender,
        provider_type="individual",
        display_name="مرسل الحملة",
        bio="bio",
        city="الرياض",
        years_experience=5,
    )
    recipient_provider = ProviderProfile.objects.create(
        user=recipient,
        provider_type="individual",
        display_name="مستلم مطابق",
        bio="bio",
        city="الرياض",
        years_experience=2,
    )
    other_provider = ProviderProfile.objects.create(
        user=other_recipient,
        provider_type="individual",
        display_name="مستلم غير مطابق",
        bio="bio",
        city="جدة",
        years_experience=2,
    )
    category = Category.objects.create(name="تصميم", is_active=True)
    subcategory = SubCategory.objects.create(
        category=category,
        name="تصميم داخلي",
        is_active=True,
    )
    ProviderCategory.objects.create(provider=recipient_provider, subcategory=subcategory)
    ProviderCategory.objects.create(provider=other_provider, subcategory=subcategory)

    now = timezone.now()
    request = PromoRequest.objects.create(
        requester=sender,
        title="حملة رسائل دعائية",
        ad_type="bundle",
        start_at=now - timedelta(hours=2),
        end_at=now + timedelta(days=2),
        frequency="60s",
        position="normal",
        status=PromoRequestStatus.ACTIVE,
    )
    item = PromoRequestItem.objects.create(
        request=request,
        service_type=PromoServiceType.PROMO_MESSAGES,
        title="رسائل دعائية",
        send_at=now - timedelta(minutes=5),
        message_title="عرض احترافي",
        message_body="تفاصيل العرض الممول",
        use_notification_channel=True,
        use_chat_channel=True,
        target_city="الرياض",
        target_category="تصميم داخلي",
        sort_order=10,
    )
    PromoAsset.objects.create(
        request=request,
        item=item,
        asset_type="image",
        title="creative",
        file=SimpleUploadedFile(
            "promo_message_asset.png",
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
            content_type="image/png",
        ),
        uploaded_by=sender,
    )

    count = send_due_promo_messages(now=now, limit=10)

    assert count == 1
    item.refresh_from_db()
    assert item.message_sent_at is not None
    assert item.message_recipients_count == 1
    assert item.message_dispatch_error == ""
    assert Notification.objects.filter(user=recipient, title="عرض احترافي").exists()
    assert not Notification.objects.filter(user=other_recipient, title="عرض احترافي").exists()

    thread = (
        Thread.objects.filter(is_direct=True, context_mode=Thread.ContextMode.PROVIDER)
        .filter(
            Q(participant_1=sender, participant_2=recipient)
            | Q(participant_1=recipient, participant_2=sender)
        )
        .first()
    )
    assert thread is not None
    assert Message.objects.filter(
        thread=thread,
        sender=sender,
        body="تفاصيل العرض الممول",
    ).exists()
    assert Message.objects.filter(thread=thread, sender=sender).exclude(attachment="").exists()

    second_count = send_due_promo_messages(now=now + timedelta(minutes=1), limit=10)
    assert second_count == 0


def test_send_due_promo_messages_dispatches_legacy_push_request_once():
    sender = User.objects.create_user(
        phone="0504444441",
        password="Pass12345!",
        role_state="provider",
    )
    recipient = User.objects.create_user(
        phone="0504444442",
        password="Pass12345!",
        role_state="provider",
    )
    _active_pro_subscription(sender, "LEGACY_PUSH_SENDER")
    _active_pro_subscription(recipient, "LEGACY_PUSH_RECIPIENT")

    ProviderProfile.objects.create(
        user=sender,
        provider_type="individual",
        display_name="مرسل إشعار مباشر",
        bio="bio",
        city="الرياض",
        years_experience=5,
    )
    ProviderProfile.objects.create(
        user=recipient,
        provider_type="individual",
        display_name="مستلم الإشعار",
        bio="bio",
        city="الرياض",
        years_experience=2,
    )

    now = timezone.now()
    request = PromoRequest.objects.create(
        requester=sender,
        title="إشعار مباشر",
        ad_type=PromoAdType.PUSH_NOTIFICATION,
        start_at=now - timedelta(minutes=10),
        end_at=now + timedelta(days=1),
        frequency="60s",
        position="normal",
        status=PromoRequestStatus.ACTIVE,
        message_title="عرض فوري",
        message_body="تفاصيل العرض السريع",
    )
    item = PromoRequestItem.objects.create(
        request=request,
        service_type=PromoServiceType.PROMO_MESSAGES,
        title="إشعار مباشر",
        send_at=now - timedelta(minutes=5),
        message_title="عرض فوري",
        message_body="تفاصيل العرض السريع",
        use_notification_channel=True,
        use_chat_channel=False,
        target_city="الرياض",
        sort_order=0,
    )

    count = send_due_promo_messages(now=now, limit=10)

    assert count == 1
    item.refresh_from_db()
    assert item.message_sent_at is not None
    assert item.message_recipients_count == 1
    assert Notification.objects.filter(user=recipient, title="عرض فوري").exists()


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

    notification_response = api.post(
        "/api/promo/requests/create/",
        data={
            "title": "promo-message-notification",
            "items": [
                {
                    "service_type": "promo_messages",
                    "title": "رسالة دعائية",
                    "send_at": start_at.isoformat(),
                    "message_body": "تفاصيل العرض",
                    "use_notification_channel": True,
                    "use_chat_channel": False,
                }
            ],
        },
        format="json",
    )
    assert notification_response.status_code == 400
    assert "الاحترافية" in str(notification_response.data)

    chat_response = api.post(
        "/api/promo/requests/create/",
        data={
            "title": "promo-message-chat",
            "items": [
                {
                    "service_type": "promo_messages",
                    "title": "رسالة دعائية",
                    "send_at": end_at.isoformat(),
                    "message_body": "تفاصيل العرض",
                    "use_notification_channel": False,
                    "use_chat_channel": True,
                }
            ],
        },
        format="json",
    )
    assert chat_response.status_code == 400
    assert "الاحترافية" in str(chat_response.data)


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
    api.force_authenticate(user=user)

    response = api.post(
        "/api/promo/requests/create/",
        data={
            "title": "push-allowed",
            "items": [
                {
                    "service_type": "promo_messages",
                    "title": "رسالة دعائية",
                    "send_at": start_at.isoformat(),
                    "message_title": "عرض خاص",
                    "message_body": "تفاصيل العرض",
                    "use_notification_channel": True,
                    "use_chat_channel": True,
                }
            ],
        },
        format="json",
    )

    assert response.status_code == 201
    pr = PromoRequest.objects.get(pk=response.data["id"])
    assert pr.ad_type == PromoAdType.BUNDLE
    item = pr.items.get()
    assert item.service_type == PromoServiceType.PROMO_MESSAGES
    assert item.use_notification_channel is True
    assert item.use_chat_channel is True


def test_push_notification_request_creates_dispatchable_item(api, user):
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مزود إشعار مباشر",
        bio="bio",
        city="الرياض",
        years_experience=1,
    )
    plan = SubscriptionPlan.objects.create(
        code="pro_legacy_push",
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
    end_at = start_at + timedelta(days=2)
    api.force_authenticate(user=user)
    response = api.post(
        "/api/promo/requests/create/",
        data={
            "title": "إشعار مباشر",
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
    pr = PromoRequest.objects.get(pk=response.data["id"])
    item = pr.items.get()
    assert item.service_type == PromoServiceType.PROMO_MESSAGES
    assert item.send_at == pr.start_at
    assert item.use_notification_channel is True
    assert item.use_chat_channel is False


def test_provider_profile_required_for_promo_request_creation(api, user):
    start_at = timezone.now() + timedelta(days=1)
    end_at = start_at + timedelta(days=2)
    api.force_authenticate(user=user)

    response = api.post(
        "/api/promo/requests/create/",
        data={
            "title": "طلب غير مصرح",
            "ad_type": "banner_home",
            "start_at": start_at.isoformat(),
            "end_at": end_at.isoformat(),
            "frequency": "60s",
            "position": "normal",
        },
        format="json",
    )

    assert response.status_code == 403


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


def test_create_multi_item_promo_request(api, user):
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مزود متعدد الخدمات",
        bio="bio",
        city="الرياض",
        years_experience=3,
    )
    plan = SubscriptionPlan.objects.create(code="PRO_MULTI", title="Pro", tier="pro", features=[], is_active=True)
    Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
        end_at=timezone.now() + timedelta(days=365),
    )
    api.force_authenticate(user=user)
    start_at = timezone.now() + timedelta(days=1)
    end_at = start_at + timedelta(days=1)

    response = api.post(
        "/api/promo/requests/create/",
        data={
            "title": "طلب ترويج شامل",
            "items": [
                {
                    "service_type": "home_banner",
                    "title": "بنر الرئيسية",
                    "start_at": start_at.isoformat(),
                    "end_at": end_at.isoformat(),
                },
                {
                    "service_type": "search_results",
                    "title": "ظهور في البحث",
                    "start_at": start_at.isoformat(),
                    "end_at": end_at.isoformat(),
                    "search_scope": "main_results",
                    "search_position": "top10",
                },
            ],
        },
        format="json",
    )

    assert response.status_code == 201
    pr = PromoRequest.objects.get(pk=response.data["id"])
    assert pr.ad_type == "bundle"
    assert pr.ops_status == PromoOpsStatus.NEW
    assert pr.items.count() == 2


def test_quote_multi_item_request_creates_invoice_lines(user):
    start_at = timezone.now() + timedelta(days=2)
    end_at = start_at + timedelta(days=1)
    pr = PromoRequest.objects.create(
        requester=user,
        title="طلب متعدد",
        ad_type="bundle",
        start_at=start_at,
        end_at=end_at,
        frequency="60s",
        position="normal",
        status=PromoRequestStatus.NEW,
    )
    banner_item = PromoRequestItem.objects.create(
        request=pr,
        service_type=PromoServiceType.HOME_BANNER,
        title="بنر الرئيسية",
        start_at=start_at,
        end_at=end_at,
        sort_order=10,
    )
    PromoRequestItem.objects.create(
        request=pr,
        service_type=PromoServiceType.SEARCH_RESULTS,
        title="بحث",
        start_at=start_at,
        end_at=end_at,
        search_scope="main_results",
        search_position="top10",
        sort_order=20,
    )
    PromoAsset.objects.create(
        request=pr,
        item=banner_item,
        asset_type="image",
        title="banner",
        file=SimpleUploadedFile(
            "bundle.png",
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
            content_type="image/png",
        ),
        uploaded_by=user,
    )

    pr = quote_and_create_invoice(pr=pr, by_user=user, quote_note="bundle")
    pr.refresh_from_db()

    assert pr.status == PromoRequestStatus.PENDING_PAYMENT
    assert pr.invoice is not None
    assert pr.invoice.lines.count() == 2
    assert str(pr.subtotal) == "2200.00"
    assert str(pr.invoice.vat_amount) == "330.00"
    assert str(pr.invoice.total) == "2530.00"


def test_preview_multi_item_request_returns_expected_pricing(api, user):
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="مزود معاينة",
        bio="bio",
        city="الرياض",
        years_experience=0,
    )
    plan = SubscriptionPlan.objects.create(code="PRO_PREVIEW", title="Pro", tier="pro", features=[], is_active=True)
    Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
        end_at=timezone.now() + timedelta(days=365),
    )
    api.force_authenticate(user=user)
    start_at = timezone.now() + timedelta(days=2)
    end_at = start_at + timedelta(days=1)

    response = api.post(
        "/api/promo/requests/preview/",
        data={
            "title": "معاينة طلب متعدد",
            "items": [
                {
                    "service_type": "home_banner",
                    "title": "بنر الرئيسية",
                    "start_at": start_at.isoformat(),
                    "end_at": end_at.isoformat(),
                    "asset_count": 1,
                },
                {
                    "service_type": "search_results",
                    "title": "بحث",
                    "start_at": start_at.isoformat(),
                    "end_at": end_at.isoformat(),
                    "search_scope": "main_results",
                    "search_position": "top10",
                },
            ],
        },
        format="json",
    )

    assert response.status_code == 200
    assert response.data["currency"] == "SAR"
    assert str(response.data["subtotal"]) == "2200.00"
    assert str(response.data["vat_amount"]) == "330.00"
    assert str(response.data["total"]) == "2530.00"
    assert len(response.data["items"]) == 2


def test_promo_signal_ignores_unconfirmed_paid_invoice(user):
    now = timezone.now()
    pr = PromoRequest.objects.create(
        requester=user,
        title="requires confirmation",
        ad_type=PromoAdType.BANNER_HOME,
        start_at=now - timedelta(hours=1),
        end_at=now + timedelta(days=2),
        frequency="60s",
        position="normal",
        status=PromoRequestStatus.NEW,
    )
    PromoAsset.objects.create(
        request=pr,
        asset_type="image",
        title="asset",
        file=SimpleUploadedFile(
            "confirm.png",
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
            content_type="image/png",
        ),
        uploaded_by=user,
    )

    pr = quote_and_create_invoice(pr=pr, by_user=user, quote_note="requires payment")
    assert pr.status == PromoRequestStatus.PENDING_PAYMENT

    pr.invoice.status = InvoiceStatus.PAID
    pr.invoice.save(update_fields=["status"])
    pr.refresh_from_db()

    assert pr.status == PromoRequestStatus.PENDING_PAYMENT
    assert pr.activated_at is None


@override_settings(BILLING_WEBHOOK_SECRETS={"mock": "promo-secret"})
def test_complete_mock_payment_endpoint_activates_promo(api, user):
    now = timezone.now()
    pr = PromoRequest.objects.create(
        requester=user,
        title="mock payment promo",
        ad_type=PromoAdType.BANNER_HOME,
        start_at=now - timedelta(hours=1),
        end_at=now + timedelta(days=2),
        frequency="60s",
        position="normal",
        status=PromoRequestStatus.NEW,
    )
    PromoAsset.objects.create(
        request=pr,
        asset_type="image",
        title="asset",
        file=SimpleUploadedFile(
            "mockpay.png",
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89",
            content_type="image/png",
        ),
        uploaded_by=user,
    )
    pr = quote_and_create_invoice(pr=pr, by_user=user, quote_note="mock pay")
    api.force_authenticate(user=user)

    response = api.post(
        f"/api/billing/invoices/{pr.invoice_id}/complete-mock-payment/",
        data={"idempotency_key": f"promo-{pr.invoice_id}"},
        format="json",
    )

    assert response.status_code == 200
    pr.refresh_from_db()
    pr.invoice.refresh_from_db()
    assert pr.invoice.payment_confirmed is True
    assert pr.status == PromoRequestStatus.ACTIVE


def test_promo_dashboard_pages_render(client, promo_operator_user, user):
    start_at = timezone.now() + timedelta(days=2)
    end_at = start_at + timedelta(days=1)
    pr = PromoRequest.objects.create(
        requester=user,
        title="dashboard promo",
        ad_type="bundle",
        start_at=start_at,
        end_at=end_at,
        frequency="60s",
        position="normal",
        status=PromoRequestStatus.NEW,
    )
    PromoRequestItem.objects.create(
        request=pr,
        service_type=PromoServiceType.HOME_BANNER,
        title="dashboard banner",
        start_at=start_at,
        end_at=end_at,
    )
    SupportTicket.objects.create(
        requester=user,
        ticket_type=SupportTicketType.ADS,
        description="أحتاج حملة ترويج",
    )

    client.force_login(promo_operator_user)
    session = client.session
    session["dashboard_otp_verified"] = True
    session.save()

    assert client.get("/dashboard/promo/").status_code == 200
    assert client.get(f"/dashboard/promo/{pr.id}/").status_code == 200
    assert client.get("/dashboard/promo/modules/home_banner/").status_code == 200
