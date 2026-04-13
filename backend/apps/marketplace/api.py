"""
DRF API views for the marketplace app.

These endpoints serve the Flutter mobile app (JSON responses).
Django template views remain in views.py.
"""
from datetime import timedelta
import logging

from django.conf import settings
from django.core.cache import cache
from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from django.core.exceptions import PermissionDenied
from django.shortcuts import get_object_or_404
from rest_framework import generics, permissions, status
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.providers.models import ProviderCategory, ProviderProfile
from apps.notifications.models import EventType
from apps.notifications.services import create_notification
from apps.subscriptions.capabilities import (
	competitive_requests_enabled_for_user,
	competitive_request_delay_for_user,
	competitive_request_is_visible,
	urgent_requests_enabled_for_user,
)
from apps.subscriptions.services import user_has_active_subscription

from apps.accounts.permissions import IsAtLeastClient

from .models import (
	DispatchStatus,
	Offer,
	OfferStatus,
	RequestStatus,
	RequestStatusLog,
	RequestType,
	ServiceRequest,
	ServiceRequestDispatch,
	ServiceRequestAttachment,
)
from .serializers import (
	ClientRequestUpdateSerializer,
	OfferCreateSerializer,
	OfferListSerializer,
	ProviderInputsDecisionSerializer,
	ProviderProgressUpdateSerializer,
	ProviderRejectSerializer,
	RequestCompleteSerializer,
	ProviderRequestDetailSerializer,
	RequestStartSerializer,
	ServiceRequestCreateSerializer,
	ServiceRequestListSerializer,
	UrgentRequestAcceptSerializer,
)

from .services.actions import execute_action
from .services.dispatch import (
	dispatch_ready_urgent_windows,
	ensure_dispatch_windows_for_urgent_request,
	provider_can_access_urgent_request,
	provider_dispatch_tier,
)

from .views import (
	_normalize_status_group,
	_status_group_to_statuses,
	_expire_urgent_requests,
)


logger = logging.getLogger(__name__)


def _dispatch_ready_urgent_windows_once(*, now=None, limit: int = 200) -> None:
	now = now or timezone.now()
	interval_seconds = max(
		10,
		int(getattr(settings, "URGENT_DISPATCH_INLINE_INTERVAL_SECONDS", 30) or 30),
	)
	cache_key = "marketplace:inline_dispatch:ready_windows:tick"
	try:
		if not cache.add(cache_key, now.isoformat(), timeout=interval_seconds):
			return
	except Exception:
		# Cache degradation should not block request flow.
		pass
	dispatch_ready_urgent_windows(now=now, limit=limit)


def _infer_attachment_type(uploaded_file) -> str:
	name = (getattr(uploaded_file, "name", "") or "").lower()
	content_type = (getattr(uploaded_file, "content_type", "") or "").lower()

	if content_type.startswith("image/") or name.endswith((".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp")):
		return "image"
	if content_type.startswith("video/") or name.endswith((".mp4", ".mov", ".avi", ".mkv", ".webm", ".m4v")):
		return "video"
	if content_type.startswith("audio/") or name.endswith((".mp3", ".wav", ".aac", ".ogg", ".m4a")):
		return "audio"
	return "document"


def _request_subcategory_ids(service_request: ServiceRequest) -> list[int]:
	try:
		return service_request.selected_subcategory_ids()
	except Exception:
		if getattr(service_request, "subcategory_id", None):
			return [service_request.subcategory_id]
		return []


def _provider_can_access_competitive_request(provider: ProviderProfile, service_request: ServiceRequest, *, now=None) -> bool:
	if not competitive_requests_enabled_for_user(provider.user):
		return False
	return competitive_request_is_visible(
		user=provider.user,
		created_at=getattr(service_request, "created_at", None),
		now=now,
	)


# ────────────────────────────────────────────────
# Permissions
# ────────────────────────────────────────────────

class IsProviderPermission(permissions.BasePermission):
	def has_permission(self, request, view):
		return bool(getattr(request, "user", None)) and hasattr(request.user, "provider_profile")


# ────────────────────────────────────────────────
# Request CRUD
# ────────────────────────────────────────────────

