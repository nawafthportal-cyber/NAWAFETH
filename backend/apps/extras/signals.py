from __future__ import annotations

from django.db.models.signals import post_save
from django.dispatch import receiver

from apps.billing.models import Invoice
from .models import ExtraPurchase
from .services import activate_extra_after_payment, sync_bundle_request_payment_state_from_invoice


@receiver(post_save, sender=Invoice)
def activate_extra_on_paid(sender, instance: Invoice, created, **kwargs):
    try:
        if instance.reference_type == "extra_purchase":
            if instance.status != "paid":
                return

            pid = instance.reference_id
            if not pid:
                return

            purchase = ExtraPurchase.objects.filter(pk=pid).first()
            if not purchase:
                return

            activate_extra_after_payment(purchase=purchase)
            return

        sync_bundle_request_payment_state_from_invoice(invoice=instance)
    except Exception:
        pass
