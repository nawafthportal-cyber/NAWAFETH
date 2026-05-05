import logging
from dataclasses import dataclass

from django.core.exceptions import PermissionDenied, ValidationError
from django.db import transaction
from django.utils import timezone

from apps.marketplace.models import (
    Offer,
    PRE_EXECUTION_REQUEST_STATUSES,
    RequestStatus,
    RequestStatusLog,
    RequestType,
    ServiceRequest,
    service_request_pending_input_return_status,
    service_request_pending_input_stage,
)
from apps.providers.models import ProviderProfile

from .cancellation_copy import provider_pool_cancel_notification_text
from .dispatch import (
    clear_request_pool_delivery_records,
    dispatch_due_competitive_request_notifications,
    dispatch_ready_urgent_windows,
    ensure_dispatch_windows_for_urgent_request,
)

logger = logging.getLogger(__name__)


def _notify_provider_inputs_decision(*, sr: ServiceRequest, actor, approved: bool, note: str = "", stage: str = "") -> None:
    if not getattr(sr, "provider_id", None):
        return

    from apps.notifications.models import EventType
    from apps.notifications.services import create_notification

    provider_profile = ProviderProfile.objects.select_related("user").filter(id=sr.provider_id).first()
    provider_user = getattr(provider_profile, "user", None)
    if provider_user is None:
        return

    subject_label = "تحديث التقدم" if stage == "progress_update" else "تفاصيل التنفيذ"
    title = f"تم {'اعتماد' if approved else 'رفض'} {subject_label}"
    if approved:
        body = f"اعتمد العميل {subject_label} الخاصة بالطلب: {sr.title}. يمكنك متابعة التنفيذ الآن."
    else:
        body = f"رفض العميل {subject_label} الخاصة بالطلب: {sr.title}."
        if note:
            body += f" السبب: {note}"

    create_notification(
        user=provider_user,
        title=title,
        body=body[:500],
        kind="request_status_change",
        url=f"/provider-orders/{sr.id}",
        actor=actor,
        event_type=EventType.STATUS_CHANGED,
        pref_key="request_status_change",
        request_id=sr.id,
        meta={
            "decision": "approved" if approved else "rejected",
            "provider_inputs_stage": stage,
            "note": (note or "")[:255],
            "to_status": sr.status,
        },
        audience_mode="provider",
    )


def _notify_pool_request_cancelled_providers(*, sr: ServiceRequest, actor, note: str, previous_provider_user_id: int | None = None) -> None:
    from apps.notifications.models import EventLog, EventType, Notification
    from apps.notifications.services import create_notification, delete_notifications

    request_type_value = (getattr(sr, "request_type", "") or "").strip().lower()
    if request_type_value not in {RequestType.URGENT, RequestType.COMPETITIVE}:
        return

    original_notification_kind = "urgent_request" if request_type_value == RequestType.URGENT else "request_created"
    replacement_title = (
        f"إلغاء الطلب العاجل: {sr.title}"
        if request_type_value == RequestType.URGENT
        else f"إلغاء الطلب التنافسي: {sr.title}"
    )
    replacement_meta_flag = (
        "cancelled_from_urgent_pool" if request_type_value == RequestType.URGENT else "cancelled_from_competitive_pool"
    )

    provider_user_ids = list(
        EventLog.objects.filter(
            event_type=EventType.REQUEST_CREATED,
            request_id=sr.id,
            target_user__isnull=False,
        )
        .values_list("target_user_id", flat=True)
        .distinct()
    )
    if previous_provider_user_id:
        provider_user_ids.append(int(previous_provider_user_id))

    provider_user_ids = list(dict.fromkeys(int(user_id) for user_id in provider_user_ids if user_id))
    if not provider_user_ids:
        return

    request_url = f"/requests/{sr.id}"
    delete_notifications(
        qs=Notification.objects.filter(
            user_id__in=provider_user_ids,
            kind=original_notification_kind,
            audience_mode="provider",
            url=request_url,
        )
    )

    note_text = ((note or "").strip() or (getattr(sr, "cancel_reason", "") or "").strip())
    body, deadline_cancellation = provider_pool_cancel_notification_text(
        sr=sr,
        actor=actor,
        note_text=note_text,
    )
    if len(body) > 500:
        body = body[:497].rstrip() + "..."

    provider_users = {
        provider.user_id: provider.user
        for provider in ProviderProfile.objects.select_related("user").filter(user_id__in=provider_user_ids)
    }

    for user_id in provider_user_ids:
        if getattr(actor, "id", None) == user_id:
            continue
        provider_user = provider_users.get(user_id)
        if provider_user is None:
            continue
        create_notification(
            user=provider_user,
            title=replacement_title,
            body=body,
            kind="request_status_change",
            url="",
            actor=actor,
            event_type=EventType.STATUS_CHANGED,
            pref_key="request_status_change",
            request_id=sr.id,
            meta={
                "from_status": RequestStatus.NEW,
                "to_status": RequestStatus.CANCELLED,
                replacement_meta_flag: True,
                "request_type": request_type_value,
                "note": note_text[:255],
                "cancelled_due_to_deadline": deadline_cancellation,
            },
            audience_mode="provider",
        )


