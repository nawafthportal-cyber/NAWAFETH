from __future__ import annotations

from .access import dashboard_allowed


def dashboard_nav_access(request):
    user = getattr(request, "user", None)
    if not user or not getattr(user, "is_authenticated", False):
        return {"dashboard_nav_access": {}}

    access = {
        "admin_control": dashboard_allowed(user, "admin_control"),
        "support": dashboard_allowed(user, "support"),
        "content": dashboard_allowed(user, "content"),
        "promo": dashboard_allowed(user, "promo"),
        "analytics": dashboard_allowed(user, "analytics"),
    }
    return {"dashboard_nav_access": access}
