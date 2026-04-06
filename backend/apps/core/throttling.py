from __future__ import annotations

import math

from rest_framework import status
from rest_framework.response import Response


def normalize_retry_after_seconds(wait) -> int | None:
    if wait is None:
        return None
    try:
        seconds = int(math.ceil(float(wait)))
    except (TypeError, ValueError):
        return None
    if seconds < 0:
        return 0
    if seconds == 0 and float(wait) > 0:
        return 1
    return seconds


def format_wait_time_short(seconds: int) -> str:
    seconds = max(0, int(seconds or 0))
    if seconds < 60:
        return f"{seconds} ث"

    minutes, remaining_seconds = divmod(seconds, 60)
    if minutes < 60:
        if remaining_seconds:
            return f"{minutes} د {remaining_seconds} ث"
        return f"{minutes} د"

    hours, remaining_minutes = divmod(minutes, 60)
    if hours < 24:
        if remaining_minutes:
            return f"{hours} س {remaining_minutes} د"
        return f"{hours} س"

    days, remaining_hours = divmod(hours, 24)
    if remaining_hours:
        return f"{days} ي {remaining_hours} س"
    return f"{days} ي"


def build_retry_after_payload(detail: str, wait_seconds, *, code: str = "throttled") -> dict:
    payload = {
        "detail": detail,
        "code": code,
    }
    normalized_wait = normalize_retry_after_seconds(wait_seconds)
    if normalized_wait is not None:
        payload["retry_after_seconds"] = normalized_wait
        payload["retry_after_text"] = format_wait_time_short(normalized_wait)
    return payload


def build_cooldown_payload(cooldown_seconds: int) -> dict:
    normalized = max(0, int(cooldown_seconds or 0))
    return {
        "cooldown_seconds": normalized,
        "cooldown_text": format_wait_time_short(normalized),
    }


def throttled_response(detail: str, wait_seconds, *, code: str = "throttled") -> Response:
    normalized_wait = normalize_retry_after_seconds(wait_seconds)
    response = Response(
        build_retry_after_payload(detail, normalized_wait, code=code),
        status=status.HTTP_429_TOO_MANY_REQUESTS,
    )
    if normalized_wait is not None:
        response["Retry-After"] = str(normalized_wait)
    return response