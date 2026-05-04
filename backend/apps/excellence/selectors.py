from __future__ import annotations

from collections import defaultdict
from datetime import timedelta
from decimal import Decimal
from itertools import groupby

from django.db.models import Count, Q
from django.utils import timezone

from apps.marketplace.models import RequestStatus
from apps.providers.models import ProviderCategory, ProviderProfile

from .models import ExcellenceBadgeAward, ExcellenceBadgeCandidate


FEATURED_SERVICE_BADGE_CODE = "featured_service"
HIGH_ACHIEVEMENT_BADGE_CODE = "high_achievement"
TOP_100_CLUB_BADGE_CODE = "top_100_club"


def current_review_window(now=None):
    from apps.core.models import PlatformConfig

    now = now or timezone.now()
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    if month_start.month == 12:
        period_end = month_start.replace(year=month_start.year + 1, month=1)
    else:
        period_end = month_start.replace(month=month_start.month + 1)
    period_start = period_end - timedelta(
        days=int(PlatformConfig.load().excellence_review_cycle_days or 365)
    )
    return period_start, period_end


def _category_map_for_providers(provider_ids: list[int]) -> dict[int, dict[str, object]]:
    rows = (
        ProviderCategory.objects.filter(provider_id__in=provider_ids)
        .select_related("subcategory", "subcategory__category")
        .order_by("provider_id", "subcategory__category__name", "subcategory__name", "id")
    )
    mapping: dict[int, dict[str, object]] = {}
    for row in rows:
        if row.provider_id in mapping:
            continue
        category = getattr(row.subcategory, "category", None)
        mapping[row.provider_id] = {
            "category_id": getattr(category, "id", None),
            "category_name": getattr(category, "name", ""),
            "subcategory_id": getattr(row.subcategory, "id", None),
            "subcategory_name": getattr(row.subcategory, "name", ""),
        }
    return mapping


def build_provider_metric_snapshots(now=None) -> list[dict[str, object]]:
    now = now or timezone.now()
    rolling_start = now - timedelta(days=365)
    completed_filter = Q(
        assigned_requests__status=RequestStatus.COMPLETED,
    ) & (
        Q(
            assigned_requests__delivered_at__isnull=False,
            assigned_requests__delivered_at__gte=rolling_start,
            assigned_requests__delivered_at__lt=now,
        )
        | Q(
            assigned_requests__delivered_at__isnull=True,
            assigned_requests__created_at__gte=rolling_start,
            assigned_requests__created_at__lt=now,
        )
    )
    providers = list(
        ProviderProfile.objects.select_related("user")
        .filter(user__is_active=True)
        .annotate(
            followers_count=Count("followers__user", distinct=True),
            completed_orders_count=Count(
                "assigned_requests",
                filter=completed_filter,
                distinct=True,
            ),
        )
    )
    if not providers:
        return []

    category_map = _category_map_for_providers([provider.id for provider in providers])
    snapshots: list[dict[str, object]] = []
    for provider in providers:
        category_info = category_map.get(provider.id, {})
        rating_count = int(getattr(provider, "rating_count", 0) or 0)
        rating_avg = getattr(provider, "rating_avg", Decimal("0.00")) or Decimal("0.00")
        snapshots.append(
            {
                "provider_id": provider.id,
                "provider": provider,
                "category_id": category_info.get("category_id"),
                "category_name": category_info.get("category_name", ""),
                "subcategory_id": category_info.get("subcategory_id"),
                "subcategory_name": category_info.get("subcategory_name", ""),
                "followers_count": int(getattr(provider, "followers_count", 0) or 0),
                "completed_orders_count": int(getattr(provider, "completed_orders_count", 0) or 0),
                "rating_avg": rating_avg,
                "rating_count": max(rating_count, int(getattr(provider, "rating_count", 0) or 0)),
            }
        )
    return snapshots


def _decorate_ranked_rows(
    rows,
    *,
    badge_code: str,
    metric_key: str,
    group_key: str | None = None,
    limit: int | None = None,
    per_group_limit: int | None = None,
):
    if not rows:
        return []
    grouped: dict[object, list[dict[str, object]]] = defaultdict(list)
    if group_key:
        for row in rows:
            grouped[row.get(group_key) or 0].append(row)
    else:
        grouped["all"] = list(rows)

    ranked: list[dict[str, object]] = []
    for _, bucket in grouped.items():
        bucket.sort(
            key=lambda item: (
                -float(item.get(metric_key) or 0),
                -int(item.get("completed_orders_count") or 0),
                -int(item.get("followers_count") or 0),
                -float(item.get("rating_avg") or 0),
                int(item.get("provider_id") or 0),
            )
        )
        if per_group_limit is not None:
            bucket = bucket[: max(1, int(per_group_limit))]
        for rank, item in enumerate(bucket, start=1):
            enriched = dict(item)
            enriched["badge_code"] = badge_code
            enriched["metric_value"] = item.get(metric_key) or 0
            enriched["rank_position"] = rank
            ranked.append(enriched)

    ranked.sort(
        key=lambda item: (
            item.get("category_name") or "",
            int(item.get("rank_position") or 0),
            int(item.get("provider_id") or 0),
        )
    )
    if limit is not None:
        return ranked[:limit]
    return ranked


