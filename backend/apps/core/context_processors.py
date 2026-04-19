from django.db import DatabaseError, OperationalError

from .db_outage import mark_database_outage


def safe_server_auth(request):
    """Expose auth hints to templates without letting session DB failures break pages."""

    payload = {
        "is_authenticated": False,
        "user_id": None,
        "role_state": "guest",
    }
    try:
        user = getattr(request, "user", None)
        if user is not None and getattr(user, "is_authenticated", False):
            payload.update(
                {
                    "is_authenticated": True,
                    "user_id": getattr(user, "id", None),
                    "role_state": getattr(user, "role_state", "") or "guest",
                }
            )
    except (OperationalError, DatabaseError) as exc:
        mark_database_outage(reason="template.server_auth", exc=exc)
    except Exception:
        pass
    return {"safe_server_auth": payload}
