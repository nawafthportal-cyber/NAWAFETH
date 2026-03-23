from __future__ import annotations

from datetime import timedelta

from django.contrib import messages
from django.core.paginator import Paginator
from django.http import Http404, HttpRequest, HttpResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.urls import reverse
from django.utils import timezone
from django.views.decorators.http import require_POST

from apps.backoffice.policies import ModerationAssignPolicy, ModerationResolvePolicy
from apps.core.feature_flags import moderation_center_enabled
from apps.moderation.integrations import moderation_sla_state
from apps.moderation.models import (
    ModerationCase,
    ModerationDecisionCode,
    ModerationSeverity,
    ModerationStatus,
)
from apps.moderation.services import assign_case, change_case_status, record_decision

from .auth import dashboard_staff_required as staff_member_required
from .access import can_access_object, dashboard_assignment_users
from .views import _dashboard_allowed, dashboard_access_required


_OPEN_CASE_STATUSES = {
    ModerationStatus.NEW,
    ModerationStatus.UNDER_REVIEW,
    ModerationStatus.ESCALATED,
}


def _ensure_moderation_flag():
    if not moderation_center_enabled():
        raise Http404


def _moderation_queryset():
    return (
        ModerationCase.objects.select_related("reporter", "reported_user", "assigned_to")
        .prefetch_related("action_logs__created_by", "decisions__applied_by")
        .order_by("-id")
    )


def _list_summary(qs):
    now = timezone.now()
    open_qs = qs.filter(status__in=_OPEN_CASE_STATUSES)
    due_soon_limit = now + timedelta(hours=12)
    return {
        "total": qs.count(),
        "new": qs.filter(status=ModerationStatus.NEW).count(),
        "under_review": qs.filter(status=ModerationStatus.UNDER_REVIEW).count(),
        "escalated": qs.filter(status=ModerationStatus.ESCALATED).count(),
        "overdue": open_qs.filter(sla_due_at__lt=now).count(),
        "due_soon": open_qs.filter(sla_due_at__gte=now, sla_due_at__lte=due_soon_limit).count(),
    }


def _case_deadline_context(case: ModerationCase) -> dict[str, object]:
    now = timezone.now()
    overdue_for_hours = None
    if case.sla_due_at and case.sla_due_at < now and not case.is_terminal:
        overdue_for_hours = round((now - case.sla_due_at).total_seconds() / 3600, 1)
    return {
        "sla_due_at": case.sla_due_at,
        "sla_state": moderation_sla_state(case, now=now),
        "overdue_for_hours": overdue_for_hours,
        "latest_decision": case.decisions.first(),
        "escalation_count": int((case.meta or {}).get("escalation_count") or 0),
    }


def _apply_sla_filter(qs, raw_value: str):
    value = str(raw_value or "").strip().lower()
    if not value:
        return qs
    now = timezone.now()
    if value == "overdue":
        return qs.filter(status__in=_OPEN_CASE_STATUSES, sla_due_at__lt=now)
    if value == "due_soon":
        return qs.filter(status__in=_OPEN_CASE_STATUSES, sla_due_at__gte=now, sla_due_at__lte=now + timedelta(hours=12))
    if value == "open":
        return qs.filter(status__in=_OPEN_CASE_STATUSES).exclude(sla_due_at__lt=now)
    if value == "closed":
        return qs.exclude(status__in=_OPEN_CASE_STATUSES)
    return qs


def _source_context(case: ModerationCase) -> dict[str, str]:
    source_url = ""
    if case.linked_support_ticket_id:
        source_url = reverse("dashboard:support_ticket_detail", args=[case.linked_support_ticket_id])
    elif case.source_app == "reviews" and case.source_model == "Review" and case.source_object_id:
        source_url = reverse("dashboard:reviews_dashboard_detail", args=[case.source_object_id])
    elif case.source_model == "ProviderPortfolioItem":
        source_url = reverse("dashboard:portfolio_moderation_list")
    elif case.source_model == "ProviderSpotlightItem":
        source_url = reverse("dashboard:spotlight_moderation_list")

    return {
        "source_title": case.source_label or f"{case.source_model} #{case.source_object_id}",
        "source_url": source_url,
        "linked_ticket_url": (
            reverse("dashboard:support_ticket_detail", args=[case.linked_support_ticket_id])
            if case.linked_support_ticket_id
            else ""
        ),
    }


@staff_member_required
@dashboard_access_required("moderation", write=False)
def moderation_cases_list(request: HttpRequest) -> HttpResponse:
    _ensure_moderation_flag()

    qs = _moderation_queryset()
    status_q = (request.GET.get("status") or "").strip()
    source_q = (request.GET.get("source_kind") or "").strip()
    severity_q = (request.GET.get("severity") or "").strip()
    category_q = (request.GET.get("category") or "").strip()
    assignee_q = (request.GET.get("assignee") or "").strip()
    sla_q = (request.GET.get("sla_state") or "").strip()

    if status_q in {choice[0] for choice in ModerationStatus.choices}:
        qs = qs.filter(status=status_q)
    if source_q:
        qs = qs.filter(source_app__iexact=source_q)
    if severity_q in {choice[0] for choice in ModerationSeverity.choices}:
        qs = qs.filter(severity=severity_q)
    if category_q:
        qs = qs.filter(category__icontains=category_q)
    if assignee_q.isdigit():
        qs = qs.filter(assigned_to_id=int(assignee_q))
    qs = _apply_sla_filter(qs, sla_q)

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or 1)
    page_items = []
    for case in page_obj.object_list:
        page_items.append(
            {
                "case": case,
                "sla_state": moderation_sla_state(case),
            }
        )

    return render(
        request,
        "dashboard/moderation_cases_list.html",
        {
            "page_obj": page_obj,
            "page_items": page_items,
            "status_q": status_q,
            "source_q": source_q,
            "severity_q": severity_q,
            "category_q": category_q,
            "assignee_q": assignee_q,
            "sla_q": sla_q,
            "status_choices": ModerationStatus.choices,
            "severity_choices": ModerationSeverity.choices,
            "summary": _list_summary(qs),
            "assignee_users": dashboard_assignment_users("moderation", write=True, limit=150),
            "can_write": _dashboard_allowed(request.user, "moderation", write=True),
        },
    )


