from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP
from uuid import uuid4

from django.core.exceptions import PermissionDenied, ValidationError
from django.db import transaction
from django.utils import timezone

from apps.marketplace.models import (
    PaymentInstallmentStatus,
    PaymentPlanStatus,
    RequestStatus,
    RequestStatusLog,
    ServiceRequest,
    ServiceRequestPaymentInstallment,
    ServiceRequestPaymentPlan,
)


MONEY_QUANT = Decimal("0.01")


def _money(value) -> Decimal:
    if value in (None, ""):
        return Decimal("0.00")
    return Decimal(str(value)).quantize(MONEY_QUANT, rounding=ROUND_HALF_UP)


def _bank_snapshot(provider):
    try:
        settings = provider.extras_portal_finance_settings
    except Exception:
        return None

    iban = (getattr(settings, "iban", "") or "").strip()
    account_number = (getattr(settings, "account_number", "") or "").strip()
    qr_image = getattr(settings, "qr_image", None)
    if not (iban or account_number or qr_image):
        return None

    account_name = (getattr(settings, "account_name", "") or "").strip()
    if not account_name:
        first = (getattr(settings, "account_holder_first_name", "") or "").strip()
        last = (getattr(settings, "account_holder_last_name", "") or "").strip()
        account_name = f"{first} {last}".strip()

    return {
        "bank_name": (getattr(settings, "bank_name", "") or "").strip(),
        "account_name": account_name,
        "account_number": account_number,
        "iban": iban,
        "qr_image_name": getattr(qr_image, "name", "") or "",
    }


def provider_has_payment_profile(provider) -> bool:
    if not provider:
        return False
    try:
        from apps.extras_portal.access import provider_has_bank_qr_registration

        if not provider_has_bank_qr_registration(provider):
            return False
    except Exception:
        return False
    return bool(_bank_snapshot(provider))


def ensure_payment_plan_for_request(sr: ServiceRequest) -> ServiceRequestPaymentPlan | None:
    if not sr.provider_id or sr.status != RequestStatus.IN_PROGRESS:
        return None

    total = _money(sr.estimated_service_amount)
    if total <= 0:
        return None

    if not provider_has_payment_profile(sr.provider):
        return None
    bank = _bank_snapshot(sr.provider)

    confirmed = _money(sr.received_amount)
    if confirmed > total:
        confirmed = total
    remaining = total - confirmed
    status = PaymentPlanStatus.PAID if remaining <= 0 else PaymentPlanStatus.OPEN

    plan, created = ServiceRequestPaymentPlan.objects.get_or_create(
        request=sr,
        defaults={
            "provider": sr.provider,
            "client": sr.client,
            "total_amount": total,
            "confirmed_amount": confirmed,
            "remaining_amount": remaining,
            "reference": f"NF-{sr.id}-{uuid4().hex[:8].upper()}",
            "status": status,
            **bank,
        },
    )
    if created:
        if confirmed > 0:
            ServiceRequestPaymentInstallment.objects.create(
                plan=plan,
                request=sr,
                sequence=1,
                title="دفعة مسجلة عند اعتماد الطلب",
                amount=confirmed,
                status=PaymentInstallmentStatus.CONFIRMED,
                provider_note="مبلغ مسجل مسبقاً ضمن تفاصيل التنفيذ",
                confirmed_at=timezone.now(),
            )
        return plan

    changed = []
    for field, value in {
        "provider": sr.provider,
        "client": sr.client,
        "total_amount": total,
    }.items():
        current = getattr(plan, field)
        if current != value:
            setattr(plan, field, value)
            changed.append(field)
    if changed:
        plan.save(update_fields=[*changed, "updated_at"])
    recalculate_payment_plan(plan)
    return plan


