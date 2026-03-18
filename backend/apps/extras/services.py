from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from apps.billing.models import Invoice, InvoiceStatus

from .models import ExtraPurchase, ExtraPurchaseStatus, ExtraType


def _extra_status_to_unified(status: str) -> str:
    if status == ExtraPurchaseStatus.ACTIVE:
        return "in_progress"
    if status in {
        ExtraPurchaseStatus.CONSUMED,
        ExtraPurchaseStatus.EXPIRED,
        ExtraPurchaseStatus.CANCELLED,
    }:
        return "completed"
    return "new"


def _sync_extra_to_unified(*, purchase: ExtraPurchase, changed_by=None):
    try:
        from apps.unified_requests.services import upsert_unified_request
        from apps.unified_requests.models import UnifiedRequestType
    except Exception:
        return

    upsert_unified_request(
        request_type=UnifiedRequestType.EXTRAS,
        requester=purchase.user,
        source_app="extras",
        source_model="ExtraPurchase",
        source_object_id=purchase.id,
        status=_extra_status_to_unified(purchase.status),
        priority="normal",
        summary=(purchase.title or purchase.sku or "")[:300],
        metadata={
            "purchase_id": purchase.id,
            "sku": purchase.sku,
            "extra_type": purchase.extra_type,
            "purchase_status": purchase.status,
            "invoice_id": purchase.invoice_id,
            "credits_total": purchase.credits_total,
            "credits_used": purchase.credits_used,
            "start_at": purchase.start_at.isoformat() if purchase.start_at else None,
            "end_at": purchase.end_at.isoformat() if purchase.end_at else None,
        },
        assigned_team_code="extras",
        assigned_team_name="الخدمات الإضافية",
        assigned_user=None,
        changed_by=changed_by,
    )


def get_extra_catalog() -> dict:
    """
    كتالوج الإضافات من settings (مبدئي)
    """
    return getattr(settings, "EXTRA_SKUS", {}) or {}


def _platform_config():
    from apps.core.models import PlatformConfig

    return PlatformConfig.load()


def extras_currency() -> str:
    return str(_platform_config().extras_currency or "SAR").strip() or "SAR"


def sku_info(sku: str) -> dict:
    catalog = get_extra_catalog()
    if sku not in catalog:
        raise ValueError("SKU غير موجود.")
    return catalog[sku]


def infer_extra_type(sku: str) -> str:
    """
    تصنيف بسيط:
    - tickets_* => credits
    - غيره => time_based
    """
    if sku.startswith("tickets_"):
        return ExtraType.CREDIT_BASED
    return ExtraType.TIME_BASED


def infer_duration(sku: str) -> timedelta:
    """
    مدد افتراضية:
    - *_month => 30 يوم
    - *_7d => 7 أيام
    """
    if sku.endswith("_month"):
        return timedelta(days=int(_platform_config().extras_default_duration_days or 30))
    if sku.endswith("_7d"):
        return timedelta(days=int(_platform_config().extras_short_duration_days or 7))
    return timedelta(days=int(_platform_config().extras_default_duration_days or 30))


def infer_credits(sku: str) -> int:
    """
    tickets_100 => 100
    """
    if sku.startswith("tickets_"):
        n = sku.replace("tickets_", "").strip()
        try:
            return int(n)
        except Exception:
            return 0
    return 0


@transaction.atomic
def create_extra_purchase_checkout(*, user, sku: str) -> ExtraPurchase:
    info = sku_info(sku)
    title = info.get("title", sku)
    price = Decimal(str(info.get("price", 0)))

    if price <= 0:
        raise ValueError("سعر الإضافة غير صحيح.")

    etype = infer_extra_type(sku)

    purchase = ExtraPurchase.objects.create(
        user=user,
        sku=sku,
        title=title,
        extra_type=etype,
        subtotal=price,
        currency=extras_currency(),
        status=ExtraPurchaseStatus.PENDING_PAYMENT,
    )

    # إعداد credits إن كانت credit-based
    if etype == ExtraType.CREDIT_BASED:
        purchase.credits_total = infer_credits(sku)
        purchase.save(update_fields=["credits_total", "updated_at"])

    inv = Invoice.objects.create(
        user=user,
        title="فاتورة إضافة مدفوعة",
        description=f"{title}",
        currency=extras_currency(),
        subtotal=purchase.subtotal,
        reference_type="extra_purchase",
        reference_id=str(purchase.pk),
        status=InvoiceStatus.DRAFT,
    )
    inv.mark_pending()
    inv.save(update_fields=["status", "subtotal", "vat_percent", "vat_amount", "total", "updated_at"])

    purchase.invoice = inv
    purchase.save(update_fields=["invoice", "updated_at"])
    _sync_extra_to_unified(purchase=purchase, changed_by=user)
    try:
        from apps.analytics.tracking import safe_track_event

        safe_track_event(
            event_name="extras.checkout_created",
            channel="server",
            surface="extras.create_checkout",
            source_app="extras",
            object_type="ExtraPurchase",
            object_id=str(purchase.id),
            actor=user,
            dedupe_key=f"extras.checkout_created:{purchase.id}:{inv.id}",
            payload={
                "sku": purchase.sku,
                "invoice_id": inv.id,
                "status": purchase.status,
                "extra_type": purchase.extra_type,
            },
        )
    except Exception:
        pass
    return purchase


