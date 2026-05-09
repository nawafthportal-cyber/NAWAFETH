from django.db import DatabaseError, OperationalError

from apps.accounts.models import UserRole
from apps.accounts.permissions import has_completed_client_registration

from .db_outage import mark_database_outage


def safe_server_auth(request):
    """Expose auth hints to templates without letting session DB failures break pages."""

    payload = {
        "is_authenticated": False,
        "user_id": None,
        "role_state": "guest",
        "profile_status": "visitor",
    }
    try:
        user = getattr(request, "user", None)
        if user is not None and getattr(user, "is_authenticated", False):
            role_state = getattr(user, "role_state", "") or "guest"
            profile_status = "unknown"
            if role_state == UserRole.PROVIDER:
                profile_status = "provider"
            elif role_state == UserRole.STAFF:
                profile_status = "staff"
            elif role_state == UserRole.VISITOR:
                profile_status = "visitor"
            elif role_state == UserRole.PHONE_ONLY:
                profile_status = "phone_only"
            elif role_state == UserRole.CLIENT:
                profile_status = "complete" if has_completed_client_registration(user) else "phone_only"
            payload.update(
                {
                    "is_authenticated": True,
                    "user_id": getattr(user, "id", None),
                    "role_state": role_state,
                    "profile_status": profile_status,
                }
            )
    except (OperationalError, DatabaseError) as exc:
        mark_database_outage(reason="template.server_auth", exc=exc)
    except Exception:
        pass
    return {"safe_server_auth": payload}
