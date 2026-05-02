"""
DRF API views for the messaging app.

These endpoints serve the Flutter mobile app (JSON responses).
Django template/session views remain in views.py.
"""
import logging
import mimetypes
import os

from django.db import DatabaseError, OperationalError
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.db.models import OuterRef, Q, Subquery
from rest_framework import generics, permissions, status
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.permissions import IsAtLeastPhoneOnly
from apps.core.unread_badges import (
	get_direct_messages_unread_payload,
	invalidate_unread_badge_cache,
)
from apps.marketplace.models import ServiceRequest
from apps.providers.models import ProviderProfile
from apps.extras_portal.models import PotentialClientSource, ProviderPotentialClient
from apps.providers.location_formatter import format_city_display
from apps.subscriptions.capabilities import direct_chat_quota_for_user
from apps.support.models import SupportTicket, SupportTicketType, SupportPriority, SupportTicketEntrypoint

from .models import Message, MessageRead, Thread, ThreadUserState, direct_thread_mode_q
from .display import display_name_for_user
from .pagination import MessagePagination
from .permissions import IsRequestParticipant, IsThreadParticipant
from .serializers import (
	MessageCreateSerializer,
	MessageListSerializer,
	ThreadSerializer,
	DirectThreadSerializer,
	ThreadUserStateSerializer,
)

from .views import (
	_active_context_mode_from_request,
	_validated_context_mode_from_request,
	_can_access_request,
	_thread_participant_users,
	_unarchive_for_participants,
	_is_blocked_by_other,
	_infer_attachment_type,
)


logger = logging.getLogger(__name__)


def _invalidate_direct_thread_badges(thread: Thread) -> None:
	if not thread.is_direct:
		return
	invalidate_unread_badge_cache(
		user_ids=[
			uid
			for uid in (thread.participant_1_id, thread.participant_2_id)
			if uid
		]
	)


def _direct_threads_count_for_user(user) -> int:
	if not getattr(user, "pk", None):
		return 0
	first_sender_subquery = Subquery(
		Message.objects.filter(
			thread=OuterRef("pk"),
			is_system_generated=False,
		)
		.order_by("created_at", "id")
		.values("sender_id")[:1]
	)
	return (
		Thread.objects.filter(is_direct=True, is_system_thread=False)
		.filter(Q(participant_1=user) | Q(participant_2=user))
		.annotate(first_sender_id=first_sender_subquery)
		.filter(first_sender_id=getattr(user, "id", None))
		.distinct()
		.count()
	)


def _direct_thread_consumes_quota(thread: Thread) -> bool:
	if not getattr(thread, "is_direct", False):
		return False
	return Message.objects.filter(thread=thread, is_system_generated=False).exists()


def _provider_direct_chat_limit_exceeded(user) -> bool:
	provider_profile = getattr(user, "provider_profile", None)
	if not provider_profile:
		return False
	return _direct_threads_count_for_user(user) >= direct_chat_quota_for_user(user)


def _apply_direct_thread_modes(*, thread: Thread, user_a, user_b, user_a_mode: str, user_b_mode: str) -> None:
	if thread.participant_1_id == getattr(user_a, "id", None):
		thread.set_participant_modes(
			participant_1_mode=user_a_mode,
			participant_2_mode=user_b_mode,
			save=True,
		)
		return
	if thread.participant_1_id == getattr(user_b, "id", None):
		thread.set_participant_modes(
			participant_1_mode=user_b_mode,
			participant_2_mode=user_a_mode,
			save=True,
		)


def _find_direct_thread_for_pair(*, user_a, user_b, user_a_mode: str, user_b_mode: str, legacy_context_mode: str = ""):
	threads = list(
		Thread.objects.filter(is_direct=True, is_system_thread=False)
		.filter(
			Q(participant_1=user_a, participant_2=user_b)
			| Q(participant_1=user_b, participant_2=user_a)
		)
		.order_by("-id")
	)
	for thread in threads:
		if thread.participant_mode_for_user(user_a) != user_a_mode:
			continue
		if thread.participant_mode_for_user(user_b) != user_b_mode:
			continue
		return thread
	if legacy_context_mode:
		for thread in threads:
			if thread.context_mode == legacy_context_mode:
				return thread
	return None


