from __future__ import annotations

from django import template

from apps.dashboard.access import dashboard_allowed

register = template.Library()


@register.simple_tag
def can_access(user, dashboard_code: str, write: bool = False) -> bool:
    return dashboard_allowed(user, dashboard_code, write=write)
