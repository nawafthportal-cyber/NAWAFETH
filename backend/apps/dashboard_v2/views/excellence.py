from __future__ import annotations

from datetime import datetime, timedelta

from django.contrib import messages
from django.core.paginator import Paginator
from django.db.models import Q
from django.shortcuts import get_object_or_404, redirect, render
from django.utils import timezone
from django.views.decorators.http import require_POST

from apps.dashboard.access import has_dashboard_access
from apps.dashboard.contracts import DashboardCode
from apps.dashboard.security import safe_redirect_url
from apps.excellence.models import (
    ExcellenceBadgeAward,
    ExcellenceBadgeCandidate,
    ExcellenceBadgeCandidateStatus,
    ExcellenceBadgeType,
)
from apps.excellence.selectors import current_cycle_candidates_queryset, current_review_window
from apps.excellence.services import approve_candidate, revoke_award, sync_badge_type_catalog

from ..view_utils import build_layout_context, dashboard_v2_access_required


EXCELLENCE_DASHBOARD_CODE = "excellence"


def _parse_datetime_local(raw_value: str):
    value = (raw_value or "").strip()
    if not value:
        return None
    try:
        parsed = datetime.strptime(value, "%Y-%m-%dT%H:%M")
        return timezone.make_aware(parsed, timezone.get_current_timezone())
    except Exception:
        return None


def _candidate_with_active_award(candidate: ExcellenceBadgeCandidate):
    active_award = None
    for award in getattr(candidate, "prefetched_awards", []):
        if award.is_active:
            active_award = award
            break
    candidate.active_award = active_award
    return candidate


@dashboard_v2_access_required(EXCELLENCE_DASHBOARD_CODE, write=False)
def excellence_home_view(request):
    sync_badge_type_catalog()

    badge_q = (request.GET.get("badge") or "").strip()
    status_q = (request.GET.get("status") or "").strip()
    q = (request.GET.get("q") or "").strip()

    _, cycle_end = current_review_window()
    queryset = current_cycle_candidates_queryset().prefetch_related("awards")
    if not queryset.exists():
        latest_end = (
            ExcellenceBadgeCandidate.objects.order_by("-evaluation_period_end")
            .values_list("evaluation_period_end", flat=True)
            .first()
        )
        if latest_end:
            queryset = (
                ExcellenceBadgeCandidate.objects.select_related(
                    "badge_type",
                    "provider",
                    "provider__user",
                    "category",
                    "subcategory",
                    "reviewed_by",
                )
                .filter(evaluation_period_end=latest_end)
                .order_by("badge_type__sort_order", "rank_position", "provider_id")
                .prefetch_related("awards")
            )
            cycle_end = latest_end

    if badge_q:
        queryset = queryset.filter(badge_type__code=badge_q)
    if status_q in {choice[0] for choice in ExcellenceBadgeCandidateStatus.choices}:
        queryset = queryset.filter(status=status_q)
    if q:
        queryset = queryset.filter(
            Q(provider__display_name__icontains=q)
            | Q(provider__user__phone__icontains=q)
            | Q(category__name__icontains=q)
            | Q(subcategory__name__icontains=q)
        )

    candidates = []
    for candidate in queryset:
        candidate.prefetched_awards = list(candidate.awards.all())
        candidates.append(_candidate_with_active_award(candidate))

    paginator = Paginator(candidates, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    query = request.GET.copy()
    query.pop("page", None)

    now = timezone.now()
    context = build_layout_context(
        request,
        title="التميز",
        subtitle="إدارة مرشحي الشارات، الاعتماد، وسحب الشارات",
        active_code=EXCELLENCE_DASHBOARD_CODE,
        breadcrumbs=[{"label": "لوحة التحكم", "url": "dashboard_v2:home"}],
    )
    context.update(
        {
            "page_obj": page_obj,
            "query_string": query.urlencode(),
            "badge_q": badge_q,
            "status_q": status_q,
            "q": q,
            "badge_types": list(ExcellenceBadgeType.objects.filter(is_active=True).order_by("sort_order", "id")),
            "status_choices": ExcellenceBadgeCandidateStatus.choices,
            "active_awards_count": ExcellenceBadgeAward.objects.filter(is_active=True).count(),
            "expiring_soon_count": ExcellenceBadgeAward.objects.filter(
                is_active=True,
                valid_until__gt=now,
                valid_until__lte=now + timedelta(days=14),
            ).count(),
            "cycle_end": cycle_end,
            "can_write": has_dashboard_access(request.user, EXCELLENCE_DASHBOARD_CODE, write=True),
            "table_headers": ["المختص", "الشارة", "الحالة", "الترتيب", "المقاييس", "إجراءات"],
        }
    )
    return render(request, "dashboard_v2/excellence/home.html", context)


@dashboard_v2_access_required(EXCELLENCE_DASHBOARD_CODE, write=False)
def excellence_candidate_detail_view(request, candidate_id: int):
    candidate = get_object_or_404(
        ExcellenceBadgeCandidate.objects.select_related(
            "badge_type",
            "provider",
            "provider__user",
            "category",
            "subcategory",
            "reviewed_by",
        ).prefetch_related("awards__approved_by", "awards__revoked_by"),
        id=candidate_id,
    )
    awards = list(candidate.awards.all())
    active_award = next((award for award in awards if award.is_active), None)

    context = build_layout_context(
        request,
        title=f"مرشح التميز #{candidate.id}",
        subtitle="تفاصيل المرشح وسجل الشارات الممنوحة",
        active_code=EXCELLENCE_DASHBOARD_CODE,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "التميز", "url": "dashboard_v2:excellence_home"},
        ],
    )
    context.update(
        {
            "candidate": candidate,
            "awards": awards,
            "active_award": active_award,
            "can_write": has_dashboard_access(request.user, EXCELLENCE_DASHBOARD_CODE, write=True),
        }
    )
    return render(request, "dashboard_v2/excellence/detail.html", context)


