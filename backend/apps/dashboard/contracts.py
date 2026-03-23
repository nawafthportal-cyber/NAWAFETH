from __future__ import annotations

from typing import Final

from apps.unified_requests.models import UnifiedRequestStatus


class DashboardCode:
    SUPPORT = "support"
    CONTENT = "content"
    MODERATION = "moderation"
    REVIEWS = "reviews"
    PROMO = "promo"
    VERIFY = "verify"
    SUBS = "subs"
    EXTRAS = "extras"
    ANALYTICS = "analytics"
    ADMIN_CONTROL = "admin_control"
    CLIENT_EXTRAS = "client_extras"

    # Backward-compatible aliases.
    ADMIN = "admin"
    ACCESS = "access"


OFFICIAL_DASHBOARD_CODES: Final[tuple[str, ...]] = (
    DashboardCode.SUPPORT,
    DashboardCode.CONTENT,
    DashboardCode.MODERATION,
    DashboardCode.REVIEWS,
    DashboardCode.PROMO,
    DashboardCode.VERIFY,
    DashboardCode.SUBS,
    DashboardCode.EXTRAS,
    DashboardCode.ANALYTICS,
    DashboardCode.ADMIN_CONTROL,
    DashboardCode.CLIENT_EXTRAS,
)


DASHBOARD_CODE_ALIASES: Final[dict[str, str]] = {
    DashboardCode.ADMIN: DashboardCode.ADMIN_CONTROL,
    DashboardCode.ACCESS: DashboardCode.ADMIN_CONTROL,
}


TEAM_CODE_TO_NAME_AR: Final[dict[str, str]] = {
    DashboardCode.SUPPORT: "الدعم والمساعدة",
    DashboardCode.CONTENT: "إدارة المحتوى",
    DashboardCode.MODERATION: "الإشراف",
    DashboardCode.REVIEWS: "المراجعات",
    DashboardCode.PROMO: "الترويج",
    DashboardCode.VERIFY: "التوثيق",
    DashboardCode.SUBS: "الاشتراكات",
    DashboardCode.EXTRAS: "الخدمات الإضافية",
    DashboardCode.ANALYTICS: "التحليلات",
    DashboardCode.ADMIN_CONTROL: "الإدارة",
    DashboardCode.CLIENT_EXTRAS: "بوابة العميل",
}


CANONICAL_OPERATIONAL_STATUSES: Final[tuple[str, ...]] = (
    UnifiedRequestStatus.NEW,
    UnifiedRequestStatus.IN_PROGRESS,
    UnifiedRequestStatus.RETURNED,
    UnifiedRequestStatus.CLOSED,
)


LEGACY_TO_CANONICAL_STATUS: Final[dict[str, str]] = {
    UnifiedRequestStatus.COMPLETED: UnifiedRequestStatus.CLOSED,
    UnifiedRequestStatus.REJECTED: UnifiedRequestStatus.CLOSED,
    UnifiedRequestStatus.EXPIRED: UnifiedRequestStatus.CLOSED,
    UnifiedRequestStatus.CANCELLED: UnifiedRequestStatus.CLOSED,
    UnifiedRequestStatus.PENDING_PAYMENT: UnifiedRequestStatus.NEW,
    UnifiedRequestStatus.ACTIVE: UnifiedRequestStatus.IN_PROGRESS,
}


def canonical_dashboard_code(code: str) -> str:
    normalized = (code or "").strip().lower()
    return DASHBOARD_CODE_ALIASES.get(normalized, normalized)


def canonical_operational_status(status: str) -> str:
    normalized = (status or "").strip().lower()
    return LEGACY_TO_CANONICAL_STATUS.get(normalized, normalized)


def is_open_operational_status(status: str) -> bool:
    return canonical_operational_status(status) in {
        UnifiedRequestStatus.NEW,
        UnifiedRequestStatus.IN_PROGRESS,
        UnifiedRequestStatus.RETURNED,
    }
