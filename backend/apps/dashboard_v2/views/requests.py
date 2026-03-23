from __future__ import annotations

from datetime import timedelta

from django.contrib import messages
from django.db import transaction
from django.db.models import Q
from django.core.paginator import Paginator
from django.http import HttpResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.utils import timezone
from django.views.decorators.http import require_POST

from apps.audit.models import AuditAction
from apps.audit.services import log_action
from apps.backoffice.models import AccessLevel
from apps.dashboard.access import (
    can_access_object,
    dashboard_assignee_user,
    dashboard_assignment_users,
    has_action_permission,
    has_dashboard_access,
)
from apps.dashboard.contracts import (
    CANONICAL_OPERATIONAL_STATUSES,
    DashboardCode,
    TEAM_CODE_TO_NAME_AR,
)
from apps.unified_requests.models import (
    UnifiedRequest,
    UnifiedRequestAssignmentLog,
    UnifiedRequestStatus,
    UnifiedRequestStatusLog,
    UnifiedRequestType,
)
from apps.unified_requests.workflows import (
    allowed_statuses_for_request_type,
    canonical_status_for_workflow,
    is_valid_transition,
)

from ..view_utils import (
    apply_role_scope,
    build_layout_context,
    dashboard_v2_login_required,
    parse_date_yyyy_mm_dd,
)


REQUEST_TYPE_TEAM_CODE: dict[str, str] = {
    UnifiedRequestType.HELPDESK: DashboardCode.SUPPORT,
    UnifiedRequestType.PROMO: DashboardCode.PROMO,
    UnifiedRequestType.VERIFICATION: DashboardCode.VERIFY,
    UnifiedRequestType.SUBSCRIPTION: DashboardCode.SUBS,
    UnifiedRequestType.EXTRAS: DashboardCode.EXTRAS,
    UnifiedRequestType.REVIEWS: DashboardCode.REVIEWS,
}


REQUEST_ACTION_PERMISSIONS: dict[str, dict[str, str]] = {
    UnifiedRequestType.HELPDESK: {
        "assign": "support.assign",
        "status": "support.resolve",
    },
    UnifiedRequestType.PROMO: {
        "assign": "promo.quote_activate",
        "status": "promo.quote_activate",
    },
    UnifiedRequestType.VERIFICATION: {
        "assign": "verification.finalize",
        "status": "verification.finalize",
    },
    UnifiedRequestType.SUBSCRIPTION: {
        "assign": "subscriptions.manage",
        "status": "subscriptions.manage",
    },
    UnifiedRequestType.EXTRAS: {
        "assign": "extras.manage",
        "status": "extras.manage",
    },
    UnifiedRequestType.REVIEWS: {
        "assign": "reviews.moderate",
        "status": "reviews.moderate",
    },
}


READ_REQUEST_CODES: tuple[str, ...] = (
    DashboardCode.ANALYTICS,
    DashboardCode.SUPPORT,
    DashboardCode.CONTENT,
    DashboardCode.MODERATION,
    DashboardCode.REVIEWS,
    DashboardCode.PROMO,
    DashboardCode.VERIFY,
    DashboardCode.SUBS,
    DashboardCode.EXTRAS,
)


def _request_dashboard_code(ur: UnifiedRequest) -> str:
    return REQUEST_TYPE_TEAM_CODE.get(ur.request_type, DashboardCode.ANALYTICS)


def _user_can_perform_action(user, ur: UnifiedRequest, *, action: str) -> bool:
    dashboard_code = _request_dashboard_code(ur)
    if not has_dashboard_access(user, dashboard_code, write=True):
        return False

    permission_code = REQUEST_ACTION_PERMISSIONS.get(ur.request_type, {}).get(action)
    if not permission_code:
        return True
    return has_action_permission(user, permission_code)


def _allowed_request_codes_for_user(user) -> set[str]:
    if getattr(user, "is_superuser", False):
        return set(READ_REQUEST_CODES)
    return {code for code in READ_REQUEST_CODES if has_dashboard_access(user, code, write=False)}


def _apply_dashboard_scope(qs, *, allowed_codes: set[str]):
    if DashboardCode.ANALYTICS in allowed_codes:
        return qs

    type_codes = [request_type for request_type, code in REQUEST_TYPE_TEAM_CODE.items() if code in allowed_codes]
    filters = Q(assigned_team_code__in=list(allowed_codes)) | Q(request_type__in=type_codes)
    return qs.filter(filters)


