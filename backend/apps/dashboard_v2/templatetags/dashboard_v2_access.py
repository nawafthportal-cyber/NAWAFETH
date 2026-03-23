from __future__ import annotations

from django import template

from apps.dashboard.access import can_access_object, has_action_permission, has_dashboard_access

register = template.Library()


@register.simple_tag
def has_dashboard(user, dashboard_code: str, write: bool = False) -> bool:
    return has_dashboard_access(user, dashboard_code, write=write)


@register.simple_tag
def has_permission(user, permission_code: str) -> bool:
    return has_action_permission(user, permission_code)


@register.simple_tag
def object_access(
    user,
    obj,
    assigned_field: str = "assigned_to",
    owner_field: str = "",
    allow_unassigned_for_user_level: bool = True,
) -> bool:
    return can_access_object(
        user,
        obj,
        assigned_field=assigned_field,
        owner_field=(owner_field or None),
        allow_unassigned_for_user_level=allow_unassigned_for_user_level,
    )

