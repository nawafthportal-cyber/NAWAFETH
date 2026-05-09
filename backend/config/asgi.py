import os
# Ensure Django settings are configured before importing anything that touches
# django.conf.settings (e.g., authentication models).
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

import django
from django.core.asgi import get_asgi_application
from django.db import DatabaseError, OperationalError

from channels.routing import ProtocolTypeRouter, URLRouter
from channels.auth import AuthMiddlewareStack

django.setup()

http_app = get_asgi_application()

# Import websocket components only after Django is initialized.
from apps.core.db_outage import is_database_outage_active, mark_database_outage  # noqa: E402
from apps.messaging.jwt_auth import JwtAuthMiddleware, get_token_from_scope  # noqa: E402
import apps.messaging.routing  # noqa: E402
import apps.notifications.routing  # noqa: E402

websocket_urlpatterns = [
    *apps.notifications.routing.websocket_urlpatterns,
    *apps.messaging.routing.websocket_urlpatterns,
]


class TokenAwareWebSocketAuthMiddleware:
    """Use JWT-only auth when a token query param is present.

    This avoids session-backed auth DB lookups on tokenized websocket handshakes
    while preserving session fallback for legacy/no-token clients.
    """

    def __init__(self, app):
        self._jwt_only_stack = JwtAuthMiddleware(app)
        self._session_stack = AuthMiddlewareStack(JwtAuthMiddleware(app))

    @staticmethod
    def _has_token(scope) -> bool:
        try:
            return bool(get_token_from_scope(scope))
        except Exception:
            return False

    async def __call__(self, scope, receive, send):
        if scope.get("type") != "websocket":
            return await self._jwt_only_stack(scope, receive, send)

        if self._has_token(scope) or is_database_outage_active():
            return await self._jwt_only_stack(scope, receive, send)

        try:
            return await self._session_stack(scope, receive, send)
        except (OperationalError, DatabaseError) as exc:
            # Session-backed auth can fail during DB outages; degrade to JWT-only path.
            mark_database_outage(reason="ws.session_auth", exc=exc)
            return await self._jwt_only_stack(scope, receive, send)


application = ProtocolTypeRouter(
	{
		"http": http_app,
		"websocket": TokenAwareWebSocketAuthMiddleware(URLRouter(websocket_urlpatterns)),
	}
)
