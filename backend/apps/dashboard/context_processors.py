from __future__ import annotations

import logging
from urllib.parse import parse_qs, urlparse

from django.db import DatabaseError, OperationalError, close_old_connections
from django.urls import reverse

from .access import dashboard_allowed


logger = logging.getLogger(__name__)


MAIN_DASHBOARD_NAV = (
    # (access_code, label, route_name, superuser_only, submenu_key)
    ("admin_control", "إدارة الصلاحيات", "dashboard:admin_control_home", False, "admin_control"),
    ("admin_control", "المالية والفواتير", "dashboard:finance_dashboard", True, None),
    ("support", "لوحة الدعم والمساعدة", "dashboard:support_dashboard", False, None),
    ("content", "لوحة إدارة المحتوى", "dashboard:content_dashboard_home", False, "content"),
    ("promo", "لوحة إدارة الترويج", "dashboard:promo_dashboard", False, "promo"),
    ("verify", "لوحة فريق التوثيق", "dashboard:verification_dashboard", False, "verify"),
    ("subs", "لوحة فريق إدارة الاشتراكات", "dashboard:subscription_dashboard", False, "subs"),
    ("extras", "لوحة فريق إدارة الخدمات الإضافية", "dashboard:extras_dashboard", False, "extras"),
)


def _is_menu_active(request_path: str, target_url: str) -> bool:
    if request_path == target_url:
        return True
    normalized = target_url if target_url.endswith("/") else f"{target_url}/"
    return request_path.startswith(normalized)


def _is_child_active(request, item_url: str) -> bool:
    """Match a submenu child against the current request (path + query subset)."""
    parsed = urlparse(item_url)
    if request.path != parsed.path:
        return False
    if not parsed.query:
        # No distinguishing query → active only when the request also carries
        # no section/tab params (avoids highlighting a "default" item when the
        # user is actually viewing a sibling section).
        return not (request.GET.get("section") or request.GET.get("tab"))
    item_params = parse_qs(parsed.query)
    for key, values in item_params.items():
        if request.GET.get(key) not in values:
            return False
    return True


def _build_submenu_children(submenu_key: str, request):
    """Return submenu children for a parent navigation item.

    Imports view-side builders lazily to avoid circular imports.
    """
    if not submenu_key:
        return []

    raw_items: list[dict] = []
    try:
        if submenu_key == "admin_control":
            base = reverse("dashboard:admin_control_home")
            raw_items = [
                {"label": "إدارة الصلاحيات", "url": f"{base}?section=access"},
                {"label": "إحصاءات وتقارير المنصة", "url": f"{base}?section=reports"},
            ]
        elif submenu_key == "content":
            from .views import _content_nav_items  # local import to avoid cycle

            raw_items = [
                {"label": item["label"], "url": item["url"]}
                for item in _content_nav_items("")
                if item.get("key") != "home"
            ]
        elif submenu_key == "promo":
            from .views import _promo_nav_items

            raw_items = [
                {"label": item["label"], "url": item["url"]}
                for item in _promo_nav_items("")
            ]
        elif submenu_key == "verify":
            from .views import _verification_nav_items

            raw_items = [
                {"label": item["label"], "url": item["url"]}
                for item in _verification_nav_items("")
            ]
        elif submenu_key == "subs":
            from .views import _subscription_nav_items

            raw_items = [
                {"label": item["label"], "url": item["url"]}
                for item in _subscription_nav_items("")
            ]
        elif submenu_key == "extras":
            from .views import _extras_nav_items

            raw_items = [
                {"label": item["label"], "url": item["url"]}
                for item in _extras_nav_items("")
            ]
    except Exception:  # pragma: no cover - submenu must never break a page
        logger.exception(
            "Failed to build dashboard submenu",
            extra={"submenu_key": submenu_key, "log_category": "ui"},
        )
        return []

    children = []
    for item in raw_items:
        url = item.get("url") or ""
        children.append(
            {
                "label": item.get("label", ""),
                "url": url,
                "active": _is_child_active(request, url),
            }
        )
    return children


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
        # Submenus that don't already include the parent's landing page
        # (i.e. the bare URL with no query string) get a synthetic
        # "نظرة عامة" entry prepended so the dashboard remains reachable
        # after the parent row turned into a pure submenu toggle.
        OVERVIEW_LABEL = "نظرة عامة"
        for code, label, route_name, superuser_only, submenu_key in MAIN_DASHBOARD_NAV:
            if superuser_only and not is_superuser:
                continue
            if not access.get(code):
                continue
            url = reverse(route_name)
            children = _build_submenu_children(submenu_key, request) if submenu_key else []
            if children:
                already_has_overview = any(
                    urlparse(child["url"]).path == url and not urlparse(child["url"]).query
                    for child in children
                )
                if not already_has_overview:
                    children.insert(
                        0,
                        {
                            "label": OVERVIEW_LABEL,
                            "url": url,
                            "active": _is_child_active(request, url),
                        },
                    )
            parent_active = _is_menu_active(request_path, url)
            child_active = any(child["active"] for child in children)
            main_nav_items.append(
                {
                    "key": code,
                    "label": label,
                    "url": url,
                    "active": parent_active,
                    "children": children,
                    "has_children": bool(children),
                    # Auto-expand when this branch is current so users see the
                    # active section without an extra click.
                    "is_open": bool(children) and (parent_active or child_active),
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
