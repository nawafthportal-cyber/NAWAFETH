from __future__ import annotations

from django.db.models.signals import post_save
from django.dispatch import receiver

from apps.marketplace.models import RequestStatus, ServiceRequest

from .loyalty import award_loyalty_points_for_completed_request


@receiver(post_save, sender=ServiceRequest)
def award_loyalty_points_when_request_completed(sender, instance: ServiceRequest, **kwargs):
    update_fields = kwargs.get("update_fields")
    if update_fields is not None and "status" not in set(update_fields):
        return
    if str(getattr(instance, "status", "") or "") != RequestStatus.COMPLETED:
        return
    award_loyalty_points_for_completed_request(instance)
