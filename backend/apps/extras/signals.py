from __future__ import annotations

import logging

from django.db.models.signals import post_save
from django.dispatch import receiver

from apps.billing.models import Invoice
from .models import ExtraPurchase
from .services import (
    activate_bundle_portal_subscription_for_request,
    activate_extra_after_payment,
    sync_bundle_request_payment_state_from_invoice,
)

logger = logging.getLogger(__name__)


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
        # Self-healing activation: if the invoice has now become payment-effective
        # but the originating extras bundle request was already closed (because
        # an admin acted before the late payment confirmation arrived), make sure
        # the portal subscription is created/extended idempotently. The function
        # is a no-op when the request is not yet closed or has no eligible
        # provider attached.
        if instance.is_payment_effective():
            from apps.unified_requests.models import UnifiedRequest, UnifiedRequestType

            reference_code = str(instance.reference_id or "").strip()
            if reference_code:
                bundle_request = (
                    UnifiedRequest.objects.select_related(
                        "requester", "assigned_user", "metadata_record"
                    )
                    .filter(
                        request_type=UnifiedRequestType.EXTRAS,
                        code=reference_code,
                        status="closed",
                    )
                    .first()
                )
                if bundle_request is not None:
                    activate_bundle_portal_subscription_for_request(
                        request_obj=bundle_request
                    )
    except Exception:
        logger.exception(
            "extras signal activate_extra_on_paid failed for Invoice pk=%s reference_type=%s",
            instance.pk,
            instance.reference_type,
        )
