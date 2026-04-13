import logging
from dataclasses import dataclass

from django.core.exceptions import PermissionDenied, ValidationError
from django.db import transaction
from django.utils import timezone

from apps.marketplace.models import RequestStatus, RequestStatusLog, RequestType, ServiceRequest
from apps.providers.models import ProviderProfile

logger = logging.getLogger(__name__)


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


def _role_flags(user, sr: ServiceRequest):
    is_staff = bool(getattr(user, "is_staff", False))
    user_id = getattr(user, "id", None)
    is_client = bool(user_id) and (sr.client_id == user_id)
    is_provider = bool(user_id) and bool(sr.provider_id) and (sr.provider.user_id == user_id)
    return is_staff, is_client, is_provider


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
        if sr.status == RequestStatus.NEW:
            acts.append("send")
            if sr.provider_id is None or sr.request_type == RequestType.URGENT:
                acts.append("cancel")
            has_provider_inputs = any(
                [
                    sr.expected_delivery_at is not None,
                    sr.estimated_service_amount is not None,
                    sr.received_amount is not None,
                ]
            )
            if has_provider_inputs and sr.provider_inputs_approved is None:
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

    # cancel — client: NEW + no provider; provider: NEW+IN_PROGRESS; staff: NEW+IN_PROGRESS
    if action == "cancel":
        if not (is_staff or is_provider or is_client):
            raise PermissionDenied("غير مصرح")
        old = sr.status
        cleaned_note = str(note or "").strip()
        if is_client and not is_staff:
            urgent_pending_with_provider = bool(
                sr.request_type == RequestType.URGENT
                and sr.status == RequestStatus.NEW
                and sr.provider_id is not None
            )
            if sr.provider_id is not None and not urgent_pending_with_provider:
                raise PermissionDenied("لا يمكن إلغاء الطلب بعد قبول مزود الخدمة")
            sr.cancel(allowed_statuses=[RequestStatus.NEW])
            if cleaned_note:
                note = cleaned_note
            elif urgent_pending_with_provider:
                note = "إلغاء الطلب العاجل من العميل بعد قبول مزود الخدمة"
            else:
                note = "إلغاء الطلب من العميل"
        else:
            sr.cancel(allowed_statuses=[RequestStatus.NEW, RequestStatus.IN_PROGRESS])
            if is_staff:
                note = cleaned_note or "إلغاء الطلب من فريق الإدارة"
            elif is_provider:
                note = cleaned_note or "إلغاء الطلب من مزود الخدمة"
            else:
                note = cleaned_note or "إلغاء الطلب"
        _log_request_status_change(sr=sr, actor=user, from_status=old, note=note)
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
            return ActionResult(True, "تم بدء التنفيذ وإسناده", sr.status)

        if not provider_profile:
            raise ValidationError("لا يوجد ملف مزود مرتبط بهذا الحساب")

        sr.accept(provider_profile)
        _log_request_status_change(
            sr=sr,
            actor=user,
            from_status=old,
            note="قبول الطلب وبدء التنفيذ من مزود الخدمة",
        )
        return ActionResult(True, "تم بدء التنفيذ", sr.status)

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

    # approve_inputs — client only, NEW + inputs not yet decided
    if action == "approve_inputs":
        if not (is_staff or is_client):
            raise PermissionDenied("غير مصرح")
        if sr.status != RequestStatus.NEW:
            raise ValidationError("لا يمكن اتخاذ قرار بشأن المدخلات في هذه الحالة")
        if sr.provider_inputs_approved is not None:
            raise ValidationError("تم اتخاذ قرار مسبقًا بشأن المدخلات")
        old = sr.status
        sr.status = RequestStatus.IN_PROGRESS
        sr.provider_inputs_approved = True
        sr.provider_inputs_decided_at = timezone.now()
        sr.save(update_fields=["status", "provider_inputs_approved", "provider_inputs_decided_at"])
        RequestStatusLog.objects.create(
            request=sr,
            actor=user,
            from_status=old,
            to_status=sr.status,
            note="العميل وافق على مدخلات المزود وبدأ التنفيذ",
        )
        return ActionResult(True, "تم اعتماد المدخلات", sr.status)

    # reject_inputs — client only, NEW + inputs not yet decided
    if action == "reject_inputs":
        if not (is_staff or is_client):
            raise PermissionDenied("غير مصرح")
        if sr.status != RequestStatus.NEW:
            raise ValidationError("لا يمكن اتخاذ قرار بشأن المدخلات في هذه الحالة")
        if sr.provider_inputs_approved is not None:
            raise ValidationError("تم اتخاذ قرار مسبقًا بشأن المدخلات")
        sr.provider_inputs_approved = False
        sr.provider_inputs_decided_at = timezone.now()
        sr.save(update_fields=["provider_inputs_approved", "provider_inputs_decided_at"])
        RequestStatusLog.objects.create(
            request=sr,
            actor=user,
            from_status=sr.status,
            to_status=sr.status,
            note="العميل رفض مدخلات المزود",
        )
        return ActionResult(True, "تم رفض المدخلات", sr.status)

    raise ValidationError("إجراء غير معروف")