@dataclass(frozen=True)
class ActionResult:
    ok: bool
    message: str
    new_status: str | None = None


def _log_request_status_change(*, sr: ServiceRequest, actor, from_status: str, note: str) -> None:
    RequestStatusLog.objects.create(
        request=sr,
        actor=actor,
        from_status=from_status,
        to_status=sr.status,
        note=(note or "")[:255],
    )


def relist_request_to_pool(
    *,
    sr: ServiceRequest,
    actor,
    note: str,
    previous_provider_user_id: int | None = None,
) -> None:
    if sr.request_type not in {RequestType.URGENT, RequestType.COMPETITIVE}:
        raise ValidationError("إعادة طرح هذا النوع من الطلبات غير مدعومة حالياً")
    if not request_is_before_execution(sr):
        raise ValidationError("لا يمكن إعادة طرح الطلب بعد بدء التنفيذ")

    old = sr.status
    sr.release_to_pool()

    if sr.request_type == RequestType.COMPETITIVE:
        Offer.objects.filter(request=sr).delete()

    _log_request_status_change(sr=sr, actor=actor, from_status=old, note=note)

    excluded_user_ids = [previous_provider_user_id] if previous_provider_user_id else []

    def _redispatch() -> None:
        clear_request_pool_delivery_records(
            sr,
            clear_event_logs=True,
            excluded_user_ids=excluded_user_ids,
        )
        now = timezone.now()
        if sr.request_type == RequestType.URGENT:
            ensure_dispatch_windows_for_urgent_request(sr, now=now)
            dispatch_ready_urgent_windows(now=now, limit=200)
        elif sr.request_type == RequestType.COMPETITIVE:
            dispatch_due_competitive_request_notifications(now=now, limit=200)

    transaction.on_commit(_redispatch)


@transaction.atomic
def hard_delete_request(*, user, request_id: int) -> ActionResult:
    sr = (
        ServiceRequest.objects.select_for_update()
        .select_related("client")
        .prefetch_related("attachments")
        .get(id=request_id)
    )

    is_staff, is_client, _ = _role_flags(user, sr)
    if not (is_staff or is_client):
        raise PermissionDenied("غير مصرح")
    if not request_is_before_execution(sr):
        raise ValidationError("لا يمكن حذف الطلب نهائياً بعد بدء التنفيذ")

    from apps.messaging.models import Message
    from apps.notifications.models import EventLog, Notification
    from apps.notifications.services import delete_notifications

    request_urls = [
        f"/requests/{sr.id}",
        f"/requests/{sr.id}/chat",
        f"/orders/{sr.id}",
        f"/provider-orders/{sr.id}",
    ]

    delete_notifications(qs=Notification.objects.filter(url__in=request_urls))
    EventLog.objects.filter(request_id=sr.id).delete()

    for attachment in list(sr.attachments.all()):
        try:
            attachment.file.delete(save=False)
        except Exception:
            logger.exception("request_attachment_delete_failed request_id=%s attachment_id=%s", sr.id, attachment.id)

    for message in Message.objects.filter(thread__request=sr).exclude(attachment=""):
        try:
            message.attachment.delete(save=False)
        except Exception:
            logger.exception("request_message_attachment_delete_failed request_id=%s message_id=%s", sr.id, message.id)

    sr.delete()
    return ActionResult(True, "تم حذف الطلب نهائياً")


