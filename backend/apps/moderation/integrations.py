from __future__ import annotations

from datetime import timedelta

from django.utils import timezone

from apps.core.feature_flags import moderation_dual_write_enabled
from apps.providers.models import ProviderPortfolioItem, ProviderSpotlightItem
from apps.reviews.models import Review
from apps.support.models import SupportPriority, SupportTicket, SupportTicketStatus, SupportTicketType

from .models import (
    ModerationActionLog,
    ModerationActionType,
    ModerationCase,
    ModerationDecisionCode,
    ModerationSeverity,
    ModerationStatus,
)
from .services import add_case_note, assign_case, change_case_status, create_case, record_decision


def _severity_for_priority(priority: str) -> str:
    value = str(priority or "").strip().lower()
    if value == SupportPriority.HIGH:
        return ModerationSeverity.HIGH
    if value in {"critical", "urgent"}:
        return ModerationSeverity.CRITICAL
    if value == SupportPriority.LOW:
        return ModerationSeverity.LOW
    return ModerationSeverity.NORMAL


def default_sla_due_at(*, severity: str, created_at=None):
    created_at = created_at or timezone.now()
    hours = {
        ModerationSeverity.LOW: 72,
        ModerationSeverity.NORMAL: 48,
        ModerationSeverity.HIGH: 24,
        ModerationSeverity.CRITICAL: 8,
    }.get(str(severity or "").strip().lower(), 48)
    return created_at + timedelta(hours=hours)


def moderation_sla_state(case: ModerationCase, *, now=None) -> str:
    return case.sla_state(now=now)


def _case_source_filter(*, source_app: str, source_model: str, source_object_id: str):
    return {
        "source_app": (source_app or "").strip()[:50],
        "source_model": (source_model or "").strip()[:80],
        "source_object_id": str(source_object_id or "").strip()[:50],
    }


def _linked_support_ticket_filter(ticket: SupportTicket | None) -> dict:
    if not ticket:
        return {}
    return {
        "linked_support_ticket_id": str(ticket.id),
        "linked_support_ticket_code": ticket.code or "",
    }


def _first_existing_case(*, ticket: SupportTicket | None = None, source_app: str, source_model: str, source_object_id: str):
    linked_ticket_id = str(getattr(ticket, "id", "") or "").strip()
    if linked_ticket_id:
        case = ModerationCase.objects.filter(linked_support_ticket_id=linked_ticket_id).first()
        if case:
            return case
    if source_app and source_model and source_object_id:
        return ModerationCase.objects.filter(
            **_case_source_filter(
                source_app=source_app,
                source_model=source_model,
                source_object_id=source_object_id,
            )
        ).first()
    return None


def _apply_payload(case: ModerationCase, *, payload: dict) -> ModerationCase:
    changed_fields: list[str] = []
    for field in (
        "reported_user",
        "source_app",
        "source_model",
        "source_object_id",
        "source_label",
        "category",
        "reason",
        "details",
        "summary",
        "severity",
        "linked_support_ticket_id",
        "linked_support_ticket_code",
        "assigned_team_code",
        "assigned_team_name",
    ):
        if field not in payload:
            continue
        value = payload[field]
        attr_name = f"{field}_id" if field == "reported_user" else field
        current = getattr(case, attr_name)
        if field == "reported_user":
            current = getattr(case, "reported_user_id", None)
        if current != value:
            setattr(case, attr_name, value)
            changed_fields.append(attr_name if attr_name != field else field)

    for json_field in ("snapshot", "meta"):
        if json_field not in payload:
            continue
        value = payload[json_field] or {}
        if getattr(case, json_field) != value:
            setattr(case, json_field, value)
            changed_fields.append(json_field)

    if not case.sla_due_at:
        case.sla_due_at = default_sla_due_at(severity=payload.get("severity") or case.severity)
        changed_fields.append("sla_due_at")

    if changed_fields:
        changed_fields.append("updated_at")
        case.save(update_fields=changed_fields)
    return case


def upsert_case(
    *,
    reporter,
    payload: dict,
    request=None,
    by_user=None,
    note: str = "",
    ticket: SupportTicket | None = None,
) -> ModerationCase | None:
    if not moderation_dual_write_enabled():
        return None

    payload = dict(payload or {})
    payload["severity"] = payload.get("severity") or ModerationSeverity.NORMAL
    payload.setdefault("snapshot", {})
    payload.setdefault("meta", {})
    payload.setdefault("summary", "")
    payload.setdefault("details", "")
    payload.setdefault("source_label", "")
    payload.setdefault("category", "")
    payload.setdefault("reason", "بلاغ")
    payload.update(_linked_support_ticket_filter(ticket))

    case = _first_existing_case(
        ticket=ticket,
        source_app=payload.get("source_app", ""),
        source_model=payload.get("source_model", ""),
        source_object_id=payload.get("source_object_id", ""),
    )
    if case is None:
        case = create_case(reporter=reporter, payload=payload, request=request)
        if not case.sla_due_at:
            case.sla_due_at = default_sla_due_at(severity=case.severity, created_at=case.created_at)
            case.save(update_fields=["sla_due_at", "updated_at"])
    else:
        case = _apply_payload(case, payload=payload)
        if note:
            add_case_note(case=case, note=note, by_user=by_user, request=request)
    return case


