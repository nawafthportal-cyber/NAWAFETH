from __future__ import annotations

from typing import Iterable

from django.utils import timezone

from apps.core.feature_flags import analytics_events_enabled

from .models import AnalyticsChannel, AnalyticsEvent


EVENT_TAXONOMY: tuple[str, ...] = (
    "marketplace.request_created",
    "messaging.direct_thread_created",
    "messaging.thread_report_created",
    "promo.request_quoted",
    "promo.request_activated",
    "promo.featured_specialist_click",
    "promo.portfolio_showcase_click",
    "subscriptions.checkout_created",
    "subscriptions.activated",
    "extras.checkout_created",
    "extras.activated",
    "extras.credit_consumed",
    "provider.profile_view",
    "promo.banner_impression",
    "promo.banner_click",
    "promo.popup_open",
    "promo.popup_click",
    "search.result_click",
)


def analytics_event_names() -> set[str]:
    return set(EVENT_TAXONOMY)


def _normalize_text(value, *, limit: int) -> str:
    return str(value or "").strip()[:limit]


def _normalize_payload(payload) -> dict:
    if isinstance(payload, dict):
        return payload
    if payload is None:
        return {}
    return {"value": payload}


def track_event(
    *,
    event_name: str,
    channel: str = AnalyticsChannel.SERVER,
    surface: str = "",
    source_app: str = "",
    object_type: str = "",
    object_id="",
    actor=None,
    session_id: str = "",
    dedupe_key: str = "",
    occurred_at=None,
    payload=None,
    version: int = 1,
) -> AnalyticsEvent | None:
    if not analytics_events_enabled():
        return None
    normalized_name = _normalize_text(event_name, limit=80)
    if normalized_name not in analytics_event_names():
        raise ValueError("unknown analytics event")

    normalized_dedupe = _normalize_text(dedupe_key, limit=160)
    if normalized_dedupe and AnalyticsEvent.objects.filter(dedupe_key=normalized_dedupe).exists():
        return None

    return AnalyticsEvent.objects.create(
        event_name=normalized_name,
        channel=_normalize_text(channel, limit=20) or AnalyticsChannel.SERVER,
        surface=_normalize_text(surface, limit=120),
        source_app=_normalize_text(source_app, limit=50),
        object_type=_normalize_text(object_type, limit=80),
        object_id=_normalize_text(object_id, limit=50),
        actor=actor if getattr(actor, "is_authenticated", False) else None,
        session_id=_normalize_text(session_id, limit=64),
        dedupe_key=normalized_dedupe,
        occurred_at=occurred_at or timezone.now(),
        payload=_normalize_payload(payload),
        version=max(1, int(version or 1)),
    )


def safe_track_event(**kwargs) -> AnalyticsEvent | None:
    try:
        return track_event(**kwargs)
    except Exception:
        return None
