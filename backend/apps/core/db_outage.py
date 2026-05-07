from __future__ import annotations

import logging
import time

from django.conf import settings
from django.core.cache import cache


logger = logging.getLogger("nawafeth.db")

_OUTAGE_CACHE_KEY = "core:db_outage:until"
_OUTAGE_LOG_THROTTLE_CACHE_KEY = "core:db_outage:log_throttle"
_local_outage_until = 0
_local_log_throttle_until = 0


def _uses_sqlite() -> bool:
    default_db = getattr(settings, "DATABASES", {}).get("default", {})
    engine = str(default_db.get("ENGINE", "") or "").strip().lower()
    return engine == "django.db.backends.sqlite3"


def _outage_ttl_seconds() -> int:
    configured = int(getattr(settings, "DB_OUTAGE_TTL_SECONDS", 30) or 30)
    if getattr(settings, "DEBUG", False) and _uses_sqlite():
        return max(1, min(configured, 3))
    return max(10, configured)


def _log_throttle_seconds() -> int:
    return max(5, int(getattr(settings, "DB_OUTAGE_LOG_THROTTLE_SECONDS", 30) or 30))


def mark_database_outage(*, reason: str = "", exc: Exception | None = None) -> None:
    global _local_outage_until, _local_log_throttle_until

    ttl = _outage_ttl_seconds()
    now = int(time.time())
    until = now + ttl
    _local_outage_until = max(_local_outage_until, until)

    try:
        cache.set(_OUTAGE_CACHE_KEY, until, timeout=ttl)
    except Exception:
        # Cache may be transiently unavailable; keep local marker as fallback.
        pass

    should_log = False
    if _local_log_throttle_until <= now:
        _local_log_throttle_until = now + _log_throttle_seconds()
        should_log = True

    # Avoid flooding logs during outage storms.
    if should_log:
        try:
            should_log = bool(cache.add(_OUTAGE_LOG_THROTTLE_CACHE_KEY, "1", timeout=_log_throttle_seconds()))
        except Exception:
            # If cache throttle is unavailable, keep local throttle behavior.
            should_log = True

    if should_log:
        logger.warning(
            "Database outage marker set ttl=%ss reason=%s error=%s",
            ttl,
            reason or "-",
            str(exc)[:220] if exc else "-",
            extra={"log_category": "database"},
        )


def clear_database_outage() -> None:
    global _local_outage_until, _local_log_throttle_until

    _local_outage_until = 0
    _local_log_throttle_until = 0
    try:
        cache.delete(_OUTAGE_CACHE_KEY)
    except Exception:
        pass


def outage_retry_after_seconds() -> int | None:
    now = int(time.time())
    cache_until = None
    try:
        raw_until = cache.get(_OUTAGE_CACHE_KEY)
        if isinstance(raw_until, int):
            cache_until = raw_until
    except Exception:
        cache_until = None

    until = max(_local_outage_until, cache_until or 0)
    if until <= 0:
        return None

    remaining = until - now
    if remaining <= 0:
        clear_database_outage()
        return None
    return remaining


def is_database_outage_active() -> bool:
    return outage_retry_after_seconds() is not None
