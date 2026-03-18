from __future__ import annotations

from django.conf import settings


def moderation_center_enabled() -> bool:
    return bool(getattr(settings, "FEATURE_MODERATION_CENTER", False))


def moderation_dual_write_enabled() -> bool:
    return bool(getattr(settings, "FEATURE_MODERATION_DUAL_WRITE", False))


def rbac_enforce_enabled() -> bool:
    return bool(getattr(settings, "FEATURE_RBAC_ENFORCE", False))


def rbac_audit_only_enabled() -> bool:
    return bool(getattr(settings, "RBAC_AUDIT_ONLY", True))


def analytics_events_enabled() -> bool:
    return bool(getattr(settings, "FEATURE_ANALYTICS_EVENTS", False))


def analytics_kpi_surfaces_enabled() -> bool:
    return bool(getattr(settings, "FEATURE_ANALYTICS_KPI_SURFACES", False))