class ServiceRequestCreateView(generics.CreateAPIView):
	serializer_class = ServiceRequestCreateSerializer
	permission_classes = [IsAtLeastClient]

	def perform_create(self, serializer):
		request_type = serializer.validated_data["request_type"]
		dispatch_mode = (serializer.validated_data.get("dispatch_mode") or "all").strip().lower()

		is_urgent = request_type == RequestType.URGENT
		status_value = RequestStatus.NEW
		now = timezone.now()

		service_request = serializer.save(
			client=self.request.user,
			is_urgent=is_urgent,
			status=status_value,
			dispatch_mode=dispatch_mode,
		)

		# Targeted normal requests (client -> specific provider) need an explicit
		# provider notification on creation because no RequestStatusLog is emitted here.
		if (
			request_type == RequestType.NORMAL
			and getattr(service_request, "provider_id", None)
			and getattr(getattr(service_request, "provider", None), "user_id", None)
		):
			create_notification(
				user=service_request.provider.user,
				title="طلب جديد",
				body=f"لديك طلب خدمة جديد: {service_request.title}",
				kind="request_created",
				url=f"/requests/{service_request.id}",
				actor=self.request.user,
				event_type=EventType.REQUEST_CREATED,
				pref_key="new_request",
				request_id=service_request.id,
				audience_mode="provider",
			)
		if is_urgent and dispatch_mode in {"all", "nearest"}:
			ensure_dispatch_windows_for_urgent_request(service_request, now=now)
			_dispatch_ready_urgent_windows_once(now=now, limit=200)


class MyClientRequestsView(generics.ListAPIView):
	permission_classes = [IsAtLeastClient]
	serializer_class = ServiceRequestListSerializer

	def get_queryset(self):
		_expire_urgent_requests()
		qs = (
			ServiceRequest.objects.select_related("provider", "review", "subcategory", "subcategory__category")
			.filter(client=self.request.user)
			.order_by("-created_at")
		)

		group_value = _normalize_status_group(self.request.query_params.get("status_group") or "")
		if group_value:
			qs = qs.filter(status__in=_status_group_to_statuses(group_value))

		status_value = (self.request.query_params.get("status") or "").strip()
		if status_value:
			allowed = {c.value for c in RequestStatus}
			if status_value in allowed:
				qs = qs.filter(status=status_value)

		type_value = (self.request.query_params.get("type") or "").strip()
		if type_value:
			allowed = {c.value for c in RequestType}
			if type_value in allowed:
				qs = qs.filter(request_type=type_value)

		q = (self.request.query_params.get("q") or "").strip()
		if q:
			qs = qs.filter(
				Q(title__icontains=q)
				| Q(description__icontains=q)
				| Q(subcategory__name__icontains=q)
				| Q(subcategory__category__name__icontains=q)
			)

		return qs


class MyClientRequestDetailView(generics.RetrieveUpdateAPIView):
	permission_classes = [IsAtLeastClient]
	lookup_url_kwarg = "request_id"

	def get_serializer_class(self):
		if self.request.method in ("PATCH", "PUT"):
			return ClientRequestUpdateSerializer
		return ProviderRequestDetailSerializer

	def get_queryset(self):
		return ServiceRequest.objects.select_related(
			"provider",
			"review",
			"subcategory",
			"subcategory__category",
		).prefetch_related(
			"attachments",
			"status_logs",
			"status_logs__actor",
		).filter(client=self.request.user)

	def update(self, request, *args, **kwargs):
		obj = self.get_object()
		s = self.get_serializer(data=request.data, partial=True)
		s.is_valid(raise_exception=True)

		if obj.status in (
			RequestStatus.IN_PROGRESS,
			RequestStatus.COMPLETED,
			RequestStatus.CANCELLED,
		):
			return Response(
				{"detail": "لا يمكن تعديل الطلب في هذه الحالة"},
				status=status.HTTP_400_BAD_REQUEST,
			)

		update_fields = []
		changes = []

		title = s.validated_data.get("title")
		if title is not None:
			title = title.strip()
			if title and title != obj.title:
				obj.title = title
				update_fields.append("title")
				changes.append("العنوان")

		description = s.validated_data.get("description")
		if description is not None:
			description = description.strip()
			if description and description != obj.description:
				obj.description = description
				update_fields.append("description")
				changes.append("التفاصيل")

		if update_fields:
			obj.save(update_fields=update_fields)
			RequestStatusLog.objects.create(
				request=obj,
				actor=request.user,
				from_status=obj.status,
				to_status=obj.status,
				note=f"تحديث بيانات الطلب من العميل ({'، '.join(changes)})",
			)

		out = ProviderRequestDetailSerializer(obj, context={"request": request})
		return Response(out.data, status=status.HTTP_200_OK)


# ────────────────────────────────────────────────
# Urgent
# ────────────────────────────────────────────────