def _can_read_request(user, ur: UnifiedRequest) -> bool:
    if getattr(user, "is_superuser", False):
        return True
    if has_dashboard_access(user, DashboardCode.ANALYTICS, write=False):
        return True
    if has_dashboard_access(user, _request_dashboard_code(ur), write=False):
        return True
    if ur.assigned_team_code and has_dashboard_access(user, ur.assigned_team_code, write=False):
        return True
    return False


def _can_access_request_object(user, ur: UnifiedRequest) -> bool:
    return can_access_object(
        user,
        ur,
        assigned_field="assigned_user",
        owner_field="requester",
        allow_unassigned_for_user_level=False,
    ) or can_access_object(
        user,
        ur,
        assigned_field="assigned_user",
        allow_unassigned_for_user_level=False,
    )


@dashboard_v2_login_required
def requests_list_view(request):
    qs = UnifiedRequest.objects.select_related("requester", "assigned_user").order_by("-id")
    allowed_codes = _allowed_request_codes_for_user(request.user)
    if not allowed_codes:
        return HttpResponse("غير مصرح", status=403)

    q = (request.GET.get("q") or "").strip()
    status_val = (request.GET.get("status") or "").strip()
    type_val = (request.GET.get("type") or "").strip()
    team_val = (request.GET.get("team") or "").strip()
    date_from_val = (request.GET.get("date_from") or "").strip()
    date_to_val = (request.GET.get("date_to") or "").strip()

    if q:
        qs = qs.filter(
            Q(code__icontains=q)
            | Q(summary__icontains=q)
            | Q(source_object_id__icontains=q)
            | Q(requester__phone__icontains=q)
        )
    if status_val:
        qs = qs.filter(status=status_val)
    if type_val:
        qs = qs.filter(request_type=type_val)
    if team_val:
        qs = qs.filter(assigned_team_code=team_val)

    date_from = parse_date_yyyy_mm_dd(date_from_val)
    date_to = parse_date_yyyy_mm_dd(date_to_val)
    if date_from:
        qs = qs.filter(created_at__gte=date_from)
    if date_to:
        qs = qs.filter(created_at__lt=(date_to + timedelta(days=1)))

    qs = _apply_dashboard_scope(qs, allowed_codes=allowed_codes)

    qs = apply_role_scope(
        qs,
        user=request.user,
        assigned_field="assigned_user",
        owner_field="requester",
        include_unassigned_for_user=False,
    )

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    query = request.GET.copy()
    query.pop("page", None)

    status_labels = dict(UnifiedRequestStatus.choices)
    status_choices = [(status, status_labels.get(status, status)) for status in CANONICAL_OPERATIONAL_STATUSES]
    context = build_layout_context(
        request,
        title="الطلبات الموحدة",
        subtitle="Inbox تشغيلي موحد عبر كل الوحدات",
        active_code=DashboardCode.ANALYTICS,
        breadcrumbs=[{"label": "لوحة التحكم", "url": "dashboard_v2:home"}],
    )
    context.update(
        {
            "page_obj": page_obj,
            "query_string": query.urlencode(),
            "q": q,
            "status_val": status_val,
            "type_val": type_val,
            "team_val": team_val,
            "date_from_val": date_from_val,
            "date_to_val": date_to_val,
            "status_choices": status_choices,
            "type_choices": UnifiedRequestType.choices,
            "team_choices": list(TEAM_CODE_TO_NAME_AR.items()),
            "can_write": has_dashboard_access(request.user, DashboardCode.ANALYTICS, write=True),
            "can_view_all_requests": has_dashboard_access(request.user, DashboardCode.ANALYTICS, write=False),
            "table_headers": [
                "الكود",
                "النوع",
                "الحالة",
                "الفريق",
                "المسند إليه",
                "آخر تحديث",
                "إجراءات",
            ],
        }
    )
    return render(request, "dashboard_v2/requests/requests_list.html", context)


