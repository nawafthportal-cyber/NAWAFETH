from __future__ import annotations

from datetime import timedelta
from decimal import Decimal
import logging

from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from apps.messaging.models import Message, Thread
from apps.notifications.services import create_notification
from apps.providers.models import ProviderProfile

from .models import (
    ExcellenceBadgeAward,
    ExcellenceBadgeCandidate,
    ExcellenceBadgeCandidateStatus,
    ExcellenceBadgeType,
)
from .selectors import (
    FEATURED_SERVICE_BADGE_CODE,
    HIGH_ACHIEVEMENT_BADGE_CODE,
    TOP_100_CLUB_BADGE_CODE,
    build_excellence_badges_payload,
    build_public_badges_payload,
    current_review_window,
    get_featured_service_candidates,
    get_high_achievement_candidates,
    get_top_100_club_candidates,
)


logger = logging.getLogger(__name__)
EXCELLENCE_CACHE_SYNC_SKIP_ATTR = "_skip_excellence_cache_sync"


DEFAULT_EXCELLENCE_BADGES = [
    {
        "code": FEATURED_SERVICE_BADGE_CODE,
        "name_ar": "الخدمة المتميزة",
        "icon": "sparkles",
        "color": "#C0841A",
        "description": "تُمنح للمختصين الأعلى تقييمًا ضمن دورة المراجعة الحالية.",
        "review_cycle_days": 90,
        "sort_order": 10,
    },
    {
        "code": HIGH_ACHIEVEMENT_BADGE_CODE,
        "name_ar": "الإنجاز العالي",
        "icon": "bolt",
        "color": "#0F766E",
        "description": "تُمنح للمختصين الأعلى إنجازًا في الطلبات المكتملة خلال آخر سنة.",
        "review_cycle_days": 90,
        "sort_order": 20,
    },
    {
        "code": TOP_100_CLUB_BADGE_CODE,
        "name_ar": "نادي المئة الكبار",
        "icon": "trophy",
        "color": "#7C3AED",
        "description": "تُمنح لأعلى 100 مختص في المتابعات والتأثير العام على المنصة.",
        "review_cycle_days": 90,
        "sort_order": 30,
    },
]


def _decimal_or_zero(value) -> Decimal:
    try:
        return Decimal(str(value or 0)).quantize(Decimal("0.01"))
    except Exception:
        return Decimal("0.00")


def sync_badge_type_catalog() -> list[ExcellenceBadgeType]:
    badge_types: list[ExcellenceBadgeType] = []
    for item in DEFAULT_EXCELLENCE_BADGES:
        badge_type, _ = ExcellenceBadgeType.objects.get_or_create(
            code=item["code"],
            defaults=item,
        )
        updates = []
        for field in ("name_ar", "icon", "color", "description", "review_cycle_days", "sort_order"):
            wanted = item[field]
            if getattr(badge_type, field) != wanted:
                setattr(badge_type, field, wanted)
                updates.append(field)
        if not badge_type.is_active:
            badge_type.is_active = True
            updates.append("is_active")
        if updates:
            badge_type.save(update_fields=updates)
        badge_types.append(badge_type)
    return badge_types


def _candidate_defaults_from_row(row: dict[str, object]) -> dict[str, object]:
    return {
        "category_id": row.get("category_id"),
        "subcategory_id": row.get("subcategory_id"),
        "metric_value": _decimal_or_zero(row.get("metric_value")),
        "rank_position": max(1, int(row.get("rank_position") or 1)),
        "followers_count": max(0, int(row.get("followers_count") or 0)),
        "completed_orders_count": max(0, int(row.get("completed_orders_count") or 0)),
        "rating_avg": _decimal_or_zero(row.get("rating_avg")),
        "rating_count": max(0, int(row.get("rating_count") or 0)),
    }


