from __future__ import annotations

import logging

from django.db import DatabaseError, OperationalError, close_old_connections
from django.urls import reverse

from .access import dashboard_allowed


logger = logging.getLogger(__name__)


MAIN_DASHBOARD_NAV = (
    # (access_code, label, route_name, superuser_only)
    ("admin_control", "إدارة الصلاحيات", "dashboard:admin_control_home", False),
    ("admin_control", "المالية والفواتير", "dashboard:finance_dashboard", True),
    ("support", "لوحة الدعم والمساعدة", "dashboard:support_dashboard", False),
    ("content", "لوحة إدارة المحتوى", "dashboard:content_dashboard_home", False),
    ("promo", "لوحة إدارة الترويج", "dashboard:promo_dashboard", False),
    ("verify", "لوحة فريق التوثيق", "dashboard:verification_dashboard", False),
    ("subs", "لوحة فريق إدارة الاشتراكات", "dashboard:subscription_dashboard", False),
    ("extras", "لوحة فريق إدارة الخدمات الإضافية", "dashboard:extras_dashboard", False),
)


def _is_menu_active(request_path: str, target_url: str) -> bool:
    if request_path == target_url:
        return True
    normalized = target_url if target_url.endswith("/") else f"{target_url}/"
    return request_path.startswith(normalized)


def dashboard_nav_access(request):
    request_path = getattr(request, "path", "") or ""
    if not request_path.startswith("/dashboard"):
        return {"dashboard_nav_access": {}, "dashboard_main_nav_items": []}

    try:
        user = getattr(request, "user", None)
        if not user or not getattr(user, "is_authenticated", False):
            return {"dashboard_nav_access": {}, "dashboard_main_nav_items": []}

        access = {
            "admin_control": dashboard_allowed(user, "admin_control"),
            "support": dashboard_allowed(user, "support"),
            "content": dashboard_allowed(user, "content"),
            "promo": dashboard_allowed(user, "promo"),
            "verify": dashboard_allowed(user, "verify"),
            "subs": dashboard_allowed(user, "subs"),
            "extras": dashboard_allowed(user, "extras"),
            "analytics": dashboard_allowed(user, "analytics"),
        }

        main_nav_items = []
        is_superuser = getattr(user, "is_superuser", False)
        for code, label, route_name, superuser_only in MAIN_DASHBOARD_NAV:
            if superuser_only and not is_superuser:
                continue
            if not access.get(code):
                continue
            url = reverse(route_name)
            main_nav_items.append(
                {
                    "key": code,
                    "label": label,
                    "url": url,
                    "active": _is_menu_active(request_path, url),
                }
            )
    except (OperationalError, DatabaseError):
        close_old_connections()
        logger.warning(
            "Dashboard navigation unavailable; returning empty navigation.",
            extra={"request_path": request_path, "log_category": "database"},
        )
        return {"dashboard_nav_access": {}, "dashboard_main_nav_items": []}

    return {
        "dashboard_nav_access": access,
        "dashboard_main_nav_items": main_nav_items,
    }