@dashboard_v2_login_required
def request_detail_view(request, request_id: int):
    ur = get_object_or_404(
        UnifiedRequest.objects.select_related("requester", "assigned_user")
        .prefetch_related(
            "status_logs__changed_by",
            "assignment_logs__from_user",
            "assignment_logs__to_user",
            "assignment_logs__changed_by",
        ),
        id=request_id,
    )
    if not _can_read_request(request.user, ur):
        return HttpResponse("غير مصرح", status=403)
    if not _can_access_request_object(request.user, ur):
        return HttpResponse("غير مصرح", status=403)

    metadata_record = getattr(ur, "metadata_record", None)
    metadata_payload = getattr(metadata_record, "payload", {}) or {}

    comments: list[dict] = []
    for key in ("ops_notes", "account_ops_notes", "notes", "comments"):
        raw_items = metadata_payload.get(key)
        if isinstance(raw_items, list):
            for item in raw_items:
                if isinstance(item, dict):
                    comments.append(item)

    attachments: list[dict] = []
    raw_attachments = metadata_payload.get("attachments") or metadata_payload.get("files")
    if isinstance(raw_attachments, list):
        for item in raw_attachments:
            if isinstance(item, dict):
                attachments.append(item)

    timeline: list[dict] = []
    for status_log in ur.status_logs.all():
        timeline.append(
            {
                "kind": "status",
                "at": status_log.created_at,
                "title": "تغيير حالة",
                "detail": f"{status_log.from_status or '—'} → {status_log.to_status}",
                "actor": getattr(getattr(status_log, "changed_by", None), "phone", "") or "النظام",
                "note": status_log.note or "",
            }
        )
    for assign_log in ur.assignment_logs.all():
        timeline.append(
            {
                "kind": "assign",
                "at": assign_log.created_at,
                "title": "تحديث إسناد",
                "detail": f"{assign_log.from_team_code or '—'} → {assign_log.to_team_code or '—'}",
                "actor": getattr(getattr(assign_log, "changed_by", None), "phone", "") or "النظام",
                "note": assign_log.note or "",
            }
        )
    timeline.sort(key=lambda item: item["at"], reverse=True)

    team_code = _request_dashboard_code(ur)
    assignees = dashboard_assignment_users(team_code, write=True, limit=120)
    can_assign = _user_can_perform_action(request.user, ur, action="assign")
    can_set_status = _user_can_perform_action(request.user, ur, action="status")
    status_labels = dict(UnifiedRequestStatus.choices)

    context = build_layout_context(
        request,
        title=f"تفاصيل الطلب {ur.code or ur.id}",
        subtitle="سجل تشغيلي موحد + timeline",
        active_code=DashboardCode.ANALYTICS,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "الطلبات الموحدة", "url": "dashboard_v2:requests_list"},
        ],
    )
    context.update(
        {
            "ur": ur,
            "metadata_payload": metadata_payload,
            "comments": comments,
            "attachments": attachments,
            "timeline": timeline[:100],
            "assignees": assignees,
            "can_assign": can_assign,
            "can_set_status": can_set_status,
            "status_choices": [
                (value, status_labels.get(value, value))
                for value in allowed_statuses_for_request_type(ur.request_type)
                if value in set(CANONICAL_OPERATIONAL_STATUSES)
            ],
        }
    )
    return render(request, "dashboard_v2/requests/request_detail.html", context)