@dashboard_v2_access_required(EXCELLENCE_DASHBOARD_CODE, write=True)
@require_POST
def excellence_candidate_approve_action(request, candidate_id: int):
    candidate = get_object_or_404(
        ExcellenceBadgeCandidate.objects.select_related(
            "badge_type",
            "provider",
            "provider__user",
            "category",
            "subcategory",
        ),
        id=candidate_id,
    )
    note = (request.POST.get("note") or "").strip()
    valid_until = _parse_datetime_local(request.POST.get("valid_until") or "")
    try:
        approve_candidate(candidate=candidate, approved_by=request.user, valid_until=valid_until, note=note)
        messages.success(request, "تم اعتماد الشارة بنجاح.")
    except Exception:
        messages.error(request, "تعذر اعتماد الشارة.")
    next_url = safe_redirect_url(request, fallback="")
    if next_url:
        return redirect(next_url)
    return redirect("dashboard_v2:excellence_candidate_detail", candidate_id=candidate.id)


@dashboard_v2_access_required(EXCELLENCE_DASHBOARD_CODE, write=True)
@require_POST
def excellence_award_revoke_action(request, award_id: int):
    award = get_object_or_404(ExcellenceBadgeAward.objects.select_related("candidate"), id=award_id)
    note = (request.POST.get("note") or "").strip()
    try:
        revoke_award(award=award, revoked_by=request.user, note=note)
        messages.success(request, "تم سحب الشارة بنجاح.")
    except Exception:
        messages.error(request, "تعذر سحب الشارة.")
    next_url = safe_redirect_url(request, fallback="")
    if next_url:
        return redirect(next_url)
    if award.candidate_id:
        return redirect("dashboard_v2:excellence_candidate_detail", candidate_id=award.candidate_id)
    return redirect("dashboard_v2:excellence_home")
