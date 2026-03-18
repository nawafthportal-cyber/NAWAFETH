from __future__ import annotations

from datetime import datetime, time, timedelta
from decimal import Decimal

import pytest
from django.test import Client, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.analytics.models import CampaignDailyStats, ExtrasDailyStats, ProviderDailyStats, SubscriptionDailyStats
from apps.analytics.services import rebuild_daily_analytics
from apps.analytics.tasks import rebuild_daily_stats_task
from apps.backoffice.models import AccessLevel, Dashboard, UserAccessProfile
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.extras.models import ExtraPurchase, ExtraPurchaseStatus, ExtraType
from apps.marketplace.models import RequestStatusLog, ServiceRequest
from apps.providers.models import Category, ProviderCategory, ProviderProfile, SubCategory
from apps.subscriptions.models import PlanPeriod, Subscription, SubscriptionPlan, SubscriptionStatus
from apps.analytics.tracking import track_event


pytestmark = pytest.mark.django_db


def _aware(day, hour: int):
    return timezone.make_aware(datetime.combine(day, time(hour=hour)), timezone.get_current_timezone())


@pytest.fixture
def api():
    return APIClient()


@pytest.fixture
def day():
    return timezone.localdate()


@pytest.fixture
def admin_user():
    user = User.objects.create_user(phone="0503000001", password="Pass12345!", is_staff=True)
    UserAccessProfile.objects.create(user=user, level=AccessLevel.ADMIN)
    return user


@pytest.fixture
def dashboard_client(admin_user):
    analytics_dashboard, _ = Dashboard.objects.get_or_create(code="analytics", defaults={"name_ar": "التحليلات", "sort_order": 5})
    admin_user.access_profile.allowed_dashboards.add(analytics_dashboard)
    client = Client()
    assert client.login(phone=admin_user.phone, password="Pass12345!")
    session = client.session
    session[SESSION_OTP_VERIFIED_KEY] = True
    session.save()
    return client