@transaction.atomic
def activate_extra_after_payment(*, purchase: ExtraPurchase) -> ExtraPurchase:
    purchase = ExtraPurchase.objects.select_for_update().get(pk=purchase.pk)

    if not purchase.invoice or purchase.invoice.status != "paid":
        raise ValueError("الفاتورة غير مدفوعة بعد.")

    if purchase.status == ExtraPurchaseStatus.ACTIVE:
        return purchase

    now = timezone.now()

    if purchase.extra_type == ExtraType.TIME_BASED:
        dur = infer_duration(purchase.sku)
        purchase.start_at = now
        purchase.end_at = now + dur
        purchase.status = ExtraPurchaseStatus.ACTIVE
        purchase.save(update_fields=["start_at", "end_at", "status", "updated_at"])
        _sync_extra_to_unified(purchase=purchase, changed_by=purchase.user)
        try:
            from apps.analytics.tracking import safe_track_event

            safe_track_event(
                event_name="extras.activated",
                channel="server",
                surface="extras.activate_after_payment",
                source_app="extras",
                object_type="ExtraPurchase",
                object_id=str(purchase.id),
                actor=purchase.user,
                dedupe_key=f"extras.activated:{purchase.id}:{purchase.status}:{purchase.start_at.isoformat() if purchase.start_at else ''}",
                payload={
                    "sku": purchase.sku,
                    "status": purchase.status,
                    "start_at": purchase.start_at.isoformat() if purchase.start_at else None,
                    "end_at": purchase.end_at.isoformat() if purchase.end_at else None,
                },
            )
        except Exception:
            pass
        return purchase

    # credit based
    if purchase.extra_type == ExtraType.CREDIT_BASED:
        purchase.status = ExtraPurchaseStatus.ACTIVE
        purchase.save(update_fields=["status", "updated_at"])
        _sync_extra_to_unified(purchase=purchase, changed_by=purchase.user)
        try:
            from apps.analytics.tracking import safe_track_event

            safe_track_event(
                event_name="extras.activated",
                channel="server",
                surface="extras.activate_after_payment",
                source_app="extras",
                object_type="ExtraPurchase",
                object_id=str(purchase.id),
                actor=purchase.user,
                dedupe_key=f"extras.activated:{purchase.id}:{purchase.status}",
                payload={
                    "sku": purchase.sku,
                    "status": purchase.status,
                    "credits_total": purchase.credits_total,
                },
            )
        except Exception:
            pass
        return purchase

    _sync_extra_to_unified(purchase=purchase, changed_by=purchase.user)
    return purchase


@transaction.atomic
def consume_credit(*, user, sku: str, amount: int = 1) -> bool:
    """
    استهلاك رصيد من أحدث عملية شراء فعالة للـ SKU (credits)
    """
    if amount <= 0:
        return True

    p = ExtraPurchase.objects.select_for_update().filter(
        user=user,
        sku=sku,
        extra_type=ExtraType.CREDIT_BASED,
        status=ExtraPurchaseStatus.ACTIVE,
    ).order_by("-id").first()

    if not p:
        return False

    if p.credits_left() < amount:
        return False

    p.credits_used += amount
    if p.credits_left() == 0:
        p.status = ExtraPurchaseStatus.CONSUMED

    p.save(update_fields=["credits_used", "status", "updated_at"])
    _sync_extra_to_unified(purchase=p, changed_by=user)
    try:
        from apps.analytics.tracking import safe_track_event

        safe_track_event(
            event_name="extras.credit_consumed",
            channel="server",
            surface="extras.consume_credit",
            source_app="extras",
            object_type="ExtraPurchase",
            object_id=str(p.id),
            actor=user,
            payload={
                "sku": p.sku,
                "amount": amount,
                "credits_used": p.credits_used,
                "credits_left": p.credits_left(),
                "status": p.status,
            },
        )
    except Exception:
        pass
    return True


def user_has_active_extra(user, sku_prefix: str) -> bool:
    """
    فحص وجود Add-on فعال (زمني أو credits) حسب بادئة sku
    """
    now = timezone.now()
    qs = ExtraPurchase.objects.filter(
        user=user,
        sku__startswith=sku_prefix,
        status=ExtraPurchaseStatus.ACTIVE,
    )
    for p in qs.order_by("-id")[:20]:
        if p.extra_type == ExtraType.TIME_BASED:
            if p.start_at and p.end_at and p.start_at <= now < p.end_at:
                return True
        else:
            if p.credits_left() > 0:
                return True
    return False
