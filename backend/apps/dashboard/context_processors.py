from __future__ import annotations

from django.urls import reverse

from .access import dashboard_allowed


MAIN_DASHBOARD_NAV = (
    ("admin_control", "إدارة الصلاحيات", "dashboard:admin_control_home"),
    ("support", "لوحة الدعم والمساعدة", "dashboard:support_dashboard"),
    ("content", "لوحة إدارة المحتوى", "dashboard:content_dashboard_home"),
    ("promo", "لوحة إدارة الترويج", "dashboard:promo_dashboard"),
    ("analytics", "التحليلات", "dashboard:analytics_insights"),
)


def _is_menu_active(request_path: str, target_url: str) -> bool:
    if request_path == target_url:
        return True
    normalized = target_url if target_url.endswith("/") else f"{target_url}/"
    return request_path.startswith(normalized)


def dashboard_nav_access(request):
    user = getattr(request, "user", None)
    if not user or not getattr(user, "is_authenticated", False):
        return {"dashboard_nav_access": {}, "dashboard_main_nav_items": []}

    access = {
        "admin_control": dashboard_allowed(user, "admin_control"),
        "support": dashboard_allowed(user, "support"),
        "content": dashboard_allowed(user, "content"),
        "promo": dashboard_allowed(user, "promo"),
        "analytics": dashboard_allowed(user, "analytics"),
    }

    main_nav_items = []
    request_path = getattr(request, "path", "") or ""
    for code, label, route_name in MAIN_DASHBOARD_NAV:
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

    return {
        "dashboard_nav_access": access,
        "dashboard_main_nav_items": main_nav_items,
    }
