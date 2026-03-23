from __future__ import annotations

from django.contrib import messages
from django.core.paginator import Paginator
from django.db.models import Q
from django.http import HttpResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.views.decorators.http import require_POST

from apps.backoffice.models import AccessLevel
from apps.backoffice.policies import SupportAssignPolicy, SupportResolvePolicy
from apps.dashboard.access import (
    can_access_object,
    dashboard_assignee_user,
    dashboard_assignment_users,
    has_action_permission,
    has_dashboard_access,
)
from apps.dashboard.contracts import DashboardCode
from apps.support.models import SupportTeam, SupportTicket, SupportTicketStatus, SupportTicketType
from apps.support.services import assign_ticket, change_ticket_status

from ..view_utils import apply_role_scope, build_layout_context, dashboard_v2_access_required


def _can_access_support_ticket(user, ticket: SupportTicket) -> bool:
    return can_access_object(
        user,
        ticket,
        assigned_field="assigned_to",
        owner_field="requester",
        allow_unassigned_for_user_level=False,
    ) or can_access_object(
        user,
        ticket,
        assigned_field="assigned_to",
        allow_unassigned_for_user_level=False,
    )


@dashboard_v2_access_required(DashboardCode.SUPPORT, write=False)
def support_list_view(request):
    qs = SupportTicket.objects.select_related("requester", "assigned_team", "assigned_to").order_by("-id")

    q = (request.GET.get("q") or "").strip()
    status_val = (request.GET.get("status") or "").strip()
    type_val = (request.GET.get("type") or "").strip()
    priority_val = (request.GET.get("priority") or "").strip()

    if q:
        qs = qs.filter(
            Q(code__icontains=q)
            | Q(requester__phone__icontains=q)
            | Q(description__icontains=q)
        )
    if status_val:
        qs = qs.filter(status=status_val)
    if type_val:
        qs = qs.filter(ticket_type=type_val)
    if priority_val:
        qs = qs.filter(priority=priority_val)

    qs = apply_role_scope(
        qs,
        user=request.user,
        assigned_field="assigned_to",
        owner_field="requester",
        include_unassigned_for_user=True,
    )

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    query = request.GET.copy()
    query.pop("page", None)

    context = build_layout_context(
        request,
        title="تذاكر الدعم",
        subtitle="متابعة عمليات الدعم والإسناد والحالة",
        active_code=DashboardCode.SUPPORT,
        breadcrumbs=[{"label": "لوحة التحكم", "url": "dashboard_v2:home"}],
    )
    context.update(
        {
            "page_obj": page_obj,
            "query_string": query.urlencode(),
            "q": q,
            "status_val": status_val,
            "type_val": type_val,
            "priority_val": priority_val,
            "status_choices": SupportTicketStatus.choices,
            "type_choices": SupportTicketType.choices,
            "priority_choices": SupportTicket._meta.get_field("priority").choices,
            "can_write": has_dashboard_access(request.user, DashboardCode.SUPPORT, write=True),
            "table_headers": [
                "الكود",
                "النوع",
                "الحالة",
                "الأولوية",
                "المسند إليه",
                "آخر تحديث",
                "إجراءات",
            ],
        }
    )
    return render(request, "dashboard_v2/support/support_list.html", context)