def recalculate_payment_plan(plan: ServiceRequestPaymentPlan) -> ServiceRequestPaymentPlan:
    confirmed = sum(
        (_money(item.amount) for item in plan.installments.filter(status=PaymentInstallmentStatus.CONFIRMED)),
        Decimal("0.00"),
    )
    total = _money(plan.total_amount)
    if confirmed > total:
        confirmed = total
    remaining = total - confirmed
    plan.confirmed_amount = confirmed
    plan.remaining_amount = remaining
    plan.status = PaymentPlanStatus.PAID if remaining <= 0 else PaymentPlanStatus.OPEN
    plan.save(update_fields=["confirmed_amount", "remaining_amount", "status", "updated_at"])

    sr = plan.request
    sr.estimated_service_amount = total
    sr.received_amount = confirmed
    sr.remaining_amount = remaining
    sr.save(update_fields=["estimated_service_amount", "received_amount", "remaining_amount"])
    return plan


def revise_payment_plan_total(plan: ServiceRequestPaymentPlan, *, total_amount) -> ServiceRequestPaymentPlan:
    total = _money(total_amount)
    if total <= 0:
        raise ValidationError("القيمة الجديدة يجب أن تكون أكبر من صفر")

    confirmed = _money(plan.confirmed_amount)
    pending_total = sum(
        (
            _money(item.amount)
            for item in plan.installments.filter(
                status__in=[
                    PaymentInstallmentStatus.PENDING_PAYMENT,
                    PaymentInstallmentStatus.RECEIPT_UPLOADED,
                ]
            )
        ),
        Decimal("0.00"),
    )
    committed_total = confirmed + pending_total
    if total < committed_total:
        raise ValidationError("لا يمكن أن تكون القيمة الجديدة أقل من الدفعات المؤكدة أو الدفعات المطلوبة حالياً")

    if _money(plan.total_amount) != total:
        plan.total_amount = total
        plan.save(update_fields=["total_amount", "updated_at"])

    return recalculate_payment_plan(plan)


def create_installment(*, provider_user, request_id: int, title: str, amount, note: str = ""):
    with transaction.atomic():
        sr = (
            ServiceRequest.objects.select_for_update()
            .select_related("client", "provider", "provider__user")
            .get(id=request_id)
        )
        if not sr.provider_id or sr.provider.user_id != getattr(provider_user, "id", None):
            raise PermissionDenied("غير مصرح")
        if sr.status != RequestStatus.IN_PROGRESS:
            raise ValidationError("يمكن طلب الدفعات بعد بدء التنفيذ فقط")

        plan = ensure_payment_plan_for_request(sr)
        if not plan:
            raise ValidationError("أكمل إعداد الحساب البنكي للمزود قبل إنشاء الدفعات")
        if plan.status == PaymentPlanStatus.PAID:
            raise ValidationError("تم سداد قيمة الطلب بالكامل")

        amount_value = _money(amount)
        if amount_value <= 0:
            raise ValidationError("قيمة الدفعة يجب أن تكون أكبر من صفر")

        pending_total = sum(
            (
                _money(item.amount)
                for item in plan.installments.filter(
                    status__in=[
                        PaymentInstallmentStatus.PENDING_PAYMENT,
                        PaymentInstallmentStatus.RECEIPT_UPLOADED,
                    ]
                )
            ),
            Decimal("0.00"),
        )
        available = _money(plan.remaining_amount) - pending_total
        if amount_value > available:
            raise ValidationError("قيمة الدفعة تتجاوز المبلغ المتبقي غير المطلوب")

        sequence = (plan.installments.order_by("-sequence").values_list("sequence", flat=True).first() or 0) + 1
        installment = ServiceRequestPaymentInstallment.objects.create(
            plan=plan,
            request=sr,
            sequence=sequence,
            title=(title or f"دفعة رقم {sequence}")[:120],
            amount=amount_value,
            provider_note=(note or "")[:255],
        )

        RequestStatusLog.objects.create(
            request=sr,
            actor=provider_user,
            from_status=sr.status,
            to_status=sr.status,
            note=f"طلب المزود دفعة بمبلغ {amount_value}",
        )
        transaction.on_commit(lambda: _notify_client_installment_requested(installment))
        return installment


