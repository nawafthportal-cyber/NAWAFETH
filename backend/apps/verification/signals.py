from __future__ import annotations

from django.db.models.signals import post_delete, post_save
from django.dispatch import receiver

from apps.billing.models import Invoice

from .models import VerificationRequest, VerifiedBadge
from .services import (
    activate_after_payment,
    revoke_after_payment_reversal,
    sync_provider_badges,
    sync_verification_request_badge_state,
)


@receiver(post_save, sender=Invoice)
def activate_verification_on_invoice_paid(sender, instance: Invoice, created, **kwargs):
    """
    عند تحول الفاتورة إلى PAID:
    - إذا كانت مرتبطة بطلب توثيق، نفعل الشارة تلقائيًا
    """
    # reference_type: verify_request
    if instance.reference_type != "verify_request":
        return

    vr = VerificationRequest.objects.filter(invoice=instance).order_by("-id").first()
    if not vr:
        # fallback: reference_id هو code
        vr = VerificationRequest.objects.filter(code=instance.reference_id).order_by("-id").first()

    if not vr:
        return

    try:
        if instance.is_payment_effective():
            activate_after_payment(vr=vr, notify_requester=True)
        else:
            revoke_after_payment_reversal(vr=vr)
    except Exception:
        # لا نفشل الدفع بسبب خطأ داخلي
        pass


@receiver(post_save, sender=VerificationRequest)
def sync_badges_on_request_state_change(sender, instance: VerificationRequest, created, **kwargs):
    try:
        sync_verification_request_badge_state(vr=instance)
    except Exception:
        pass


@receiver(post_save, sender=VerifiedBadge)
def sync_badges_on_save(sender, instance: VerifiedBadge, created, **kwargs):
    try:
        sync_provider_badges(instance.user)
    except Exception:
        pass


@receiver(post_delete, sender=VerifiedBadge)
def sync_badges_on_delete(sender, instance: VerifiedBadge, **kwargs):
    try:
        sync_provider_badges(instance.user)
    except Exception:
        pass