def refresh_excellence_candidates(now=None) -> dict[str, object]:
    sync_badge_type_catalog()
    period_start, period_end = current_review_window(now)
    badge_type_map = {
        item.code: item
        for item in ExcellenceBadgeType.objects.filter(
            code__in=[
                FEATURED_SERVICE_BADGE_CODE,
                HIGH_ACHIEVEMENT_BADGE_CODE,
                TOP_100_CLUB_BADGE_CODE,
            ]
        )
    }
    batches = [
        (FEATURED_SERVICE_BADGE_CODE, get_featured_service_candidates(now)),
        (HIGH_ACHIEVEMENT_BADGE_CODE, get_high_achievement_candidates(now)),
        (TOP_100_CLUB_BADGE_CODE, get_top_100_club_candidates(now)),
    ]
    seen_keys: set[tuple[int, str]] = set()
    created = 0
    updated = 0
    expired = 0

    with transaction.atomic():
        for badge_code, rows in batches:
            badge_type = badge_type_map.get(badge_code)
            if badge_type is None:
                continue
            for row in rows:
                provider_id = int(row.get("provider_id") or 0)
                if provider_id <= 0:
                    continue
                seen_keys.add((provider_id, badge_code))
                candidate, was_created = ExcellenceBadgeCandidate.objects.get_or_create(
                    badge_type=badge_type,
                    provider_id=provider_id,
                    evaluation_period_start=period_start,
                    evaluation_period_end=period_end,
                    defaults=_candidate_defaults_from_row(row),
                )
                defaults = _candidate_defaults_from_row(row)
                dirty_fields = []
                for field_name, wanted_value in defaults.items():
                    if getattr(candidate, field_name) != wanted_value:
                        setattr(candidate, field_name, wanted_value)
                        dirty_fields.append(field_name)
                if candidate.status in {
                    ExcellenceBadgeCandidateStatus.PENDING,
                    ExcellenceBadgeCandidateStatus.EXPIRED,
                } and candidate.status != ExcellenceBadgeCandidateStatus.PENDING:
                    candidate.status = ExcellenceBadgeCandidateStatus.PENDING
                    dirty_fields.append("status")
                if was_created:
                    created += 1
                    if dirty_fields:
                        candidate.save(update_fields=dirty_fields)
                elif dirty_fields:
                    dirty_fields.append("updated_at")
                    candidate.save(update_fields=dirty_fields)
                    updated += 1

        current_cycle_candidates = ExcellenceBadgeCandidate.objects.select_related("badge_type").filter(
            evaluation_period_start=period_start,
            evaluation_period_end=period_end,
        )
        for candidate in current_cycle_candidates:
            key = (candidate.provider_id, candidate.badge_type.code)
            if key in seen_keys:
                continue
            if candidate.status != ExcellenceBadgeCandidateStatus.PENDING:
                continue
            candidate.status = ExcellenceBadgeCandidateStatus.EXPIRED
            candidate.save(update_fields=["status", "updated_at"])
            expired += 1

    return {
        "created": created,
        "updated": updated,
        "expired": expired,
        "period_start": period_start.isoformat(),
        "period_end": period_end.isoformat(),
    }


def _normalize_provider_ids(*, provider=None, provider_id=None, provider_ids=None) -> list[int]:
    raw_ids = []
    if provider is not None:
        raw_ids.append(getattr(provider, "id", provider))
    if provider_id is not None:
        raw_ids.append(provider_id)
    if provider_ids is not None:
        raw_ids.extend(provider_ids)

    normalized: list[int] = []
    seen: set[int] = set()
    for raw_id in raw_ids:
        try:
            value = int(raw_id or 0)
        except (TypeError, ValueError):
            continue
        if value <= 0 or value in seen:
            continue
        seen.add(value)
        normalized.append(value)
    return normalized


def _mark_manual_cache_sync(instance) -> None:
    setattr(instance, EXCELLENCE_CACHE_SYNC_SKIP_ATTR, True)


def sync_provider_excellence_cache(*, provider=None, provider_id=None, provider_ids=None, now=None, include_stats: bool = False):
    normalized_ids = _normalize_provider_ids(provider=provider, provider_id=provider_id, provider_ids=provider_ids)
    if not normalized_ids:
        return {"processed": 0, "updated": 0, "payloads": {}} if include_stats else []

    payload_map = build_excellence_badges_payload(provider_ids=normalized_ids, now=now)
    profiles = list(
        ProviderProfile.objects.filter(id__in=normalized_ids).only("id", "excellence_badges_cache")
    )
    changed = []
    for profile in profiles:
        desired_payload = payload_map.get(profile.id, [])
        if profile.excellence_badges_cache != desired_payload:
            profile.excellence_badges_cache = desired_payload
            changed.append(profile)
    if changed:
        ProviderProfile.objects.bulk_update(changed, ["excellence_badges_cache"])

    if include_stats:
        return {
            "processed": len(profiles),
            "updated": len(changed),
            "payloads": payload_map,
        }
    if len(normalized_ids) == 1:
        return payload_map.get(normalized_ids[0], [])
    return payload_map