def upload_installment_receipt(*, client_user, installment_id: int, receipt, note: str = "", request_id: int | None = None):
    with transaction.atomic():
        installment = (
            ServiceRequestPaymentInstallment.objects.select_for_update()
            .select_related("plan", "request", "request__provider", "request__client")
            .get(id=installment_id)
        )
        sr = installment.request
        if request_id is not None and sr.id != int(request_id):
            raise ValidationError("الدفعة لا تتبع هذا الطلب")
        if sr.client_id != getattr(client_user, "id", None):
            raise PermissionDenied("غير مصرح")
        if installment.status not in {
            PaymentInstallmentStatus.PENDING_PAYMENT,
            PaymentInstallmentStatus.REJECTED,
        }:
            raise ValidationError("لا يمكن رفع إيصال لهذه الدفعة حالياً")
        if _money(installment.amount) > _money(installment.plan.remaining_amount):
            raise ValidationError("قيمة الدفعة تتجاوز المبلغ المتبقي")

        installment.receipt = receipt
        installment.client_note = (note or "")[:255]
        installment.receipt_uploaded_by = client_user
        installment.receipt_uploaded_at = timezone.now()
        installment.status = PaymentInstallmentStatus.RECEIPT_UPLOADED
        installment.rejected_by = None
        installment.rejected_at = None
        installment.rejection_reason = ""
        installment.save(
            update_fields=[
                "receipt",
                "client_note",
                "receipt_uploaded_by",
                "receipt_uploaded_at",
                "status",
                "rejected_by",
                "rejected_at",
                "rejection_reason",
                "updated_at",
            ]
        )
        RequestStatusLog.objects.create(
            request=sr,
            actor=client_user,
            from_status=sr.status,
            to_status=sr.status,
            note=f"رفع العميل إيصال دفعة بمبلغ {installment.amount}",
        )
        transaction.on_commit(lambda: _notify_provider_receipt_uploaded(installment))
        return installment


def decide_installment_receipt(*, provider_user, installment_id: int, approved: bool, note: str = "", request_id: int | None = None):
    with transaction.atomic():
        installment = (
            ServiceRequestPaymentInstallment.objects.select_for_update()
            .select_related("plan", "request", "request__provider", "request__client")
            .get(id=installment_id)
        )
        sr = installment.request
        if request_id is not None and sr.id != int(request_id):
            raise ValidationError("الدفعة لا تتبع هذا الطلب")
        if not sr.provider_id or sr.provider.user_id != getattr(provider_user, "id", None):
            raise PermissionDenied("غير مصرح")
        if installment.status != PaymentInstallmentStatus.RECEIPT_UPLOADED:
            raise ValidationError("لا توجد دفعة بانتظار التأكيد")

        if approved:
            installment.status = PaymentInstallmentStatus.CONFIRMED
            installment.confirmed_by = provider_user
            installment.confirmed_at = timezone.now()
            installment.rejection_reason = ""
            update_fields = ["status", "confirmed_by", "confirmed_at", "rejection_reason", "updated_at"]
            log_note = f"أكد المزود استلام دفعة بمبلغ {installment.amount}"
        else:
            clean_note = (note or "").strip()
            if not clean_note:
                raise ValidationError("سبب الرفض مطلوب")
            installment.status = PaymentInstallmentStatus.REJECTED
            installment.rejected_by = provider_user
            installment.rejected_at = timezone.now()
            installment.rejection_reason = clean_note[:255]
            update_fields = ["status", "rejected_by", "rejected_at", "rejection_reason", "updated_at"]
            log_note = f"رفض المزود إيصال دفعة بمبلغ {installment.amount}: {clean_note[:160]}"

        installment.save(update_fields=update_fields)
        if approved:
            recalculate_payment_plan(installment.plan)

        RequestStatusLog.objects.create(
            request=sr,
            actor=provider_user,
            from_status=sr.status,
            to_status=sr.status,
            note=log_note[:255],
        )
        transaction.on_commit(lambda: _notify_client_installment_decision(installment, approved))
        return installment


