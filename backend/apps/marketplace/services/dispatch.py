from __future__ import annotations

from datetime import timedelta

from django.db import transaction
from django.utils import timezone

from apps.notifications.models import EventLog, EventType
from apps.notifications.services import create_notification
from apps.providers.models import ProviderCategory, ProviderProfile
from apps.subscriptions.services import get_effective_active_subscriptions_map, plan_to_tier
from apps.subscriptions.tiering import CanonicalPlanTier

from ..models import (
    DispatchStatus,
    DispatchTier,
    RequestStatus,
    RequestType,
    ServiceRequest,
    ServiceRequestDispatch,
)


DISPATCH_DELAYS = {
    DispatchTier.PRO: timedelta(hours=0),
    DispatchTier.RIYADI: timedelta(hours=24),
    DispatchTier.BASIC: timedelta(hours=72),
}


def _normalize_dispatch_tier(value: str) -> str:
    tier = (value or "").strip().lower()
    if tier in {DispatchTier.PRO, DispatchTier.RIYADI, DispatchTier.BASIC}:
        return tier
    return DispatchTier.BASIC


def _plan_tier_to_dispatch_tier(plan_tier: str) -> str:
    tier = (plan_tier or "").strip().lower()
    if tier == CanonicalPlanTier.PROFESSIONAL:
        return DispatchTier.PRO
    if tier == CanonicalPlanTier.PIONEER:
        return DispatchTier.RIYADI
    return DispatchTier.BASIC


def _provider_dispatch_tiers(user_ids: list[int]) -> dict[int, str]:
    if not user_ids:
        return {}

    tier_by_user_id: dict[int, str] = {}
    subscriptions_by_user = get_effective_active_subscriptions_map(user_ids)
    for user_id, subscription in subscriptions_by_user.items():
        tier_by_user_id[subscription.user_id] = _plan_tier_to_dispatch_tier(plan_to_tier(subscription.plan))

    for user_id in user_ids:
        tier_by_user_id.setdefault(user_id, DispatchTier.BASIC)

    return tier_by_user_id


def provider_dispatch_tier(provider: ProviderProfile) -> str:
    if not getattr(provider, "user_id", None):
        return DispatchTier.BASIC
    plan_tier = CanonicalPlanTier.BASIC
    try:
        from apps.subscriptions.services import user_plan_tier

        plan_tier = user_plan_tier(provider.user, fallback=CanonicalPlanTier.BASIC)
    except Exception:
        plan_tier = CanonicalPlanTier.BASIC
    return _plan_tier_to_dispatch_tier(plan_tier)


def ensure_dispatch_windows_for_urgent_request(service_request: ServiceRequest, *, now=None) -> list[ServiceRequestDispatch]:
    if service_request.request_type != RequestType.URGENT:
        return []

    now = now or timezone.now()
    windows: list[ServiceRequestDispatch] = []

    for tier, delay in DISPATCH_DELAYS.items():
        available_at = now + delay
        defaults = {
            "available_at": available_at,
            "dispatch_status": DispatchStatus.PENDING,
            "idempotency_key": f"urgent:{service_request.id}:{tier}",
        }
        window, created = ServiceRequestDispatch.objects.get_or_create(
            request=service_request,
            dispatch_tier=tier,
            defaults=defaults,
        )
        if not created and window.dispatch_status in {DispatchStatus.PENDING, DispatchStatus.READY, DispatchStatus.FAILED}:
            window.available_at = available_at
            window.idempotency_key = defaults["idempotency_key"]
            window.save(update_fields=["available_at", "idempotency_key", "updated_at"])
        windows.append(window)

    return windows


def _eligible_matching_providers(service_request: ServiceRequest):
    subcategory_ids = service_request.selected_subcategory_ids()
    if not subcategory_ids:
        return ProviderProfile.objects.none()

    provider_ids = ProviderCategory.objects.filter(
        subcategory_id__in=subcategory_ids
    ).values_list("provider_id", flat=True)

    providers = ProviderProfile.objects.select_related("user").filter(
        id__in=provider_ids,
        accepts_urgent=True,
    )

    city = (service_request.city or "").strip()
    if city:
        providers = providers.filter(city=city)

    return providers


def _event_already_sent(*, user_id: int, request_id: int) -> bool:
    return EventLog.objects.filter(
        event_type=EventType.REQUEST_CREATED,
        target_user_id=user_id,
        request_id=request_id,
    ).exists()


def _mark_ready_windows(*, now=None) -> int:
    now = now or timezone.now()
    return ServiceRequestDispatch.objects.filter(
        dispatch_status=DispatchStatus.PENDING,
        available_at__lte=now,
    ).update(dispatch_status=DispatchStatus.READY)


