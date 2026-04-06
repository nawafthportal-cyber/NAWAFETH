import json
import logging
from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.generic.websocket import AsyncJsonWebsocketConsumer
from django.core.exceptions import PermissionDenied
from django.utils import timezone
from django.utils.html import strip_tags

from apps.marketplace.models import ServiceRequest
from .models import Thread, Message, MessageRead, ThreadUserState
from .display import display_name_for_user


logger = logging.getLogger(__name__)

MAX_MESSAGE_LEN = 2000


@database_sync_to_async
def get_request_and_check_participant(request_id: int, user_id: int):
    sr = (
        ServiceRequest.objects.select_related("client", "provider__user")
        .filter(id=request_id)
        .first()
    )
    if not sr:
        return None, False

    is_client = sr.client_id == user_id
    is_provider = bool(sr.provider_id) and sr.provider.user_id == user_id

    return sr, (is_client or is_provider)


@database_sync_to_async
def get_or_create_thread(sr: ServiceRequest):
    return Thread.objects.get_or_create(request=sr)


@database_sync_to_async
def create_message(thread: Thread, sender_id: int, body: str):
    body = (body or "").strip()
    if not body:
        raise ValueError("empty_body")
    if len(body) > 2000:
        raise ValueError("too_long")

    # Blocked by peer?
    t = (
        Thread.objects.select_related(
            "request",
            "request__client",
            "request__provider__user",
            "participant_1",
            "participant_2",
        )
        .filter(id=thread.id)
        .first()
    )
    if t:
        participant_ids = []
        if t.is_direct:
            participant_ids = [pid for pid in [t.participant_1_id, t.participant_2_id] if pid]
        elif t.request_id and t.request:
            participant_ids = [t.request.client_id]
            if getattr(t.request, "provider_id", None) and getattr(t.request.provider, "user_id", None):
                participant_ids.append(t.request.provider.user_id)

        other_ids = [pid for pid in participant_ids if pid and pid != sender_id]
        if other_ids and ThreadUserState.objects.filter(thread_id=t.id, user_id__in=other_ids, is_blocked=True).exists():
            raise ValueError("blocked")
        if not t.can_user_send(sender_id):
            raise ValueError("reply_locked")

    msg = Message.objects.create(thread=thread, sender_id=sender_id, body=body)

    # Unarchive for participants when a new message arrives
    if t and participant_ids:
        ThreadUserState.objects.filter(thread_id=t.id, user_id__in=participant_ids, is_archived=True).update(
            is_archived=False,
            archived_at=None,
        )
    return msg


@database_sync_to_async
def mark_thread_read(thread: Thread, reader_id: int):
    # اقرأ كل الرسائل غير المقروءة (عدا رسائل القارئ)
    unread_ids = (
        Message.objects.filter(thread=thread)
        .exclude(sender_id=reader_id)
        .exclude(reads__user_id=reader_id)
        .values_list("id", flat=True)
    )
    now = timezone.now()
    rows = [MessageRead(message_id=mid, user_id=reader_id, read_at=now) for mid in unread_ids]
    if rows:
        MessageRead.objects.bulk_create(rows, ignore_conflicts=True)
    return list(unread_ids)


class RequestChatConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.request_id = int(self.scope["url_route"]["kwargs"]["request_id"])
        user = self.scope.get("user")

        if not user or user.is_anonymous:
            await self.close(code=4401)  # Unauthorized
            return

        sr, ok = await get_request_and_check_participant(self.request_id, user.id)
        if not sr or not ok:
            await self.close(code=4403)  # Forbidden
            return

        # لا محادثة بدون مزود معيّن
        if not sr.provider_id:
            await self.close(code=4400)  # Bad Request
            return

        self.sr = sr
        self.group_name = f"chat_request_{self.request_id}"

        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

        # إشعار “متصل”
        await self.send_json({"type": "connected", "request_id": self.request_id})

    async def disconnect(self, close_code):
        try:
            await self.channel_layer.group_discard(self.group_name, self.channel_name)
        except Exception:
            pass

    async def receive(self, text_data=None, bytes_data=None):
        try:
            payload = json.loads(text_data or "{}")
        except Exception:
            await self.send_json({"type": "error", "code": "bad_json"})
            return

        action = payload.get("action")
        user = self.scope["user"]

        # 1) إرسال رسالة
        if action == "send":
            body = payload.get("body", "")
            try:
                thread, _ = await get_or_create_thread(self.sr)
                msg = await create_message(thread, user.id, body)
            except ValueError as e:
                code = str(e)
                if code == "blocked":
                    await self.send_json({"type": "error", "code": "blocked", "error": "تم حظرك من الطرف الآخر"})
                elif code == "reply_locked":
                    await self.send_json({"type": "error", "code": "reply_locked", "error": "الردود مغلقة لهذه الرسائل الآلية."})
                else:
                    await self.send_json({"type": "error", "code": code})
                return
            except Exception:
                await self.send_json({"type": "error", "code": "server_error"})
                return

            event = {
                "type": "message",
                "id": msg.id,
                "sender_id": user.id,
                "body": msg.body,
                "created_at": msg.created_at.isoformat(),
            }
            await self.channel_layer.group_send(
                self.group_name, {"type": "broadcast", "event": event}
            )
            return

        # 2) typing
        if action == "typing":
            event = {
                "type": "typing",
                "user_id": user.id,
                "is_typing": bool(payload.get("is_typing", True)),
            }
            await self.channel_layer.group_send(
                self.group_name, {"type": "broadcast", "event": event}
            )
            return

        # 3) mark_read
        if action == "read":
            try:
                thread, _ = await get_or_create_thread(self.sr)
                marked_ids = await mark_thread_read(thread, user.id)
            except Exception:
                await self.send_json({"type": "error", "code": "server_error"})
                return

            event = {
                "type": "read",
                "user_id": user.id,
                "marked": len(marked_ids),
                "message_ids": marked_ids,
            }
            await self.channel_layer.group_send(
                self.group_name, {"type": "broadcast", "event": event}
            )
            return

        # 4) ping/pong
        if action == "ping":
            await self.send_json({"type": "pong"})
            return

        await self.send_json({"type": "error", "code": "unknown_action"})

    async def broadcast(self, event):
        await self.send_json(event["event"])

    async def send_json(self, data: dict):
        await self.send(text_data=json.dumps(data, ensure_ascii=False))


@database_sync_to_async
def _get_thread_with_request(thread_id: int):
    return (
        Thread.objects.select_related("request", "request__client", "request__provider__user")
        .filter(id=thread_id)
        .first()
    )


@database_sync_to_async
def _assert_thread_access(thread_id: int, user, active_mode: str = "") -> Thread:
    if not user or user.is_anonymous:
        raise PermissionDenied("anon")

    thread = (
        Thread.objects.select_related(
            "request",
            "request__client",
            "request__provider__user",
            "participant_1",
            "participant_2",
        )
        .filter(id=thread_id)
        .first()
    )
    if not thread:
        raise PermissionDenied("not_found")

    if getattr(user, "is_staff", False):
        return thread

    # If the other participant blocked this thread, forbid WS access
    participant_ids = []
    if thread.is_direct:
        participant_ids = [pid for pid in [thread.participant_1_id, thread.participant_2_id] if pid]
    elif thread.request_id and thread.request:
        participant_ids = [thread.request.client_id]
        if getattr(thread.request, "provider_id", None) and getattr(thread.request.provider, "user_id", None):
            participant_ids.append(thread.request.provider.user_id)

    other_ids = [pid for pid in participant_ids if pid and pid != user.id]
    if other_ids and ThreadUserState.objects.filter(thread_id=thread.id, user_id__in=other_ids, is_blocked=True).exists():
        raise PermissionDenied("blocked")

    # Direct thread: check participant_1 / participant_2
    if thread.is_direct:
        if user.id in (thread.participant_1_id, thread.participant_2_id) and thread.mode_matches_user(user, active_mode):
            return thread
        raise PermissionDenied("not_participant")

    # Request-based thread
    sr = thread.request
    if sr is None:
        raise PermissionDenied("not_participant")
    is_client = sr.client_id == user.id
    is_provider = bool(sr.provider_id) and sr.provider.user_id == user.id
    if active_mode == "client":
        is_provider = False
    elif active_mode == "provider":
        is_client = False
    if not (is_client or is_provider):
        raise PermissionDenied("not_participant")

    return thread