class UrgentRequestAcceptView(APIView):
	permission_classes = [permissions.IsAuthenticated, IsProviderPermission]

	def post(self, request):
		_expire_urgent_requests()
		_dispatch_ready_urgent_windows_once(limit=200)
		serializer = UrgentRequestAcceptSerializer(data=request.data)
		serializer.is_valid(raise_exception=True)

		request_id = serializer.validated_data["request_id"]
		provider: ProviderProfile = request.user.provider_profile

		with transaction.atomic():
			service_request = (
				ServiceRequest.objects.select_for_update()
				.filter(id=request_id)
				.first()
			)

			if not service_request:
				return Response(
					{"detail": "الطلب غير موجود"},
					status=status.HTTP_404_NOT_FOUND,
				)

			if service_request.request_type != RequestType.URGENT:
				return Response(
					{"detail": "هذا الطلب ليس عاجلًا"},
					status=status.HTTP_400_BAD_REQUEST,
				)

			if service_request.status != RequestStatus.NEW:
				return Response(
					{"detail": "لا يمكن قبول الطلب في هذه الحالة"},
					status=status.HTTP_400_BAD_REQUEST,
				)

			if service_request.provider is not None:
				return Response(
					{"detail": "تم قبول الطلب بالفعل"},
					status=status.HTTP_409_CONFLICT,
				)

			if not getattr(provider, "accepts_urgent", False):
				return Response(
					{"detail": "هذا المزود لا يقبل الطلبات العاجلة"},
					status=status.HTTP_403_FORBIDDEN,
				)
			if not urgent_requests_enabled_for_user(request.user):
				return Response(
					{"detail": "الطلبات العاجلة تتطلب اشتراكًا فعالًا في إحدى الباقات."},
					status=status.HTTP_403_FORBIDDEN,
				)
			if (service_request.city or "").strip() and (provider.city or "").strip() and service_request.city.strip() != provider.city.strip():
				return Response(
					{"detail": "هذا الطلب خارج نطاق مدينتك"},
					status=status.HTTP_403_FORBIDDEN,
				)
			if not ProviderCategory.objects.filter(
				provider=provider,
				subcategory_id__in=_request_subcategory_ids(service_request),
			).exists():
				return Response(
					{"detail": "هذا الطلب لا يطابق تخصصاتك"},
					status=status.HTTP_403_FORBIDDEN,
				)
			now = timezone.now()
			if not provider_can_access_urgent_request(provider, service_request, now=now):
				return Response(
					{"detail": "هذا الطلب لم يصبح متاحًا لباقتك بعد"},
					status=status.HTTP_403_FORBIDDEN,
				)

			old = service_request.status
			service_request.provider = provider
			# Keep urgent request in NEW until client approves provider inputs.
			service_request.status = RequestStatus.NEW
			service_request.provider_inputs_approved = None
			service_request.provider_inputs_decided_at = None
			service_request.provider_inputs_decision_note = ""
			service_request.save(
				update_fields=[
					"provider",
					"status",
					"provider_inputs_approved",
					"provider_inputs_decided_at",
					"provider_inputs_decision_note",
				]
			)
			RequestStatusLog.objects.create(
				request=service_request,
				actor=request.user,
				from_status=old,
				to_status=service_request.status,
				note="تم قبول الطلب العاجل من مزود الخدمة بانتظار إرسال تفاصيل التنفيذ",
			)

		return Response(
			{
				"ok": True,
				"request_id": service_request.id,
				"status": service_request.status,
				"provider": provider.display_name,
			},
			status=status.HTTP_200_OK,
		)


class AvailableUrgentRequestsView(generics.ListAPIView):
	permission_classes = [permissions.IsAuthenticated, IsProviderPermission]
	serializer_class = ServiceRequestListSerializer

	def get_queryset(self):
		_expire_urgent_requests()
		provider = self.request.user.provider_profile
		if not user_has_active_subscription(self.request.user):
			return ServiceRequest.objects.none()
		now = timezone.now()
		_dispatch_ready_urgent_windows_once(now=now, limit=200)

		if not provider.accepts_urgent or not urgent_requests_enabled_for_user(self.request.user):
			return ServiceRequest.objects.none()

		provider_tier = provider_dispatch_tier(provider)

		provider_subcats = ProviderCategory.objects.filter(provider=provider).values_list(
			"subcategory_id",
			flat=True,
		)

		qs = (
			ServiceRequest.objects.select_related("client", "subcategory", "subcategory__category")
			.filter(
				request_type=RequestType.URGENT,
				provider__isnull=True,
				status=RequestStatus.NEW,
			)
			.filter(
				Q(subcategory_id__in=provider_subcats)
				| Q(subcategories__id__in=provider_subcats)
			)
			.filter(Q(city=provider.city) | Q(city=""))
			.order_by("-created_at")
			.distinct()
		)

		ready_request_ids = ServiceRequestDispatch.objects.filter(
			dispatch_tier=provider_tier,
			dispatch_status__in=[
				DispatchStatus.PENDING,
				DispatchStatus.READY,
				DispatchStatus.DISPATCHED,
			],
			available_at__lte=now,
		).values_list("request_id", flat=True)

		return qs.filter(Q(id__in=ready_request_ids) | Q(dispatch_windows__isnull=True)).distinct()


