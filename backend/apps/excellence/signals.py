from __future__ import annotations

import logging

from django.db.models.signals import post_delete, post_save
from django.dispatch import receiver

from .models import ExcellenceBadgeAward, ExcellenceBadgeType
from .services import EXCELLENCE_CACHE_SYNC_SKIP_ATTR, schedule_provider_excellence_cache_sync


logger = logging.getLogger(__name__)


def _should_skip_cache_sync(instance) -> bool:
    return bool(getattr(instance, EXCELLENCE_CACHE_SYNC_SKIP_ATTR, False))


@receiver(post_save, sender=ExcellenceBadgeAward)
def sync_excellence_badges_on_save(sender, instance: ExcellenceBadgeAward, raw=False, **kwargs):
    if raw or _should_skip_cache_sync(instance):
        return
    try:
        schedule_provider_excellence_cache_sync(provider_id=instance.provider_id)
    except Exception:
        logger.exception("Failed to schedule excellence cache sync after award save")


@receiver(post_delete, sender=ExcellenceBadgeAward)
def sync_excellence_badges_on_delete(sender, instance: ExcellenceBadgeAward, **kwargs):
    try:
        if _should_skip_cache_sync(instance):
            return
        schedule_provider_excellence_cache_sync(provider_id=instance.provider_id)
    except Exception:
        logger.exception("Failed to schedule excellence cache sync after award delete")


@receiver(post_save, sender=ExcellenceBadgeType)
def sync_excellence_badges_on_type_save(sender, instance: ExcellenceBadgeType, raw=False, **kwargs):
    if raw:
        return
    provider_ids = list(
        ExcellenceBadgeAward.objects.filter(badge_type_id=instance.id)
        .values_list("provider_id", flat=True)
        .distinct()
    )
    if not provider_ids:
        return
    try:
        schedule_provider_excellence_cache_sync(provider_ids=provider_ids)
    except Exception:
        logger.exception("Failed to schedule excellence cache sync after badge type save")