def _ticket_source(ticket: SupportTicket) -> tuple[str, str, str, str]:
    kind = str(ticket.reported_kind or "").strip().lower()
    object_id = str(ticket.reported_object_id or "").strip()
    label = kind or ticket.code or f"support-ticket-{ticket.id}"
    mapping = {
        "review": ("reviews", "Review", object_id, f"Review #{object_id}" if object_id else label),
        "message": ("messaging", "Message", object_id, f"Message #{object_id}" if object_id else label),
        "thread": ("messaging", "Thread", object_id, f"Thread #{object_id}" if object_id else label),
        "portfolio_item": ("providers", "ProviderPortfolioItem", object_id, f"Portfolio #{object_id}" if object_id else label),
        "spotlight_item": ("providers", "ProviderSpotlightItem", object_id, f"Spotlight #{object_id}" if object_id else label),
        "service": ("providers", "ProviderService", object_id, f"Service #{object_id}" if object_id else label),
    }
    if kind in mapping:
        return mapping[kind]
    return ("support", "SupportTicket", str(ticket.id), ticket.code or f"SupportTicket #{ticket.id}")


def sync_support_ticket_case(*, ticket: SupportTicket, by_user=None, request=None, note: str = "") -> ModerationCase | None:
    if not moderation_dual_write_enabled():
        return None
    if ticket.ticket_type != SupportTicketType.COMPLAINT and not (ticket.reported_kind or "").strip():
        return None

    source_app, source_model, source_object_id, source_label = _ticket_source(ticket)
    payload = {
        "reported_user": ticket.reported_user_id,
        "source_app": source_app,
        "source_model": source_model,
        "source_object_id": source_object_id,
        "source_label": source_label,
        "category": "complaint",
        "reason": (ticket.ticket_type or SupportTicketType.COMPLAINT).strip(),
        "details": (ticket.description or "")[:500],
        "severity": _severity_for_priority(ticket.priority),
        "summary": (ticket.description or ticket.code or "")[:300],
        "snapshot": {
            "ticket": {
                "id": ticket.id,
                "code": ticket.code or "",
                "ticket_type": ticket.ticket_type,
                "status": ticket.status,
                "priority": ticket.priority,
            },
            "reported_target": {
                "kind": ticket.reported_kind or "",
                "object_id": ticket.reported_object_id or "",
                "reported_user_id": ticket.reported_user_id,
            },
        },
        "meta": {
            "origin": "support_ticket",
            "reported_kind": ticket.reported_kind or "",
            "reported_object_id": ticket.reported_object_id or "",
        },
    }
    case = upsert_case(
        reporter=ticket.requester,
        payload=payload,
        request=request,
        by_user=by_user,
        note=note,
        ticket=ticket,
    )
    if case is None:
        return None

    team = getattr(ticket, "assigned_team", None)
    target_assignee_id = ticket.assigned_to_id
    if case.assigned_to_id != target_assignee_id or case.assigned_team_code != (getattr(team, "code", "") or ""):
        assign_case(
            case=case,
            assigned_team_code=getattr(team, "code", "") or "",
            assigned_team_name=getattr(team, "name_ar", "") or "",
            assigned_to_id=target_assignee_id,
            note=note or f"support_sync:{ticket.status}",
            by_user=by_user,
            request=request,
        )

    status_map = {
        SupportTicketStatus.NEW: ModerationStatus.NEW,
        SupportTicketStatus.IN_PROGRESS: ModerationStatus.UNDER_REVIEW,
        SupportTicketStatus.RETURNED: ModerationStatus.ESCALATED,
    }
    desired_status = status_map.get(ticket.status)
    if desired_status and case.status != desired_status and not case.is_terminal:
        change_case_status(
            case=case,
            new_status=desired_status,
            note=note or f"support_status:{ticket.status}",
            by_user=by_user,
            request=request,
        )
    return case


