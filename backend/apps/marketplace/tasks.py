from __future__ import annotations

from celery import shared_task

from .services.dispatch import dispatch_ready_urgent_windows


@shared_task(name="marketplace.dispatch_ready_urgent_windows")
def dispatch_ready_urgent_windows_task(limit: int = 200) -> dict[str, int]:
    return dispatch_ready_urgent_windows(limit=limit)