@dashboard_v2_access_required(DashboardCode.SUPPORT, write=False)
def support_detail_view(request, ticket_id: int):
    ticket = get_object_or_404(
        SupportTicket.objects.select_related("requester", "assigned_team", "assigned_to", "last_action_by"),
        id=ticket_id,
    )
    if not _can_access_support_ticket(request.user, ticket):
        return HttpResponse("غير مصرح", status=403)

    comments = list(ticket.comments.select_related("created_by").order_by("-id")[:40])
    attachments = list(ticket.attachments.select_related("uploaded_by").order_by("-id")[:20])
    logs = list(ticket.status_logs.select_related("changed_by").order_by("-id")[:50])
    teams = list(SupportTeam.objects.filter(is_active=True).order_by("sort_order", "id"))
    assignees = dashboard_assignment_users(DashboardCode.SUPPORT, write=True, limit=120)

    can_write = has_dashboard_access(request.user, DashboardCode.SUPPORT, write=True)
    can_assign = can_write and has_action_permission(request.user, "support.assign")
    can_set_status = can_write and has_action_permission(request.user, "support.resolve")

    context = build_layout_context(
        request,
        title=f"تفاصيل التذكرة {ticket.code or ticket.id}",
        subtitle="Timeline + تعليقات + مرفقات",
        active_code=DashboardCode.SUPPORT,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "تذاكر الدعم", "url": "dashboard_v2:support_list"},
        ],
    )
    context.update(
        {
            "ticket": ticket,
            "comments": comments,
            "attachments": attachments,
            "logs": logs,
            "teams": teams,
            "assignees": assignees,
            "can_assign": can_assign,
            "can_set_status": can_set_status,
            "status_choices": SupportTicketStatus.choices,
        }
    )
    return render(request, "dashboard_v2/support/support_detail.html", context)


@dashboard_v2_access_required(DashboardCode.SUPPORT, write=True)
@require_POST
def support_assign_action(request, ticket_id: int):
    ticket = get_object_or_404(SupportTicket, id=ticket_id)
    if not _can_access_support_ticket(request.user, ticket):
        return HttpResponse("غير مصرح", status=403)

    policy = SupportAssignPolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="support.ticket",
        reference_id=str(ticket.id),
        extra={"surface": "dashboard_v2.support_assign_action"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بإسناد هذه التذكرة.")
        return redirect("dashboard_v2:support_detail", ticket_id=ticket.id)

    team_id_raw = request.POST.get("assigned_team") or None
    assigned_to_raw = request.POST.get("assigned_to") or None
    note = (request.POST.get("note") or "").strip()

    try:
        team_id = int(team_id_raw) if team_id_raw else None
    except Exception:
        team_id = None
    try:
        assigned_to = int(assigned_to_raw) if assigned_to_raw else None
    except Exception:
        assigned_to = None

    ap = getattr(request.user, "access_profile", None)
    if ap and ap.level == AccessLevel.USER and assigned_to not in (None, request.user.id):
        return HttpResponse("غير مصرح", status=403)
    if assigned_to is not None and dashboard_assignee_user(assigned_to, DashboardCode.SUPPORT, write=True) is None:
        messages.error(request, "المستخدم المحدد غير صالح للتعيين.")
        return redirect("dashboard_v2:support_detail", ticket_id=ticket.id)

    try:
        assign_ticket(
            ticket=ticket,
            team_id=team_id,
            user_id=assigned_to,
            by_user=request.user,
            note=note,
        )
        messages.success(request, "تم تحديث الإسناد بنجاح.")
    except Exception:
        messages.error(request, "تعذر تحديث الإسناد.")
    return redirect("dashboard_v2:support_detail", ticket_id=ticket.id)


@dashboard_v2_access_required(DashboardCode.SUPPORT, write=True)
@require_POST
def support_status_action(request, ticket_id: int):
    ticket = get_object_or_404(SupportTicket, id=ticket_id)
    if not _can_access_support_ticket(request.user, ticket):
        return HttpResponse("غير مصرح", status=403)

    policy = SupportResolvePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="support.ticket",
        reference_id=str(ticket.id),
        extra={"surface": "dashboard_v2.support_status_action"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتحديث حالة هذه التذكرة.")
        return redirect("dashboard_v2:support_detail", ticket_id=ticket.id)

    new_status = (request.POST.get("status") or "").strip()
    note = (request.POST.get("note") or "").strip()
    if not new_status:
        messages.warning(request, "اختر حالة صالحة.")
        return redirect("dashboard_v2:support_detail", ticket_id=ticket.id)

    try:
        change_ticket_status(ticket=ticket, new_status=new_status, by_user=request.user, note=note)
        messages.success(request, "تم تحديث حالة التذكرة.")
    except Exception as exc:
        messages.error(request, str(exc) or "تعذر تحديث الحالة.")
    return redirect("dashboard_v2:support_detail", ticket_id=ticket.id)
