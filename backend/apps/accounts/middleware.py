"""Middleware to maintain ``User.last_seen`` for the presence indicator."""
from __future__ import annotations

from .presence import mark_seen


class LastSeenMiddleware:
    """Update the authenticated user's ``last_seen`` once per request.

    Writes are throttled inside :func:`apps.accounts.presence.mark_seen` so the
    middleware is safe to install globally.  The work runs *after* the response
    is generated so it never adds latency to the request itself.

    The Django ``AuthenticationMiddleware`` only resolves session-based users.
    Mobile-web and Flutter clients authenticate via JWT (``Authorization:
    Bearer …``), so when ``request.user`` is anonymous we make a best-effort
    attempt to resolve the bearer token via ``simplejwt`` and mark that user as
    seen instead.  Failures are swallowed – presence is best-effort.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        try:
            user = getattr(request, "user", None)
            if not user or not getattr(user, "is_authenticated", False):
                user = self._resolve_jwt_user(request)
            mark_seen(user)
        except Exception:
            # Presence is best-effort – never break the request cycle.
            pass
        return response

    @staticmethod
    def _resolve_jwt_user(request):
        auth_header = request.META.get("HTTP_AUTHORIZATION", "") or ""
        if not auth_header.lower().startswith("bearer "):
            return None
        try:
            from rest_framework_simplejwt.authentication import JWTAuthentication

            authenticator = JWTAuthentication()
            raw_token = auth_header.split(None, 1)[1].strip()
            if not raw_token:
                return None
            validated = authenticator.get_validated_token(raw_token)
            return authenticator.get_user(validated)
        except Exception:
            return None

