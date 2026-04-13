import asyncio
import logging
import time

from channels.generic.websocket import AsyncJsonWebsocketConsumer


logger = logging.getLogger(__name__)

# Per-user connection tracking (process-local; sufficient for single-node or
# when each node independently enforces limits).
_user_connections: dict[int, set[str]] = {}


def _ws_setting(name: str, default: int) -> int:
    from django.conf import settings
    return int(getattr(settings, name, default))


class NotificationConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        user = self.scope.get("user")
        if not user or user.is_anonymous:
            await self.close(code=4401)
            return

        self.user = user
        self.group_name = f"notifications_user_{user.id}"
        self._last_pong: float = time.monotonic()
        self._heartbeat_task: asyncio.Task | None = None

        # ── Enforce per-user connection cap ───────────────────────────
        uid = user.id
        conns = _user_connections.setdefault(uid, set())
        if len(conns) >= _ws_setting("WS_MAX_CONNECTIONS_PER_USER", 5):
            logger.warning(
                "notification websocket: user %s exceeded %d connections — rejecting",
                uid,
                _ws_setting("WS_MAX_CONNECTIONS_PER_USER", 5),
            )
            await self.close(code=4429)
            return
        conns.add(self.channel_name)

        try:
            await self.channel_layer.group_add(self.group_name, self.channel_name)
        except Exception:
            logger.warning(
                "notification websocket: channel_layer.group_add failed for user %s — closing",
                user.id,
            )
            conns.discard(self.channel_name)
            await self.close(code=4503)
            return

        await self.accept()
        await self.send_json({"type": "connected"})

        # Start server-side heartbeat loop.
        self._heartbeat_task = asyncio.ensure_future(self._heartbeat_loop())

    async def disconnect(self, close_code):
        # Cancel heartbeat.
        if self._heartbeat_task and not self._heartbeat_task.done():
            self._heartbeat_task.cancel()

        # Remove from per-user tracking.
        uid = getattr(getattr(self, "user", None), "id", None)
        if uid and uid in _user_connections:
            _user_connections[uid].discard(self.channel_name)
            if not _user_connections[uid]:
                del _user_connections[uid]

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
        msg_type = (content or {}).get("type")
        if msg_type == "ping":
            self._last_pong = time.monotonic()
            await self.send_json({"type": "pong"})
        elif msg_type == "pong":
            self._last_pong = time.monotonic()

    async def notification_created(self, event):
        await self.send_json(
            {
                "type": "notification.created",
                "notification": event.get("notification") or {},
            }
        )

    # ── Server-side heartbeat ────────────────────────────────────────
    async def _heartbeat_loop(self):
        """Periodically ping the client; close if no pong arrives in time."""
        try:
            while True:
                await asyncio.sleep(_ws_setting("WS_HEARTBEAT_INTERVAL_SECONDS", 45))
                # Send a server-initiated ping.
                try:
                    await self.send_json({"type": "ping"})
                except Exception:
                    break
                # Check staleness.
                if time.monotonic() - self._last_pong > _ws_setting("WS_HEARTBEAT_TIMEOUT_SECONDS", 90):
                    logger.info(
                        "notification websocket: heartbeat timeout for user %s — closing",
                        getattr(self.user, "id", "?"),
                    )
                    await self.close(code=4408)
                    break
        except asyncio.CancelledError:
            pass
