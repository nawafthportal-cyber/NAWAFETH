from __future__ import annotations

from celery import shared_task

from .services import expire_verified_badges_and_sync


@shared_task(name="verification.expire_badges_and_sync")
def expire_badges_and_sync_task(batch_size: int = 1000, max_batches: int = 10) -> int:
    per_batch = max(1, int(batch_size or 1000))
    loops = max(1, int(max_batches or 1))

    total = 0
    for _ in range(loops):
        changed = expire_verified_badges_and_sync(limit=per_batch)
        total += changed
        if changed < per_batch:
            break

    return total
