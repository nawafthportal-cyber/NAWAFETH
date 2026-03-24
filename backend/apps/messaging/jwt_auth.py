from urllib.parse import parse_qs

from django.contrib.auth.models import AnonymousUser
from django.db import close_old_connections, OperationalError

from channels.db import database_sync_to_async
from channels.middleware import BaseMiddleware

from rest_framework_simplejwt.tokens import AccessToken
from rest_framework_simplejwt.exceptions import TokenError

from apps.accounts.models import User

import logging

logger = logging.getLogger(__name__)


@database_sync_to_async
def get_user_for_token(token_str: str):
    # Step 1: validate JWT signature + expiry — purely cryptographic, no DB hit.
    try:
        access = AccessToken(token_str)
        user_id = access.get("user_id")
        if not user_id:
            return AnonymousUser()
    except TokenError:
        # Expired, tampered, or malformed token — reject cleanly.
        return AnonymousUser()
    except Exception:
        return AnonymousUser()

    # Step 2: verify the user still exists and is active in the database.
    try:
        return User.objects.filter(id=user_id, is_active=True).first() or AnonymousUser()
    except OperationalError:
        # Database is temporarily unreachable. Log clearly so the outage is visible.
        # We deliberately return AnonymousUser — the WS handshake will be rejected (4401).
        # The client (Flutter) has exponential-backoff reconnect, so it will retry
        # automatically once the DB recovers. Creating a synthetic User object here
        # is unsafe: it bypasses is_active checks and produces an incomplete model
        # instance that crashes any code accessing uninitialised fields (groups,
        # permissions, username, etc.).
        logger.warning(
            "jwt_auth: DB unavailable while authenticating WS token for user_id=%s "
            "— rejecting connection (client will retry via backoff).",
            user_id,
        )
        return AnonymousUser()
    except Exception:
        return AnonymousUser()


class JwtAuthMiddleware(BaseMiddleware):
    async def __call__(self, scope, receive, send):
        close_old_connections()

        query = parse_qs(scope.get("query_string", b"").decode())
        token = (query.get("token") or [None])[0]

        # If a token is provided, prefer JWT auth.
        # Otherwise, keep any existing user set by upstream middleware (e.g. AuthMiddlewareStack).
        if token:
            scope["user"] = await get_user_for_token(token)
        else:
            scope.setdefault("user", AnonymousUser())

        return await super().__call__(scope, receive, send)
