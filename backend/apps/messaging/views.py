"""
Django template/session views for the messaging app.

DRF API views (JSON endpoints for the Flutter mobile app) live in api.py.
Shared helper functions used by both modules are defined here.
"""
import json
import logging
import mimetypes
import os

from django.http import JsonResponse
from django.views.decorators.csrf import csrf_protect
from django.views.decorators.http import require_POST
from django.utils.html import strip_tags
from django.shortcuts import get_object_or_404
from django.utils import timezone

from apps.accounts.permissions import ROLE_LEVELS, role_level
from apps.accounts.role_context import get_active_role
from apps.marketplace.models import ServiceRequest

from .models import Message, Thread, ThreadUserState


def _active_context_mode_from_request(request) -> str:
	"""Return the active context mode using the shared role utility.

	Falls back to 'shared' (instead of 'client') so that requests without
	an explicit mode still see all threads.
	"""
	return get_active_role(request, fallback="shared")


logger = logging.getLogger(__name__)

MAX_MESSAGE_LEN = 2000


def _infer_attachment_type(file_obj, requested_type: str | None = None) -> str:
	req_type = (requested_type or "").strip().lower()
	if req_type in {"audio", "image", "file"}:
		return req_type

	name = getattr(file_obj, "name", "") or ""
	mime, _ = mimetypes.guess_type(name)
	if mime:
		if mime.startswith("audio/"):
			return "audio"
		if mime.startswith("image/"):
			return "image"
	return "file"


def _can_access_request(user, sr: ServiceRequest) -> bool:
	if not user or not getattr(user, "is_authenticated", False):
		return False
	if getattr(user, "is_staff", False):
		return True
	is_client = sr.client_id == user.id
	is_provider = bool(sr.provider_id) and sr.provider.user_id == user.id
	return bool(is_client or is_provider)


def _thread_participant_users(thread: Thread):
	"""Return participants as user objects for direct and request threads."""
	if thread.is_direct:
		users = []
		if thread.participant_1_id:
			users.append(thread.participant_1)
		if thread.participant_2_id:
			users.append(thread.participant_2)
		return [u for u in users if u is not None]

	if thread.request_id and thread.request:
		users = [thread.request.client]
		if getattr(thread.request, "provider_id", None) and getattr(thread.request.provider, "user", None):
			users.append(thread.request.provider.user)
		return [u for u in users if u is not None]

	return []


def _unarchive_for_participants(thread: Thread):
	participants = _thread_participant_users(thread)
	if not participants:
		return
	ThreadUserState.objects.filter(thread=thread, user__in=participants, is_archived=True).update(
		is_archived=False,
		archived_at=None,
	)


def _is_blocked_by_other(thread: Thread, sender_user_id: int) -> bool:
	participants = _thread_participant_users(thread)
	other_ids = [u.id for u in participants if u and u.id and u.id != sender_user_id]
	if not other_ids:
		return False
	return ThreadUserState.objects.filter(thread=thread, user_id__in=other_ids, is_blocked=True).exists()


@require_POST
@csrf_protect
def post_message(request, thread_id: int):
	"""Fallback POST endpoint for the dashboard chat when WS is unavailable.

	Returns JSON and enforces the same access policy as WebSocket:
	- staff allowed
	- request.client or request.provider.user allowed
	"""
	try:
		user = request.user
		if not user or not user.is_authenticated:
			return JsonResponse({"ok": False, "error": "غير مصرح"}, status=401)
		if role_level(user) < ROLE_LEVELS["phone_only"]:
			return JsonResponse({"ok": False, "error": "غير مصرح"}, status=403)

		thread = (
			Thread.objects.select_related("request", "request__client", "request__provider__user")
			.filter(id=thread_id)
			.first()
		)
		if not thread:
			return JsonResponse({"ok": False, "error": "المحادثة غير موجودة"}, status=404)

		# Direct threads: check participant
		if thread.is_direct:
			if user.id not in (thread.participant_1_id, thread.participant_2_id):
				return JsonResponse({"ok": False, "error": "غير مصرح"}, status=403)
		elif thread.request:
			if not _can_access_request(user, thread.request):
				return JsonResponse({"ok": False, "error": "غير مصرح"}, status=403)
		else:
			return JsonResponse({"ok": False, "error": "غير مصرح"}, status=403)

		if _is_blocked_by_other(thread, user.id):
			return JsonResponse({"ok": False, "error": "تم حظرك من الطرف الآخر"}, status=403)

		# Accept form-encoded or JSON
		text = ""
		if (request.content_type or "").startswith("application/json"):
			try:
				payload = json.loads(request.body.decode("utf-8") or "{}")
				text = (payload.get("text") or payload.get("body") or "").strip()
			except Exception:
				text = ""
		else:
			text = (request.POST.get("text") or request.POST.get("body") or "").strip()

		text = strip_tags(text)
		if not text:
			return JsonResponse({"ok": False, "error": "الرسالة فارغة"}, status=400)
		if len(text) > MAX_MESSAGE_LEN:
			return JsonResponse({"ok": False, "error": "الرسالة طويلة جدًا"}, status=400)

		msg = Message.objects.create(thread=thread, sender=user, body=text, created_at=timezone.now())
		_unarchive_for_participants(thread)

		get_full_name = getattr(user, "get_full_name", None)
		if callable(get_full_name):
			sender_name = get_full_name() or ""
		else:
			sender_name = ""
		sender_name = sender_name or getattr(user, "phone", "") or str(user)

		return JsonResponse(
			{
				"ok": True,
				"message": {
					"id": msg.id,
					"text": msg.body,
					"sender_id": user.id,
					"sender_name": sender_name,
					"sent_at": msg.created_at.isoformat(),
				},
			},
			status=200,
		)
	except Exception:
		logger.exception("post_message error")
		return JsonResponse({"ok": False, "error": "حدث خطأ غير متوقع"}, status=500)

