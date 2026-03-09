from __future__ import annotations

from datetime import timedelta

from django.contrib import messages
from django.core.paginator import Paginator
from django.utils import timezone
from django.http import HttpRequest, HttpResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.db.models import Q
from django.views.decorators.http import require_POST

from apps.core.models import PlatformConfig
from apps.dashboard.auth import dashboard_staff_required as staff_member_required
from apps.dashboard.exports import pdf_response, xlsx_response
from apps.dashboard.views import (
    _csv_response,
    _parse_datetime_local,
    _want_csv,
    _want_pdf,
    _want_xlsx,
    require_dashboard_access,
)

from .models import ExcellenceBadgeAward, ExcellenceBadgeCandidate, ExcellenceBadgeCandidateStatus, ExcellenceBadgeType
from .selectors import current_cycle_candidates_queryset, current_review_window
from .services import approve_candidate, revoke_award, sync_badge_type_catalog


def _status_label(candidate: ExcellenceBadgeCandidate) -> str:
    return dict(ExcellenceBadgeCandidateStatus.choices).get(candidate.status, candidate.status)


def _candidate_active_award(candidate: ExcellenceBadgeCandidate):
    for award in getattr(candidate, "prefetched_awards", []):
        if award.is_active:
            return award
    return None


def _export_rows(candidates):
    rows = []
    for candidate in candidates:
        provider = candidate.provider
        rows.append(
            [
                provider.display_name or "",
                getattr(getattr(provider, "user", None), "phone", ""),
                candidate.badge_type.name_ar,
                candidate.rank_position,
                candidate.followers_count,
                candidate.completed_orders_count,
                candidate.rating_avg,
                candidate.rating_count,
                getattr(candidate.category, "name", "—") or "—",
                getattr(candidate.subcategory, "name", "—") or "—",
                _status_label(candidate),
                candidate.evaluation_period_end.date().isoformat(),
            ]
        )
    return rows


@staff_member_required
@require_dashboard_access("excellence")
def excellence_dashboard(request: HttpRequest) -> HttpResponse:
    sync_badge_type_catalog()

    badge_code = (request.GET.get("badge") or "").strip()
    status_val = (request.GET.get("status") or "").strip()
    q = (request.GET.get("q") or "").strip()

    current_start, current_end = current_review_window()
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
            current_end = latest_end

    if badge_code:
        queryset = queryset.filter(badge_type__code=badge_code)
    if status_val:
        queryset = queryset.filter(status=status_val)
    if q:
        queryset = queryset.filter(
            Q(provider__display_name__icontains=q)
            | Q(provider__user__phone__icontains=q)
            | Q(category__name__icontains=q)
            | Q(subcategory__name__icontains=q)
        )

    candidates = list(queryset)
    for candidate in candidates:
        candidate.prefetched_awards = list(candidate.awards.all())
        candidate.active_award = _candidate_active_award(candidate)

    badge_types = list(ExcellenceBadgeType.objects.filter(is_active=True).order_by("sort_order", "id"))
    status_choices = ExcellenceBadgeCandidateStatus.choices
    active_awards_count = ExcellenceBadgeAward.objects.filter(is_active=True).count()
    now = timezone.now()
    expiring_soon_count = ExcellenceBadgeAward.objects.filter(
        is_active=True,
        valid_until__gt=now,
        valid_until__lte=now + timedelta(days=14),
    ).count()

    headers = [
        "provider_name",
        "phone",
        "badge_type",
        "rank_position",
        "followers_count",
        "completed_orders_count",
        "rating_avg",
        "rating_count",
        "category",
        "subcategory",
        "status",
        "cycle_end",
    ]
    rows = _export_rows(candidates)
    if _want_csv(request):
        return _csv_response(
            "excellence_candidates.csv",
            headers,
            rows[: max(1, int(PlatformConfig.load().export_xlsx_max_rows or 2000))],
        )
    if _want_xlsx(request):
        return xlsx_response(
            "excellence_candidates.xlsx",
            "excellence",
            headers,
            rows[: max(1, int(PlatformConfig.load().export_xlsx_max_rows or 2000))],
        )
    if _want_pdf(request):
        return pdf_response(
            "excellence_candidates.pdf",
            "تقرير مرشحي شارات التميز",
            headers,
            rows[: max(1, int(PlatformConfig.load().export_pdf_max_rows or 200))],
            landscape=True,
        )

    paginator = Paginator(candidates, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")

    return render(
        request,
        "dashboard/excellence_dashboard.html",
        {
            "page_obj": page_obj,
            "badge_types": badge_types,
            "selected_badge": badge_code,
            "status_val": status_val,
            "status_choices": status_choices,
            "q": q,
            "active_awards_count": active_awards_count,
            "expiring_soon_count": expiring_soon_count,
            "current_cycle_end": current_end,
        },
    )


@staff_member_required
@require_dashboard_access("excellence")
def excellence_candidate_detail(request: HttpRequest, candidate_id: int) -> HttpResponse:
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
    active_award = None
    for award in awards:
        if award.is_active:
            active_award = award
            break
    return render(
        request,
        "dashboard/excellence_candidate_detail.html",
        {
            "candidate": candidate,
            "awards": awards,
            "active_award": active_award,
            "can_write": True,
        },
    )


@staff_member_required
@require_dashboard_access("excellence", write=True)
@require_POST
def excellence_candidate_approve_action(request: HttpRequest, candidate_id: int) -> HttpResponse:
    candidate = get_object_or_404(
        ExcellenceBadgeCandidate.objects.select_related("badge_type", "provider", "provider__user", "category", "subcategory"),
        id=candidate_id,
    )
    note = (request.POST.get("note") or "").strip()
    valid_until = _parse_datetime_local(request.POST.get("valid_until"))
    try:
        approve_candidate(candidate=candidate, approved_by=request.user, valid_until=valid_until, note=note)
        messages.success(request, "تم اعتماد الشارة بنجاح.")
    except Exception:
        messages.error(request, "تعذر اعتماد الشارة.")
    next_url = (request.POST.get("next") or "").strip()
    if next_url:
        return redirect(next_url)
    return redirect("dashboard:excellence_candidate_detail", candidate_id=candidate.id)


@staff_member_required
@require_dashboard_access("excellence", write=True)
@require_POST
def excellence_award_revoke_action(request: HttpRequest, award_id: int) -> HttpResponse:
    award = get_object_or_404(ExcellenceBadgeAward.objects.select_related("candidate"), id=award_id)
    note = (request.POST.get("note") or "").strip()
    try:
        revoke_award(award=award, revoked_by=request.user, note=note)
        messages.success(request, "تم سحب الشارة بنجاح.")
    except Exception:
        messages.error(request, "تعذر سحب الشارة.")
    next_url = (request.POST.get("next") or "").strip()
    if next_url:
        return redirect(next_url)
    if award.candidate_id:
        return redirect("dashboard:excellence_candidate_detail", candidate_id=award.candidate_id)
    return redirect("dashboard:excellence_dashboard")
