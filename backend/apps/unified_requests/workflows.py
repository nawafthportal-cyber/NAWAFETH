from __future__ import annotations

from .models import UnifiedRequestStatus, UnifiedRequestType


CANONICAL_OPERATIONAL_STATUSES: tuple[str, ...] = (
    UnifiedRequestStatus.NEW,
    UnifiedRequestStatus.IN_PROGRESS,
    UnifiedRequestStatus.RETURNED,
    UnifiedRequestStatus.CLOSED,
)

# Backward-compatible export name used by dashboard views/tests.
THREE_STAGE_ALLOWED_STATUSES: tuple[str, ...] = CANONICAL_OPERATIONAL_STATUSES
HELPDESK_ALLOWED_STATUSES: tuple[str, ...] = CANONICAL_OPERATIONAL_STATUSES


OPERATIONAL_TRANSITIONS: dict[str, set[str]] = {
    UnifiedRequestStatus.NEW: {
        UnifiedRequestStatus.IN_PROGRESS,
        UnifiedRequestStatus.RETURNED,
    },
    UnifiedRequestStatus.IN_PROGRESS: {
        UnifiedRequestStatus.RETURNED,
        UnifiedRequestStatus.CLOSED,
    },
    UnifiedRequestStatus.RETURNED: {
        UnifiedRequestStatus.IN_PROGRESS,
        UnifiedRequestStatus.CLOSED,
    },
    UnifiedRequestStatus.CLOSED: set(),
}


_CANONICALIZED_REQUEST_TYPES: frozenset[str] = frozenset(
    {
        UnifiedRequestType.HELPDESK,
        UnifiedRequestType.PROMO,
        UnifiedRequestType.SUBSCRIPTION,
        UnifiedRequestType.EXTRAS,
        UnifiedRequestType.REVIEWS,
    }
)


_LEGACY_TO_CANONICAL_STATUS: dict[str, str] = {
    UnifiedRequestStatus.COMPLETED: UnifiedRequestStatus.CLOSED,
    UnifiedRequestStatus.REJECTED: UnifiedRequestStatus.CLOSED,
    UnifiedRequestStatus.EXPIRED: UnifiedRequestStatus.CLOSED,
    UnifiedRequestStatus.CANCELLED: UnifiedRequestStatus.CLOSED,
    UnifiedRequestStatus.PENDING_PAYMENT: UnifiedRequestStatus.NEW,
    UnifiedRequestStatus.ACTIVE: UnifiedRequestStatus.IN_PROGRESS,
}


def canonical_status_for_workflow(*, request_type: str, status: str) -> str:
    normalized = str(status or "").strip().lower()
    if request_type not in _CANONICALIZED_REQUEST_TYPES:
        return normalized
    return _LEGACY_TO_CANONICAL_STATUS.get(normalized, normalized)


def allowed_statuses_for_request_type(request_type: str) -> tuple[str, ...]:
    if request_type in _CANONICALIZED_REQUEST_TYPES:
        return HELPDESK_ALLOWED_STATUSES
    return tuple(v for v, _ in UnifiedRequestStatus.choices)


def is_valid_transition(*, request_type: str, from_status: str, to_status: str) -> bool:
    from_status = canonical_status_for_workflow(request_type=request_type, status=from_status)
    to_status = canonical_status_for_workflow(request_type=request_type, status=to_status)
    if from_status == to_status:
        return True
    if request_type in _CANONICALIZED_REQUEST_TYPES:
        return to_status in OPERATIONAL_TRANSITIONS.get(from_status, set())
    return True
