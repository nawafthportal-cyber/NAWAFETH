"""Celery tasks for the reviews app."""
from __future__ import annotations

import logging

from celery import shared_task

logger = logging.getLogger("nawafeth.reviews")


@shared_task(bind=True, max_retries=3, default_retry_delay=5, time_limit=30)
def recalculate_provider_rating(self, provider_id: int):
    """Recalculate and persist a provider's aggregate rating."""
    if not provider_id:
        return

    from .services import refresh_provider_rating

    return refresh_provider_rating(provider_id)