@staff_member_required
@dashboard_access_required("moderation", write=False)
def moderation_case_detail(request: HttpRequest, case_id: int) -> HttpResponse:
    _ensure_moderation_flag()
    case = get_object_or_404(_moderation_queryset(), id=case_id)
    if not can_access_object(request.user, case, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)
    assign_policy = ModerationAssignPolicy.evaluate(request.user)
    resolve_policy = ModerationResolvePolicy.evaluate(request.user)
    return render(
        request,
        "dashboard/moderation_case_detail.html",
        {
            "case": case,
            "source_context": _source_context(case),
            "status_choices": ModerationStatus.choices,
            "decision_choices": ModerationDecisionCode.choices,
            "assignee_users": dashboard_assignment_users("moderation", write=True, limit=150),
            "can_assign": assign_policy.allowed and _dashboard_allowed(request.user, "moderation", write=True),
            "can_resolve": resolve_policy.allowed and _dashboard_allowed(request.user, "moderation", write=True),
            **_case_deadline_context(case),
        },
    )


@staff_member_required
@dashboard_access_required("moderation", write=True)
@require_POST
def moderation_case_assign_action(request: HttpRequest, case_id: int) -> HttpResponse:
    _ensure_moderation_flag()
    case = get_object_or_404(ModerationCase, id=case_id)
    if not can_access_object(request.user, case, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)
    policy = ModerationAssignPolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="moderation.case",
        reference_id=str(case.id),
        extra={"surface": "dashboard.moderation_case_assign_action"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بإسناد هذه الحالة")
        return redirect("dashboard:moderation_case_detail", case_id=case.id)

    assigned_to_raw = request.POST.get("assigned_to") or None
    try:
        assigned_to = int(assigned_to_raw) if assigned_to_raw else None
    except Exception:
        assigned_to = None
    team_code = (request.POST.get("assigned_team_code") or "").strip()
    team_name = (request.POST.get("assigned_team_name") or "").strip()
    note = (request.POST.get("note") or "").strip()

    assign_case(
        case=case,
        assigned_team_code=team_code,
        assigned_team_name=team_name,
        assigned_to_id=assigned_to,
        note=note,
        by_user=request.user,
        request=request,
    )
    messages.success(request, "تم تحديث الإسناد")
    return redirect("dashboard:moderation_case_detail", case_id=case.id)


@staff_member_required
@dashboard_access_required("moderation", write=True)
@require_POST
def moderation_case_status_action(request: HttpRequest, case_id: int) -> HttpResponse:
    _ensure_moderation_flag()
    case = get_object_or_404(ModerationCase, id=case_id)
    if not can_access_object(request.user, case, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)
    policy = ModerationResolvePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="moderation.case",
        reference_id=str(case.id),
        extra={"surface": "dashboard.moderation_case_status_action"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتحديث هذه الحالة")
        return redirect("dashboard:moderation_case_detail", case_id=case.id)

    new_status = (request.POST.get("status") or "").strip()
    note = (request.POST.get("note") or "").strip()
    if new_status not in {choice[0] for choice in ModerationStatus.choices}:
        messages.error(request, "حالة غير صالحة")
        return redirect("dashboard:moderation_case_detail", case_id=case.id)

    change_case_status(case=case, new_status=new_status, note=note, by_user=request.user, request=request)
    messages.success(request, "تم تحديث الحالة")
    return redirect("dashboard:moderation_case_detail", case_id=case.id)


@staff_member_required
@dashboard_access_required("moderation", write=True)
@require_POST
def moderation_case_decision_action(request: HttpRequest, case_id: int) -> HttpResponse:
    _ensure_moderation_flag()
    case = get_object_or_404(ModerationCase, id=case_id)
    if not can_access_object(request.user, case, assigned_field="assigned_to", allow_unassigned_for_user_level=True):
        return HttpResponse("غير مصرح", status=403)
    policy = ModerationResolvePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="moderation.case",
        reference_id=str(case.id),
        extra={"surface": "dashboard.moderation_case_decision_action"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتسجيل القرار")
        return redirect("dashboard:moderation_case_detail", case_id=case.id)

    decision_code = (request.POST.get("decision_code") or "").strip()
    note = (request.POST.get("note") or "").strip()
    is_final = (request.POST.get("is_final") or "1").strip() not in {"0", "false", "False"}
    if decision_code not in {choice[0] for choice in ModerationDecisionCode.choices}:
        messages.error(request, "القرار غير صالح")
        return redirect("dashboard:moderation_case_detail", case_id=case.id)

    record_decision(
        case=case,
        decision_code=decision_code,
        note=note,
        outcome={"surface": "dashboard"},
        is_final=is_final,
        by_user=request.user,
        request=request,
    )
    messages.success(request, "تم تسجيل القرار")
    return redirect("dashboard:moderation_case_detail", case_id=case.id)
