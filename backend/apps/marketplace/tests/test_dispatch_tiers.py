from datetime import timedelta
from decimal import Decimal

import pytest
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.marketplace.models import (
    DispatchStatus,
    RequestStatus,
    RequestType,
    ServiceRequest,
    ServiceRequestDispatch,
)
from apps.marketplace.services.dispatch import (
    dispatch_ready_urgent_windows,
    ensure_dispatch_windows_for_urgent_request,
)
from apps.marketplace.tasks import dispatch_ready_urgent_windows_task
from apps.notifications.models import EventLog, EventType, Notification
from apps.providers.models import Category, ProviderCategory, ProviderProfile, SubCategory
from apps.subscriptions.models import PlanPeriod, PlanTier, Subscription, SubscriptionPlan, SubscriptionStatus


pytestmark = pytest.mark.django_db


def _create_provider_with_tier(*, phone: str, tier: str, subcategory: SubCategory, city: str = "Riyadh") -> ProviderProfile:
    user = User.objects.create(phone=phone, username=f"u_{phone}")
    provider = ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name=f"Provider {tier} {phone[-2:]}",
        bio="bio",
        years_experience=1,
        city=city,
        accepts_urgent=True,
    )
    ProviderCategory.objects.get_or_create(provider=provider, subcategory=subcategory)

    plan = SubscriptionPlan.objects.create(
        code=f"{tier}_{phone[-4:]}",
        tier=tier,
        title=f"{tier} plan",
        period=PlanPeriod.MONTH,
        price=Decimal("10.00"),
        features=["verify_green"],
    )
    Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
        end_at=timezone.now() + timedelta(days=30),
    )
    return provider


def _create_urgent_request(*, client: User, subcategory: SubCategory, city: str = "Riyadh") -> ServiceRequest:
    return ServiceRequest.objects.create(
        client=client,
        subcategory=subcategory,
        title="Urgent request",
        description="desc",
        request_type=RequestType.URGENT,
        status=RequestStatus.NEW,
        city=city,
        is_urgent=True,
        expires_at=timezone.now() + timedelta(days=7),
        dispatch_mode="all",
    )


def test_dispatch_tiers_respect_0_24_72_timing_windows():
    cat = Category.objects.create(name="خدمات", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="كهرباء", is_active=True)

    client_user = User.objects.create(phone="0509100000", username="client_dispatch")

    provider_pro = _create_provider_with_tier(phone="0509100001", tier=PlanTier.PRO, subcategory=sub)
    provider_riyadi = _create_provider_with_tier(phone="0509100002", tier=PlanTier.RIYADI, subcategory=sub)
    provider_basic = _create_provider_with_tier(phone="0509100003", tier=PlanTier.BASIC, subcategory=sub)

    request_obj = _create_urgent_request(client=client_user, subcategory=sub)

    base_now = timezone.now()
    ensure_dispatch_windows_for_urgent_request(request_obj, now=base_now)

    dispatch_ready_urgent_windows(now=base_now)
    assert Notification.objects.filter(user=provider_pro.user, kind="urgent_request").count() == 1
    assert Notification.objects.filter(user=provider_riyadi.user, kind="urgent_request").count() == 0
    assert Notification.objects.filter(user=provider_basic.user, kind="urgent_request").count() == 0

    dispatch_ready_urgent_windows(now=base_now + timedelta(hours=23, minutes=59))
    assert Notification.objects.filter(user=provider_riyadi.user, kind="urgent_request").count() == 0

    dispatch_ready_urgent_windows(now=base_now + timedelta(hours=24))
    assert Notification.objects.filter(user=provider_riyadi.user, kind="urgent_request").count() == 1

    dispatch_ready_urgent_windows(now=base_now + timedelta(hours=71, minutes=59))
    assert Notification.objects.filter(user=provider_basic.user, kind="urgent_request").count() == 0

    dispatch_ready_urgent_windows(now=base_now + timedelta(hours=72))
    assert Notification.objects.filter(user=provider_basic.user, kind="urgent_request").count() == 1


def test_dispatch_scheduler_is_idempotent_when_run_twice():
    cat = Category.objects.create(name="خدمات", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="سباكة", is_active=True)

    client_user = User.objects.create(phone="0509200000", username="client_dispatch_dup")
    provider_pro = _create_provider_with_tier(phone="0509200001", tier=PlanTier.PRO, subcategory=sub)

    request_obj = _create_urgent_request(client=client_user, subcategory=sub)

    base_now = timezone.now()
    ensure_dispatch_windows_for_urgent_request(request_obj, now=base_now)

    dispatch_ready_urgent_windows(now=base_now)
    dispatch_ready_urgent_windows(now=base_now)

    assert Notification.objects.filter(user=provider_pro.user, kind="urgent_request").count() == 1
    assert EventLog.objects.filter(
        event_type=EventType.REQUEST_CREATED,
        target_user=provider_pro.user,
        request_id=request_obj.id,
    ).count() == 1


def test_dispatch_task_processes_pending_ready_windows():
    cat = Category.objects.create(name="خدمات", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="دهان", is_active=True)

    client_user = User.objects.create(phone="0509300000", username="client_dispatch_task")
    provider_pro = _create_provider_with_tier(phone="0509300001", tier=PlanTier.PRO, subcategory=sub)

    request_obj = _create_urgent_request(client=client_user, subcategory=sub)
    ensure_dispatch_windows_for_urgent_request(request_obj, now=timezone.now())

    window = ServiceRequestDispatch.objects.get(request=request_obj, dispatch_tier=PlanTier.PRO)
    window.available_at = timezone.now() - timedelta(minutes=1)
    window.dispatch_status = DispatchStatus.PENDING
    window.save(update_fields=["available_at", "dispatch_status", "updated_at"])

    result = dispatch_ready_urgent_windows_task(limit=20)

    window.refresh_from_db()
    assert result["processed"] >= 1
    assert window.dispatch_status == DispatchStatus.DISPATCHED
    assert Notification.objects.filter(user=provider_pro.user, kind="urgent_request").count() == 1


def test_available_urgent_respects_tier_visibility_window():
    cat = Category.objects.create(name="خدمات", is_active=True)
    sub = SubCategory.objects.create(category=cat, name="تكييف", is_active=True)

    client_user = User.objects.create(phone="0509400000", username="client_dispatch_visibility")
    provider_basic = _create_provider_with_tier(phone="0509400001", tier=PlanTier.BASIC, subcategory=sub)

    request_obj = _create_urgent_request(client=client_user, subcategory=sub)
    base_now = timezone.now()
    ensure_dispatch_windows_for_urgent_request(request_obj, now=base_now)

    api = APIClient()
    api.force_authenticate(user=provider_basic.user)

    before = api.get("/api/marketplace/provider/urgent/available/")
    assert before.status_code == 200
    assert request_obj.id not in {item["id"] for item in before.json()}

    basic_window = ServiceRequestDispatch.objects.get(request=request_obj, dispatch_tier=PlanTier.BASIC)
    basic_window.available_at = timezone.now() - timedelta(minutes=1)
    basic_window.dispatch_status = DispatchStatus.READY
    basic_window.save(update_fields=["available_at", "dispatch_status", "updated_at"])

    after = api.get("/api/marketplace/provider/urgent/available/")
    assert after.status_code == 200
    assert request_obj.id in {item["id"] for item in after.json()}
