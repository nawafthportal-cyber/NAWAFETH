from django.db import transaction
from django.db.models.signals import post_save, post_delete
from django.dispatch import receiver

from .models import Review


@receiver(post_save, sender=Review)
def update_provider_rating(sender, instance: Review, created, **kwargs):
    provider_id = instance.provider_id
    if not provider_id:
        return
    from .tasks import recalculate_provider_rating
    transaction.on_commit(lambda: recalculate_provider_rating.delay(provider_id))


@receiver(post_delete, sender=Review)
def update_provider_rating_on_delete(sender, instance: Review, **kwargs):
    provider_id = instance.provider_id
    if not provider_id:
        return
    from .tasks import recalculate_provider_rating
    transaction.on_commit(lambda: recalculate_provider_rating.delay(provider_id))
