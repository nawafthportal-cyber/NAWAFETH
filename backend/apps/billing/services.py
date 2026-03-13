from __future__ import annotations

import hashlib
import hmac
import json
import secrets
from decimal import Decimal, InvalidOperation

from django.conf import settings
from django.db import IntegrityError, transaction
from django.utils import timezone

from .models import (
    Invoice,
    InvoiceStatus,
    PaymentAttempt,
    PaymentAttemptStatus,
    PaymentProvider,
    WebhookEvent,
)


SUCCESS_STATUSES = {"paid", "success", "succeeded"}
FAILURE_STATUSES = {"failed", "error"}
CANCELLED_STATUSES = {"cancelled", "canceled"}
REVERSAL_STATUSES = {"refunded", "refund", "reversed", "reverse", "chargeback"}


def _make_checkout_url(provider: str, attempt_id: str) -> str:
    """
    رابط تجريبي (Mock).
    لاحقًا سيتم استبداله برابط بوابة الدفع الحقيقي.
    """
    return f"https://example-pay.local/checkout/{provider}/{attempt_id}"


def _money_or_none(value) -> Decimal | None:
    if value in (None, ""):
        return None
    try:
        return Decimal(str(value)).quantize(Decimal("0.01"))
    except (ArithmeticError, InvalidOperation, TypeError, ValueError):
        return None


