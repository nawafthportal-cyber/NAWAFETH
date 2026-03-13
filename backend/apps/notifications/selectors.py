from __future__ import annotations

from collections import defaultdict
from typing import Iterable
import re

from apps.marketplace.models import ServiceRequest
from apps.messaging.models import Thread

from .models import Notification


_REQUEST_URL_RE = re.compile(r"/requests/(?P<id>\d+)(?:/|$)")
_THREAD_URL_RE = re.compile(r"/threads?/(?P<id>\d+)(?:/|$)")

_CLIENT_ONLY_KINDS = {
    "offer_created",
    "review_reply",
}
_PROVIDER_ONLY_KINDS = {
    "urgent_request",
    "offer_selected",
}
_SHARED_ALWAYS_KINDS = {
    "report_status_change",
    "info",
    "urgent",
}


def normalize_notification_mode(mode: str | None) -> str:
    normalized = (mode or "").strip().lower()
    return normalized if normalized in {"client", "provider"} else ""


def filter_notification_ids_by_mode(*, qs, user, mode: str):
    normalized = normalize_notification_mode(mode)
    if not normalized:
        return None

    matched_ids = set(qs.filter(audience_mode=normalized).values_list("id", flat=True))
    matched_ids.update(
        _matching_shared_notification_ids(
            rows=_shared_notification_rows(qs),
            user=user,
            mode=normalized,
        )
    )
    return list(matched_ids)


def count_notifications_by_mode(*, qs, user, mode: str) -> int:
    normalized = normalize_notification_mode(mode)
    if not normalized:
        return qs.count()

    direct_count = qs.filter(audience_mode=normalized).count()
    shared_count = len(
        _matching_shared_notification_ids(
            rows=_shared_notification_rows(qs),
            user=user,
            mode=normalized,
        )
    )
    return direct_count + shared_count


def _shared_notification_rows(qs) -> list[Notification]:
    return list(
        qs.exclude(
            audience_mode__in=[
                Notification.AudienceMode.CLIENT,
                Notification.AudienceMode.PROVIDER,
            ]
        ).only("id", "kind", "url", "audience_mode")
    )


def _matching_shared_notification_ids(*, rows: Iterable[Notification], user, mode: str) -> set[int]:
    matched_ids: set[int] = set()
    request_to_notifications: dict[int, list[int]] = defaultdict(list)
    thread_to_notifications: dict[int, list[int]] = defaultdict(list)

    for notif in rows:
        kind = (notif.kind or "").strip().lower()
        if kind in _CLIENT_ONLY_KINDS:
            if mode == "client":
                matched_ids.add(notif.id)
            continue
        if kind in _PROVIDER_ONLY_KINDS:
            if mode == "provider":
                matched_ids.add(notif.id)
            continue
        if kind in _SHARED_ALWAYS_KINDS:
            matched_ids.add(notif.id)
            continue

        url = (notif.url or "").strip()
        if not url:
            matched_ids.add(notif.id)
            continue

        request_match = _REQUEST_URL_RE.search(url)
        if request_match:
            request_to_notifications[int(request_match.group("id"))].append(notif.id)
            continue

        thread_match = _THREAD_URL_RE.search(url)
        if thread_match:
            thread_to_notifications[int(thread_match.group("id"))].append(notif.id)
            continue

        matched_ids.add(notif.id)

    _match_request_bound_notifications(
        matched_ids=matched_ids,
        request_to_notifications=request_to_notifications,
        user=user,
        mode=mode,
    )
    _match_thread_bound_notifications(
        matched_ids=matched_ids,
        thread_to_notifications=thread_to_notifications,
        user=user,
        mode=mode,
    )
    return matched_ids


def _match_request_bound_notifications(*, matched_ids: set[int], request_to_notifications: dict[int, list[int]], user, mode: str) -> None:
    if not request_to_notifications:
        return

    requests_by_id = {
        request.id: request
        for request in ServiceRequest.objects.select_related("provider__user").filter(
            id__in=request_to_notifications.keys()
        )
    }
    for request_id, notification_ids in request_to_notifications.items():
        service_request = requests_by_id.get(request_id)
        if service_request is None:
            matched_ids.update(notification_ids)
            continue
        if mode == "client" and service_request.client_id == user.id:
            matched_ids.update(notification_ids)
            continue
        if mode == "provider" and bool(
            service_request.provider_id and service_request.provider.user_id == user.id
        ):
            matched_ids.update(notification_ids)


def _match_thread_bound_notifications(*, matched_ids: set[int], thread_to_notifications: dict[int, list[int]], user, mode: str) -> None:
    if not thread_to_notifications:
        return

    threads_by_id = {
        thread.id: thread
        for thread in Thread.objects.select_related(
            "request",
            "request__provider__user",
        ).filter(id__in=thread_to_notifications.keys())
    }
    for thread_id, notification_ids in thread_to_notifications.items():
        thread = threads_by_id.get(thread_id)
        if thread is None:
            matched_ids.update(notification_ids)
            continue
        if thread.is_direct:
            # Respect thread context_mode for role isolation
            ctx = (thread.context_mode or "").strip().lower()
            if ctx in ("client", "provider"):
                if ctx == mode and user.id in {thread.participant_1_id, thread.participant_2_id}:
                    matched_ids.update(notification_ids)
            elif user.id in {thread.participant_1_id, thread.participant_2_id}:
                matched_ids.update(notification_ids)
            continue
        service_request = thread.request
        if service_request is None:
            matched_ids.update(notification_ids)
            continue
        if mode == "client" and service_request.client_id == user.id:
            matched_ids.update(notification_ids)
            continue
        if mode == "provider" and bool(
            service_request.provider_id and service_request.provider.user_id == user.id
        ):
            matched_ids.update(notification_ids)
