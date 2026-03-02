"""
Shared utility for extracting the active account role (client / provider)
from an incoming DRF request.

The mobile app sends the mode via:
  1. query-param  ?mode=client|provider
  2. JSON body    {"mode": "client"|"provider"}
  3. HTTP header  X-Account-Mode: client|provider

All social / messaging / notification views MUST use ``get_active_role()``
so that actions are bound to the correct role context.
"""
from __future__ import annotations

VALID_ROLES = {"client", "provider"}


def get_active_role(request, *, fallback: str = "client") -> str:
    """Return the active role from the request.

    Priority:  query-param  →  body  →  header  →  fallback.
    """
    raw = (
        getattr(request, "query_params", {}).get("mode")
        or (request.data.get("mode") if hasattr(request, "data") else None)
        or request.META.get("HTTP_X_ACCOUNT_MODE")
        or ""
    )
    role = raw.strip().lower()
    return role if role in VALID_ROLES else fallback
