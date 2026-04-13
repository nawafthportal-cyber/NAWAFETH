"""Celery tasks for the reviews app."""
from __future__ import annotations

import logging

from celery import shared_task

logger = logging.getLogger("nawafeth.reviews")


@shared_task(bind=True, max_retries=3, default_retry_delay=5, time_limit=30)
def recalculate_provider_rating(self, provider_id: int):
    """Recalculate and persist a provider's aggregate rating.

    Runs in a Celery worker so the signal handler that triggers it stays
    non-blocking on the HTTP thread.
    """
    from django.db.models import Avg, Count

    from apps.providers.models import ProviderProfile
    from .models import Review, ReviewModerationStatus

    if not provider_id:
        return

    agg = Review.objects.filter(
        provider_id=provider_id,
        moderation_status=ReviewModerationStatus.APPROVED,
    ).aggregate(
        avg=Avg("rating"),
        cnt=Count("id"),
    )

    avg = agg["avg"] or 0
    cnt = agg["cnt"] or 0

    ProviderProfile.objects.filter(id=provider_id).update(
        rating_avg=avg,
        rating_count=cnt,
    )