def _can_access_direct_thread_for_request(thread: Thread, request) -> bool:
	if not thread.is_participant(request.user):
		return False
	return thread.mode_matches_user(request.user, _validated_context_mode_from_request(request))


def _reply_restricted_detail(thread: Thread) -> str:
	label = (getattr(thread, "system_sender_label", "") or "").strip()
	reason = (getattr(thread, "reply_restriction_reason", "") or "").strip()
	if reason:
		return reason
	if label:
		return f"الردود مغلقة لهذه الرسائل من {label}."
	return "الردود مغلقة لهذه الرسائل الآلية."


def _sync_provider_potential_client_state(*, thread: Thread, actor_user, state: ThreadUserState) -> None:
	provider = getattr(actor_user, "provider_profile", None)
	if provider is None:
		return

	peer_user = thread.other_participant(actor_user)
	if peer_user is None or getattr(peer_user, "provider_profile", None) is not None:
		return

	is_potential = bool(getattr(state, "is_favorite", False))
	existing = ProviderPotentialClient.objects.filter(provider=provider, user=peer_user).first()

	if is_potential:
		if existing is None:
			ProviderPotentialClient.objects.create(
				provider=provider,
				user=peer_user,
				source=PotentialClientSource.SYSTEM,
			)
		return

	if existing and existing.source == PotentialClientSource.SYSTEM:
		existing.delete()


# ────────────────────────────────────────────────
# Request-based messaging
# ────────────────────────────────────────────────

class GetOrCreateThreadView(APIView):
	permission_classes = [IsAtLeastPhoneOnly, IsRequestParticipant]

	def get(self, request, request_id):
		service_request = get_object_or_404(ServiceRequest, id=request_id)
		thread, _ = Thread.objects.get_or_create(request=service_request)
		return Response(ThreadSerializer(thread).data, status=status.HTTP_200_OK)

	def post(self, request, request_id):
		# نفس سلوك GET (مفيد لبعض العملاء)
		return self.get(request, request_id)


class ThreadMessagesListView(generics.ListAPIView):
	permission_classes = [IsAtLeastPhoneOnly, IsRequestParticipant]
	serializer_class = MessageListSerializer
	pagination_class = MessagePagination

	def get_queryset(self):
		request_id = self.kwargs["request_id"]
		thread = get_object_or_404(Thread, request_id=request_id)
		return (
			Message.objects.select_related("sender")
			.prefetch_related("reads")
			.filter(thread=thread)
			.order_by("-id")
		)


class SendMessageView(APIView):
	permission_classes = [IsAtLeastPhoneOnly, IsRequestParticipant]
	parser_classes = [JSONParser, MultiPartParser, FormParser]

	def post(self, request, request_id):
		service_request = get_object_or_404(ServiceRequest, id=request_id)
		thread, _ = Thread.objects.get_or_create(request=service_request)

		if _is_blocked_by_other(thread, request.user.id):
			return Response({"detail": "تم حظرك من الطرف الآخر"}, status=status.HTTP_403_FORBIDDEN)

		if not thread.can_user_send(request.user):
			return Response({"detail": _reply_restricted_detail(thread)}, status=status.HTTP_403_FORBIDDEN)

		serializer = MessageCreateSerializer(data=request.data)
		serializer.is_valid(raise_exception=True)
		attachment = serializer.validated_data.get("attachment")
		attachment_type = _infer_attachment_type(
			attachment,
			serializer.validated_data.get("attachment_type"),
		) if attachment else ""
		attachment_name = ""
		if attachment:
			attachment_name = os.path.basename(getattr(attachment, "name", "") or "").strip()
		message = Message.objects.create(
			thread=thread,
			sender=request.user,
			body=serializer.validated_data["body"],
			attachment=attachment,
			attachment_type=attachment_type,
			attachment_name=attachment_name,
			created_at=timezone.now(),
		)
		if attachment_type == "video":
			from apps.uploads.tasks import schedule_video_optimization
			schedule_video_optimization(message, "attachment")
		_unarchive_for_participants(thread)
		_invalidate_direct_thread_badges(thread)

		return Response(
			{"ok": True, "message_id": message.id},
			status=status.HTTP_201_CREATED,
		)