@dashboard_v2_login_required
@require_POST
def request_assign_action(request, request_id: int):
    ur = get_object_or_404(UnifiedRequest, id=request_id)
    if not _can_access_request_object(request.user, ur):
        return HttpResponse("غير مصرح", status=403)
    if not _user_can_perform_action(request.user, ur, action="assign"):
        messages.error(request, "ليس لديك صلاحية إسناد هذا الطلب.")
        return redirect("dashboard_v2:request_detail", request_id=ur.id)

    assigned_to_raw = request.POST.get("assigned_to") or None
    note = (request.POST.get("note") or "").strip()
    try:
        assigned_to = int(assigned_to_raw) if assigned_to_raw else None
    except Exception:
        assigned_to = None

    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == AccessLevel.USER and assigned_to not in (None, request.user.id):
        return HttpResponse("غير مصرح", status=403)

    team_code = _request_dashboard_code(ur)
    if assigned_to is not None and dashboard_assignee_user(assigned_to, team_code, write=True) is None:
        messages.error(request, "المستخدم المحدد غير صالح للإسناد.")
        return redirect("dashboard_v2:request_detail", request_id=ur.id)

    team_name = TEAM_CODE_TO_NAME_AR.get(team_code, "")
    try:
        with transaction.atomic():
            ur = UnifiedRequest.objects.select_for_update().get(id=ur.id)
            old_user_id = ur.assigned_user_id
            old_team = ur.assigned_team_code or ""
            ur.assigned_team_code = team_code
            ur.assigned_team_name = team_name
            ur.assigned_user_id = assigned_to
            ur.assigned_at = timezone.now() if assigned_to else None
            ur.save(
                update_fields=[
                    "assigned_team_code",
                    "assigned_team_name",
                    "assigned_user",
                    "assigned_at",
                    "updated_at",
                ]
            )

            if old_user_id != ur.assigned_user_id or old_team != (ur.assigned_team_code or ""):
                UnifiedRequestAssignmentLog.objects.create(
                    request=ur,
                    from_team_code=old_team,
                    to_team_code=ur.assigned_team_code or "",
                    from_user_id=old_user_id,
                    to_user=ur.assigned_user,
                    changed_by=request.user,
                    note=note[:200],
                )
                log_action(
                    actor=request.user,
                    action=AuditAction.FIELD_CHANGED,
                    reference_type="unified_request",
                    reference_id=str(ur.id),
                    request=request,
                    extra={
                        "field": "assigned_user",
                        "from_user_id": old_user_id,
                        "to_user_id": ur.assigned_user_id,
                        "from_team": old_team,
                        "to_team": ur.assigned_team_code or "",
                        "note": note[:200],
                    },
                )
        messages.success(request, "تم تحديث الإسناد بنجاح.")
    except Exception:
        messages.error(request, "تعذر تحديث الإسناد.")
    return redirect("dashboard_v2:request_detail", request_id=ur.id)


@dashboard_v2_login_required
@require_POST
def request_status_action(request, request_id: int):
    ur = get_object_or_404(UnifiedRequest, id=request_id)
    if not _can_access_request_object(request.user, ur):
        return HttpResponse("غير مصرح", status=403)
    if not _user_can_perform_action(request.user, ur, action="status"):
        messages.error(request, "ليس لديك صلاحية تعديل حالة هذا الطلب.")
        return redirect("dashboard_v2:request_detail", request_id=ur.id)

    new_status_raw = (request.POST.get("status") or "").strip()
    note = (request.POST.get("note") or "").strip()
    new_status = canonical_status_for_workflow(request_type=ur.request_type, status=new_status_raw)
    allowed = set(allowed_statuses_for_request_type(ur.request_type))
    if not new_status or new_status not in allowed:
        messages.warning(request, "حالة غير صالحة.")
        return redirect("dashboard_v2:request_detail", request_id=ur.id)

    try:
        with transaction.atomic():
            ur = UnifiedRequest.objects.select_for_update().get(id=ur.id)
            old_status = ur.status
            if old_status != new_status:
                if not is_valid_transition(
                    request_type=ur.request_type,
                    from_status=old_status,
                    to_status=new_status,
                ):
                    messages.warning(request, "انتقال الحالة غير مسموح.")
                    return redirect("dashboard_v2:request_detail", request_id=ur.id)

                ur.status = new_status
                if new_status == UnifiedRequestStatus.CLOSED and ur.closed_at is None:
                    ur.closed_at = timezone.now()
                    ur.save(update_fields=["status", "closed_at", "updated_at"])
                else:
                    ur.save(update_fields=["status", "updated_at"])
                UnifiedRequestStatusLog.objects.create(
                    request=ur,
                    from_status=old_status,
                    to_status=new_status,
                    changed_by=request.user,
                    note=note[:200],
                )
                log_action(
                    actor=request.user,
                    action=AuditAction.FIELD_CHANGED,
                    reference_type="unified_request",
                    reference_id=str(ur.id),
                    request=request,
                    extra={
                        "field": "status",
                        "from_status": old_status,
                        "to_status": new_status,
                        "note": note[:200],
                    },
                )
        messages.success(request, "تم تحديث حالة الطلب.")
    except Exception:
        messages.error(request, "تعذر تحديث الحالة.")
    return redirect("dashboard_v2:request_detail", request_id=ur.id)