def sync_review_case(*, review: Review, action_name: str, note: str = "", by_user=None, request=None) -> ModerationCase | None:
    if not moderation_dual_write_enabled():
        return None

    reporter = review.client
    reported_user = getattr(getattr(review, "provider", None), "user_id", None)
    payload = {
        "reported_user": reported_user,
        "source_app": "reviews",
        "source_model": "Review",
        "source_object_id": str(review.id),
        "source_label": f"Review #{review.id}",
        "category": "review_moderation",
        "reason": "review_moderation",
        "details": (review.comment or "")[:500],
        "severity": ModerationSeverity.NORMAL,
        "summary": f"Review moderation for review #{review.id}"[:300],
        "snapshot": {
            "review": {
                "id": review.id,
                "rating": review.rating,
                "comment": review.comment,
                "provider_id": review.provider_id,
                "request_id": review.request_id,
                "moderation_status": review.moderation_status,
            }
        },
        "meta": {"origin": "reviews_dashboard"},
    }
    case = upsert_case(
        reporter=reporter,
        payload=payload,
        request=request,
        by_user=by_user,
        note=note or f"review_action:{action_name}",
    )
    if case is None:
        return None

    decision_code = {
        "approve": ModerationDecisionCode.NO_ACTION,
        "reject": ModerationDecisionCode.HIDE,
        "hide": ModerationDecisionCode.HIDE,
    }.get(action_name, ModerationDecisionCode.NO_ACTION)
    record_decision(
        case=case,
        decision_code=decision_code,
        note=note or action_name,
        outcome={"review_status": review.moderation_status, "action_name": action_name},
        is_final=True,
        by_user=by_user,
        request=request,
    )
    return case


def record_content_action_case(*, item, content_kind: str, action_name: str, by_user=None, request=None, note: str = "") -> ModerationCase | None:
    if not moderation_dual_write_enabled():
        return None

    provider = getattr(item, "provider", None)
    provider_user = getattr(provider, "user", None)
    payload = {
        "reported_user": getattr(provider_user, "id", None),
        "source_app": "providers",
        "source_model": type(item).__name__,
        "source_object_id": str(item.id),
        "source_label": f"{content_kind} #{item.id}",
        "category": "content_moderation",
        "reason": action_name,
        "details": (getattr(item, "caption", "") or "")[:500],
        "severity": ModerationSeverity.NORMAL,
        "summary": f"{content_kind} moderation #{item.id}"[:300],
        "snapshot": {
            "content": {
                "id": item.id,
                "content_kind": content_kind,
                "provider_id": getattr(item, "provider_id", None),
                "provider_display_name": getattr(provider, "display_name", "") or "",
                "file_type": getattr(item, "file_type", "") or "",
                "caption": getattr(item, "caption", "") or "",
            }
        },
        "meta": {"origin": "dashboard_content", "action_name": action_name},
    }
    case = upsert_case(
        reporter=by_user or provider_user,
        payload=payload,
        request=request,
        by_user=by_user,
        note=note or action_name,
    )
    if case is None:
        return None

    decision_code = ModerationDecisionCode.DELETE if action_name == "delete" else ModerationDecisionCode.HIDE
    record_decision(
        case=case,
        decision_code=decision_code,
        note=note or action_name,
        outcome={"content_kind": content_kind, "action_name": action_name},
        is_final=True,
        by_user=by_user,
        request=request,
    )
    return case


def record_support_target_delete_case(*, ticket: SupportTicket, by_user=None, request=None, note: str = "") -> ModerationCase | None:
    if not moderation_dual_write_enabled():
        return None
    kind = str(ticket.reported_kind or "").strip().lower()
    object_id = str(ticket.reported_object_id or "").strip()
    if kind == "portfolio_item":
        item = ProviderPortfolioItem.objects.select_related("provider", "provider__user").filter(id=object_id).first()
        if item:
            return record_content_action_case(
                item=item,
                content_kind="portfolio_item",
                action_name="delete",
                by_user=by_user,
                request=request,
                note=note or "support_delete_reported_object",
            )
    if kind == "spotlight_item":
        item = ProviderSpotlightItem.objects.select_related("provider", "provider__user").filter(id=object_id).first()
        if item:
            return record_content_action_case(
                item=item,
                content_kind="spotlight_item",
                action_name="delete",
                by_user=by_user,
                request=request,
                note=note or "support_delete_reported_object",
            )
    case = sync_support_ticket_case(
        ticket=ticket,
        by_user=by_user,
        request=request,
        note=note or "support_delete_reported_object",
    )
    if case is None:
        return None
    record_decision(
        case=case,
        decision_code=ModerationDecisionCode.DELETE,
        note=note or "support_delete_reported_object",
        outcome={
            "reported_kind": ticket.reported_kind or "",
            "reported_object_id": ticket.reported_object_id or "",
        },
        is_final=True,
        by_user=by_user,
        request=request,
    )
    return case
