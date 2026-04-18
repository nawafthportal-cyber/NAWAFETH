from __future__ import annotations

from django.contrib.auth import get_user_model
from django.db import transaction
from django.utils import timezone

from apps.audit.models import AuditAction
from apps.audit.services import log_action
from apps.notifications.services import create_notification

from .models import (
    ModerationActionLog,
    ModerationActionType,
    ModerationCase,
    ModerationDecision,
    ModerationDecisionCode,
    ModerationStatus,
)


User = get_user_model()


def _case_status_label(value: str) -> str:
    return dict(ModerationStatus.choices).get(value, value or "-")


def _decision_label(value: str) -> str:
    return dict(ModerationDecisionCode.choices).get(value, value or "-")


def _case_notification_url(case: ModerationCase) -> str:
    linked_ticket_id = str(getattr(case, "linked_support_ticket_id", "") or "").strip()
    if linked_ticket_id.isdigit():
        return f"/contact/?ticket={int(linked_ticket_id)}"

    source_model = str(getattr(case, "source_model", "") or "").strip()
    source_object_id = str(getattr(case, "source_object_id", "") or "").strip()
    if source_model == "Review" and source_object_id.isdigit():
        try:
            from apps.reviews.models import Review

            review = Review.objects.filter(id=int(source_object_id)).only("request_id").first()
        except Exception:
            review = None
        request_id = getattr(review, "request_id", None)
        if request_id:
            return f"/requests/{request_id}/"

    return "/contact/"


def _reporter_audience_mode(user) -> str:
    if user is None:
        return "client"
    try:
        return "provider" if getattr(user, "provider_profile", None) is not None else "client"
    except Exception:
        return "client"


def _notify_case_reporter(*, case: ModerationCase, title: str, body: str, actor=None, meta: dict | None = None) -> None:
    reporter = getattr(case, "reporter", None)
    reporter_id = getattr(case, "reporter_id", None)
    if reporter is None or not reporter_id:
        return
    if str(getattr(case, "linked_support_ticket_id", "") or "").strip():
        return

    transaction.on_commit(
        lambda: create_notification(
            user=reporter,
            title=title,
            body=body[:500],
            kind="report_status_change",
            url=_case_notification_url(case),
            actor=actor,
            meta={
                "case_id": case.id,
                "case_code": case.code or "",
                **(meta or {}),
            },
            pref_key="report_status_change",
            audience_mode=_reporter_audience_mode(reporter),
        )
    )


def _decision_target_status(decision_code: str) -> str:
    if decision_code in {
        ModerationDecisionCode.HIDE,
        ModerationDecisionCode.DELETE,
        ModerationDecisionCode.WARN,
        ModerationDecisionCode.CLOSE,
    }:
        return ModerationStatus.ACTION_TAKEN
    if decision_code == ModerationDecisionCode.NO_ACTION:
        return ModerationStatus.DISMISSED
    if decision_code == ModerationDecisionCode.ESCALATE:
        return ModerationStatus.ESCALATED
    return ModerationStatus.UNDER_REVIEW


def calculate_sla_due_at(*, severity: str, created_at=None):
    from .integrations import default_sla_due_at

    return default_sla_due_at(severity=severity, created_at=created_at)


def _merge_case_meta(case: ModerationCase, **extra) -> dict:
    meta = dict(case.meta or {})
    for key, value in extra.items():
        meta[key] = value
    case.meta = meta
    return meta


@transaction.atomic
def create_case(*, reporter, payload: dict, request=None) -> ModerationCase:
    payload = dict(payload or {})
    reported_user = payload.pop("reported_user", None)
    if reported_user not in (None, ""):
        if hasattr(reported_user, "pk"):
            payload["reported_user"] = reported_user
        else:
            payload["reported_user_id"] = reported_user
    if not payload.get("sla_due_at"):
        payload["sla_due_at"] = calculate_sla_due_at(severity=payload.get("severity"))
    case = ModerationCase.objects.create(reporter=reporter, **payload)
    ModerationActionLog.objects.create(
        case=case,
        action_type=ModerationActionType.CREATED,
        note=(payload.get("reason") or "").strip()[:500],
        payload={
            "source_app": payload.get("source_app", ""),
            "source_model": payload.get("source_model", ""),
            "source_object_id": payload.get("source_object_id", ""),
        },
        created_by=reporter,
    )
    log_action(
        actor=reporter,
        action=AuditAction.MODERATION_CASE_CREATED,
        reference_type="moderation.case",
        reference_id=str(case.id),
        request=request,
        extra={"status": case.status, "severity": case.severity},
    )
    return case


@transaction.atomic
def add_case_note(*, case: ModerationCase, note: str, payload: dict | None = None, by_user=None, request=None) -> ModerationCase:
    trimmed = (note or "").strip()[:500]
    if not trimmed:
        return case
    ModerationActionLog.objects.create(
        case=case,
        action_type=ModerationActionType.NOTE_ADDED,
        note=trimmed,
        payload=payload or {},
        created_by=by_user,
    )
    log_action(
        actor=by_user,
        action=AuditAction.MODERATION_CASE_STATUS_CHANGED,
        reference_type="moderation.case",
        reference_id=str(case.id),
        request=request,
        extra={"note_only": True},
    )
    return case