@override_settings(FEATURE_ANALYTICS_EVENTS=True, FEATURE_ANALYTICS_KPI_SURFACES=True)
def test_rebuild_daily_analytics_creates_aggregate_rows(day):
    category = Category.objects.create(name="تصميم", is_active=True)
    subcategory = SubCategory.objects.create(category=category, name="هوية", is_active=True)
    client_user = User.objects.create_user(phone="0503000002", password="Pass12345!")
    provider_user = User.objects.create_user(phone="0503000003", password="Pass12345!")
    provider = ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود KPI",
        bio="bio",
        city="الرياض",
        years_experience=2,
    )
    ProviderCategory.objects.create(provider=provider, subcategory=subcategory)

    request_obj = ServiceRequest.objects.create(
        client=client_user,
        provider=provider,
        subcategory=subcategory,
        title="طلب",
        description="تفاصيل",
        request_type="normal",
        city="الرياض",
    )
    ServiceRequest.objects.filter(id=request_obj.id).update(created_at=_aware(day, 9))
    accept_log = RequestStatusLog.objects.create(
        request=request_obj,
        actor=provider_user,
        from_status="new",
        to_status="in_progress",
        note="accepted",
    )
    complete_log = RequestStatusLog.objects.create(
        request=request_obj,
        actor=provider_user,
        from_status="in_progress",
        to_status="completed",
        note="done",
    )
    RequestStatusLog.objects.filter(id=accept_log.id).update(created_at=_aware(day, 10))
    RequestStatusLog.objects.filter(id=complete_log.id).update(created_at=_aware(day, 11))

    basic_plan = SubscriptionPlan.objects.create(
        code="BASIC-AGG",
        title="Basic",
        tier="basic",
        period=PlanPeriod.MONTH,
        price=Decimal("0.00"),
    )
    pro_plan = SubscriptionPlan.objects.create(
        code="PRO-AGG",
        title="Pro",
        tier="pro",
        period=PlanPeriod.MONTH,
        price=Decimal("99.00"),
    )
    Subscription.objects.create(
        user=provider_user,
        plan=basic_plan,
        status=SubscriptionStatus.CANCELLED,
        start_at=_aware(day - timedelta(days=35), 8),
        end_at=_aware(day - timedelta(days=5), 8),
    )
    active_subscription = Subscription.objects.create(
        user=provider_user,
        plan=pro_plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=_aware(day, 8),
        end_at=_aware(day + timedelta(days=30), 8),
    )

    cancelled_subscription = Subscription.objects.create(
        user=client_user,
        plan=pro_plan,
        status=SubscriptionStatus.CANCELLED,
        start_at=_aware(day - timedelta(days=10), 8),
        end_at=_aware(day + timedelta(days=20), 8),
    )
    Subscription.objects.filter(id=cancelled_subscription.id).update(updated_at=_aware(day, 15))

    purchase = ExtraPurchase.objects.create(
        user=client_user,
        sku="tickets_2",
        title="تذاكر",
        extra_type=ExtraType.CREDIT_BASED,
        subtotal=Decimal("10.00"),
        currency="SAR",
        credits_total=2,
        credits_used=1,
        status=ExtraPurchaseStatus.ACTIVE,
    )

    track_event(
        event_name="provider.profile_view",
        channel="mobile_web",
        surface="provider.detail",
        source_app="providers",
        object_type="ProviderProfile",
        object_id=str(provider.id),
        actor=client_user,
        dedupe_key=f"provider.profile_view:test:{provider.id}",
        occurred_at=_aware(day, 9),
    )
    track_event(
        event_name="messaging.direct_thread_created",
        channel="server",
        surface="messaging.direct",
        source_app="messaging",
        object_type="Thread",
        object_id="101",
        actor=client_user,
        dedupe_key="messaging.direct_thread_created:test:101",
        occurred_at=_aware(day, 10),
        payload={"provider_profile_id": provider.id},
    )
    track_event(
        event_name="promo.banner_impression",
        channel="flutter",
        surface="home.banner",
        source_app="promo",
        object_type="ProviderProfile",
        object_id=str(provider.id),
        dedupe_key="promo.banner_impression:test:44",
        occurred_at=_aware(day, 10),
        payload={"banner_id": 44, "title": "بنر رئيسي"},
    )
    track_event(
        event_name="promo.banner_click",
        channel="flutter",
        surface="home.banner",
        source_app="promo",
        object_type="ProviderProfile",
        object_id=str(provider.id),
        dedupe_key="promo.banner_click:test:44",
        occurred_at=_aware(day, 10),
        payload={"banner_id": 44, "title": "بنر رئيسي"},
    )
    track_event(
        event_name="subscriptions.checkout_created",
        channel="server",
        surface="subscriptions.checkout",
        source_app="subscriptions",
        object_type="Subscription",
        object_id=str(active_subscription.id),
        dedupe_key=f"subscriptions.checkout_created:test:{active_subscription.id}",
        occurred_at=_aware(day, 11),
        payload={"plan_code": pro_plan.code, "plan_title": pro_plan.title, "tier": pro_plan.tier},
    )
    track_event(
        event_name="subscriptions.activated",
        channel="server",
        surface="subscriptions.activate",
        source_app="subscriptions",
        object_type="Subscription",
        object_id=str(active_subscription.id),
        dedupe_key=f"subscriptions.activated:test:{active_subscription.id}",
        occurred_at=_aware(day, 11),
        payload={"plan_code": pro_plan.code, "plan_title": pro_plan.title, "tier": pro_plan.tier},
    )
    track_event(
        event_name="extras.checkout_created",
        channel="server",
        surface="extras.checkout",
        source_app="extras",
        object_type="ExtraPurchase",
        object_id=str(purchase.id),
        dedupe_key=f"extras.checkout_created:test:{purchase.id}",
        occurred_at=_aware(day, 12),
        payload={"sku": purchase.sku, "title": purchase.title, "extra_type": purchase.extra_type},
    )
    track_event(
        event_name="extras.activated",
        channel="server",
        surface="extras.activate",
        source_app="extras",
        object_type="ExtraPurchase",
        object_id=str(purchase.id),
        dedupe_key=f"extras.activated:test:{purchase.id}",
        occurred_at=_aware(day, 12),
        payload={"sku": purchase.sku, "title": purchase.title, "extra_type": purchase.extra_type},
    )
    track_event(
        event_name="extras.credit_consumed",
        channel="server",
        surface="extras.consume",
        source_app="extras",
        object_type="ExtraPurchase",
        object_id=str(purchase.id),
        dedupe_key=f"extras.credit_consumed:test:{purchase.id}",
        occurred_at=_aware(day, 13),
        payload={"sku": purchase.sku, "title": purchase.title, "extra_type": purchase.extra_type, "amount": 1},
    )

    result = rebuild_daily_analytics(day)

    provider_stats = ProviderDailyStats.objects.get(day=day, provider=provider)
    campaign_stats = CampaignDailyStats.objects.get(day=day, campaign_key="banner:44")
    subscription_stats = SubscriptionDailyStats.objects.get(day=day, plan_code=pro_plan.code)
    extras_stats = ExtrasDailyStats.objects.get(day=day, sku=purchase.sku)

    assert result["provider_rows"] >= 1
    assert provider_stats.profile_views == 1
    assert provider_stats.chat_starts == 1
    assert provider_stats.requests_received == 1
    assert provider_stats.requests_accepted == 1
    assert provider_stats.requests_completed == 1
    assert float(provider_stats.accept_rate) == 100.0
    assert float(provider_stats.completion_rate) == 100.0

    assert campaign_stats.impressions == 1
    assert campaign_stats.clicks == 1
    assert campaign_stats.leads == 1
    assert float(campaign_stats.ctr) == 100.0

    assert subscription_stats.checkouts_started == 1
    assert subscription_stats.activations == 1
    assert subscription_stats.upgrades == 1
    assert subscription_stats.churns == 1

    assert extras_stats.purchases == 1
    assert extras_stats.activations == 1
    assert extras_stats.consumptions == 1
    assert extras_stats.credits_consumed == 1