class MarkThreadReadView(APIView):
	permission_classes = [IsAtLeastPhoneOnly, IsRequestParticipant]

	def post(self, request, request_id):
		thread = get_object_or_404(Thread, request_id=request_id)

		message_ids = list(
			Message.objects.filter(thread=thread)
			.exclude(reads__user=request.user)
			.values_list("id", flat=True)
		)

		MessageRead.objects.bulk_create(
			[
				MessageRead(message_id=mid, user=request.user, read_at=timezone.now())
				for mid in message_ids
			],
			ignore_conflicts=True,
		)
		_invalidate_direct_thread_badges(thread)

		return Response(
			{
				"ok": True,
				"thread_id": thread.id,
				"marked": len(message_ids),
				"message_ids": message_ids,
			},
			status=status.HTTP_200_OK,
		)


# ────────────────────────────────────────────────
# Direct messaging (no request required)
# ────────────────────────────────────────────────

class DirectThreadGetOrCreateView(APIView):
	"""Create or get an existing direct thread between the current user and another user."""
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request):
		provider_id = request.data.get("provider_id")
		request_id = request.data.get("request_id")
		if not provider_id and not request_id:
			return Response({"error": "provider_id أو request_id مطلوب"}, status=status.HTTP_400_BAD_REQUEST)

		me = request.user
		recipient_user = None
		analytics_payload = {}

		if provider_id:
			provider_profile = ProviderProfile.objects.select_related("user").filter(id=provider_id).first()
			if not provider_profile:
				return Response({"error": "المزود غير موجود"}, status=status.HTTP_404_NOT_FOUND)
			recipient_user = provider_profile.user
			recipient_provider_profile = provider_profile
			analytics_payload = {
				"provider_profile_id": provider_profile.id,
				"provider_user_id": recipient_user.id,
			}
		else:
			try:
				request_id = int(request_id)
			except (TypeError, ValueError):
				return Response({"error": "request_id غير صالح"}, status=status.HTTP_400_BAD_REQUEST)
			service_request = (
				ServiceRequest.objects.select_related("client", "provider__user")
				.filter(id=request_id)
				.first()
			)
			if not service_request:
				return Response({"error": "الطلب غير موجود"}, status=status.HTTP_404_NOT_FOUND)
			if not _can_access_request(me, service_request):
				return Response({"error": "غير مصرح"}, status=status.HTTP_403_FORBIDDEN)
			recipient_user = service_request.client
			if not recipient_user or not getattr(recipient_user, "is_active", False):
				return Response({"error": "العميل غير موجود"}, status=status.HTTP_404_NOT_FOUND)
			analytics_payload = {
				"client_user_id": recipient_user.id,
				"request_id": service_request.id,
			}

		active_mode = _validated_context_mode_from_request(request)
		desired_mode = (
			active_mode
			if active_mode in {Thread.ContextMode.CLIENT, Thread.ContextMode.PROVIDER}
			else Thread.ContextMode.SHARED
		)
		recipient_mode = (
			Thread.ContextMode.PROVIDER
			if getattr(recipient_user, "provider_profile", None)
			else Thread.ContextMode.CLIENT
		)

		if me.id == recipient_user.id:
			return Response({"error": "لا يمكنك محادثة نفسك"}, status=status.HTTP_400_BAD_REQUEST)

		thread = _find_direct_thread_for_pair(
			user_a=me,
			user_b=recipient_user,
			user_a_mode=desired_mode,
			user_b_mode=recipient_mode,
			legacy_context_mode=desired_mode,
		)

		if thread:
			_apply_direct_thread_modes(
				thread=thread,
				user_a=me,
				user_b=recipient_user,
				user_a_mode=desired_mode,
				user_b_mode=recipient_mode,
			)
		else:
			thread = Thread.objects.create(
				is_direct=True,
				context_mode=desired_mode,
				participant_1=me,
				participant_2=recipient_user,
				participant_1_mode=desired_mode,
				participant_2_mode=recipient_mode,
			)
			try:
				from apps.analytics.tracking import safe_track_event

				safe_track_event(
					event_name="messaging.direct_thread_created",
					channel="server",
					surface="messaging.direct_thread_create",
					source_app="messaging",
					object_type="Thread",
					object_id=str(thread.id),
					actor=me,
					dedupe_key=f"messaging.direct_thread_created:{thread.id}",
					payload={
						"context_mode": desired_mode,
						**analytics_payload,
					},
				)
			except Exception:
				pass

		return Response(DirectThreadSerializer(thread).data, status=status.HTTP_200_OK)


