from urllib.parse import parse_qs

from django.contrib.auth.models import AnonymousUser
from django.db import DatabaseError, OperationalError, close_old_connections

from channels.db import database_sync_to_async
from channels.middleware import BaseMiddleware

from rest_framework_simplejwt.tokens import AccessToken
from rest_framework_simplejwt.exceptions import TokenError

from apps.accounts.models import User
from apps.core.db_outage import mark_database_outage


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
    except (OperationalError, DatabaseError) as exc:
        # DB outage: mark globally and reject this handshake safely.
        mark_database_outage(reason="ws.jwt_auth", exc=exc)
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