def _role_flags(user, sr: ServiceRequest):
    is_staff = bool(getattr(user, "is_staff", False))
    user_id = getattr(user, "id", None)
    is_client = bool(user_id) and (sr.client_id == user_id)
    is_provider = bool(user_id) and bool(sr.provider_id) and (sr.provider.user_id == user_id)
    return is_staff, is_client, is_provider


def request_is_before_execution(sr: ServiceRequest) -> bool:
    if sr.status in (RequestStatus.NEW, RequestStatus.PROVIDER_ACCEPTED):
        return True
    if sr.status == RequestStatus.AWAITING_CLIENT_APPROVAL:
        return service_request_pending_input_stage(sr) != "progress_update"
    return False


def allowed_actions(user, sr: ServiceRequest, *, has_provider_profile: bool | None = None) -> list[str]:
    """
    Returns actions allowed for a given user and service request.
    """
    is_staff, is_client, is_provider = _role_flags(user, sr)
    acts: list[str] = []

    if is_staff:
        base = ["cancel", "accept", "start", "complete"]
        if sr.status == RequestStatus.CANCELLED:
            base.append("reopen")
        return base

    if is_client:
        pending_input_stage = service_request_pending_input_stage(sr)
        is_before_execution = request_is_before_execution(sr)
        if is_before_execution:
            acts.append("delete")
        if (
            is_before_execution
            and sr.provider_id is not None
            and sr.request_type in {RequestType.URGENT, RequestType.COMPETITIVE}
        ):
            acts.append("relist")
        if sr.status == RequestStatus.NEW:
            acts.append("send")
            if sr.provider_id is None or sr.request_type == RequestType.URGENT:
                acts.append("cancel")
        elif (
            sr.request_type == RequestType.URGENT
            and sr.status in PRE_EXECUTION_REQUEST_STATUSES
            and pending_input_stage != "progress_update"
        ):
            acts.append("cancel")
        if sr.status == RequestStatus.AWAITING_CLIENT_APPROVAL and sr.provider_inputs_approved is None:
            acts.extend(["approve_inputs", "reject_inputs"])
        if sr.status == RequestStatus.CANCELLED:
            acts.append("reopen")
        return acts

    # Legacy HTML pages only expose a safe subset of provider actions.
    # Full provider lifecycle now flows through dedicated API endpoints that
    # validate request-type specific constraints and required payloads.
    if sr.status == RequestStatus.NEW:
        user_id = getattr(user, "id", None)
        if user_id:
            if has_provider_profile is None:
                has_provider_profile = ProviderProfile.objects.filter(user_id=user_id).exists()
            if has_provider_profile:
                if sr.provider_id is None and sr.request_type == RequestType.URGENT:
                    acts.append("accept")
                elif is_provider and sr.request_type != RequestType.COMPETITIVE:
                    acts.append("accept")

    if is_provider:
        return acts

    return acts


