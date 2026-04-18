from django.utils import timezone

from apps.marketplace.models import RequestType, ServiceRequest


def cancel_availability_copy(request_type_value: str) -> str:
    if request_type_value == RequestType.URGENT:
        return "ولم يعد متاحًا للقبول."
    return "ولم يعد متاحًا لتقديم عرض."


def is_generic_cancel_note(note_text: str) -> bool:
    normalized = (note_text or "").strip()
    return normalized in {
        "إلغاء الطلب من العميل",
        "إلغاء الطلب العاجل من العميل بعد قبول مزود الخدمة",
        "إلغاء الطلب من فريق الإدارة",
        "إلغاء الطلب من مزود الخدمة",
        "إلغاء الطلب",
    }


def looks_like_deadline_cancellation(*, sr: ServiceRequest, note_text: str) -> bool:
    lowered_note = (note_text or "").strip().lower()
    if sr.request_type != RequestType.COMPETITIVE:
        return False
    if any(token in lowered_note for token in ("deadline", "expired", "مهلة", "انتهت")):
        return True
    quote_deadline = getattr(sr, "quote_deadline", None)
    if quote_deadline and timezone.localdate() > quote_deadline:
        return True
    return False


def provider_pool_cancel_notification_text(*, sr: ServiceRequest, actor, note_text: str) -> tuple[str, bool]:
    request_type_value = (getattr(sr, "request_type", "") or "").strip().lower()
    request_label = "الطلب العاجل" if request_type_value == RequestType.URGENT else "الطلب التنافسي"
    availability_copy = cancel_availability_copy(request_type_value)
    deadline_cancellation = looks_like_deadline_cancellation(sr=sr, note_text=note_text)
    if deadline_cancellation:
        return (
            f"انتهت مهلة استقبال عروض الأسعار لهذا الطلب التنافسي {availability_copy}",
            True,
        )

    extra_reason = ""
    if note_text and not is_generic_cancel_note(note_text):
        extra_reason = f" السبب: {note_text.strip()}"

    role_state = (getattr(actor, "role_state", "") or "").strip().lower()
    if role_state == "staff" or getattr(actor, "is_staff", False):
        body = f"تم إلغاء {request_label} من الإدارة {availability_copy}{extra_reason}".strip()
    elif role_state == "provider":
        body = f"تم إلغاء {request_label} من مزود الخدمة {availability_copy}{extra_reason}".strip()
    else:
        body = f"تم إلغاء {request_label} من العميل {availability_copy}{extra_reason}".strip()
    return body, False


def client_cancel_status_notification_text(*, sr: ServiceRequest, actor, note_text: str) -> str:
    request_type_value = (getattr(sr, "request_type", "") or "").strip().lower()
    request_label = "طلبك العاجل" if request_type_value == RequestType.URGENT else "طلبك التنافسي"

    if looks_like_deadline_cancellation(sr=sr, note_text=note_text):
        body = f"انتهت مهلة استقبال عروض الأسعار لـ{request_label}، لذلك أُلغي الطلب."
        if note_text and not is_generic_cancel_note(note_text):
            body = f"{body} السبب: {note_text.strip()}"
        return body

    extra_reason = ""
    if note_text and not is_generic_cancel_note(note_text):
        extra_reason = f" السبب: {note_text.strip()}"

    role_state = (getattr(actor, "role_state", "") or "").strip().lower()
    if role_state == "staff" or getattr(actor, "is_staff", False):
        return f"ألغت الإدارة {request_label}.{extra_reason}".strip()
    if role_state == "provider":
        return f"ألغى مزود الخدمة {request_label}.{extra_reason}".strip()
    return f"تم إلغاء {request_label} بناءً على طلبك.{extra_reason}".strip()