@override_settings(FEATURE_ANALYTICS_EVENTS=True, FEATURE_ANALYTICS_KPI_SURFACES=True)
def test_kpi_endpoints_and_dashboard_surface_use_aggregates(api, admin_user, dashboard_client, day):
    provider_user = User.objects.create_user(phone="0503000004", password="Pass12345!")
    provider = ProviderProfile.objects.create(
        user=provider_user,
        provider_type="individual",
        display_name="مزود السطح",
        bio="bio",
        city="الرياض",
        years_experience=1,
    )
    ProviderDailyStats.objects.create(
        day=day,
        provider=provider,
        profile_views=12,
        chat_starts=4,
        requests_received=5,
        requests_accepted=4,
        requests_completed=3,
        accept_rate=Decimal("80.00"),
        completion_rate=Decimal("75.00"),
    )
    CampaignDailyStats.objects.create(
        day=day,
        campaign_key="banner:9",
        campaign_kind="banner",
        label="بنر 9",
        impressions=20,
        clicks=5,
        leads=5,
        conversions=2,
        ctr=Decimal("25.00"),
    )
    SubscriptionDailyStats.objects.create(
        day=day,
        plan_code="PRO",
        plan_title="Pro",
        tier="pro",
        checkouts_started=3,
        activations=2,
        renewals=1,
        upgrades=1,
        churns=0,
    )
    ExtrasDailyStats.objects.create(
        day=day,
        sku="tickets_5",
        title="تذاكر 5",
        extra_type="credit_based",
        purchases=3,
        activations=2,
        consumptions=4,
        credits_consumed=4,
    )

    api.force_authenticate(user=admin_user)
    provider_response = api.get(f"/api/analytics/kpis/providers/?start={day.isoformat()}&end={day.isoformat()}")
    promo_response = api.get(f"/api/analytics/kpis/promo/?start={day.isoformat()}&end={day.isoformat()}")
    subs_response = api.get(f"/api/analytics/kpis/subscriptions/?start={day.isoformat()}&end={day.isoformat()}")
    extras_response = api.get(f"/api/analytics/kpis/extras/?start={day.isoformat()}&end={day.isoformat()}")
    dashboard_response = dashboard_client.get(reverse("dashboard:analytics_insights"), {"start": day.isoformat(), "end": day.isoformat()})

    assert provider_response.status_code == 200
    assert provider_response.data["summary"]["profile_views"] == 12
    assert provider_response.data["items"][0]["display_name"] == "مزود السطح"
    assert promo_response.status_code == 200
    assert promo_response.data["summary"]["clicks"] == 5
    assert subs_response.status_code == 200
    assert subs_response.data["summary"]["activations"] == 2
    assert extras_response.status_code == 200
    assert extras_response.data["summary"]["credits_consumed"] == 4
    assert dashboard_response.status_code == 200
    assert "مؤشرات التشغيل والتجارة" in dashboard_response.content.decode("utf-8")
    assert "مزود السطح" in dashboard_response.content.decode("utf-8")


@override_settings(FEATURE_ANALYTICS_EVENTS=True, FEATURE_ANALYTICS_KPI_SURFACES=False)
def test_kpi_surfaces_hidden_when_flag_off(api, admin_user, dashboard_client):
    api.force_authenticate(user=admin_user)
    api_response = api.get("/api/analytics/kpis/providers/")
    dashboard_response = dashboard_client.get(reverse("dashboard:analytics_insights"))

    assert api_response.status_code == 404
    assert dashboard_response.status_code == 404


@override_settings(FEATURE_ANALYTICS_EVENTS=True)
def test_rebuild_daily_stats_task_accepts_explicit_day(day):
    result = rebuild_daily_stats_task(day=day.isoformat())
    assert result["day"] == day.isoformat()
