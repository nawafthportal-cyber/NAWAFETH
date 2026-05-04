from __future__ import annotations

from datetime import timedelta
import math

from django.db import transaction
from django.utils import timezone

from apps.notifications.models import EventLog, EventType, Notification
from apps.notifications.services import create_notification, delete_notifications
from apps.providers.location_formatter import city_matches_scope
from apps.providers.models import ProviderCategory, ProviderProfile, SubCategory
from apps.subscriptions.capabilities import (
    competitive_request_delay_for_user,
    competitive_requests_enabled_for_user,
    urgent_request_delay_for_tier,
)
from apps.subscriptions.services import get_effective_active_subscriptions_map, plan_to_tier, user_has_active_subscription
from apps.subscriptions.tiering import CanonicalPlanTier

from ..models import (
    DispatchMode,
    DispatchStatus,
    DispatchTier,
    RequestStatus,
    RequestType,
    ServiceRequest,
    ServiceRequestDispatch,
)


def _normalize_dispatch_tier(value: str) -> str:
    tier = (value or "").strip().lower()
    if tier in {DispatchTier.PRO, DispatchTier.RIYADI, DispatchTier.BASIC}:
        return tier
    return DispatchTier.BASIC


def _dispatch_delays() -> dict[str, timedelta]:
    return {
        DispatchTier.PRO: urgent_request_delay_for_tier(DispatchTier.PRO),
        DispatchTier.RIYADI: urgent_request_delay_for_tier(DispatchTier.RIYADI),
        DispatchTier.BASIC: urgent_request_delay_for_tier(DispatchTier.BASIC),
    }


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

    return tier_by_user_id


def provider_dispatch_tier(provider: ProviderProfile) -> str:
    if not getattr(provider, "user_id", None):
        return ""
    if not user_has_active_subscription(provider.user):
        return ""
    plan_tier = CanonicalPlanTier.BASIC
    try:
        from apps.subscriptions.services import user_plan_tier

        plan_tier = user_plan_tier(provider.user, fallback=CanonicalPlanTier.BASIC)
    except Exception:
        plan_tier = CanonicalPlanTier.BASIC
    return _plan_tier_to_dispatch_tier(plan_tier)


def _as_float(value) -> float | None:
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(parsed):
        return None
    return parsed


def _request_coordinates(service_request: ServiceRequest) -> tuple[float, float] | None:
    lat = _as_float(getattr(service_request, "request_lat", None))
    lng = _as_float(getattr(service_request, "request_lng", None))
    if lat is None or lng is None:
        return None
    if not (-90 <= lat <= 90 and -180 <= lng <= 180):
        return None
    return (lat, lng)


def _provider_coordinates(provider: ProviderProfile) -> tuple[float, float] | None:
    lat = _as_float(getattr(provider, "lat", None))
    lng = _as_float(getattr(provider, "lng", None))
    if lat is None or lng is None:
        return None
    if not (-90 <= lat <= 90 and -180 <= lng <= 180):
        return None
    return (lat, lng)


def request_subcategory_ids(service_request: ServiceRequest) -> list[int]:
    try:
        ids = service_request.selected_subcategory_ids()
    except Exception:
        ids = []
    if ids:
        return ids
    subcategory_id = getattr(service_request, "subcategory_id", None)
    return [subcategory_id] if subcategory_id else []


def provider_requires_geo_scope_for_request(
    provider: ProviderProfile,
    service_request: ServiceRequest,
) -> bool | None:
    subcategory_ids = request_subcategory_ids(service_request)
    if not subcategory_ids:
        return None

    if not ProviderCategory.objects.filter(
        provider=provider,
        subcategory_id__in=subcategory_ids,
    ).exists():
        return None
    matches = list(
        SubCategory.objects.filter(id__in=subcategory_ids, is_active=True).values_list("requires_geo_scope", flat=True)
    )
    if not matches:
        return None
    return any(bool(flag) for flag in matches)