class DirectThreadMessagesListView(generics.ListAPIView):
	"""List messages in a direct thread."""
	permission_classes = [IsAtLeastPhoneOnly]
	serializer_class = MessageListSerializer
	pagination_class = MessagePagination

	def get_queryset(self):
		thread_id = self.kwargs["thread_id"]
		thread = get_object_or_404(Thread, id=thread_id, is_direct=True)
		if not _can_access_direct_thread_for_request(thread, self.request):
			from rest_framework.exceptions import PermissionDenied
			raise PermissionDenied("غير مصرح")
		return (
			Message.objects.select_related("sender")
			.prefetch_related("reads")
			.filter(thread=thread)
			.order_by("-id")
		)


class DirectThreadSendMessageView(APIView):
	"""Send a message in a direct thread."""
	permission_classes = [IsAtLeastPhoneOnly]
	parser_classes = [JSONParser, MultiPartParser, FormParser]

	def post(self, request, thread_id):
		thread = get_object_or_404(Thread, id=thread_id, is_direct=True)
		if not _can_access_direct_thread_for_request(thread, request):
			return Response({"error": "غير مصرح"}, status=status.HTTP_403_FORBIDDEN)

		if _is_blocked_by_other(thread, request.user.id):
			return Response({"detail": "تم حظرك من الطرف الآخر"}, status=status.HTTP_403_FORBIDDEN)

		if not thread.can_user_send(request.user):
			return Response({"detail": _reply_restricted_detail(thread)}, status=status.HTTP_403_FORBIDDEN)

		serializer = MessageCreateSerializer(data=request.data)
		serializer.is_valid(raise_exception=True)
		if not _direct_thread_consumes_quota(thread):
			provider_users = []
			for candidate in (thread.participant_1, thread.participant_2):
				if getattr(candidate, "provider_profile", None) and candidate not in provider_users:
					provider_users.append(candidate)
			for candidate in provider_users:
				if _provider_direct_chat_limit_exceeded(candidate):
					return Response(
						{"error": "تم بلوغ الحد الأقصى للمحادثات المباشرة في الباقة الحالية"},
						status=status.HTTP_403_FORBIDDEN,
					)
		attachment = serializer.validated_data.get("attachment")
		attachment_type = _infer_attachment_type(
			attachment,
			serializer.validated_data.get("attachment_type"),
		) if attachment else ""
		attachment_name = ""
		if attachment:
			attachment_name = os.path.basename(getattr(attachment, "name", "") or "").strip()
		message = Message.objects.create(
			thread=thread,
			sender=request.user,
			body=serializer.validated_data["body"],
			attachment=attachment,
			attachment_type=attachment_type,
			attachment_name=attachment_name,
			created_at=timezone.now(),
		)
		if attachment_type == "video":
			from apps.uploads.tasks import schedule_video_optimization
			schedule_video_optimization(message, "attachment")
		_unarchive_for_participants(thread)

		return Response(
			{"ok": True, "message_id": message.id},
			status=status.HTTP_201_CREATED,
		)