def get_featured_service_candidates(now=None) -> list[dict[str, object]]:
    base = [
        row
        for row in build_provider_metric_snapshots(now)
        if row.get("category_id")
        and int(row.get("rating_count") or 0) > 0
        and Decimal(str(row.get("rating_avg") or 0)) > Decimal("0.00")
    ]
    return _decorate_ranked_rows(
        base,
        badge_code=FEATURED_SERVICE_BADGE_CODE,
        metric_key="rating_avg",
        group_key="category_id",
        per_group_limit=1,
    )


def get_high_achievement_candidates(now=None) -> list[dict[str, object]]:
    base = [
        row
        for row in build_provider_metric_snapshots(now)
        if row.get("category_id")
        and int(row.get("completed_orders_count") or 0) > 100
    ]
    return _decorate_ranked_rows(
        base,
        badge_code=HIGH_ACHIEVEMENT_BADGE_CODE,
        metric_key="completed_orders_count",
        group_key="category_id",
        per_group_limit=1,
    )


def get_top_100_club_candidates(now=None) -> list[dict[str, object]]:
    base = [
        row
        for row in build_provider_metric_snapshots(now)
        if row.get("category_id")
        and int(row.get("followers_count") or 0) > 100
    ]
    return _decorate_ranked_rows(
        base,
        badge_code=TOP_100_CLUB_BADGE_CODE,
        metric_key="followers_count",
        group_key="category_id",
        per_group_limit=1,
    )


def current_cycle_candidates_queryset(now=None):
    period_start, period_end = current_review_window(now)
    return (
        ExcellenceBadgeCandidate.objects.select_related(
            "badge_type",
            "provider",
            "provider__user",
            "category",
            "subcategory",
            "reviewed_by",
        )
        .filter(
            evaluation_period_start=period_start,
            evaluation_period_end=period_end,
        )
        .order_by("badge_type__sort_order", "rank_position", "provider_id")
    )


def active_awards_queryset(provider_ids=None, now=None):
    now = now or timezone.now()
    queryset = ExcellenceBadgeAward.objects.select_related("badge_type", "provider", "provider__user").filter(
        is_active=True,
        revoked_at__isnull=True,
        valid_until__gt=now,
        badge_type__is_active=True,
    )
    if provider_ids is not None:
        queryset = queryset.filter(provider_id__in=provider_ids)
    return queryset.order_by("provider_id", "badge_type__sort_order", "badge_type__code", "-awarded_at", "id")


def serialize_active_excellence_badges(awards) -> list[dict[str, object]]:
    payload: list[dict[str, object]] = []
    seen_codes: set[str] = set()
    for award in awards:
        badge_type = getattr(award, "badge_type", None)
        badge_code = getattr(badge_type, "code", "") or ""
        if not badge_code or badge_code in seen_codes:
            continue
        seen_codes.add(badge_code)
        payload.append(
            {
                "code": badge_code,
                "name": badge_type.name_ar,
                "name_ar": badge_type.name_ar,
                "name_en": getattr(badge_type, "name_en", "") or "",
                "description": getattr(badge_type, "description", "") or "",
                "description_ar": getattr(badge_type, "description", "") or "",
                "description_en": getattr(badge_type, "description_en", "") or "",
                "icon": badge_type.icon,
                "color": badge_type.color,
                "awarded_at": award.awarded_at.isoformat() if award.awarded_at else "",
                "valid_until": award.valid_until.isoformat() if award.valid_until else "",
            }
        )
    return payload


def build_excellence_badges_payload(provider_ids=None, now=None) -> dict[int, list[dict[str, object]]]:
    payload: dict[int, list[dict[str, object]]] = defaultdict(list)
    awards = active_awards_queryset(provider_ids=provider_ids, now=now)
    for provider_id, provider_awards in groupby(awards, key=lambda award: award.provider_id):
        payload[provider_id] = serialize_active_excellence_badges(provider_awards)
    return dict(payload)


def build_public_badges_payload(provider_ids=None, now=None) -> dict[int, list[dict[str, object]]]:
    return build_excellence_badges_payload(provider_ids=provider_ids, now=now)