def dispatch_window(window_id: int, *, now=None) -> dict[str, int | str]:
    now = now or timezone.now()

    with transaction.atomic():
        window = (
            ServiceRequestDispatch.objects.select_for_update()
            .select_related("request", "request__client")
            .filter(id=window_id)
            .first()
        )
        if not window:
            return {"status": "missing", "window_id": window_id, "sent": 0}

        if window.dispatch_status == DispatchStatus.DISPATCHED:
            return {"status": "already_dispatched", "window_id": window.id, "sent": 0}

        if window.available_at > now and window.dispatch_status == DispatchStatus.PENDING:
            return {"status": "not_ready", "window_id": window.id, "sent": 0}

        if window.dispatch_status == DispatchStatus.PENDING:
            window.dispatch_status = DispatchStatus.READY
            window.save(update_fields=["dispatch_status", "updated_at"])

        request = window.request
        if request.request_type != RequestType.URGENT or request.status != RequestStatus.NEW:
            window.dispatch_status = DispatchStatus.FAILED
            window.dispatch_attempts += 1
            window.last_error = "request_not_dispatchable"
            window.save(update_fields=["dispatch_status", "dispatch_attempts", "last_error", "updated_at"])
            return {"status": "request_not_dispatchable", "window_id": window.id, "sent": 0}

        # Urgent requests no longer auto-expire; skip expiry check.

        providers = list(_eligible_matching_providers(request))
        tier_by_user_id = _provider_dispatch_tiers([provider.user_id for provider in providers if provider.user_id])

        sent_count = 0
        for provider in providers:
            user_id = getattr(provider, "user_id", None)
            if not user_id:
                continue
            provider_tier = _normalize_dispatch_tier(tier_by_user_id.get(user_id, DispatchTier.BASIC))
            if provider_tier != window.dispatch_tier:
                continue
            if _event_already_sent(user_id=user_id, request_id=request.id):
                continue

            create_notification(
                user=provider.user,
                title="طلب خدمة عاجلة جديد",
                body=f"يوجد طلب عاجل جديد في تخصصك: {request.title}",
                kind="urgent_request",
                url=f"/requests/{request.id}",
                actor=request.client,
                event_type=EventType.REQUEST_CREATED,
                pref_key="urgent_request",
                request_id=request.id,
                is_urgent=True,
                audience_mode="provider",
                meta={
                    "dispatch_tier": window.dispatch_tier,
                    "dispatch_window_id": window.id,
                },
            )
            sent_count += 1

        window.dispatch_status = DispatchStatus.DISPATCHED
        window.dispatched_at = now
        window.dispatch_attempts += 1
        window.last_error = ""
        window.save(
            update_fields=[
                "dispatch_status",
                "dispatched_at",
                "dispatch_attempts",
                "last_error",
                "updated_at",
            ]
        )

    return {
        "status": "dispatched",
        "window_id": window.id,
        "sent": sent_count,
    }


def dispatch_ready_urgent_windows(*, now=None, limit: int = 100) -> dict[str, int]:
    now = now or timezone.now()

    readied = _mark_ready_windows(now=now)

    window_ids = list(
        ServiceRequestDispatch.objects.filter(
            dispatch_status=DispatchStatus.READY,
            available_at__lte=now,
        )
        .order_by("available_at", "id")
        .values_list("id", flat=True)[:limit]
    )

    dispatched = 0
    failed = 0
    already_dispatched = 0

    for window_id in window_ids:
        result = dispatch_window(window_id, now=now)
        status_value = result.get("status")
        if status_value == "dispatched":
            dispatched += 1
        elif status_value == "already_dispatched":
            already_dispatched += 1
        elif status_value in {"request_expired", "request_not_dispatchable"}:
            failed += 1

    return {
        "readied": readied,
        "processed": len(window_ids),
        "dispatched": dispatched,
        "already_dispatched": already_dispatched,
        "failed": failed,
    }


def provider_can_access_urgent_request(provider: ProviderProfile, service_request: ServiceRequest, *, now=None) -> bool:
    if service_request.request_type != RequestType.URGENT:
        return True

    now = now or timezone.now()

    # Backward compatibility for legacy requests created before dispatch windows.
    if not ServiceRequestDispatch.objects.filter(request=service_request).exists():
        return True

    tier = provider_dispatch_tier(provider)
    return ServiceRequestDispatch.objects.filter(
        request=service_request,
        dispatch_tier=tier,
        available_at__lte=now,
    ).exists()