class DirectThreadMarkReadView(APIView):
	"""Mark all messages in a direct thread as read."""
	permission_classes = [IsAtLeastPhoneOnly]

	def post(self, request, thread_id):
		thread = get_object_or_404(Thread, id=thread_id, is_direct=True)
		if not _can_access_direct_thread_for_request(thread, request):
			return Response({"error": "غير مصرح"}, status=status.HTTP_403_FORBIDDEN)

		message_ids = list(
			Message.objects.filter(thread=thread)
			.exclude(reads__user=request.user)
			.values_list("id", flat=True)
		)

		MessageRead.objects.bulk_create(
			[
				MessageRead(message_id=mid, user=request.user, read_at=timezone.now())
				for mid in message_ids
			],
			ignore_conflicts=True,
		)

		return Response(
			{
				"ok": True,
				"thread_id": thread.id,
				"marked": len(message_ids),
				"message_ids": message_ids,
			},
			status=status.HTTP_200_OK,
		)


class MyDirectThreadsListView(APIView):
	"""List all direct threads for the current user."""
	permission_classes = [IsAtLeastPhoneOnly]

	def get(self, request):
		from django.db.models import Max
		me = request.user
		mode = _validated_context_mode_from_request(request)
		threads = (
			Thread.objects.filter(is_direct=True)
			.filter(direct_thread_mode_q(user=me, mode=mode))
			.select_related("participant_1", "participant_2")
			.annotate(last_message_at=Max("messages__created_at"))
			.order_by("-last_message_at")
		)

		result = []
		for t in threads:
			peer = t.participant_2 if t.participant_1_id == me.id else t.participant_1
			last_msg = t.messages.order_by("-id").first()
			unread = t.messages.exclude(sender=me).exclude(reads__user=me).count()
			peer_message_body = ""
			peer_sender_team_name = ""
			if getattr(peer, "is_staff", False):
				last_peer_message = t.messages.filter(sender=peer).order_by("-id").first()
				peer_message_body = getattr(last_peer_message, "body", "") or getattr(last_msg, "body", "") or ""
				peer_sender_team_name = getattr(last_peer_message, "sender_team_name", "") or getattr(t, "system_sender_label", "") or ""

			# Get provider profile for peer if exists
			peer_provider = getattr(peer, "provider_profile", None)
			peer_profile_image = ""
			if peer_provider:
				profile_image = getattr(peer_provider, "profile_image", None)
				if profile_image and getattr(profile_image, "name", ""):
					peer_profile_image = getattr(profile_image, "url", "") or ""
			peer_kind = "member"
			if getattr(peer, "is_staff", False):
				peer_kind = "team"
			elif peer_provider:
				peer_kind = "provider"
			elif mode == "provider":
				peer_kind = "client"

			result.append({
				"thread_id": t.id,
				"is_system_thread": bool(t.is_system_thread),
				"peer_id": peer.id,
				"peer_kind": peer_kind,
				"peer_provider_id": getattr(peer_provider, "id", None),
				"peer_profile_image": peer_profile_image,
				"peer_excellence_badges": (
					getattr(peer_provider, "excellence_badges_cache", [])
					if peer_provider and isinstance(getattr(peer_provider, "excellence_badges_cache", []), list)
					else []
				),
				"peer_name": (
					t.system_sender_label if (t.is_system_thread and (t.system_sender_label or "").strip())
					else peer_provider.display_name if (peer_provider and not getattr(peer, "is_staff", False))
					else display_name_for_user(peer, message_body=peer_message_body, sender_team_name=peer_sender_team_name)
				),
				"peer_first_name": getattr(peer, "first_name", "") or "",
				"peer_last_name": getattr(peer, "last_name", "") or "",
				"peer_username": getattr(peer, "username", "") or "",
				"peer_phone": getattr(peer, "phone", ""),
				"peer_city": getattr(peer_provider, "city", "") if peer_provider else getattr(peer, "city", ""),
				"peer_city_display": format_city_display(
					getattr(peer_provider, "city", "") if peer_provider else getattr(peer, "city", ""),
					region=getattr(peer_provider, "region", "") if peer_provider else "",
				),
				"last_message": last_msg.body if last_msg else "",
				"last_message_at": last_msg.created_at.isoformat() if last_msg else t.created_at.isoformat(),
				"unread_count": unread,
				"reply_restricted_to_me": t.reply_restricted_to_id == me.id,
				"reply_restriction_reason": t.reply_restriction_reason,
				"system_sender_label": t.system_sender_label,
			})

		return Response(result, status=status.HTTP_200_OK)


