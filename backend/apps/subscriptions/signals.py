from __future__ import annotations

import logging

from django.db.models.signals import post_save
from django.dispatch import receiver

from apps.billing.models import Invoice
from apps.providers.models import ProviderProfile
from .models import Subscription
from .services import (
    activate_subscription_after_payment,
    ensure_basic_subscription_entitlement,
    revoke_subscription_after_payment_reversal,
)

logger = logging.getLogger(__name__)


@receiver(post_save, sender=Invoice)
def activate_subscription_on_paid(sender, instance: Invoice, created, **kwargs):
    if instance.reference_type != "subscription":
        return

    sub_id = instance.reference_id
    if not sub_id:
        return

    sub = Subscription.objects.filter(pk=sub_id, invoice=instance).first()
    if not sub:
        sub = Subscription.objects.filter(pk=sub_id).first()

    if not sub:
        return

    try:
        if instance.is_payment_effective():
            activate_subscription_after_payment(sub=sub)
        else:
            revoke_subscription_after_payment_reversal(sub=sub)
    except Exception:
        pass


@receiver(post_save, sender=ProviderProfile)
def assign_basic_entitlement_on_provider_create(sender, instance: ProviderProfile, created, **kwargs):
    if not created or not getattr(instance, "user_id", None):
        return

    try:
        ensure_basic_subscription_entitlement(user=instance.user)
    except Exception:
        logger.exception(
            "Failed to assign basic subscription entitlement for provider user_id=%s",
            getattr(instance, "user_id", None),
        )
