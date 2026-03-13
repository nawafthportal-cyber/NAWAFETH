from __future__ import annotations

from django.db.models.signals import post_save
from django.dispatch import receiver

from apps.billing.models import Invoice
from .models import PromoRequest
from .services import activate_after_payment, revoke_after_payment_reversal


@receiver(post_save, sender=Invoice)
def activate_promo_on_invoice_paid(sender, instance: Invoice, created, **kwargs):
    if instance.reference_type != "promo_request":
        return

    pr = PromoRequest.objects.filter(invoice=instance).order_by("-id").first()
    if not pr:
        pr = PromoRequest.objects.filter(code=instance.reference_id).order_by("-id").first()

    if not pr:
        return

    try:
        if instance.is_payment_effective():
            activate_after_payment(pr=pr)
        else:
            revoke_after_payment_reversal(pr=pr)
    except Exception:
        pass
