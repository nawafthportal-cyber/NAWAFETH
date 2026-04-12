from __future__ import annotations

from django.db.models.signals import post_save
from django.dispatch import receiver

from apps.billing.models import Invoice, InvoiceStatus
from .models import PromoAdPrice, PromoPricingRule, PromoRequest
from .services import (
    apply_effective_payment,
    discard_incomplete_promo_request,
    revoke_after_payment_reversal,
    sync_legacy_ad_price_from_pricing_rule,
    sync_pricing_rules_from_legacy_ad_type,
)


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
            apply_effective_payment(pr=pr)
        elif instance.status in {InvoiceStatus.CANCELLED, InvoiceStatus.FAILED}:
            discard_incomplete_promo_request(
                pr=pr,
                by_user=pr.requester,
                reason=f"invoice_{instance.status}",
            )
        else:
            revoke_after_payment_reversal(pr=pr)
    except Exception:
        pass


@receiver(post_save, sender=PromoAdPrice)
def sync_rules_when_legacy_price_changes(sender, instance: PromoAdPrice, created, **kwargs):
    try:
        sync_pricing_rules_from_legacy_ad_type(ad_type=instance.ad_type)
    except Exception:
        # Pricing sync must never break admin save flow.
        pass


@receiver(post_save, sender=PromoPricingRule)
def sync_legacy_price_when_rule_changes(sender, instance: PromoPricingRule, created, **kwargs):
    try:
        sync_legacy_ad_price_from_pricing_rule(rule=instance)
    except Exception:
        # Pricing sync must never break dashboard/admin save flow.
        pass
