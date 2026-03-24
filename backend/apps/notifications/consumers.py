import logging

from channels.generic.websocket import AsyncJsonWebsocketConsumer


logger = logging.getLogger(__name__)


class NotificationConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        user = self.scope.get("user")
        if not user or user.is_anonymous:
            await self.close(code=4401)
            return

        self.user = user
        self.group_name = f"notifications_user_{user.id}"

        try:
            await self.channel_layer.group_add(self.group_name, self.channel_name)
        except Exception:
            logger.warning(
                "notification websocket: channel_layer.group_add failed for user %s — closing",
                user.id,
            )
            await self.close(code=4503)
            return

        await self.accept()
        await self.send_json({"type": "connected"})

    async def disconnect(self, close_code):
        group_name = getattr(self, "group_name", None)
        if not group_name:
            return
        try:
            channel_layer = self.channel_layer
            if channel_layer is not None:
                await channel_layer.group_discard(group_name, self.channel_name)
        except Exception:
            # group_discard failures are non-critical (Redis may be temporarily unavailable).
            logger.debug(
                "notification websocket: group_discard failed for group %s (code=%s)",
                group_name,
                close_code,
            )

    async def receive_json(self, content, **kwargs):
        if (content or {}).get("type") == "ping":
            await self.send_json({"type": "pong"})

    async def notification_created(self, event):
        await self.send_json(
            {
                "type": "notification.created",
                "notification": event.get("notification") or {},
            }
        )