@database_sync_to_async
def _create_message_for_thread(thread_id: int, sender_id: int, body: str) -> Message:
    body = (body or "").strip()
    if not body:
        raise ValueError("empty_body")
    if len(body) > MAX_MESSAGE_LEN:
        raise ValueError("too_long")

    thread = Thread.objects.select_related(
        "request",
        "request__client",
        "request__provider__user",
        "participant_1",
        "participant_2",
    ).get(id=thread_id)

    participant_ids = []
    if thread.is_direct:
        participant_ids = [pid for pid in [thread.participant_1_id, thread.participant_2_id] if pid]
    elif thread.request_id and thread.request:
        participant_ids = [thread.request.client_id]
        if getattr(thread.request, "provider_id", None) and getattr(thread.request.provider, "user_id", None):
            participant_ids.append(thread.request.provider.user_id)

    other_ids = [pid for pid in participant_ids if pid and pid != sender_id]
    if other_ids and ThreadUserState.objects.filter(thread_id=thread.id, user_id__in=other_ids, is_blocked=True).exists():
        raise ValueError("blocked")
    if not thread.can_user_send(sender_id):
        raise ValueError("reply_locked")

    msg = Message.objects.create(thread=thread, sender_id=sender_id, body=body)

    if participant_ids:
        ThreadUserState.objects.filter(thread_id=thread.id, user_id__in=participant_ids, is_archived=True).update(
            is_archived=False,
            archived_at=None,
        )

    return msg


@database_sync_to_async
def _mark_thread_read_by_thread_id(thread_id: int, reader_id: int):
    thread = Thread.objects.get(id=thread_id)
    unread_ids = (
        Message.objects.filter(thread=thread)
        .exclude(sender_id=reader_id)
        .exclude(reads__user_id=reader_id)
        .values_list("id", flat=True)
    )
    now = timezone.now()
    rows = [MessageRead(message_id=mid, user_id=reader_id, read_at=now) for mid in unread_ids]
    if rows:
        MessageRead.objects.bulk_create(rows, ignore_conflicts=True)
    return list(unread_ids)


class ThreadConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        self.user = self.scope.get("user")
        self.thread_id = int(self.scope["url_route"]["kwargs"]["thread_id"])
        self.group_name = f"thread_{self.thread_id}"
        query_string = (self.scope.get("query_string") or b"").decode("utf-8", errors="ignore")
        query_params = parse_qs(query_string)
        self.active_mode = str((query_params.get("mode") or [""])[0] or "").strip().lower()

        try:
            await _assert_thread_access(self.thread_id, self.user, self.active_mode)
        except PermissionDenied as e:
            # Map common cases to codes
            if str(e) == "anon":
                await self.close(code=4401)
            elif str(e) == "blocked":
                await self.close(code=4403)
            else:
                await self.close(code=4403)
            return
        except Exception:
            logger.exception("WS connect error")
            await self.close(code=1011)
            return

        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

        # Optional: confirm connected
        await self.send_json({"type": "connected", "thread_id": self.thread_id})

    async def disconnect(self, close_code):
        try:
            await self.channel_layer.group_discard(self.group_name, self.channel_name)
        except Exception:
            logger.exception("WS disconnect error")

    async def receive_json(self, content, **kwargs):
        try:
            msg_type = content.get("type")

            if msg_type == "typing":
                await self._handle_typing(content)
                return

            if msg_type == "read":
                await self._handle_read(content)
                return

            if msg_type == "message":
                await self._handle_message(content)
                return

            await self.send_json({"type": "error", "error": "نوع غير مدعوم"})
        except PermissionDenied:
            await self.send_json({"type": "error", "error": "غير مصرح"})
        except Exception:
            logger.exception("WS receive_json error")
            await self.send_json({"type": "error", "error": "حدث خطأ غير متوقع"})

    async def _handle_typing(self, content):
        await _assert_thread_access(self.thread_id, self.user, self.active_mode)
        is_typing = bool(content.get("is_typing"))
        await self.channel_layer.group_send(
            self.group_name,
            {
                "type": "broadcast.typing",
                "user_id": self.user.id,
                "is_typing": is_typing,
            },
        )

    async def _handle_read(self, content):
        await _assert_thread_access(self.thread_id, self.user, self.active_mode)
        marked_ids = await _mark_thread_read_by_thread_id(self.thread_id, self.user.id)
        await self.channel_layer.group_send(
            self.group_name,
            {
                "type": "broadcast.read",
                "user_id": self.user.id,
                "read_at": timezone.now().isoformat(),
                "marked": len(marked_ids),
                "message_ids": marked_ids,
            },
        )

    async def _handle_message(self, content):
        await _assert_thread_access(self.thread_id, self.user, self.active_mode)

        text = (content.get("text") or "").strip()
        client_id = content.get("client_id")  # قد يكون None
        text = strip_tags(text)
        if not text:
            await self.send_json({"type": "error", "error": "الرسالة فارغة"})
            return
        if len(text) > MAX_MESSAGE_LEN:
            await self.send_json({"type": "error", "error": "الرسالة طويلة جدًا"})
            return

        try:
            msg = await _create_message_for_thread(self.thread_id, self.user.id, text)
        except ValueError as e:
            code = str(e)
            if code == "empty_body":
                await self.send_json({"type": "error", "error": "الرسالة فارغة"})
            elif code == "too_long":
                await self.send_json({"type": "error", "error": "الرسالة طويلة جدًا"})
            elif code == "blocked":
                await self.send_json({"type": "error", "code": "blocked", "error": "تم حظرك من الطرف الآخر"})
            elif code == "reply_locked":
                thread = await _assert_thread_access(self.thread_id, self.user, self.active_mode)
                label = (getattr(thread, "system_sender_label", "") or "").strip()
                reason = (getattr(thread, "reply_restriction_reason", "") or "").strip()
                await self.send_json(
                    {
                        "type": "error",
                        "code": "reply_locked",
                        "error": reason or (f"الردود مغلقة لهذه الرسائل من {label}." if label else "الردود مغلقة لهذه الرسائل الآلية."),
                    }
                )
            else:
                await self.send_json({"type": "error", "error": "بيانات غير صالحة"})
            return
        except Exception:
            logger.exception("WS create_message error")
            await self.send_json({"type": "error", "error": "حدث خطأ غير متوقع"})
            return

        get_full_name = getattr(self.user, "get_full_name", None)
        if callable(get_full_name):
            sender_name = get_full_name() or ""
        else:
            sender_name = ""
        sender_name = sender_name or display_name_for_user(self.user, sender_team_name=getattr(msg, "sender_team_name", ""))

        payload = {
            "type": "broadcast.message",
            "message": {
                "id": msg.id,
                "text": msg.body,
                "sender_id": msg.sender_id,
                "sender_name": sender_name,
                "sent_at": msg.created_at.isoformat(),
                "client_id": client_id,
            },
        }
        await self.channel_layer.group_send(self.group_name, payload)

    async def broadcast_message(self, event):
        # event["message"] is a dict
        await self.send_json({"type": "message", **event["message"]})

    async def broadcast_typing(self, event):
        await self.send_json(
            {
                "type": "typing",
                "user_id": event["user_id"],
                "is_typing": event["is_typing"],
            }
        )

    async def broadcast_read(self, event):
        await self.send_json(
            {
                "type": "read",
                "user_id": event["user_id"],
                "read_at": event.get("read_at"),
                "marked": event.get("marked", 0),
                "message_ids": event.get("message_ids", []),
            }
        )

    async def broadcast_blocked(self, event):
        blocked_by = event.get("blocked_by")
        # Close connections for the other participant immediately
        if blocked_by and self.user and getattr(self.user, "id", None) != blocked_by:
            await self.send_json({"type": "error", "code": "blocked", "error": "تم حظرك من الطرف الآخر"})
            await self.close(code=4403)

    async def broadcast_unblocked(self, event):
        # Inform clients; they may choose to re-enable UI
        await self.send_json({"type": "unblocked"})

    async def broadcast_message_deleted(self, event):
        await self.send_json(
            {
                "type": "message_deleted",
                "message_id": event.get("message_id"),
                "deleted_by": event.get("deleted_by"),
            }
        )