class DirectUnreadCountView(APIView):
	"""Return aggregate unread messages count for direct threads."""
	permission_classes = [IsAtLeastPhoneOnly]

	def get(self, request):
		mode = _validated_context_mode_from_request(request)
		try:
			payload = get_direct_messages_unread_payload(user=request.user, mode=mode)
		except (OperationalError, DatabaseError):
			return Response(
				{
					"unread": 0,
					"degraded": True,
					"stale": False,
					"mode": (mode or "shared").strip().lower() or "shared",
					"detail": "عداد الرسائل غير متاح مؤقتًا.",
				},
				status=status.HTTP_503_SERVICE_UNAVAILABLE,
			)
		return Response(payload, status=status.HTTP_200_OK)


# ────────────────────────────────────────────────
# Thread state management
# ────────────────────────────────────────────────

class MyThreadStatesListView(APIView):
	permission_classes = [IsAtLeastPhoneOnly]

	def get(self, request):
		from django.db.models import Q
		me = request.user
		mode = _validated_context_mode_from_request(request)

		q = Q()
		if mode in {"client", "provider"}:
			direct_q = Q(is_direct=True) & direct_thread_mode_q(user=me, mode=mode)
			q |= direct_q
			if mode == "client":
				q |= Q(request__client=me)
			else:
				q |= Q(request__provider__user=me)
		else:
			q |= (
				Q(is_direct=True, participant_1=me)
				| Q(is_direct=True, participant_2=me)
				| Q(request__client=me)
				| Q(request__provider__user=me)
			)

		thread_ids = list(Thread.objects.filter(q).values_list("id", flat=True))

		states = ThreadUserState.objects.filter(user=me, thread_id__in=thread_ids)
		return Response(ThreadUserStateSerializer(states, many=True).data, status=status.HTTP_200_OK)


class ThreadStateDetailView(APIView):
	permission_classes = [IsAtLeastPhoneOnly, IsThreadParticipant]

	def get(self, request, thread_id: int):
		obj, _ = ThreadUserState.objects.get_or_create(thread_id=thread_id, user=request.user)
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
		data = ThreadUserStateSerializer(obj).data
		data["blocked_by_other"] = bool(thread and _is_blocked_by_other(thread, request.user.id))
		data["reply_restricted_to_me"] = bool(thread and thread.reply_restricted_to_id == request.user.id)
		data["reply_restriction_reason"] = getattr(thread, "reply_restriction_reason", "") if thread else ""
		data["system_sender_label"] = getattr(thread, "system_sender_label", "") if thread else ""
		data["is_system_thread"] = bool(thread and thread.is_system_thread)
		return Response(data, status=status.HTTP_200_OK)


class ThreadFavoriteView(APIView):
	permission_classes = [IsAtLeastPhoneOnly, IsThreadParticipant]

	def post(self, request, thread_id: int):
		thread = get_object_or_404(
			Thread.objects.select_related(
				"request",
				"request__client",
				"request__provider__user",
				"participant_1",
				"participant_2",
			),
			id=thread_id,
		)
		action = (request.data.get("action") or "").strip().lower()
		obj, _ = ThreadUserState.objects.get_or_create(thread_id=thread_id, user=request.user)
		if action == "remove":
			obj.is_favorite = False
			obj.favorite_label = ""
		else:
			obj.is_favorite = True
			obj.favorite_label = ""
		obj.save(update_fields=["is_favorite", "favorite_label", "updated_at"])
		_sync_provider_potential_client_state(thread=thread, actor_user=request.user, state=obj)
		return Response({"ok": True, "is_favorite": obj.is_favorite, "favorite_label": obj.favorite_label}, status=status.HTTP_200_OK)


class ThreadArchiveView(APIView):
	permission_classes = [IsAtLeastPhoneOnly, IsThreadParticipant]

	def post(self, request, thread_id: int):
		action = (request.data.get("action") or "").strip().lower()
		obj, _ = ThreadUserState.objects.get_or_create(thread_id=thread_id, user=request.user)

		if action == "remove":
			obj.is_archived = False
			obj.archived_at = None
		else:
			obj.is_archived = True
			obj.archived_at = timezone.now()

		obj.save(update_fields=["is_archived", "archived_at", "updated_at"])
		return Response({"ok": True, "is_archived": obj.is_archived}, status=status.HTTP_200_OK)