class AvailableCompetitiveRequestsView(generics.ListAPIView):
	permission_classes = [permissions.IsAuthenticated, IsProviderPermission]
	serializer_class = ServiceRequestListSerializer

	def get_queryset(self):
		provider = self.request.user.provider_profile
		if not user_has_active_subscription(self.request.user):
			return ServiceRequest.objects.none()
		now = timezone.now()
		if not competitive_requests_enabled_for_user(self.request.user):
			return ServiceRequest.objects.none()

		provider_subcats = ProviderCategory.objects.filter(provider=provider).values_list(
			"subcategory_id",
			flat=True,
		)

		delay = competitive_request_delay_for_user(provider.user)

		qs = (
			ServiceRequest.objects.select_related("client", "subcategory", "subcategory__category")
			.filter(
				request_type=RequestType.COMPETITIVE,
				provider__isnull=True,
				status=RequestStatus.NEW,
			)
			.filter(
				Q(subcategory_id__in=provider_subcats)
				| Q(subcategories__id__in=provider_subcats)
			)
			.filter(Q(city=provider.city) | Q(city=""))
			.order_by("-created_at")
			.distinct()
		)
		if delay.total_seconds() > 0:
			qs = qs.filter(created_at__lte=now - delay)
		return qs


# ────────────────────────────────────────────────
# Provider request actions
# ────────────────────────────────────────────────

class MyProviderRequestsView(generics.ListAPIView):
	permission_classes = [permissions.IsAuthenticated, IsProviderPermission]
	serializer_class = ServiceRequestListSerializer

	def get_queryset(self):
		_expire_urgent_requests()
		provider = self.request.user.provider_profile
		qs = (
			ServiceRequest.objects.select_related("client", "review", "subcategory", "subcategory__category")
			.filter(provider=provider)
			.order_by("-created_at")
		)

		group_value = _normalize_status_group(self.request.query_params.get("status_group") or "")
		if group_value:
			qs = qs.filter(status__in=_status_group_to_statuses(group_value))

		client_user_id = (self.request.query_params.get("client_user_id") or "").strip()
		if client_user_id.isdigit():
			qs = qs.filter(client_id=int(client_user_id))

		return qs


class ProviderRequestDetailView(generics.RetrieveAPIView):
	permission_classes = [permissions.IsAuthenticated, IsProviderPermission]
	serializer_class = ProviderRequestDetailSerializer
	lookup_url_kwarg = "request_id"

	def get_queryset(self):
		return ServiceRequest.objects.select_related(
			"client",
			"provider",
			"provider__user",
			"review",
			"subcategory",
			"subcategory__category",
		).prefetch_related("attachments", "status_logs", "status_logs__actor")

	def get_object(self):
		obj = super().get_object()
		provider = self.request.user.provider_profile

		if obj.provider_id == provider.id:
			return obj

		if obj.provider_id is not None:
			raise PermissionDenied("غير مصرح")

		if obj.status != RequestStatus.NEW:
			raise PermissionDenied("غير مصرح")

		if obj.request_type == RequestType.NORMAL:
			raise PermissionDenied("غير مصرح")

		if obj.request_type == RequestType.URGENT and not provider.accepts_urgent:
			raise PermissionDenied("غير مصرح")
		if obj.request_type == RequestType.URGENT and not user_has_active_subscription(self.request.user):
			raise PermissionDenied("غير مصرح")
		if obj.request_type == RequestType.URGENT and not provider_can_access_urgent_request(provider, obj):
			raise PermissionDenied("غير مصرح")
		if obj.request_type == RequestType.COMPETITIVE and not user_has_active_subscription(self.request.user):
			raise PermissionDenied("غير مصرح")
		if obj.request_type == RequestType.COMPETITIVE and not _provider_can_access_competitive_request(provider, obj):
			raise PermissionDenied("غير مصرح")

		if (obj.city or "").strip() and (provider.city or "").strip() and obj.city.strip() != provider.city.strip():
			raise PermissionDenied("غير مصرح")

		if not ProviderCategory.objects.filter(
			provider=provider,
			subcategory_id__in=_request_subcategory_ids(obj),
		).exists():
			raise PermissionDenied("غير مصرح")

		return obj