def schedule_provider_excellence_cache_sync(*, provider=None, provider_id=None, provider_ids=None, now=None) -> int:
    normalized_ids = _normalize_provider_ids(provider=provider, provider_id=provider_id, provider_ids=provider_ids)
    if not normalized_ids:
        return 0

    try:
        sync_provider_excellence_cache(provider_ids=normalized_ids, now=now)
    except Exception:
        logger.exception(
            "Failed to sync excellence badges cache for providers %s",
            normalized_ids,
        )
        raise
    return len(normalized_ids)


def sync_provider_excellence_badges(*, provider_ids=None, now=None) -> int:
    if provider_ids is None:
        provider_ids = list(ProviderProfile.objects.order_by("id").values_list("id", flat=True))
    result = sync_provider_excellence_cache(provider_ids=provider_ids, now=now, include_stats=True)
    return int(result["updated"])


def rebuild_excellence_badges_cache(*, provider_id=None, provider_ids=None, limit: int | None = None, batch_size: int = 500, now=None) -> dict[str, int]:
    normalized_ids = _normalize_provider_ids(provider_id=provider_id, provider_ids=provider_ids)
    queryset = ProviderProfile.objects.order_by("id")
    if normalized_ids:
        queryset = queryset.filter(id__in=normalized_ids)
    target_ids = list(queryset.values_list("id", flat=True))
    if limit is not None:
        target_ids = target_ids[: max(0, int(limit or 0))]

    processed = 0
    updated = 0
    errors = 0
    batch_size = max(1, int(batch_size or 500))

    for index in range(0, len(target_ids), batch_size):
        batch_ids = target_ids[index : index + batch_size]
        if not batch_ids:
            continue
        try:
            stats = sync_provider_excellence_cache(
                provider_ids=batch_ids,
                now=now,
                include_stats=True,
            )
            processed += int(stats["processed"])
            updated += int(stats["updated"])
        except Exception:
            errors += len(batch_ids)
            logger.exception(
                "Failed to rebuild excellence badges cache for provider batch %s",
                batch_ids,
            )

    return {
        "processed": processed,
        "updated": updated,
        "errors": errors,
    }


def _get_or_create_direct_thread(user_a, user_b):
    if not user_a or not user_b or user_a.id == user_b.id:
        return None
    thread = (
        Thread.objects.filter(is_direct=True)
        .filter(
            Q(participant_1=user_a, participant_2=user_b)
            | Q(participant_1=user_b, participant_2=user_a)
        )
        .order_by("-id")
        .first()
    )
    if thread:
        return thread
    return Thread.objects.create(
        is_direct=True,
        context_mode=Thread.ContextMode.SHARED,
        participant_1=user_a,
        participant_2=user_b,
    )


def send_award_celebration(award: ExcellenceBadgeAward, *, actor=None):
    badge_name = award.badge_type.name_ar
    provider_user = award.provider.user
    create_notification(
        user=provider_user,
        title="شارة تميز جديدة",
        body=f"مبارك، حصلت على شارة {badge_name}.",
        kind="excellence_badge_awarded",
        url=f"/provider/{award.provider_id}/",
        actor=actor,
        meta={
            "badge_code": award.badge_type.code,
            "badge_name": badge_name,
            "provider_id": award.provider_id,
        },
        pref_key="excellence_badge_awarded",
        audience_mode="provider",
    )
    if actor is None or getattr(actor, "id", None) == provider_user.id:
        return
    thread = _get_or_create_direct_thread(actor, provider_user)
    if thread is None:
        return
    Message.objects.create(
        thread=thread,
        sender=actor,
        body=f"مبارك، تم منحك شارة {badge_name} ضمن نظام التميز في نوافذ.",
        created_at=timezone.now(),
    )