def provider_matches_request_scope(provider: ProviderProfile, service_request: ServiceRequest) -> bool:
    requires_geo_scope = provider_requires_geo_scope_for_request(provider, service_request)
    if requires_geo_scope is None:
        return False
    if not requires_geo_scope:
        return True
    return city_matches_scope(
        getattr(service_request, "city", "") or "",
        provider_city=getattr(provider, "city", "") or "",
        provider_region=getattr(provider, "region", "") or "",
    )


def _haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    radius_km = 6371.0
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lng2 - lng1)
    arc = (
        math.sin(delta_phi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2) ** 2
    )
    return 2 * radius_km * math.atan2(math.sqrt(arc), math.sqrt(1 - arc))


def provider_matches_nearest_urgent_request(provider: ProviderProfile, service_request: ServiceRequest) -> bool:
    dispatch_mode = (getattr(service_request, "dispatch_mode", "") or "").strip().lower()
    if dispatch_mode != DispatchMode.NEAREST:
        return True

    requires_geo_scope = provider_requires_geo_scope_for_request(provider, service_request)
    if requires_geo_scope is False:
        return True
    if requires_geo_scope is None:
        return False

    request_coords = _request_coordinates(service_request)
    provider_coords = _provider_coordinates(provider)
    if request_coords is None or provider_coords is None:
        return False

    distance_km = _haversine_km(
        request_coords[0],
        request_coords[1],
        provider_coords[0],
        provider_coords[1],
    )
    coverage_radius_km = _as_float(getattr(provider, "coverage_radius_km", None)) or 0.0
    if coverage_radius_km > 0 and distance_km > coverage_radius_km:
        return False
    return True


def _provider_distance_for_request(provider: ProviderProfile, service_request: ServiceRequest) -> float | None:
    request_coords = _request_coordinates(service_request)
    provider_coords = _provider_coordinates(provider)
    if request_coords is None or provider_coords is None:
        return None
    return _haversine_km(
        request_coords[0],
        request_coords[1],
        provider_coords[0],
        provider_coords[1],
    )


def ensure_dispatch_windows_for_urgent_request(service_request: ServiceRequest, *, now=None) -> list[ServiceRequestDispatch]:
    if service_request.request_type != RequestType.URGENT:
        return []

    now = now or timezone.now()
    windows: list[ServiceRequestDispatch] = []

    for tier, delay in _dispatch_delays().items():
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


def _eligible_matching_providers_queryset(service_request: ServiceRequest):
    subcategory_ids = request_subcategory_ids(service_request)
    if not subcategory_ids:
        return ProviderProfile.objects.none()

    provider_ids = ProviderCategory.objects.filter(
        subcategory_id__in=subcategory_ids,
        accepts_urgent=True,
        subcategory__allows_urgent_requests=True,
    ).values_list("provider_id", flat=True)

    providers = ProviderProfile.objects.select_related("user").filter(
        id__in=provider_ids,
        accepts_urgent=True,
    )

    return providers.distinct()


def _eligible_matching_providers(service_request: ServiceRequest):
    providers = [
        provider
        for provider in _eligible_matching_providers_queryset(service_request)
        if provider_can_access_urgent_request(provider, service_request)
    ]
    dispatch_mode = (getattr(service_request, "dispatch_mode", "") or "").strip().lower()
    if dispatch_mode != DispatchMode.NEAREST:
        return providers

    ranked: list[tuple[float, ProviderProfile]] = []
    for provider in providers:
        if not provider_matches_nearest_urgent_request(provider, service_request):
            continue
        distance_km = _provider_distance_for_request(provider, service_request)
        if distance_km is None:
            continue
        ranked.append((distance_km, provider))

    ranked.sort(key=lambda item: item[0])
    return [provider for _, provider in ranked]


def _event_already_sent(*, user_id: int, request_id: int) -> bool:
    return EventLog.objects.filter(
        event_type=EventType.REQUEST_CREATED,
        target_user_id=user_id,
        request_id=request_id,
    ).exists()


def _eligible_competitive_providers(service_request: ServiceRequest):
    subcategory_ids = request_subcategory_ids(service_request)
    if not subcategory_ids:
        return []

    provider_ids = ProviderCategory.objects.filter(
        subcategory_id__in=subcategory_ids,
    ).values_list("provider_id", flat=True)

    providers = ProviderProfile.objects.select_related("user").filter(id__in=provider_ids)
    return [provider for provider in providers.distinct() if provider_matches_request_scope(provider, service_request)]