@transaction.atomic
def assign_case(
    *,
    case: ModerationCase,
    assigned_team_code: str = "",
    assigned_team_name: str = "",
    assigned_to_id=None,
    note: str = "",
    by_user=None,
    request=None,
) -> ModerationCase:
    from_user = case.assigned_to
    to_user = None
    if assigned_to_id not in (None, ""):
        to_user = User.objects.filter(id=assigned_to_id, is_active=True).first()

    case.assigned_team_code = (assigned_team_code or "").strip()[:50]
    case.assigned_team_name = (assigned_team_name or "").strip()[:120]
    case.assigned_to = to_user
    case.assigned_at = timezone.now()
    if case.status == ModerationStatus.NEW:
        case.status = ModerationStatus.UNDER_REVIEW
    case.save(
        update_fields=[
            "assigned_team_code",
            "assigned_team_name",
            "assigned_to",
            "assigned_at",
            "status",
            "updated_at",
        ]
    )
    ModerationActionLog.objects.create(
        case=case,
        action_type=ModerationActionType.ASSIGNED,
        from_assigned_to=from_user,
        to_assigned_to=to_user,
        note=(note or "").strip()[:500],
        payload={
            "assigned_team_code": case.assigned_team_code,
            "assigned_team_name": case.assigned_team_name,
        },
        created_by=by_user,
    )
    log_action(
        actor=by_user,
        action=AuditAction.MODERATION_CASE_ASSIGNED,
        reference_type="moderation.case",
        reference_id=str(case.id),
        request=request,
        extra={
            "from_assigned_to": getattr(from_user, "id", None),
            "to_assigned_to": getattr(to_user, "id", None),
            "assigned_team_code": case.assigned_team_code,
        },
    )
    return case


@transaction.atomic
def change_case_status(*, case: ModerationCase, new_status: str, note: str = "", by_user=None, request=None) -> ModerationCase:
    old_status = case.status
    case.status = new_status
    if new_status in {ModerationStatus.ACTION_TAKEN, ModerationStatus.DISMISSED}:
        case.closed_at = timezone.now()
    else:
        case.closed_at = None
    update_fields = ["status", "closed_at", "updated_at"]
    if new_status == ModerationStatus.ESCALATED:
        meta = dict(case.meta or {})
        meta["escalation_count"] = int(meta.get("escalation_count") or 0) + 1
        meta["last_escalated_at"] = timezone.now().isoformat()
        meta["last_escalated_by_id"] = getattr(by_user, "id", None)
        case.meta = meta
        update_fields.append("meta")
    case.save(update_fields=update_fields)
    ModerationActionLog.objects.create(
        case=case,
        action_type=ModerationActionType.STATUS_CHANGED,
        from_status=old_status,
        to_status=new_status,
        note=(note or "").strip()[:500],
        created_by=by_user,
    )
    log_action(
        actor=by_user,
        action=AuditAction.MODERATION_CASE_STATUS_CHANGED,
        reference_type="moderation.case",
        reference_id=str(case.id),
        request=request,
        extra={"before": old_status, "after": new_status},
    )
    trimmed_note = (note or "").strip()
    body = f"تم تحديث حالة البلاغ ({case.code or case.id}) من {_case_status_label(old_status)} إلى {_case_status_label(new_status)}."
    if trimmed_note:
        body = f"{body} ملاحظة: {trimmed_note}"
    _notify_case_reporter(
        case=case,
        title="تحديث على البلاغ",
        body=body,
        actor=by_user,
        meta={"from_status": old_status, "to_status": new_status},
    )
    return case


@transaction.atomic
def record_decision(
    *,
    case: ModerationCase,
    decision_code: str,
    note: str = "",
    outcome: dict | None = None,
    is_final: bool = True,
    by_user=None,
    request=None,
) -> ModerationDecision:
    decision = ModerationDecision.objects.create(
        case=case,
        decision_code=decision_code,
        note=(note or "").strip()[:500],
        outcome=outcome or {},
        is_final=bool(is_final),
        applied_by=by_user,
    )
    target_status = _decision_target_status(decision_code)
    ModerationActionLog.objects.create(
        case=case,
        action_type=ModerationActionType.DECISION_RECORDED,
        from_status=case.status,
        to_status=target_status,
        note=decision.note,
        payload={"decision_code": decision_code, "is_final": bool(is_final)},
        created_by=by_user,
    )
    if is_final:
        _merge_case_meta(
            case,
            last_decision={
                "decision_code": decision_code,
                "note": decision.note,
                "is_final": bool(is_final),
                "applied_by_id": getattr(by_user, "id", None),
                "applied_at": decision.applied_at.isoformat() if decision.applied_at else None,
            },
        )
        case.status = target_status
        case.closed_at = timezone.now() if target_status in {
            ModerationStatus.ACTION_TAKEN,
            ModerationStatus.DISMISSED,
            ModerationStatus.ESCALATED,
        } else None
        update_fields = ["status", "closed_at", "updated_at", "meta"]
        if target_status == ModerationStatus.ESCALATED:
            meta = dict(case.meta or {})
            meta["escalation_count"] = int(meta.get("escalation_count") or 0) + 1
            meta["last_escalated_at"] = timezone.now().isoformat()
            meta["last_escalated_by_id"] = getattr(by_user, "id", None)
            case.meta = meta
        case.save(update_fields=update_fields)
    log_action(
        actor=by_user,
        action=AuditAction.MODERATION_CASE_DECISION_RECORDED,
        reference_type="moderation.case",
        reference_id=str(case.id),
        request=request,
        extra={"decision_code": decision_code, "is_final": bool(is_final)},
    )
    body = f"تم تحديث البلاغ ({case.code or case.id}) بقرار: {_decision_label(decision_code)}."
    trimmed_note = (note or "").strip()
    if is_final:
        body = f"{body} الحالة الحالية: {_case_status_label(case.status)}."
    if trimmed_note:
        body = f"{body} ملاحظة: {trimmed_note}"
    _notify_case_reporter(
        case=case,
        title="تحديث على البلاغ",
        body=body,
        actor=by_user,
        meta={"decision_code": decision_code, "is_final": bool(is_final), "status": case.status},
    )
    return decision