def approve_candidate(
    *,
    candidate: ExcellenceBadgeCandidate,
    approved_by,
    valid_until=None,
    note: str = "",
) -> ExcellenceBadgeAward:
    now = timezone.now()
    review_days = max(1, int(candidate.badge_type.review_cycle_days or 90))
    valid_until = valid_until or (now + timedelta(days=review_days))

    with transaction.atomic():
        award = (
            ExcellenceBadgeAward.objects.select_for_update()
            .filter(provider=candidate.provider, badge_type=candidate.badge_type, is_active=True)
            .order_by("-awarded_at", "-id")
            .first()
        )
        should_notify = award is None or award.candidate_id != candidate.id
        snapshot_defaults = {
            "candidate": candidate,
            "category_name": getattr(candidate.category, "name", "") if candidate.category_id else "",
            "subcategory_name": getattr(candidate.subcategory, "name", "") if candidate.subcategory_id else "",
            "metric_value": candidate.metric_value,
            "rank_position": candidate.rank_position,
            "followers_count": candidate.followers_count,
            "completed_orders_count": candidate.completed_orders_count,
            "rating_avg": candidate.rating_avg,
            "rating_count": candidate.rating_count,
            "awarded_at": now,
            "valid_until": valid_until,
            "approved_by": approved_by,
            "approval_note": note,
            "is_active": True,
            "revoked_at": None,
            "revoked_by": None,
            "revoke_note": "",
        }
        if award is None:
            award = ExcellenceBadgeAward(
                badge_type=candidate.badge_type,
                provider=candidate.provider,
                **snapshot_defaults,
            )
            _mark_manual_cache_sync(award)
            award.save()
        else:
            dirty_fields = []
            for field_name, wanted_value in snapshot_defaults.items():
                if getattr(award, field_name) != wanted_value:
                    setattr(award, field_name, wanted_value)
                    dirty_fields.append(field_name)
            if dirty_fields:
                dirty_fields.append("updated_at")
                _mark_manual_cache_sync(award)
                award.save(update_fields=dirty_fields)

        candidate.status = ExcellenceBadgeCandidateStatus.APPROVED
        candidate.reviewed_by = approved_by
        candidate.reviewed_at = now
        candidate.review_note = note
        candidate.save(update_fields=["status", "reviewed_by", "reviewed_at", "review_note", "updated_at"])

    schedule_provider_excellence_cache_sync(provider_id=candidate.provider_id, now=now)
    if should_notify:
        send_award_celebration(award, actor=approved_by)
    return award


def revoke_award(*, award: ExcellenceBadgeAward, revoked_by, note: str = "") -> ExcellenceBadgeAward:
    now = timezone.now()
    dirty_fields = []
    if award.is_active:
        award.is_active = False
        dirty_fields.append("is_active")
    if award.revoked_at != now:
        award.revoked_at = now
        dirty_fields.append("revoked_at")
    if award.revoked_by_id != getattr(revoked_by, "id", None):
        award.revoked_by = revoked_by
        dirty_fields.append("revoked_by")
    if award.revoke_note != note:
        award.revoke_note = note
        dirty_fields.append("revoke_note")
    if award.valid_until > now:
        award.valid_until = now
        dirty_fields.append("valid_until")
    if dirty_fields:
        dirty_fields.append("updated_at")
        _mark_manual_cache_sync(award)
        award.save(update_fields=dirty_fields)

    if award.candidate_id:
        candidate = award.candidate
        candidate.status = ExcellenceBadgeCandidateStatus.REVOKED
        candidate.reviewed_by = revoked_by
        candidate.reviewed_at = now
        candidate.review_note = note
        candidate.save(update_fields=["status", "reviewed_by", "reviewed_at", "review_note", "updated_at"])

    schedule_provider_excellence_cache_sync(provider_id=award.provider_id, now=now)
    return award


def expire_excellence_awards(*, now=None, limit: int = 500) -> int:
    now = now or timezone.now()
    awards = list(
        ExcellenceBadgeAward.objects.select_related("candidate")
        .filter(is_active=True, valid_until__lte=now)
        .order_by("id")[: max(1, int(limit or 500))]
    )
    if not awards:
        return 0

    provider_ids = []
    for award in awards:
        award.is_active = False
        award.revoked_at = award.revoked_at or now
        _mark_manual_cache_sync(award)
        award.save(update_fields=["is_active", "revoked_at", "updated_at"])
        provider_ids.append(award.provider_id)
        if award.candidate_id and award.candidate.status == ExcellenceBadgeCandidateStatus.APPROVED:
            award.candidate.status = ExcellenceBadgeCandidateStatus.EXPIRED
            award.candidate.reviewed_at = now
            award.candidate.save(update_fields=["status", "reviewed_at", "updated_at"])

    schedule_provider_excellence_cache_sync(provider_ids=provider_ids, now=now)
    return len(awards)
