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

        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()
        await self.send_json({"type": "connected"})

    async def disconnect(self, close_code):
        try:
            await self.channel_layer.group_discard(self.group_name, self.channel_name)
        except Exception:
            logger.exception("notification websocket disconnect error")

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
