from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP

from django.core.cache import cache
from django.db.models import Avg, Count

from apps.unified_requests.models import UnifiedRequestStatus, UnifiedRequestType
from apps.unified_requests.services import upsert_unified_request

from .models import Review, ReviewModerationStatus


def _decimal_rating(value) -> Decimal:
    return Decimal(str(value or "0")).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def calculate_provider_rating(provider_id: int) -> dict[str, Decimal | int]:
    if not provider_id:
        return {"rating_avg": Decimal("0.00"), "rating_count": 0}

    aggregate = Review.objects.filter(
        provider_id=provider_id,
        moderation_status=ReviewModerationStatus.APPROVED,
    ).aggregate(
        rating_avg=Avg("rating"),
        rating_count=Count("id"),
    )
    return {
        "rating_avg": _decimal_rating(aggregate.get("rating_avg")),
        "rating_count": int(aggregate.get("rating_count") or 0),
    }


def invalidate_provider_rating_cache(provider_id: int) -> None:
    if not provider_id:
        return
    cache.delete_many(
        [
            f"provider:{provider_id}:public_stats:client",
            f"provider:{provider_id}:public_stats:provider",
            f"provider:{provider_id}:public_stats:shared",
        ]
    )


def refresh_provider_rating(provider_id: int) -> dict[str, Decimal | int]:
    values = calculate_provider_rating(provider_id)
    if provider_id:
        from apps.providers.models import ProviderProfile

        ProviderProfile.objects.filter(id=provider_id).update(**values)
        invalidate_provider_rating_cache(provider_id)
    return values


def provider_rating_values(provider) -> dict[str, Decimal | int]:
    provider_id = getattr(provider, "id", None)
    if not provider_id:
        return {"rating_avg": Decimal("0.00"), "rating_count": 0}

    cached_values = getattr(provider, "_rating_values_cache", None)
    if cached_values is not None:
        return cached_values

    annotated_count = getattr(provider, "computed_rating_count", None)
    annotated_avg = getattr(provider, "computed_rating_avg", None)
    if annotated_count is not None:
        values = {
            "rating_avg": _decimal_rating(annotated_avg),
            "rating_count": int(annotated_count or 0),
        }
        provider._rating_values_cache = values
        return values

    cached_count = int(getattr(provider, "rating_count", 0) or 0)
    cached_avg = _decimal_rating(getattr(provider, "rating_avg", 0))
    if cached_count > 0 or cached_avg > 0:
        values = {"rating_avg": cached_avg, "rating_count": cached_count}
        provider._rating_values_cache = values
        return values

    values = calculate_provider_rating(provider_id)
    provider._rating_values_cache = values
    return values


def _review_status_to_unified(moderation_status: str) -> str:
    if moderation_status in {ReviewModerationStatus.REJECTED, ReviewModerationStatus.HIDDEN}:
        return UnifiedRequestStatus.CLOSED
    return UnifiedRequestStatus.NEW


def sync_review_to_unified(*, review: Review, changed_by=None, force_status: str | None = None):
    status = force_status or _review_status_to_unified(review.moderation_status)
    summary = (review.comment or "").strip()
    if not summary:
        summary = f"مراجعة للطلب #{review.request_id}"

    return upsert_unified_request(
        request_type=UnifiedRequestType.REVIEWS,
        requester=review.client,
        source_app="reviews",
        source_model="Review",
        source_object_id=review.id,
        status=status,
        priority="normal",
        summary=summary[:300],
        metadata={
            "review_id": review.id,
            "request_id": review.request_id,
            "provider_id": review.provider_id,
            "moderation_status": review.moderation_status,
            "rating": review.rating,
        },
        assigned_team_code="content",
        assigned_team_name="المحتوى والمراجعات",
        assigned_user=None,
        changed_by=changed_by,
    )