class ThreadBlockView(APIView):
	permission_classes = [IsAtLeastPhoneOnly, IsThreadParticipant]

	def post(self, request, thread_id: int):
		action = (request.data.get("action") or "").strip().lower()
		obj, _ = ThreadUserState.objects.get_or_create(thread_id=thread_id, user=request.user)

		if action == "remove":
			obj.is_blocked = False
			obj.blocked_at = None
		else:
			obj.is_blocked = True
			obj.blocked_at = timezone.now()

		obj.save(update_fields=["is_blocked", "blocked_at", "updated_at"])
		return Response({"ok": True, "is_blocked": obj.is_blocked}, status=status.HTTP_200_OK)


class ThreadReportView(APIView):
	permission_classes = [IsAtLeastPhoneOnly, IsThreadParticipant]

	def post(self, request, thread_id: int):
		thread = get_object_or_404(
			Thread.objects.select_related(
				"request",
				"request__client",
				"request__provider__user",
				"participant_1",
				"participant_2",
			),
			id=thread_id,
		)

		reason = (request.data.get("reason") or "").strip()
		details = (request.data.get("details") or "").strip()
		reported_label = (request.data.get("reported_label") or "").strip()
		legacy = (request.data.get("description") or request.data.get("text") or "").strip()
		if not details:
			details = legacy

		# Reason is required in the new UI (matches mobile screenshot).
		# For legacy clients that only send description/text, default reason to "أخرى".
		if not reason and details:
			reason = "أخرى"
		if not reason:
			return Response({"detail": "reason مطلوب"}, status=status.HTTP_400_BAD_REQUEST)

		prefix = f"بلاغ محادثة (Thread#{thread.id})"
		if thread.request_id:
			prefix += f" طلب#{thread.request_id}"

		reported_user_id = None
		try:
			if thread.is_direct:
				if thread.participant_1_id == request.user.id:
					reported_user_id = thread.participant_2_id
				else:
					reported_user_id = thread.participant_1_id
			elif thread.request_id and getattr(thread.request, "provider_id", None):
				reported_user_id = thread.request.provider.user_id
		except Exception:
			reported_user_id = None

		if reported_user_id:
			prefix += f" المبلغ_عنه#{reported_user_id}"

		full = f"{prefix} - السبب: {reason}"
		if details:
			full += f" - التفاصيل: {details}"
		if reported_label:
			full += f" - الاسم: {reported_label}"
		full = full.strip()[:300]

		ticket = SupportTicket.objects.create(
			requester=request.user,
			ticket_type=SupportTicketType.COMPLAINT,
			priority=SupportPriority.NORMAL,
			entrypoint=SupportTicketEntrypoint.MESSAGING_REPORT,
			description=full,
			reported_kind="thread",
			reported_object_id=str(thread.id),
			reported_user_id=reported_user_id,
		)
		try:
			from apps.moderation.integrations import sync_support_ticket_case

			sync_support_ticket_case(ticket=ticket, by_user=request.user, request=request, note="thread_report")
		except Exception:
			pass
		try:
			from apps.analytics.tracking import safe_track_event

			safe_track_event(
				event_name="messaging.thread_report_created",
				channel="server",
				surface="messaging.thread_report",
				source_app="messaging",
				object_type="Thread",
				object_id=str(thread.id),
				actor=request.user,
				dedupe_key=f"messaging.thread_report_created:{thread.id}:{ticket.id}",
				payload={
					"ticket_id": ticket.id,
					"reason": reason,
					"reported_user_id": reported_user_id,
				},
			)
		except Exception:
			pass

		return Response({"ok": True, "ticket_id": ticket.id, "ticket_code": ticket.code}, status=status.HTTP_201_CREATED)


