import os

# Ensure Django settings are configured before importing anything that touches
# django.conf.settings (e.g., authentication models).
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

import django
from django.core.asgi import get_asgi_application

from channels.routing import ProtocolTypeRouter, URLRouter
from channels.auth import AuthMiddlewareStack

django.setup()

http_app = get_asgi_application()

# Import websocket components only after Django is initialized.
from apps.messaging.jwt_auth import JwtAuthMiddleware  # noqa: E402
import apps.messaging.routing  # noqa: E402
import apps.notifications.routing  # noqa: E402

websocket_urlpatterns = (
    list(apps.messaging.routing.websocket_urlpatterns)
    + list(apps.notifications.routing.websocket_urlpatterns)
)

application = ProtocolTypeRouter(
	{
		"http": http_app,
		# Session/Auth middleware should run first, then JWT middleware can
		# override scope["user"] when a token query param is provided.
		"websocket": AuthMiddlewareStack(
			JwtAuthMiddleware(
				URLRouter(websocket_urlpatterns)
			)
		),
	}
)
