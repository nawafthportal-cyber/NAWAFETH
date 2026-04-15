from __future__ import annotations

from decimal import Decimal

from django.db.models.signals import post_save
from django.dispatch import receiver

from apps.notifications.models import EventLog, EventType
from apps.notifications.services import create_notification

from .models import Invoice


def _payment_amount_label(invoice: Invoice) -> str:
    amount = getattr(invoice, "payment_amount", None)
    if amount is None:
        amount = getattr(invoice, "total", Decimal("0.00"))
    normalized_amount = Decimal(str(amount or 0)).quantize(Decimal("0.01"))
    currency = str(
        getattr(invoice, "payment_currency", "")
        or getattr(invoice, "currency", "SAR")
        or "SAR"
    ).strip()
    return f"{normalized_amount} {currency}".strip()


def _payment_reference_label(invoice: Invoice) -> str:
    return str(getattr(invoice, "code", "") or f"#{invoice.id}").strip()


def _payment_notification_url(invoice: Invoice) -> str:
    reference_type = str(getattr(invoice, "reference_type", "") or "").strip().lower()
    reference_id = str(getattr(invoice, "reference_id", "") or "").strip()

    if reference_type == "subscription":
        return "/plans/"
    if reference_type == "verify_request" and reference_id:
        return f"/verification/?request_id={reference_id}"
    if reference_type == "promo_request" and reference_id:
        return f"/promotion/?request_id={reference_id}"
    if reference_type in {"extra_purchase", "extras_bundle_request", "extras_bundle", "extras"}:
        return "/additional-services/"
    return "/notifications/"


@receiver(post_save, sender=Invoice)
def notify_provider_payment_received(sender, instance: Invoice, created, **kwargs):
    user = getattr(instance, "user", None)
    if user is None or getattr(getattr(user, "provider_profile", None), "id", None) is None:
        return
    if not instance.is_payment_effective():
        return
    if EventLog.objects.filter(
        event_type=EventType.PAYMENT_RECEIVED,
        target_user_id=user.id,
        request_id=instance.id,
    ).exists():
        return

    payment_ref = _payment_reference_label(instance)
    payment_amount = _payment_amount_label(instance)
    payment_title = str(getattr(instance, "title", "") or "عملية سداد").strip()

    create_notification(
        user=user,
        title="تم تسجيل عملية سداد جديدة",
        body=f"تم اعتماد سداد الفاتورة {payment_ref} الخاصة بـ {payment_title} بقيمة {payment_amount}.",
        kind="success",
        url=_payment_notification_url(instance),
        event_type=EventType.PAYMENT_RECEIVED,
        request_id=instance.id,
        meta={
            "invoice_id": instance.id,
            "invoice_code": payment_ref,
            "reference_type": str(getattr(instance, "reference_type", "") or ""),
            "reference_id": str(getattr(instance, "reference_id", "") or ""),
            "payment_amount": str(getattr(instance, "payment_amount", "") or getattr(instance, "total", "") or ""),
            "payment_currency": str(getattr(instance, "payment_currency", "") or getattr(instance, "currency", "") or ""),
        },
        pref_key="new_payment",
        audience_mode="provider",
    )