class ThreadMarkUnreadView(APIView):
	"""Mark a thread as unread for the current user."""
	permission_classes = [IsAtLeastPhoneOnly, IsThreadParticipant]

	def post(self, request, thread_id: int):
		thread = get_object_or_404(Thread, id=thread_id)

		last_peer_message = (
			Message.objects.filter(thread=thread)
			.exclude(sender=request.user)
			.order_by("-created_at", "-id")
			.first()
		)

		if not last_peer_message:
			return Response(
				{"ok": True, "marked": 0, "detail": "لا توجد رسائل من الطرف الآخر"},
				status=status.HTTP_200_OK,
			)

		deleted, _ = MessageRead.objects.filter(message=last_peer_message, user=request.user).delete()
		if thread.is_direct:
			_invalidate_direct_thread_badges(thread)
		return Response(
			{
				"ok": True,
				"marked": 1,
				"message_id": last_peer_message.id,
				"deleted": deleted,
			},
			status=status.HTTP_200_OK,
		)


class ThreadDeleteMessageView(APIView):
	"""Delete one message from a thread for both participants."""
	permission_classes = [IsAtLeastPhoneOnly, IsThreadParticipant]

	def post(self, request, thread_id: int, message_id: int):
		thread = get_object_or_404(Thread, id=thread_id)
		message = get_object_or_404(Message, id=message_id, thread=thread)

		if message.sender_id != request.user.id:
			return Response(
				{"detail": "يمكنك حذف الرسائل التي أرسلتها فقط"},
				status=status.HTTP_403_FORBIDDEN,
			)

		message.delete()
		if thread.is_direct:
			_invalidate_direct_thread_badges(thread)

		return Response(
			{"ok": True, "thread_id": thread_id, "message_id": message_id},
			status=status.HTTP_200_OK,
		)


class ThreadFavoriteLabelView(APIView):
	"""Set the favorite label for a thread."""
	permission_classes = [IsAtLeastPhoneOnly, IsThreadParticipant]

	VALID_LABELS = {"potential_client", "important_conversation", "incomplete_contact", ""}

	def post(self, request, thread_id: int):
		thread = get_object_or_404(
			Thread.objects.select_related(
				"request",
				"request__client",
				"request__provider__user",
				"participant_1",
				"participant_2",
			),
			id=thread_id,
		)
		label = (request.data.get("label") or "").strip().lower()
		if label not in self.VALID_LABELS:
			return Response(
				{"detail": f"قيمة label غير صحيحة. القيم المقبولة: {', '.join(self.VALID_LABELS - {''})}"},
				status=status.HTTP_400_BAD_REQUEST,
			)
		obj, _ = ThreadUserState.objects.get_or_create(thread_id=thread_id, user=request.user)
		obj.favorite_label = label
		# Setting a label auto-marks as favorite
		if label:
			obj.is_favorite = True
		obj.save(update_fields=["favorite_label", "is_favorite", "updated_at"])
		return Response(
			{"ok": True, "favorite_label": obj.favorite_label, "is_favorite": obj.is_favorite},
			status=status.HTTP_200_OK,
		)


class ThreadClientLabelView(APIView):
	"""Tag a client in the thread as potential / current / past."""
	permission_classes = [IsAtLeastPhoneOnly, IsThreadParticipant]

	VALID_LABELS = {"potential", "current", "past", ""}

	def post(self, request, thread_id: int):
		thread = get_object_or_404(
			Thread.objects.select_related(
				"request",
				"request__client",
				"request__provider__user",
				"participant_1",
				"participant_2",
			),
			id=thread_id,
		)
		label = (request.data.get("label") or "").strip().lower()
		if label not in self.VALID_LABELS:
			return Response(
				{"detail": f"قيمة label غير صحيحة. القيم المقبولة: {', '.join(self.VALID_LABELS - {''})}"},
				status=status.HTTP_400_BAD_REQUEST,
			)
		obj, _ = ThreadUserState.objects.get_or_create(thread_id=thread_id, user=request.user)
		obj.client_label = label
		obj.save(update_fields=["client_label", "updated_at"])
		return Response(
			{"ok": True, "client_label": obj.client_label},
			status=status.HTTP_200_OK,
		)
