from __future__ import annotations

from django.db import transaction
from django.utils import timezone

from .models import SupportTicket, SupportStatusLog, SupportTicketStatus
from apps.notifications.services import create_notification


SUPPORT_STATUS_TRANSITIONS: dict[str, set[str]] = {
    SupportTicketStatus.NEW: {
        SupportTicketStatus.IN_PROGRESS,
        SupportTicketStatus.RETURNED,
        SupportTicketStatus.CLOSED,
    },
    SupportTicketStatus.IN_PROGRESS: {
        SupportTicketStatus.RETURNED,
        SupportTicketStatus.CLOSED,
    },
    SupportTicketStatus.RETURNED: {
        SupportTicketStatus.IN_PROGRESS,
        SupportTicketStatus.CLOSED,
    },
    SupportTicketStatus.CLOSED: set(),
}


def build_ticket_notification_url(ticket: SupportTicket | int) -> str:
    ticket_id = ticket if isinstance(ticket, int) else ticket.id
    return f"/contact/?ticket={int(ticket_id)}"


def _ticket_reference(ticket: SupportTicket) -> str:
    return (ticket.code or "").strip() or f"HD{ticket.id}"


def _ticket_requester_audience_mode(ticket: SupportTicket) -> str:
    requester = getattr(ticket, "requester", None)
    if requester is None:
        return "client"
    try:
        if getattr(requester, "provider_profile", None) is not None:
            return "provider"
    except Exception:
        pass
    return "client"


def notify_ticket_requester_about_comment(*, ticket: SupportTicket, comment, by_user):
    if not ticket.requester_id or comment is None:
        return None
    if getattr(comment, "is_internal", False):
        return None
    if by_user is not None and ticket.requester_id == getattr(by_user, "id", None):
        return None

    author_name = ""
    if by_user is not None:
        author_name = (
            getattr(by_user, "name", None)
            or getattr(by_user, "phone", None)
            or ""
        ).strip()

    snippet = " ".join(str(getattr(comment, "text", "") or "").split())
    if len(snippet) > 180:
        snippet = snippet[:177].rstrip() + "..."

    body = f"تمت إضافة تعليق جديد على البلاغ ({_ticket_reference(ticket)})."
    if author_name:
        body = f"أضاف {author_name} تعليقًا جديدًا على البلاغ ({_ticket_reference(ticket)})."
    if snippet:
        body += f" {snippet}"
    body = body[:500]

    return create_notification(
        user=ticket.requester,
        title="تعليق جديد على البلاغ",
        body=body,
        kind="report_status_change",
        url=build_ticket_notification_url(ticket),
        actor=by_user,
        meta={
            "ticket_id": ticket.id,
            "ticket_code": ticket.code or "",
            "comment_id": getattr(comment, "id", None),
        },
        pref_key="report_status_change",
        audience_mode=_ticket_requester_audience_mode(ticket),
    )


def _sync_ticket_to_unified(*, ticket: SupportTicket, changed_by=None):
    """
    مزامنة تذكرة الدعم مع محرك الطلبات الموحد (تكامل تدريجي غير معطّل).
    """
    try:
        from apps.unified_requests.services import upsert_unified_request
        from apps.unified_requests.models import UnifiedRequestType
    except Exception:
        return

    team = getattr(ticket, "assigned_team", None)
    upsert_unified_request(
        request_type=UnifiedRequestType.HELPDESK,
        requester=ticket.requester,
        source_app="support",
        source_model="SupportTicket",
        source_object_id=ticket.id,
        status=ticket.status,
        priority=ticket.priority or "normal",
        summary=(ticket.description or "")[:300],
        metadata={
            "ticket_type": ticket.ticket_type,
            "ticket_code": ticket.code or "",
        },
        assigned_team_code=getattr(team, "code", "") or "",
        assigned_team_name=getattr(team, "name_ar", "") or "",
        assigned_user=ticket.assigned_to,
        changed_by=changed_by,
    )


