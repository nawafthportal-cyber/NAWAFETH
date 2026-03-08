from __future__ import annotations

import logging

from celery import shared_task

from .services import (
    expire_excellence_awards,
    rebuild_excellence_badges_cache,
    refresh_excellence_candidates,
    sync_provider_excellence_badges,
)


logger = logging.getLogger(__name__)


@shared_task(name="excellence.generate_candidates")
def generate_candidates_task():
    return refresh_excellence_candidates()


@shared_task(name="excellence.expire_awards")
def expire_awards_task(batch_size: int = 500, max_batches: int = 10) -> int:
    total = 0
    per_batch = max(1, int(batch_size or 500))
    loops = max(1, int(max_batches or 1))
    for _ in range(loops):
        changed = expire_excellence_awards(limit=per_batch)
        total += changed
        if changed < per_batch:
            break
    return total


@shared_task(name="excellence.sync_public_badges")
def sync_public_badges_task(provider_ids=None) -> int:
    return sync_provider_excellence_badges(provider_ids=provider_ids)


@shared_task(name="excellence.rebuild_all_cache")
def rebuild_all_excellence_badges_cache(batch_size: int = 500, limit: int | None = None) -> dict[str, int]:
    result = rebuild_excellence_badges_cache(batch_size=batch_size, limit=limit)
    logger.info(
        "Excellence badges cache rebuild completed: processed=%s updated=%s errors=%s",
        result["processed"],
        result["updated"],
        result["errors"],
    )
    return result