class ProviderAssignedRequestAcceptView(APIView):
	permission_classes = [permissions.IsAuthenticated, IsProviderPermission]

	def post(self, request, request_id: int):
		try:
			_expire_urgent_requests()
			provider = request.user.provider_profile

			with transaction.atomic():
				sr = (
					ServiceRequest.objects.select_for_update()
					.select_related("client")
					.filter(id=request_id)
					.first()
				)

				if not sr:
					return Response({"detail": "الطلب غير موجود"}, status=status.HTTP_404_NOT_FOUND)

				if sr.provider_id != provider.id:
					return Response({"detail": "غير مصرح"}, status=status.HTTP_403_FORBIDDEN)

				if sr.request_type == RequestType.COMPETITIVE:
					return Response({"detail": "هذا الطلب تنافسي ويتم التعامل معه عبر العروض"}, status=status.HTTP_400_BAD_REQUEST)

				if sr.status != RequestStatus.NEW:
					return Response({"detail": "لا يمكن قبول الطلب في هذه الحالة"}, status=status.HTTP_400_BAD_REQUEST)

				old = sr.status
				RequestStatusLog.objects.create(
					request=sr,
					actor=request.user,
					from_status=old,
					to_status=sr.status,
					note="قبول من المزود بانتظار إرسال تفاصيل التنفيذ",
				)

			return Response({"ok": True, "request_id": sr.id, "status": sr.status}, status=status.HTTP_200_OK)
		except Exception as e:
			logger.exception("provider_request_accept_error request_id=%s user_id=%s", request_id, getattr(request.user, "id", None))
			detail = "تعذر قبول الطلب حالياً. حاول مرة أخرى."
			if getattr(settings, "DEBUG", False):
				detail = f"{detail} ({e})"
			return Response({"detail": detail}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


class ProviderAssignedRequestRejectView(APIView):
	permission_classes = [permissions.IsAuthenticated, IsProviderPermission]

	def post(self, request, request_id: int):
		_expire_urgent_requests()
		provider = request.user.provider_profile
		s = ProviderRejectSerializer(data=request.data)
		s.is_valid(raise_exception=True)
		note = s.validated_data.get("note", "")
		canceled_at = s.validated_data["canceled_at"]
		cancel_reason = s.validated_data["cancel_reason"].strip()

		with transaction.atomic():
			sr = (
				ServiceRequest.objects.select_for_update()
				.select_related("client")
				.filter(id=request_id)
				.first()
			)

			if not sr:
				return Response({"detail": "الطلب غير موجود"}, status=status.HTTP_404_NOT_FOUND)

			if sr.provider_id != provider.id:
				return Response({"detail": "غير مصرح"}, status=status.HTTP_403_FORBIDDEN)

			if sr.request_type == RequestType.COMPETITIVE:
				return Response({"detail": "هذا الطلب تنافسي ويتم التعامل معه عبر العروض"}, status=status.HTTP_400_BAD_REQUEST)

			if sr.status != RequestStatus.NEW:
				return Response({"detail": "لا يمكن رفض الطلب في هذه الحالة"}, status=status.HTTP_400_BAD_REQUEST)

			old = sr.status
			if sr.request_type == RequestType.URGENT:
				# Return urgent request to the shared pool for eligible providers.
				sr.provider = None
				sr.status = RequestStatus.NEW
				sr.expected_delivery_at = None
				sr.estimated_service_amount = None
				sr.received_amount = None
				sr.remaining_amount = None
				sr.provider_inputs_approved = None
				sr.provider_inputs_decided_at = None
				sr.provider_inputs_decision_note = ""
				sr.canceled_at = None
				sr.cancel_reason = ""
				sr.save(
					update_fields=[
						"provider",
						"status",
						"expected_delivery_at",
						"estimated_service_amount",
						"received_amount",
						"remaining_amount",
						"provider_inputs_approved",
						"provider_inputs_decided_at",
						"provider_inputs_decision_note",
						"canceled_at",
						"cancel_reason",
					]
				)
			else:
				sr.status = RequestStatus.CANCELLED
				sr.canceled_at = canceled_at
				sr.cancel_reason = cancel_reason
				sr.save(update_fields=["status", "canceled_at", "cancel_reason"])
			RequestStatusLog.objects.create(
				request=sr,
				actor=request.user,
				from_status=old,
				to_status=sr.status,
				note=(
					note
					or (
						f"اعتذار مزود الخدمة عن الطلب العاجل: {cancel_reason}"
						if sr.request_type == RequestType.URGENT
						else f"إلغاء من المزود: {cancel_reason}"
					)
				),
			)

			if sr.request_type == RequestType.URGENT:
				now = timezone.now()
				ensure_dispatch_windows_for_urgent_request(sr, now=now)
				_dispatch_ready_urgent_windows_once(now=now, limit=200)

		return Response({"ok": True, "request_id": sr.id, "status": sr.status}, status=status.HTTP_200_OK)


class ProviderProgressUpdateView(APIView):
	permission_classes = [permissions.IsAuthenticated, IsProviderPermission]

	def post(self, request, request_id):
		s = ProviderProgressUpdateSerializer(data=request.data)
		s.is_valid(raise_exception=True)
		note = s.validated_data.get("note", "").strip()

		provider = request.user.provider_profile

		with transaction.atomic():
			sr = (
				ServiceRequest.objects.select_for_update()
				.select_related("client")
				.filter(id=request_id)
				.first()
			)

			if not sr:
				return Response({"detail": "الطلب غير موجود"}, status=status.HTTP_404_NOT_FOUND)

			if sr.provider_id != provider.id:
				return Response({"detail": "غير مصرح"}, status=status.HTTP_403_FORBIDDEN)

			if sr.status not in (RequestStatus.NEW, RequestStatus.IN_PROGRESS):
				return Response(
					{"detail": "لا يمكن تحديث التنفيذ في هذه الحالة"},
					status=status.HTTP_400_BAD_REQUEST,
				)

			update_fields = []
			if "expected_delivery_at" in s.validated_data:
				sr.expected_delivery_at = s.validated_data["expected_delivery_at"]
				update_fields.append("expected_delivery_at")

			if "estimated_service_amount" in s.validated_data:
				sr.estimated_service_amount = s.validated_data["estimated_service_amount"]
				sr.received_amount = s.validated_data["received_amount"]
				sr.remaining_amount = s.validated_data["remaining_amount"]
				update_fields.extend(
					[
						"estimated_service_amount",
						"received_amount",
						"remaining_amount",
					]
				)

			if sr.status == RequestStatus.NEW:
				sr.provider_inputs_approved = None
				sr.provider_inputs_decided_at = None
				sr.provider_inputs_decision_note = ""
				update_fields.extend(
					[
						"provider_inputs_approved",
						"provider_inputs_decided_at",
						"provider_inputs_decision_note",
					]
				)

			if update_fields:
				sr.save(update_fields=update_fields)

			RequestStatusLog.objects.create(
				request=sr,
				actor=request.user,
				from_status=sr.status,
				to_status=sr.status,
				note=note or "إرسال/تحديث مدخلات التنفيذ من مزود الخدمة",
			)

		return Response(
			{"ok": True, "request_id": sr.id, "status": sr.status},
			status=status.HTTP_200_OK,
		)


class ProviderInputsDecisionView(APIView):
	permission_classes = [IsAtLeastClient]

	def post(self, request, request_id):
		s = ProviderInputsDecisionSerializer(data=request.data)
		s.is_valid(raise_exception=True)
		approved = s.validated_data["approved"]
		note = (s.validated_data.get("note") or "").strip()

		action = "approve_inputs" if approved else "reject_inputs"
		try:
			result = execute_action(
				user=request.user,
				request_id=request_id,
				action=action,
			)
		except Exception as e:
			return Response({"detail": str(e)}, status=status.HTTP_400_BAD_REQUEST)

		# Save optional decision note
		if note:
			ServiceRequest.objects.filter(id=request_id).update(
				provider_inputs_decision_note=note,
			)

		return Response(
			{"ok": True, "request_id": request_id, "approved": approved},
			status=status.HTTP_200_OK,
		)


# ────────────────────────────────────────────────
# Offers
# ────────────────────────────────────────────────

class CreateOfferView(APIView):
	permission_classes = [permissions.IsAuthenticated, IsProviderPermission]

	def post(self, request, request_id):
		provider = request.user.provider_profile
		service_request = get_object_or_404(ServiceRequest, id=request_id)

		if service_request.request_type != RequestType.COMPETITIVE:
			return Response(
				{"detail": "هذا الطلب ليس تنافسيًا"},
				status=status.HTTP_400_BAD_REQUEST,
			)

		if service_request.status != RequestStatus.NEW:
			return Response(
				{"detail": "لا يمكن إرسال عرض في هذه الحالة"},
				status=status.HTTP_400_BAD_REQUEST,
			)

		if service_request.quote_deadline and timezone.localdate() > service_request.quote_deadline:
			return Response(
				{"detail": "انتهت مهلة استقبال عروض الأسعار لهذا الطلب"},
				status=status.HTTP_400_BAD_REQUEST,
			)

		if (service_request.city or "").strip() and (provider.city or "").strip() and service_request.city.strip() != provider.city.strip():
			return Response(
				{"detail": "هذا الطلب خارج نطاق مدينتك"},
				status=status.HTTP_403_FORBIDDEN,
			)
		if not ProviderCategory.objects.filter(
			provider=provider,
			subcategory_id__in=_request_subcategory_ids(service_request),
		).exists():
			return Response(
				{"detail": "هذا الطلب لا يطابق تخصصاتك"},
				status=status.HTTP_403_FORBIDDEN,
			)
		if not _provider_can_access_competitive_request(provider, service_request, now=timezone.now()):
			return Response(
				{"detail": "هذا الطلب لم يصبح متاحًا لباقتك بعد"},
				status=status.HTTP_403_FORBIDDEN,
			)

		serializer = OfferCreateSerializer(data=request.data)
		serializer.is_valid(raise_exception=True)

		offer, created = Offer.objects.get_or_create(
			request=service_request,
			provider=provider,
			defaults=serializer.validated_data,
		)

		if not created:
			return Response(
				{"detail": "تم إرسال عرض مسبقًا"},
				status=status.HTTP_409_CONFLICT,
			)

		return Response(
			{"ok": True, "offer_id": offer.id},
			status=status.HTTP_201_CREATED,
		)


class RequestOffersListView(generics.ListAPIView):
	permission_classes = [IsAtLeastClient]
	serializer_class = OfferListSerializer

	def get_queryset(self):
		request_id = self.kwargs["request_id"]
		return (
			Offer.objects.select_related("provider")
			.filter(request_id=request_id, request__client=self.request.user)
			.order_by("-created_at")
		)


class AcceptOfferView(APIView):
	permission_classes = [IsAtLeastClient]

	def post(self, request, offer_id):
		with transaction.atomic():
			offer = (
				Offer.objects.select_for_update()
				.select_related("request", "provider")
				.get(id=offer_id)
			)

			service_request = offer.request

			if service_request.client != request.user:
				return Response(
					{"detail": "غير مصرح"},
					status=status.HTTP_403_FORBIDDEN,
				)

			if service_request.status != RequestStatus.NEW:
				return Response(
					{"detail": "لا يمكن اختيار عرض الآن"},
					status=status.HTTP_400_BAD_REQUEST,
				)

			old = service_request.status
			service_request.provider = offer.provider
			service_request.status = RequestStatus.NEW
			service_request.save(update_fields=["provider", "status"])
			RequestStatusLog.objects.create(
				request=service_request,
				actor=request.user,
				from_status=old,
				to_status=service_request.status,
				note="اختيار عرض وإسناد الطلب لمزود الخدمة",
			)

			Offer.objects.filter(request=service_request).exclude(id=offer.id).update(
				status=OfferStatus.REJECTED,
			)
			offer.status = OfferStatus.SELECTED
			offer.save(update_fields=["status"])

		return Response(
			{"ok": True, "request_id": service_request.id},
			status=status.HTTP_200_OK,
		)


# ────────────────────────────────────────────────
# Status transitions
# ────────────────────────────────────────────────

class RequestStartView(APIView):
	permission_classes = [permissions.IsAuthenticated, IsProviderPermission]

	def post(self, request, request_id):
		s = RequestStartSerializer(data=request.data)
		s.is_valid(raise_exception=True)
		note = s.validated_data.get("note", "")

		provider = request.user.provider_profile

		with transaction.atomic():
			sr = (
				ServiceRequest.objects.select_for_update()
				.select_related("client")
				.filter(id=request_id)
				.first()
			)

			if not sr:
				return Response({"detail": "الطلب غير موجود"}, status=status.HTTP_404_NOT_FOUND)

			if sr.provider_id != provider.id:
				return Response({"detail": "غير مصرح"}, status=status.HTTP_403_FORBIDDEN)

			if sr.status != RequestStatus.NEW:
				return Response(
					{"detail": "لا يمكن بدء التنفيذ في هذه الحالة"},
					status=status.HTTP_400_BAD_REQUEST,
				)

			old = sr.status
			sr.expected_delivery_at = s.validated_data["expected_delivery_at"]
			sr.estimated_service_amount = s.validated_data["estimated_service_amount"]
			sr.received_amount = s.validated_data["received_amount"]
			sr.remaining_amount = s.validated_data["remaining_amount"]
			sr.provider_inputs_approved = None
			sr.provider_inputs_decided_at = None
			sr.provider_inputs_decision_note = ""
			sr.save(
				update_fields=[
					"expected_delivery_at",
					"estimated_service_amount",
					"received_amount",
					"remaining_amount",
					"provider_inputs_approved",
					"provider_inputs_decided_at",
					"provider_inputs_decision_note",
				]
			)

			RequestStatusLog.objects.create(
				request=sr,
				actor=request.user,
				from_status=old,
				to_status=sr.status,
				note=note or "إرسال مدخلات التنفيذ بانتظار اعتماد العميل",
			)

		return Response(
			{"ok": True, "request_id": sr.id, "status": sr.status},
			status=status.HTTP_200_OK,
		)


class RequestCompleteView(APIView):
	permission_classes = [permissions.IsAuthenticated, IsProviderPermission]
	parser_classes = [MultiPartParser, FormParser, JSONParser]

	def post(self, request, request_id):
		s = RequestCompleteSerializer(data=request.data)
		s.is_valid(raise_exception=True)
		note = s.validated_data.get("note", "")
		attachments = s.validated_data.get("attachments", [])

		provider = request.user.provider_profile

		with transaction.atomic():
			sr = (
				ServiceRequest.objects.select_for_update()
				.select_related("client")
				.filter(id=request_id)
				.first()
			)

			if not sr:
				return Response({"detail": "الطلب غير موجود"}, status=status.HTTP_404_NOT_FOUND)

			if sr.provider_id != provider.id:
				return Response({"detail": "غير مصرح"}, status=status.HTTP_403_FORBIDDEN)

			if sr.status != RequestStatus.IN_PROGRESS:
				return Response(
					{"detail": "لا يمكن الإكمال في هذه الحالة"},
					status=status.HTTP_400_BAD_REQUEST,
				)

			old = sr.status
			sr.status = RequestStatus.COMPLETED
			sr.delivered_at = s.validated_data["delivered_at"]
			sr.actual_service_amount = s.validated_data["actual_service_amount"]
			sr.save(update_fields=["status", "delivered_at", "actual_service_amount"])

			if attachments:
				created_atts = ServiceRequestAttachment.objects.bulk_create(
					[
						ServiceRequestAttachment(
							request=sr,
							file=attachment,
							file_type=_infer_attachment_type(attachment),
						)
						for attachment in attachments
					]
				)
				from apps.uploads.tasks import schedule_video_optimization
				for att in created_atts:
					if att.file_type == "video":
						schedule_video_optimization(att, "file")

			RequestStatusLog.objects.create(
				request=sr,
				actor=request.user,
				from_status=old,
				to_status=sr.status,
				note=note or "تم الإكمال. يرجى مراجعة الطلب وتقييم الخدمة.",
			)

		return Response(
			{"ok": True, "request_id": sr.id, "status": sr.status},
			status=status.HTTP_200_OK,
		)


class RequestCancelView(APIView):
	permission_classes = [IsAtLeastClient]

	def post(self, request, request_id):
		reason = str(request.data.get("reason") or "").strip()
		try:
			result = execute_action(
				user=request.user,
				request_id=request_id,
				action="cancel",
				note=reason,
			)
		except PermissionDenied:
			return Response(
				{"detail": "غير مصرح بإلغاء الطلب"},
				status=status.HTTP_403_FORBIDDEN,
			)
		except Exception as e:
			return Response({"detail": str(e)}, status=status.HTTP_400_BAD_REQUEST)

		return Response(
			{"ok": True, "request_id": request_id, "status": result.new_status},
			status=status.HTTP_200_OK,
		)


class RequestReopenView(APIView):
	permission_classes = [IsAtLeastClient]

	def post(self, request, request_id):
		try:
			result = execute_action(
				user=request.user,
				request_id=request_id,
				action="reopen",
			)
		except PermissionDenied:
			return Response(
				{"detail": "غير مصرح بإعادة فتح الطلب"},
				status=status.HTTP_403_FORBIDDEN,
			)
		except Exception as e:
			return Response({"detail": str(e)}, status=status.HTTP_400_BAD_REQUEST)

		return Response(
			{"ok": True, "request_id": request_id, "status": result.new_status},
			status=status.HTTP_200_OK,
		)