def change_ticket_status(*, ticket: SupportTicket, new_status: str, by_user, note: str = ""):
    """
    تغيير الحالة + تسجيل Log
    """
    if new_status not in set(SupportTicketStatus.values):
        raise ValueError("حالة التذكرة غير صالحة")

    if ticket.status == new_status:
        return ticket

    allowed = SUPPORT_STATUS_TRANSITIONS.get(ticket.status, set())
    if new_status not in allowed:
        raise ValueError("انتقال حالة التذكرة غير مسموح")

    old = ticket.status
    ticket.status = new_status
    ticket.last_action_by = by_user

    if new_status == SupportTicketStatus.IN_PROGRESS:
        # لو أول مرة يبدأ معالجة
        if not ticket.assigned_at:
            ticket.assigned_at = timezone.now()

    if new_status == SupportTicketStatus.RETURNED:
        ticket.returned_at = timezone.now()

    if new_status == SupportTicketStatus.CLOSED:
        ticket.closed_at = timezone.now()

    ticket.save(update_fields=["status", "last_action_by", "assigned_at", "returned_at", "closed_at", "updated_at"])

    SupportStatusLog.objects.create(
        ticket=ticket,
        from_status=old,
        to_status=new_status,
        changed_by=by_user,
        note=(note or "")[:200],
    )
    _sync_ticket_to_unified(ticket=ticket, changed_by=by_user)
    try:
        from apps.moderation.integrations import sync_support_ticket_case

        sync_support_ticket_case(ticket=ticket, by_user=by_user, note=note)
    except Exception:
        pass

    # Notify ticket requester immediately when support status changes.
    status_labels = {
        SupportTicketStatus.NEW: "جديد",
        SupportTicketStatus.IN_PROGRESS: "تحت المعالجة",
        SupportTicketStatus.RETURNED: "معاد للعميل",
        SupportTicketStatus.CLOSED: "مغلق",
    }
    from_label = status_labels.get(old, old)
    to_label = status_labels.get(new_status, new_status)
    body = f"تم تحديث حالة البلاغ ({ticket.code or ticket.id}) من {from_label} إلى {to_label}."
    trimmed_note = (note or "").strip()
    if trimmed_note:
        body += f" ملاحظة: {trimmed_note}"
    body = body[:500]

    create_notification(
        user=ticket.requester,
        title="تحديث على البلاغ",
        body=body,
        kind="report_status_change",
        url=build_ticket_notification_url(ticket),
        actor=by_user,
        meta={
            "ticket_id": ticket.id,
            "ticket_code": ticket.code or "",
            "from_status": old,
            "to_status": new_status,
        },
        pref_key="report_status_change",
        audience_mode=_ticket_requester_audience_mode(ticket),
    )
    return ticket


@transaction.atomic
def assign_ticket(*, ticket: SupportTicket, team_id, user_id, by_user, note: str = ""):
    """
    تعيين فريق/موظف + تحويل تلقائي إلى IN_PROGRESS إذا كانت NEW
    """
    # lock ticket
    ticket = SupportTicket.objects.select_for_update().get(pk=ticket.pk)

    if team_id is not None:
        ticket.assigned_team_id = team_id
    if user_id is not None:
        ticket.assigned_to_id = user_id

    ticket.last_action_by = by_user
    if not ticket.assigned_at:
        ticket.assigned_at = timezone.now()

    ticket.save(update_fields=["assigned_team", "assigned_to", "assigned_at", "last_action_by", "updated_at"])

    # لو كانت جديدة نحولها لمعالجة
    if ticket.status == SupportTicketStatus.NEW:
        change_ticket_status(ticket=ticket, new_status=SupportTicketStatus.IN_PROGRESS, by_user=by_user, note=note)
    else:
        _sync_ticket_to_unified(ticket=ticket, changed_by=by_user)
        try:
            from apps.moderation.integrations import sync_support_ticket_case

            sync_support_ticket_case(ticket=ticket, by_user=by_user, note=note or "support_assign")
        except Exception:
            pass

    return ticket