@transaction.atomic
def execute_action(
    *,
    user,
    request_id: int,
    action: str,
    provider_profile: ProviderProfile | None = None,
    note: str = "",
) -> ActionResult:
    sr = (
        ServiceRequest.objects.select_for_update()
        # provider is nullable; joining it with FOR UPDATE on PostgreSQL may raise
        # "cannot be applied to the nullable side of an outer join".
        .select_related("client")
        .get(id=request_id)
    )

    is_staff, is_client, is_provider = _role_flags(user, sr)

    # send — backward-compatible no-op for competitive/new flow
    if action == "send":
        if not (is_staff or is_client):
            raise PermissionDenied("غير مصرح")
        if sr.status != RequestStatus.NEW:
            raise ValidationError("لا يمكن إرسال الطلب في هذه الحالة")
        return ActionResult(True, "تم إرسال الطلب", sr.status)

    # cancel — client: NEW + no provider (plus urgent pre-execution); provider/staff: pre-execution + in-progress
    if action == "cancel":
        if not (is_staff or is_provider or is_client):
            raise PermissionDenied("غير مصرح")
        old = sr.status
        cleaned_note = str(note or "").strip()
        previous_provider_user_id = None
        if sr.provider_id:
            previous_provider_user_id = ProviderProfile.objects.filter(id=sr.provider_id).values_list("user_id", flat=True).first()
        if is_client and not is_staff:
            pending_input_stage = service_request_pending_input_stage(sr)
            urgent_pending_with_provider = bool(
                sr.request_type == RequestType.URGENT
                and sr.status in PRE_EXECUTION_REQUEST_STATUSES
                and sr.provider_id is not None
                and pending_input_stage != "progress_update"
            )
            if sr.provider_id is not None and not urgent_pending_with_provider:
                raise PermissionDenied("لا يمكن إلغاء الطلب بعد قبول مزود الخدمة")
            client_allowed_statuses = list(PRE_EXECUTION_REQUEST_STATUSES) if urgent_pending_with_provider else [RequestStatus.NEW]
            sr.cancel(allowed_statuses=client_allowed_statuses)
            sr.canceled_at = timezone.now()
            sr.cancel_reason = cleaned_note[:255]
            sr.save(update_fields=["canceled_at", "cancel_reason"])
            if cleaned_note:
                note = cleaned_note
            elif urgent_pending_with_provider:
                note = "إلغاء الطلب العاجل من العميل بعد قبول مزود الخدمة"
            else:
                note = "إلغاء الطلب من العميل"
        else:
            sr.cancel(allowed_statuses=[*PRE_EXECUTION_REQUEST_STATUSES, RequestStatus.IN_PROGRESS])
            sr.canceled_at = timezone.now()
            sr.cancel_reason = cleaned_note[:255]
            sr.save(update_fields=["canceled_at", "cancel_reason"])
            if is_staff:
                note = cleaned_note or "إلغاء الطلب من فريق الإدارة"
            elif is_provider:
                note = cleaned_note or "إلغاء الطلب من مزود الخدمة"
            else:
                note = cleaned_note or "إلغاء الطلب"
        _log_request_status_change(sr=sr, actor=user, from_status=old, note=note)
        if sr.request_type in {RequestType.URGENT, RequestType.COMPETITIVE}:
            transaction.on_commit(
                lambda: _notify_pool_request_cancelled_providers(
                    sr=sr,
                    actor=user,
                    note=note,
                    previous_provider_user_id=previous_provider_user_id,
                )
            )
        return ActionResult(True, "تم إلغاء الطلب", sr.status)

    # accept
    if action == "accept":
        if sr.status != RequestStatus.NEW:
            raise ValidationError("لا يمكن قبول الطلب الآن")
        old = sr.status

        if is_staff:
            if not provider_profile:
                raise ValidationError("اختر مزودًا لقبول الطلب")
            sr.accept(provider_profile)
            _log_request_status_change(
                sr=sr,
                actor=user,
                from_status=old,
                note="قبول الطلب وإسناده لمزود الخدمة",
            )
            return ActionResult(True, "تم قبول الطلب وإسناده", sr.status)

        if not provider_profile:
            raise ValidationError("لا يوجد ملف مزود مرتبط بهذا الحساب")

        sr.accept(provider_profile)
        _log_request_status_change(
            sr=sr,
            actor=user,
            from_status=old,
            note="قبول الطلب من مزود الخدمة",
        )
        return ActionResult(True, "تم قبول الطلب", sr.status)

    # start
    if action == "start":
        if not (is_staff or is_provider):
            raise PermissionDenied("غير مصرح")
        old = sr.status
        sr.start()
        _log_request_status_change(
            sr=sr,
            actor=user,
            from_status=old,
            note="بدء التنفيذ",
        )
        return ActionResult(True, "تم بدء التنفيذ", sr.status)

    # complete
    if action == "complete":
        if not (is_staff or is_provider):
            raise PermissionDenied("غير مصرح")
        old = sr.status
        sr.complete()
        _log_request_status_change(
            sr=sr,
            actor=user,
            from_status=old,
            note="تم إكمال الطلب. يرجى مراجعة الطلب وتقييم الخدمة.",
        )
        return ActionResult(True, "تم إكمال الطلب", sr.status)

    # reopen — client + staff only, CANCELLED → NEW
    if action == "reopen":
        if not (is_staff or is_client):
            raise PermissionDenied("غير مصرح")
        old = sr.status
        sr.reopen()
        RequestStatusLog.objects.create(
            request=sr,
            actor=user,
            from_status=old,
            to_status=RequestStatus.NEW,
            note="إعادة فتح الطلب",
        )
        return ActionResult(True, "تم إعادة فتح الطلب", sr.status)

    if action == "relist":
        if not (is_staff or is_client):
            raise PermissionDenied("غير مصرح")
        if sr.provider_id is None:
            raise ValidationError("الطلب متاح بالفعل ولا يحتاج إلى إعادة طرح")
        previous_provider_user_id = ProviderProfile.objects.filter(id=sr.provider_id).values_list("user_id", flat=True).first()
        relist_request_to_pool(
            sr=sr,
            actor=user,
            note=str(note or "").strip() or "أعاد العميل طرح الطلب لمزودين آخرين قبل التنفيذ",
            previous_provider_user_id=previous_provider_user_id,
        )
        return ActionResult(True, "تمت إعادة طرح الطلب للمزودين الآخرين", sr.status)

    # approve_inputs — client only, awaiting client approval + inputs not yet decided
    if action == "approve_inputs":
        if not (is_staff or is_client):
            raise PermissionDenied("غير مصرح")
        if sr.status != RequestStatus.AWAITING_CLIENT_APPROVAL:
            raise ValidationError("لا يمكن اتخاذ قرار بشأن المدخلات في هذه الحالة")
        if sr.provider_inputs_approved is not None:
            raise ValidationError("تم اتخاذ قرار مسبقًا بشأن المدخلات")
        stage = service_request_pending_input_stage(sr)
        clean_note = str(note or "").strip()
        old = sr.status
        sr.status = RequestStatus.IN_PROGRESS
        sr.provider_inputs_approved = True
        sr.provider_inputs_decided_at = timezone.now()
        sr.provider_inputs_decision_note = clean_note[:255]
        sr.save(update_fields=["status", "provider_inputs_approved", "provider_inputs_decided_at", "provider_inputs_decision_note"])
        RequestStatusLog.objects.create(
            request=sr,
            actor=user,
            from_status=old,
            to_status=sr.status,
            note=(
                f"العميل وافق على {('تحديث التقدم' if stage == 'progress_update' else 'مدخلات المزود')}: {clean_note}"
                if clean_note
                else ("العميل وافق على تحديث التقدم ويمكن متابعة التنفيذ" if stage == "progress_update" else "العميل وافق على مدخلات المزود وبدأ التنفيذ")
            )[:255],
        )
        transaction.on_commit(
            lambda: _notify_provider_inputs_decision(
                sr=sr,
                actor=user,
                approved=True,
                note=clean_note,
                stage=stage,
            )
        )
        return ActionResult(True, "تم اعتماد التحديث" if stage == "progress_update" else "تم اعتماد المدخلات", sr.status)

    # reject_inputs — client only, awaiting client approval + inputs not yet decided
    if action == "reject_inputs":
        if not (is_staff or is_client):
            raise PermissionDenied("غير مصرح")
        if sr.status != RequestStatus.AWAITING_CLIENT_APPROVAL:
            raise ValidationError("لا يمكن اتخاذ قرار بشأن المدخلات في هذه الحالة")
        if sr.provider_inputs_approved is not None:
            raise ValidationError("تم اتخاذ قرار مسبقًا بشأن المدخلات")
        stage = service_request_pending_input_stage(sr)
        clean_note = str(note or "").strip()
        old = sr.status
        sr.status = service_request_pending_input_return_status(sr)
        sr.provider_inputs_approved = False
        sr.provider_inputs_decided_at = timezone.now()
        sr.provider_inputs_decision_note = clean_note[:255]
        sr.save(update_fields=["status", "provider_inputs_approved", "provider_inputs_decided_at", "provider_inputs_decision_note"])
        RequestStatusLog.objects.create(
            request=sr,
            actor=user,
            from_status=old,
            to_status=sr.status,
            note=(
                f"العميل رفض {('تحديث التقدم' if stage == 'progress_update' else 'مدخلات المزود')}: {clean_note}"
                if clean_note
                else ("العميل رفض تحديث التقدم" if stage == "progress_update" else "العميل رفض مدخلات المزود")
            )[:255],
        )
        transaction.on_commit(
            lambda: _notify_provider_inputs_decision(
                sr=sr,
                actor=user,
                approved=False,
                note=clean_note,
                stage=stage,
            )
        )
        return ActionResult(True, "تم رفض التحديث" if stage == "progress_update" else "تم رفض المدخلات", sr.status)

    raise ValidationError("إجراء غير معروف")
