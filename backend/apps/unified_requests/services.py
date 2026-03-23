from __future__ import annotations

from django.db import transaction
from django.utils import timezone

from .models import (
    UnifiedRequest,
    UnifiedRequestAssignmentLog,
    UnifiedRequestMetadata,
    UnifiedRequestStatusLog,
)
from .workflows import canonical_status_for_workflow


@transaction.atomic
def upsert_unified_request(
    *,
    request_type: str,
    requester,
    source_app: str,
    source_model: str,
    source_object_id,
    status: str,
    priority: str = "normal",
    summary: str = "",
    metadata: dict | None = None,
    assigned_team_code: str = "",
    assigned_team_name: str = "",
    assigned_user=None,
    changed_by=None,
) -> UnifiedRequest:
    source_object_id = str(source_object_id)
    status = canonical_status_for_workflow(request_type=request_type, status=status)
    ur, created = UnifiedRequest.objects.select_for_update().get_or_create(
        source_app=source_app,
        source_model=source_model,
        source_object_id=source_object_id,
        defaults={
            "request_type": request_type,
            "requester": requester,
            "status": status,
            "priority": priority,
            "summary": (summary or "")[:300],
            "assigned_team_code": (assigned_team_code or "")[:50],
            "assigned_team_name": (assigned_team_name or "")[:120],
            "assigned_user": assigned_user,
            "assigned_at": timezone.now() if assigned_user else None,
            "closed_at": timezone.now() if status == "closed" else None,
        },
    )

    if not created:
        old_status = ur.status
        old_assigned_user_id = ur.assigned_user_id
        old_team_code = ur.assigned_team_code or ""
        updates = []
        if ur.request_type != request_type:
            ur.request_type = request_type
            updates.append("request_type")
        if ur.requester_id != getattr(requester, "id", None):
            ur.requester = requester
            updates.append("requester")
        if ur.status != status:
            ur.status = status
            updates.append("status")
        if ur.priority != priority:
            ur.priority = priority
            updates.append("priority")
        new_summary = (summary or "")[:300]
        if ur.summary != new_summary:
            ur.summary = new_summary
            updates.append("summary")
        if ur.assigned_team_code != (assigned_team_code or "")[:50]:
            ur.assigned_team_code = (assigned_team_code or "")[:50]
            updates.append("assigned_team_code")
        if ur.assigned_team_name != (assigned_team_name or "")[:120]:
            ur.assigned_team_name = (assigned_team_name or "")[:120]
            updates.append("assigned_team_name")
        if ur.assigned_user_id != getattr(assigned_user, "id", None):
            ur.assigned_user = assigned_user
            ur.assigned_at = timezone.now() if assigned_user else None
            updates.extend(["assigned_user", "assigned_at"])
        if status == "closed" and ur.closed_at is None:
            ur.closed_at = timezone.now()
            updates.append("closed_at")
        if status != "closed" and ur.closed_at is not None and old_status == "closed":
            ur.closed_at = None
            updates.append("closed_at")
        if updates:
            updates.append("updated_at")
            ur.save(update_fields=updates)

        if old_status != ur.status:
            UnifiedRequestStatusLog.objects.create(
                request=ur,
                from_status=old_status,
                to_status=ur.status,
                changed_by=changed_by,
            )
        if old_assigned_user_id != ur.assigned_user_id or old_team_code != (ur.assigned_team_code or ""):
            UnifiedRequestAssignmentLog.objects.create(
                request=ur,
                from_team_code=old_team_code,
                to_team_code=ur.assigned_team_code or "",
                from_user_id=old_assigned_user_id,
                to_user=ur.assigned_user,
                changed_by=changed_by,
            )
    else:
        UnifiedRequestStatusLog.objects.create(
            request=ur,
            from_status="",
            to_status=ur.status,
            changed_by=changed_by,
        )
        if ur.assigned_user_id or ur.assigned_team_code:
            UnifiedRequestAssignmentLog.objects.create(
                request=ur,
                from_team_code="",
                to_team_code=ur.assigned_team_code or "",
                from_user=None,
                to_user=ur.assigned_user,
                changed_by=changed_by,
            )

    if metadata is not None:
        meta_obj, _ = UnifiedRequestMetadata.objects.get_or_create(request=ur)
        meta_obj.payload = metadata
        meta_obj.updated_by = changed_by
        meta_obj.save(update_fields=["payload", "updated_by", "updated_at"])

    return ur
