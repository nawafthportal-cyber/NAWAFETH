from __future__ import annotations

import logging
from typing import Iterable

from django.conf import settings
from django.core.cache import cache
from django.db import DatabaseError, OperationalError
from django.db.models import Q

from apps.messaging.models import Message, Thread, direct_thread_mode_q
from apps.notifications.models import Notification
from apps.notifications.selectors import (
    count_notifications_by_mode,
    normalize_notification_mode,
)


polling_logger = logging.getLogger("nawafeth.polling")
db_logger = logging.getLogger("nawafeth.db")

_CACHE_VERSION = "v1"
_SUPPORTED_CACHE_MODES = ("shared", "client", "provider")


def get_unread_badges_snapshot(*, user, mode: str | None):
    normalized = normalize_notification_mode(mode)
    cache_mode = normalized or "shared"
    cache_key = _combined_cache_key(user.id, cache_mode)
    cached = cache.get(cache_key)
    if cached is not None:
        return dict(cached)

    stale_key = _combined_stale_cache_key(user.id, cache_mode)
    try:
        payload = _compute_unread_badges(user=user, mode=normalized)
    except (OperationalError, DatabaseError) as exc:
        stale_payload = cache.get(stale_key)
        db_logger.warning(
            "unread_badges_degraded user_id=%s mode=%s error=%s",
            user.id,
            cache_mode,
            exc,
            extra={"log_category": "db_failure"},
        )
        if stale_payload is not None:
            return {
                **dict(stale_payload),
                "degraded": True,
                "stale": True,
            }
        raise

    cache.set(cache_key, payload, _cache_ttl())
    cache.set(stale_key, payload, _stale_cache_ttl())
    return dict(payload)


def get_notifications_unread_payload(*, user, mode: str | None):
    snapshot = get_unread_badges_snapshot(user=user, mode=mode)
    return {
        "unread": snapshot["notifications"],
        "degraded": bool(snapshot.get("degraded")),
        "stale": bool(snapshot.get("stale")),
        "mode": snapshot.get("mode") or "shared",
    }


def get_direct_messages_unread_payload(*, user, mode: str | None):
    snapshot = get_unread_badges_snapshot(user=user, mode=mode)
    return {
        "unread": snapshot["chats"],
        "degraded": bool(snapshot.get("degraded")),
        "stale": bool(snapshot.get("stale")),
        "mode": snapshot.get("mode") or "shared",
    }


def invalidate_unread_badge_cache(*, user_id: int | None = None, user_ids: Iterable[int] | None = None) -> None:
    ids = {uid for uid in (user_ids or []) if uid}
    if user_id:
        ids.add(user_id)
    if not ids:
        return

    keys: list[str] = []
    for uid in ids:
        for mode in _SUPPORTED_CACHE_MODES:
            keys.append(_combined_cache_key(uid, mode))
            keys.append(_combined_stale_cache_key(uid, mode))
    cache.delete_many(keys)


def _compute_unread_badges(*, user, mode: str):
    notification_queryset = Notification.objects.filter(user=user, is_read=False)
    notifications_count = count_notifications_by_mode(
        qs=notification_queryset,
        user=user,
        mode=mode,
    )
    chats_count = _count_direct_messages(user=user, mode=mode)
    payload = {
        "notifications": notifications_count,
        "chats": chats_count,
        "mode": mode or "shared",
        "degraded": False,
        "stale": False,
    }
    polling_logger.debug(
        "unread_badges_computed user_id=%s mode=%s notifications=%s chats=%s",
        user.id,
        payload["mode"],
        notifications_count,
        chats_count,
        extra={"log_category": "polling"},
    )
    return payload


def _count_direct_messages(*, user, mode: str) -> int:
    threads = Thread.objects.filter(is_direct=True).filter(direct_thread_mode_q(user=user, mode=mode))

    return (
        Message.objects.filter(thread__in=threads)
        .exclude(sender=user)
        .exclude(reads__user=user)
        .count()
    )


def _cache_ttl() -> int:
    return int(getattr(settings, "UNREAD_BADGE_CACHE_TTL", 15))


def _stale_cache_ttl() -> int:
    return int(
        getattr(
            settings,
            "UNREAD_BADGE_STALE_CACHE_TTL",
            max(_cache_ttl() * 8, _cache_ttl() + 60),
        )
    )


def _combined_cache_key(user_id: int, mode: str) -> str:
    return f"nawafeth:{_CACHE_VERSION}:unread_badges:{user_id}:{mode}"


def _combined_stale_cache_key(user_id: int, mode: str) -> str:
    return f"nawafeth:{_CACHE_VERSION}:unread_badges_stale:{user_id}:{mode}"
