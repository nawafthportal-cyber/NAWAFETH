"""Provider presence helpers (online/offline indicator).

The implementation deliberately keeps the surface tiny:

* ``mark_seen(user)``    – update ``user.last_seen`` (throttled via cache so we
  do not write to the database on every request).
* ``is_online(user)``    – boolean: was the user active within the configured
  window (default 2 minutes)?
* ``last_seen(user)``    – the raw database timestamp (``datetime`` or ``None``).
* ``effective_last_seen(user)`` – the freshest timestamp from cache or database.

Only providers expose presence externally (per product decision), but the
middleware records ``last_seen`` for every authenticated user so that a user
toggling between modes gets accurate state immediately.
"""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import Optional

from django.conf import settings
from django.core.cache import cache
from django.utils import timezone


# How fresh ``last_seen`` must be for a user to be considered online.
ONLINE_WINDOW_SECONDS: int = int(getattr(settings, "PRESENCE_ONLINE_WINDOW_SECONDS", 120))

# Throttle: do not write ``last_seen`` to the database more than once per this
# many seconds for the same user.  Reads stay fresh because the cache key has
# the same TTL as the throttle window.
WRITE_THROTTLE_SECONDS: int = int(getattr(settings, "PRESENCE_WRITE_THROTTLE_SECONDS", 60))

_THROTTLE_KEY = "presence:lastwrite:{user_id}"
_SEEN_KEY = "presence:lastseen:{user_id}"
_SEEN_CACHE_TTL_SECONDS = max(ONLINE_WINDOW_SECONDS + WRITE_THROTTLE_SECONDS, ONLINE_WINDOW_SECONDS * 2)


def _is_authenticated(user) -> bool:
    return bool(user and getattr(user, "is_authenticated", False) and getattr(user, "pk", None))


def mark_seen(user) -> None:
    """Update ``user.last_seen`` to ``now`` if the throttle window has elapsed.

    Safe to call on every request – the cache short-circuits repeated writes.
    Silently ignores anonymous users and any database/cache errors so it can
    never break the request cycle.
    """
    if not _is_authenticated(user):
        return
    now = timezone.now()
    try:
        cache.set(_SEEN_KEY.format(user_id=user.pk), now, timeout=_SEEN_CACHE_TTL_SECONDS)
    except Exception:
        pass
    key = _THROTTLE_KEY.format(user_id=user.pk)
    try:
        if cache.get(key):
            return
        # Reserve the slot first to avoid a thundering herd of writes when
        # several requests for the same user land at once.
        cache.set(key, 1, timeout=WRITE_THROTTLE_SECONDS)
    except Exception:
        # If the cache is unavailable we still want to update the row – just
        # without the throttle.  Continue.
        pass

    try:
        # Use update() to avoid loading/saving the whole user row (no signals,
        # no race with concurrent profile saves).
        type(user).objects.filter(pk=user.pk).update(last_seen=now)
        # Keep the in-memory instance consistent for the rest of the request.
        try:
            user.last_seen = now
        except Exception:
            pass
    except Exception:
        # Database hiccup – swallow; presence is best-effort.
        pass


def last_seen(user) -> Optional[datetime]:
    if not _is_authenticated(user):
        return None
    return getattr(user, "last_seen", None)


def effective_last_seen(user) -> Optional[datetime]:
    if not _is_authenticated(user):
        return None
    try:
        cached = cache.get(_SEEN_KEY.format(user_id=user.pk))
        if cached:
            return cached
    except Exception:
        pass
    return last_seen(user)


def is_online_value(value: Optional[datetime]) -> bool:
    """Pure helper that decides if a timestamp counts as 'online' right now."""
    if not value:
        return False
    return (timezone.now() - value) <= timedelta(seconds=ONLINE_WINDOW_SECONDS)


def is_online(user) -> bool:
    return is_online_value(effective_last_seen(user))
