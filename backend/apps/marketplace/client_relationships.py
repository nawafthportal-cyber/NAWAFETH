from __future__ import annotations

from django.db.models import Q

from apps.providers.models import ProviderProfile

from .models import ServiceRequest


def provider_service_requests_queryset(
    provider: ProviderProfile,
    *,
    start_at=None,
    end_at=None,
):
    queryset = ServiceRequest.objects.filter(provider=provider)
    if start_at is not None:
        queryset = queryset.filter(created_at__gte=start_at)
    if end_at is not None:
        queryset = queryset.filter(created_at__lte=end_at)
    return queryset


def provider_service_request_client_ids(
    provider: ProviderProfile | None,
    *,
    user_ids=None,
    start_at=None,
    end_at=None,
) -> set[int]:
    if provider is None:
        return set()
    queryset = provider_service_requests_queryset(
        provider,
        start_at=start_at,
        end_at=end_at,
    )
    if user_ids is not None:
        user_ids = [int(user_id) for user_id in user_ids if user_id]
        if not user_ids:
            return set()
        queryset = queryset.filter(client_id__in=user_ids)
    return set(
        queryset.exclude(client_id=None)
        .values_list("client_id", flat=True)
        .distinct()
    )


def provider_service_request_user_filter(
    provider: ProviderProfile,
    *,
    relation_prefix: str = "requests",
    start_at=None,
    end_at=None,
) -> Q:
    prefix = f"{relation_prefix}__" if relation_prefix else ""
    query = Q(**{f"{prefix}provider": provider})
    if start_at is not None:
        query &= Q(**{f"{prefix}created_at__gte": start_at})
    if end_at is not None:
        query &= Q(**{f"{prefix}created_at__lte": end_at})
    return query