def _canonical_webhook_payload(payload: dict) -> str:
    return json.dumps(payload or {}, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _webhook_secret(provider: str) -> str:
    secrets_map = getattr(settings, "BILLING_WEBHOOK_SECRETS", {}) or {}
    return str(secrets_map.get(provider) or "").strip()


def sign_webhook_payload(*, provider: str, payload: dict, event_id: str) -> str:
    secret = _webhook_secret(provider)
    normalized_event_id = (event_id or "").strip()
    if not secret or not normalized_event_id:
        return ""
    message = f"{provider}:{normalized_event_id}:{_canonical_webhook_payload(payload)}".encode("utf-8")
    return hmac.new(secret.encode("utf-8"), message, hashlib.sha256).hexdigest()


def _verify_webhook_signature(*, provider: str, payload: dict, signature: str, event_id: str) -> bool:
    expected = sign_webhook_payload(provider=provider, payload=payload, event_id=event_id)
    presented = (signature or "").strip()
    return bool(expected and presented and hmac.compare_digest(expected, presented))


def _result(*, ok: bool, detail: str, code: str, http_status: int, **extra):
    payload = {
        "ok": ok,
        "detail": detail,
        "code": code,
        "http_status": http_status,
    }
    payload.update(extra)
    return payload


def _log_action_safe(*, actor=None, action: str, reference_type: str = "", reference_id: str = "", extra=None):
    try:
        from apps.audit.services import log_action

        log_action(
            actor=actor,
            action=action,
            reference_type=reference_type,
            reference_id=reference_id,
            request=None,
            extra=extra or {},
        )
    except Exception:
        pass


def _reject_webhook(*, provider: str, event_id: str, code: str, detail: str, http_status: int, invoice: Invoice | None = None, payload: dict | None = None):
    try:
        from apps.audit.models import AuditAction

        _log_action_safe(
            actor=getattr(invoice, "user", None),
            action=AuditAction.INVOICE_WEBHOOK_REJECTED,
            reference_type="billing.webhook",
            reference_id=event_id or getattr(invoice, "code", "") or "",
            extra={
                "provider": provider,
                "code": code,
                "detail": detail,
                "invoice_code": getattr(invoice, "code", ""),
                "reference_type": getattr(invoice, "reference_type", ""),
                "reference_id": getattr(invoice, "reference_id", ""),
                "payload": payload or {},
            },
        )
    except Exception:
        pass

    return _result(ok=False, detail=detail, code=code, http_status=http_status)


def _success_amount_and_currency(*, attempt: PaymentAttempt, invoice: Invoice, payload: dict):
    amount = _money_or_none(payload.get("amount"))
    if amount is None:
        amount = _money_or_none(payload.get("total"))
    if amount is None:
        amount = _money_or_none(payload.get("invoice_total"))
    if amount is None:
        return None, None, "missing_amount"

    currency = (payload.get("currency") or "").strip().upper()
    if not currency:
        return None, None, "missing_currency"

    expected_attempt_amount = _money_or_none(attempt.amount)
    expected_invoice_amount = _money_or_none(invoice.total)
    if amount != expected_attempt_amount or amount != expected_invoice_amount:
        return None, None, "amount_mismatch"

    expected_attempt_currency = (attempt.currency or "").strip().upper()
    expected_invoice_currency = (invoice.currency or "").strip().upper()
    if currency != expected_attempt_currency or currency != expected_invoice_currency:
        return None, None, "currency_mismatch"

    return amount, currency, ""


def _mark_invoice_reversal(*, invoice: Invoice, next_status: str):
    invoice.clear_payment_confirmation()
    if next_status == InvoiceStatus.REFUNDED:
        invoice.mark_refunded()
    elif next_status == InvoiceStatus.CANCELLED:
        invoice.mark_cancelled(force=True)
    else:
        invoice.mark_failed()


@transaction.atomic
def init_payment(*, invoice: Invoice, provider: str, by_user, idempotency_key: str | None = None):
    """
    إنشاء محاولة دفع مع idempotency:
    - إذا وصل نفس idempotency_key لنفس الفاتورة ولم تنجح/تفشل بشكل نهائي => نعيد نفس المحاولة
    """
    invoice = Invoice.objects.select_for_update().get(pk=invoice.pk)

    if invoice.is_payment_effective():
        raise ValueError("الفاتورة مدفوعة بالفعل.")

    if invoice.status == InvoiceStatus.PAID and not invoice.is_payment_effective():
        invoice.status = InvoiceStatus.PENDING
        invoice.clear_payment_confirmation()
        invoice.save(
            update_fields=[
                "status",
                "payment_confirmed",
                "payment_confirmed_at",
                "payment_provider",
                "payment_reference",
                "payment_event_id",
                "payment_amount",
                "payment_currency",
                "updated_at",
            ]
        )

    if not idempotency_key:
        idempotency_key = secrets.token_urlsafe(24)

    existing = PaymentAttempt.objects.filter(
        invoice=invoice,
        idempotency_key=idempotency_key,
    ).order_by("-created_at").first()

    if existing:
        return existing

    invoice.status = InvoiceStatus.PENDING
    invoice.save(update_fields=["status", "updated_at"])

    attempt = PaymentAttempt.objects.create(
        invoice=invoice,
        provider=provider,
        status=PaymentAttemptStatus.INITIATED,
        idempotency_key=idempotency_key,
        amount=invoice.total,
        currency=invoice.currency,
        created_by=by_user,
        request_payload={"invoice_code": invoice.code, "total": str(invoice.total)},
    )

    # في المزود الحقيقي هنا سننشئ Session/Intent ثم نخزن checkout_url + provider_reference
    attempt.checkout_url = _make_checkout_url(provider, str(attempt.id))
    attempt.provider_reference = f"mock_ref_{attempt.id.hex[:12]}"
    attempt.status = PaymentAttemptStatus.REDIRECTED
    attempt.save(update_fields=["checkout_url", "provider_reference", "status"])

    return attempt


@transaction.atomic
def complete_mock_payment(*, invoice: Invoice, by_user, idempotency_key: str | None = None):
    invoice = Invoice.objects.select_for_update().get(pk=invoice.pk)
    if invoice.is_payment_effective():
        attempt = PaymentAttempt.objects.filter(
            invoice=invoice,
            provider=PaymentProvider.MOCK,
        ).order_by("-created_at").first()
        return invoice, attempt

    attempt = init_payment(
        invoice=invoice,
        provider=PaymentProvider.MOCK,
        by_user=by_user,
        idempotency_key=idempotency_key or f"mock-invoice-{invoice.id}",
    )
    event_id = f"mock-complete-{attempt.id}"
    payload = {
        "provider_reference": attempt.provider_reference,
        "invoice_code": invoice.code,
        "status": "success",
        "amount": str(invoice.total),
        "currency": invoice.currency,
    }
    signature = sign_webhook_payload(provider=PaymentProvider.MOCK, payload=payload, event_id=event_id)
    result = handle_webhook(
        provider=PaymentProvider.MOCK,
        payload=payload,
        signature=signature,
        event_id=event_id,
    )
    if not result.get("ok"):
        raise ValueError(result.get("detail") or "تعذر إتمام الدفع التجريبي.")
    invoice.refresh_from_db()
    attempt.refresh_from_db()
    return invoice, attempt


@transaction.atomic
def handle_webhook(*, provider: str, payload: dict, signature: str = "", event_id: str = ""):
    """
    معالجة webhook بشكل آمن:
    - تحقق من التوقيع
    - تحقق من idempotency عبر event_id
    - تحقق من amount/currency
    - تحديث حالة المحاولة والفاتورة فقط إذا كان الحدث موثوقًا
    """
    provider = (provider or "").strip().lower()
    payload = payload if isinstance(payload, dict) else {}
    signature = (signature or "").strip()
    event_id = ((event_id or payload.get("event_id") or "")).strip()[:120]
    supported_providers = {str(value).strip().lower() for value in PaymentProvider.values}

    if provider not in supported_providers:
        return _reject_webhook(
            provider=provider,
            event_id=event_id,
            code="unsupported_provider",
            detail="مزود الدفع غير مدعوم.",
            http_status=400,
            payload=payload,
        )

    if not event_id:
        return _reject_webhook(
            provider=provider,
            event_id=event_id,
            code="missing_event_id",
            detail="رقم الحدث مطلوب للتحقق من عدم التكرار.",
            http_status=400,
            payload=payload,
        )

    if not _verify_webhook_signature(provider=provider, payload=payload, signature=signature, event_id=event_id):
        return _reject_webhook(
            provider=provider,
            event_id=event_id,
            code="invalid_signature",
            detail="توقيع webhook غير صالح.",
            http_status=403,
            payload=payload,
        )

    try:
        WebhookEvent.objects.create(
            provider=provider,
            event_id=event_id,
            signature=signature[:200],
            payload=payload or {},
        )
    except IntegrityError:
        return _reject_webhook(
            provider=provider,
            event_id=event_id,
            code="duplicate_event",
            detail="تمت معالجة هذا الحدث مسبقًا.",
            http_status=409,
            payload=payload,
        )

    provider_reference = (payload.get("provider_reference") or payload.get("reference") or "").strip()
    invoice_code = (payload.get("invoice_code") or "").strip()
    status_str = (payload.get("status") or "").lower().strip()

    if not status_str:
        return _reject_webhook(
            provider=provider,
            event_id=event_id,
            code="missing_status",
            detail="حالة الدفع غير موجودة في الـ webhook.",
            http_status=400,
            payload=payload,
        )

    if not provider_reference and not invoice_code:
        return _reject_webhook(
            provider=provider,
            event_id=event_id,
            code="missing_reference",
            detail="مرجع الدفع أو رقم الفاتورة مطلوب.",
            http_status=400,
            payload=payload,
        )

    attempt = None
    if provider_reference:
        attempt = (
            PaymentAttempt.objects.select_for_update()
            .select_related("invoice")
            .filter(provider=provider, provider_reference=provider_reference)
            .order_by("-created_at")
            .first()
        )

    if not attempt and invoice_code:
        attempt = (
            PaymentAttempt.objects.select_for_update()
            .select_related("invoice")
            .filter(provider=provider, invoice__code=invoice_code)
            .order_by("-created_at")
            .first()
        )

    if not attempt:
        return _reject_webhook(
            provider=provider,
            event_id=event_id,
            code="attempt_not_found",
            detail="تعذر العثور على محاولة الدفع المرتبطة.",
            http_status=404,
            payload=payload,
        )

    invoice = Invoice.objects.select_for_update().get(pk=attempt.invoice_id)

    if invoice_code and invoice.code != invoice_code:
        return _reject_webhook(
            provider=provider,
            event_id=event_id,
            code="invoice_mismatch",
            detail="مرجع الفاتورة في الـ webhook لا يطابق محاولة الدفع.",
            http_status=400,
            invoice=invoice,
            payload=payload,
        )

    amount, currency, amount_error = _success_amount_and_currency(attempt=attempt, invoice=invoice, payload=payload)
    if amount_error:
        detail_map = {
            "missing_amount": "مبلغ العملية مفقود في الـ webhook.",
            "missing_currency": "عملة العملية مفقودة في الـ webhook.",
            "amount_mismatch": "مبلغ العملية لا يطابق مبلغ الفاتورة/المحاولة.",
            "currency_mismatch": "عملة العملية لا تطابق عملة الفاتورة/المحاولة.",
        }
        return _reject_webhook(
            provider=provider,
            event_id=event_id,
            code=amount_error,
            detail=detail_map.get(amount_error, "Webhook غير صالح."),
            http_status=400,
            invoice=invoice,
            payload=payload,
        )

    previous_effective_payment = invoice.is_payment_effective()
    attempt.response_payload = payload

    if status_str in SUCCESS_STATUSES:
        attempt.status = PaymentAttemptStatus.SUCCESS
        attempt.save(update_fields=["status", "response_payload"])

        invoice.mark_payment_confirmed(
            provider=provider,
            provider_reference=provider_reference or attempt.provider_reference or invoice.code,
            event_id=event_id,
            amount=amount,
            currency=currency,
            when=timezone.now(),
        )
        invoice.save(
            update_fields=[
                "status",
                "paid_at",
                "cancelled_at",
                "payment_confirmed",
                "payment_confirmed_at",
                "payment_provider",
                "payment_reference",
                "payment_event_id",
                "payment_amount",
                "payment_currency",
                "updated_at",
            ]
        )

        try:
            from apps.audit.models import AuditAction

            _log_action_safe(
                actor=invoice.user,
                action=AuditAction.INVOICE_PAID,
                reference_type="invoice",
                reference_id=invoice.code,
                extra={
                    "total": str(invoice.total),
                    "trusted": True,
                    "provider": provider,
                    "event_id": event_id,
                    "reference_type": invoice.reference_type,
                    "reference_id": invoice.reference_id,
                },
            )
        except Exception:
            pass

        return _result(
            ok=True,
            detail="تم اعتماد الدفع بنجاح.",
            code="paid",
            http_status=200,
            invoice=invoice.code,
            status="paid",
        )

    if status_str in FAILURE_STATUSES:
        attempt.status = PaymentAttemptStatus.FAILED
        attempt.save(update_fields=["status", "response_payload"])

        _mark_invoice_reversal(
            invoice=invoice,
            next_status=InvoiceStatus.REFUNDED if previous_effective_payment else InvoiceStatus.FAILED,
        )
        invoice.save(
            update_fields=[
                "status",
                "cancelled_at",
                "payment_confirmed",
                "payment_confirmed_at",
                "payment_provider",
                "payment_reference",
                "payment_event_id",
                "payment_amount",
                "payment_currency",
                "updated_at",
            ]
        )
        if previous_effective_payment:
            try:
                from apps.audit.models import AuditAction

                _log_action_safe(
                    actor=invoice.user,
                    action=AuditAction.INVOICE_PAYMENT_REVERSED,
                    reference_type="invoice",
                    reference_id=invoice.code,
                    extra={
                        "provider": provider,
                        "event_id": event_id,
                        "new_status": invoice.status,
                        "reason": status_str,
                        "reference_type": invoice.reference_type,
                        "reference_id": invoice.reference_id,
                    },
                )
            except Exception:
                pass
        return _result(
            ok=True,
            detail="تم تحديث الفاتورة بحالة فشل.",
            code="failed",
            http_status=200,
            invoice=invoice.code,
            status=invoice.status,
        )

    if status_str in CANCELLED_STATUSES:
        attempt.status = PaymentAttemptStatus.CANCELLED
        attempt.save(update_fields=["status", "response_payload"])

        _mark_invoice_reversal(invoice=invoice, next_status=InvoiceStatus.CANCELLED)
        invoice.save(
            update_fields=[
                "status",
                "cancelled_at",
                "payment_confirmed",
                "payment_confirmed_at",
                "payment_provider",
                "payment_reference",
                "payment_event_id",
                "payment_amount",
                "payment_currency",
                "updated_at",
            ]
        )
        if previous_effective_payment:
            try:
                from apps.audit.models import AuditAction

                _log_action_safe(
                    actor=invoice.user,
                    action=AuditAction.INVOICE_PAYMENT_REVERSED,
                    reference_type="invoice",
                    reference_id=invoice.code,
                    extra={
                        "provider": provider,
                        "event_id": event_id,
                        "new_status": invoice.status,
                        "reason": status_str,
                        "reference_type": invoice.reference_type,
                        "reference_id": invoice.reference_id,
                    },
                )
            except Exception:
                pass
        return _result(
            ok=True,
            detail="تم إلغاء الفاتورة.",
            code="cancelled",
            http_status=200,
            invoice=invoice.code,
            status=invoice.status,
        )

    if status_str in REVERSAL_STATUSES:
        attempt.status = PaymentAttemptStatus.REFUNDED
        attempt.save(update_fields=["status", "response_payload"])

        _mark_invoice_reversal(invoice=invoice, next_status=InvoiceStatus.REFUNDED)
        invoice.save(
            update_fields=[
                "status",
                "cancelled_at",
                "payment_confirmed",
                "payment_confirmed_at",
                "payment_provider",
                "payment_reference",
                "payment_event_id",
                "payment_amount",
                "payment_currency",
                "updated_at",
            ]
        )
        try:
            from apps.audit.models import AuditAction

            _log_action_safe(
                actor=invoice.user,
                action=AuditAction.INVOICE_PAYMENT_REVERSED,
                reference_type="invoice",
                reference_id=invoice.code,
                extra={
                    "provider": provider,
                    "event_id": event_id,
                    "new_status": invoice.status,
                    "reason": status_str,
                    "reference_type": invoice.reference_type,
                    "reference_id": invoice.reference_id,
                },
            )
        except Exception:
            pass
        return _result(
            ok=True,
            detail="تم عكس/استرجاع عملية الدفع.",
            code="reversed",
            http_status=200,
            invoice=invoice.code,
            status=invoice.status,
        )

    attempt.save(update_fields=["response_payload"])
    return _result(
        ok=True,
        detail="تم تجاهل حالة webhook غير معروفة.",
        code="ignored",
        http_status=200,
        invoice=invoice.code,
        status="ignored",
    )
