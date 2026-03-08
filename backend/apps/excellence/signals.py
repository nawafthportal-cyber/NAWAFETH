from __future__ import annotations

from django.db.models.signals import post_delete, post_save
from django.dispatch import receiver

from .models import ExcellenceBadgeAward
from .services import sync_provider_excellence_badges


@receiver(post_save, sender=ExcellenceBadgeAward)
def sync_excellence_badges_on_save(sender, instance: ExcellenceBadgeAward, created, **kwargs):
    try:
        sync_provider_excellence_badges(provider_ids=[instance.provider_id])
    except Exception:
        pass


@receiver(post_delete, sender=ExcellenceBadgeAward)
def sync_excellence_badges_on_delete(sender, instance: ExcellenceBadgeAward, **kwargs):
    try:
        sync_provider_excellence_badges(provider_ids=[instance.provider_id])
    except Exception:
        pass