def _competitive_request_due_for_provider(*, provider: ProviderProfile, service_request: ServiceRequest, now=None) -> bool:
    user = getattr(provider, "user", None)
    if user is None or not getattr(provider, "user_id", None):
        return False
    if not user_has_active_subscription(user):
        return False
    if not competitive_requests_enabled_for_user(user):
        return False

    created_at = getattr(service_request, "created_at", None)
    if created_at is None:
        return False

    delay = competitive_request_delay_for_user(user)
    return created_at + delay <= (now or timezone.now())


def dispatch_due_competitive_request_notifications(*, now=None, limit: int = 100) -> dict[str, int]:
    now = now or timezone.now()
    requests = list(
        ServiceRequest.objects.select_related("client", "subcategory", "subcategory__category")
        .prefetch_related("subcategories")
        .filter(
            request_type=RequestType.COMPETITIVE,
            provider__isnull=True,
            status=RequestStatus.NEW,
        )
        .order_by("created_at", "id")[:limit]
    )

    processed = 0
    sent_count = 0
    for request in requests:
        if request.quote_deadline and timezone.localdate() > request.quote_deadline:
            continue

        processed += 1
        for provider in _eligible_competitive_providers(request):
            user_id = getattr(provider, "user_id", None)
            if not user_id:
                continue
            if _event_already_sent(user_id=user_id, request_id=request.id):
                continue
            if not _competitive_request_due_for_provider(provider=provider, service_request=request, now=now):
                continue

            create_notification(
                user=provider.user,
                title="طلب عرض خدمة تنافسية جديد",
                body=f"يوجد طلب تنافسي جديد يطابق تخصصك: {request.title}",
                kind="request_created",
                url=f"/requests/{request.id}",
                actor=request.client,
                event_type=EventType.REQUEST_CREATED,
                pref_key="competitive_offer_request",
                request_id=request.id,
                audience_mode="provider",
                meta={
                    "request_type": request.request_type,
                    "competitive": True,
                    "provider_id": provider.id,
                    "quote_deadline": request.quote_deadline.isoformat() if request.quote_deadline else None,
                },
            )
            sent_count += 1

    return {
        "processed": processed,
        "sent": sent_count,
    }


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
            provider_tier_value = tier_by_user_id.get(user_id)
            if not provider_tier_value:
                continue
            provider_tier = _normalize_dispatch_tier(provider_tier_value)
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

    if not provider_matches_request_scope(provider, service_request):
        return False

    if not provider_matches_nearest_urgent_request(provider, service_request):
        return False

    # Backward compatibility for legacy requests created before dispatch windows.
    if not ServiceRequestDispatch.objects.filter(request=service_request).exists():
        return True

    tier = provider_dispatch_tier(provider)
    return ServiceRequestDispatch.objects.filter(
        request=service_request,
        dispatch_tier=tier,
        available_at__lte=now,
    ).exists()


def clear_urgent_request_provider_notifications(service_request: ServiceRequest) -> int:
    if getattr(service_request, "request_type", "") != RequestType.URGENT:
        return 0

    provider_user_ids = list(
        EventLog.objects.filter(
            event_type=EventType.REQUEST_CREATED,
            request_id=service_request.id,
            target_user__isnull=False,
        ).values_list("target_user_id", flat=True).distinct()
    )

    assigned_provider_user_id = getattr(getattr(service_request, "provider", None), "user_id", None)
    if assigned_provider_user_id:
        provider_user_ids.append(int(assigned_provider_user_id))

    provider_user_ids = list(dict.fromkeys(int(user_id) for user_id in provider_user_ids if user_id))
    if not provider_user_ids:
        return 0

    request_url = f"/requests/{service_request.id}"
    return delete_notifications(
        qs=Notification.objects.filter(
            user_id__in=provider_user_ids,
            audience_mode="provider",
            url=request_url,
            kind__in=["urgent_request", "request_created"],
        )
    )