def serialize_payment_plan(plan: ServiceRequestPaymentPlan | None, *, request=None) -> dict | None:
    if not plan:
        return None

    def file_url(field):
        try:
            url = field.url
        except Exception:
            return ""
        return request.build_absolute_uri(url) if request else url

    qr_url = ""
    if plan.qr_image_name:
        from django.core.files.storage import default_storage

        try:
            url = default_storage.url(plan.qr_image_name)
            qr_url = request.build_absolute_uri(url) if request else url
        except Exception:
            qr_url = ""

    installments = []
    for item in plan.installments.all():
        installments.append(
            {
                "id": item.id,
                "sequence": item.sequence,
                "title": item.title,
                "amount": str(_money(item.amount)),
                "status": item.status,
                "provider_note": item.provider_note,
                "client_note": item.client_note,
                "receipt_url": file_url(item.receipt),
                "receipt_uploaded_at": item.receipt_uploaded_at,
                "confirmed_at": item.confirmed_at,
                "rejected_at": item.rejected_at,
                "rejection_reason": item.rejection_reason,
                "created_at": item.created_at,
            }
        )

    can_client_pay = (
        plan.status == PaymentPlanStatus.OPEN
        and _money(plan.remaining_amount) > 0
        and any(item["status"] in {PaymentInstallmentStatus.PENDING_PAYMENT, PaymentInstallmentStatus.REJECTED} for item in installments)
    )
    can_provider_request_installment = plan.status == PaymentPlanStatus.OPEN and _money(plan.remaining_amount) > 0

    return {
        "id": plan.id,
        "request_id": plan.request_id,
        "reference": plan.reference,
        "status": plan.status,
        "currency": plan.currency,
        "total_amount": str(_money(plan.total_amount)),
        "confirmed_amount": str(_money(plan.confirmed_amount)),
        "remaining_amount": str(_money(plan.remaining_amount)),
        "bank": {
            "bank_name": plan.bank_name,
            "account_name": plan.account_name,
            "account_number": plan.account_number,
            "iban": plan.iban,
            "qr_image_url": qr_url,
        },
        "installments": installments,
        "can_client_pay": can_client_pay,
        "can_provider_request_installment": can_provider_request_installment,
        "created_at": plan.created_at,
        "updated_at": plan.updated_at,
    }


def _notify_client_installment_requested(installment) -> None:
    from apps.notifications.models import EventType
    from apps.notifications.services import create_notification

    sr = installment.request
    create_notification(
        user=sr.client,
        title="دفعة جديدة مطلوبة",
        body=f"طلب مزود الخدمة دفعة بمبلغ {installment.amount} للطلب: {sr.title}.",
        kind="request_status_change",
        url=f"/orders/{sr.id}",
        actor=getattr(sr.provider, "user", None),
        event_type=EventType.STATUS_CHANGED,
        pref_key="request_status_change",
        request_id=sr.id,
        meta={"payment_installment_id": installment.id, "payment_status": installment.status},
        audience_mode="client",
    )


def _notify_provider_receipt_uploaded(installment) -> None:
    from apps.notifications.models import EventType
    from apps.notifications.services import create_notification

    sr = installment.request
    provider_user = getattr(sr.provider, "user", None)
    if not provider_user:
        return
    create_notification(
        user=provider_user,
        title="إيصال دفعة بانتظار التأكيد",
        body=f"رفع العميل إيصال دفعة بمبلغ {installment.amount} للطلب: {sr.title}.",
        kind="request_status_change",
        url=f"/provider-orders/{sr.id}",
        actor=sr.client,
        event_type=EventType.STATUS_CHANGED,
        pref_key="request_status_change",
        request_id=sr.id,
        meta={"payment_installment_id": installment.id, "payment_status": installment.status},
        audience_mode="provider",
    )


def _notify_client_installment_decision(installment, approved: bool) -> None:
    from apps.notifications.models import EventType
    from apps.notifications.services import create_notification

    sr = installment.request
    title = "تم تأكيد الدفعة" if approved else "تم رفض إيصال الدفعة"
    body = f"أكد مزود الخدمة استلام دفعة بمبلغ {installment.amount}."
    if not approved:
        body = f"رفض مزود الخدمة إيصال دفعة بمبلغ {installment.amount}."
        if installment.rejection_reason:
            body += f" السبب: {installment.rejection_reason}"
    create_notification(
        user=sr.client,
        title=title,
        body=body[:500],
        kind="request_status_change",
        url=f"/orders/{sr.id}",
        actor=getattr(sr.provider, "user", None),
        event_type=EventType.STATUS_CHANGED,
        pref_key="request_status_change",
        request_id=sr.id,
        meta={"payment_installment_id": installment.id, "payment_status": installment.status},
        audience_mode="client",
    )
