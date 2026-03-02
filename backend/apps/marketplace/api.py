"""
DRF API views for the marketplace app.

These endpoints serve the Flutter mobile app (JSON responses).
Django template views remain in views.py.
"""
from datetime import timedelta
import logging

from django.conf import settings
from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from django.core.exceptions import PermissionDenied
from django.shortcuts import get_object_or_404
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.providers.models import ProviderCategory, ProviderProfile
from apps.notifications.models import EventType
from apps.notifications.services import create_notification

from apps.accounts.permissions import IsAtLeastClient

from .models import (
	Offer,
	OfferStatus,
	RequestStatus,
	RequestStatusLog,
	RequestType,
	ServiceRequest,
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

from .views import (
	_normalize_status_group,
	_status_group_to_statuses,
	_expire_urgent_requests,
)


logger = logging.getLogger(__name__)


# ────────────────────────────────────────────────
# Helpers (internal to API layer)
# ────────────────────────────────────────────────

def _notify_urgent_request_to_matching_providers(service_request: ServiceRequest) -> None:
	if service_request.request_type != RequestType.URGENT:
		return

	provider_ids = ProviderCategory.objects.filter(
		subcategory_id=service_request.subcategory_id
	).values_list("provider_id", flat=True)

	qs = ProviderProfile.objects.select_related("user").filter(
		id__in=provider_ids,
		accepts_urgent=True,
	)
	city = (service_request.city or "").strip()
	if city:
		qs = qs.filter(city=city)

	for provider in qs:
		if not provider.user_id:
			continue
		create_notification(
			user=provider.user,
			title="طلب خدمة عاجلة جديد",
			body=f"يوجد طلب عاجل جديد في تخصصك: {service_request.title}",
			kind="urgent_request",
			url=f"/requests/{service_request.id}",
			actor=service_request.client,
			event_type=EventType.REQUEST_CREATED,
			pref_key="urgent_request",
			request_id=service_request.id,
			is_urgent=True,
			audience_mode="provider",
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

		expires_at = None
		if is_urgent:
			minutes = getattr(settings, "URGENT_REQUEST_EXPIRY_MINUTES", 15)
			expires_at = timezone.now() + timedelta(minutes=minutes)

		service_request = serializer.save(
			client=self.request.user,
			is_urgent=is_urgent,
			status=status_value,
			expires_at=expires_at,
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
			_notify_urgent_request_to_matching_providers(service_request)


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

			now = timezone.now()
			if service_request.expires_at and service_request.expires_at < now:
				service_request.status = RequestStatus.CANCELLED
				service_request.save(update_fields=["status"])
				return Response(
					{"detail": "انتهت صلاحية الطلب"},
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
			if (service_request.city or "").strip() and (provider.city or "").strip() and service_request.city.strip() != provider.city.strip():
				return Response(
					{"detail": "هذا الطلب خارج نطاق مدينتك"},
					status=status.HTTP_403_FORBIDDEN,
				)
			if not ProviderCategory.objects.filter(provider=provider, subcategory_id=service_request.subcategory_id).exists():
				return Response(
					{"detail": "هذا الطلب لا يطابق تخصصاتك"},
					status=status.HTTP_403_FORBIDDEN,
				)

			old = service_request.status
			service_request.provider = provider
			service_request.status = RequestStatus.IN_PROGRESS
			service_request.save(update_fields=["provider", "status"])
			RequestStatusLog.objects.create(
				request=service_request,
				actor=request.user,
				from_status=old,
				to_status=service_request.status,
				note="قبول طلب عاجل من المزود",
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

		provider_subcats = ProviderCategory.objects.filter(provider=provider).values_list(
			"subcategory_id",
			flat=True,
		)

		now = timezone.now()

		qs = (
			ServiceRequest.objects.select_related("client", "subcategory", "subcategory__category")
			.filter(
				request_type=RequestType.URGENT,
				provider__isnull=True,
				status=RequestStatus.NEW,
				subcategory_id__in=provider_subcats,
			)
			.filter(Q(city=provider.city) | Q(city=""))
			.exclude(expires_at__isnull=False, expires_at__lt=now)
			.order_by("-created_at")
		)

		if not provider.accepts_urgent:
			return ServiceRequest.objects.none()

		return qs


class AvailableCompetitiveRequestsView(generics.ListAPIView):
	permission_classes = [permissions.IsAuthenticated, IsProviderPermission]
	serializer_class = ServiceRequestListSerializer

	def get_queryset(self):
		provider = self.request.user.provider_profile

		provider_subcats = ProviderCategory.objects.filter(provider=provider).values_list(
			"subcategory_id",
			flat=True,
		)

		return (
			ServiceRequest.objects.select_related("client", "subcategory", "subcategory__category")
			.filter(
				request_type=RequestType.COMPETITIVE,
				provider__isnull=True,
				status=RequestStatus.NEW,
				subcategory_id__in=provider_subcats,
			)
			.filter(Q(city=provider.city) | Q(city=""))
			.order_by("-created_at")
		)


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

		if (obj.city or "").strip() and (provider.city or "").strip() and obj.city.strip() != provider.city.strip():
			raise PermissionDenied("غير مصرح")

		if not ProviderCategory.objects.filter(
			provider=provider,
			subcategory_id=obj.subcategory_id,
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
				sr.status = RequestStatus.IN_PROGRESS
				sr.save(update_fields=["status"])
				RequestStatusLog.objects.create(
					request=sr,
					actor=request.user,
					from_status=old,
					to_status=sr.status,
					note="قبول من المزود",
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
			sr.status = RequestStatus.CANCELLED
			sr.canceled_at = canceled_at
			sr.cancel_reason = cancel_reason
			sr.save(update_fields=["status", "canceled_at", "cancel_reason"])
			RequestStatusLog.objects.create(
				request=sr,
				actor=request.user,
				from_status=old,
				to_status=sr.status,
				note=note or f"إلغاء من المزود: {cancel_reason}",
			)

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

			if sr.status != RequestStatus.IN_PROGRESS:
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

			if update_fields:
				sr.save(update_fields=update_fields)

			RequestStatusLog.objects.create(
				request=sr,
				actor=request.user,
				from_status=sr.status,
				to_status=sr.status,
				note=note or "تحديث من مزود الخدمة",
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

		if (service_request.city or "").strip() and (provider.city or "").strip() and service_request.city.strip() != provider.city.strip():
			return Response(
				{"detail": "هذا الطلب خارج نطاق مدينتك"},
				status=status.HTTP_403_FORBIDDEN,
			)
		if not ProviderCategory.objects.filter(provider=provider, subcategory_id=service_request.subcategory_id).exists():
			return Response(
				{"detail": "هذا الطلب لا يطابق تخصصاتك"},
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

			if sr.status not in (RequestStatus.NEW, RequestStatus.IN_PROGRESS):
				return Response(
					{"detail": "لا يمكن بدء التنفيذ في هذه الحالة"},
					status=status.HTTP_400_BAD_REQUEST,
				)

			old = sr.status
			sr.status = RequestStatus.IN_PROGRESS
			sr.expected_delivery_at = s.validated_data["expected_delivery_at"]
			sr.estimated_service_amount = s.validated_data["estimated_service_amount"]
			sr.received_amount = s.validated_data["received_amount"]
			sr.remaining_amount = s.validated_data["remaining_amount"]
			sr.provider_inputs_approved = None
			sr.provider_inputs_decided_at = None
			sr.provider_inputs_decision_note = ""
			sr.save(
				update_fields=[
					"status",
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

	def post(self, request, request_id):
		s = RequestCompleteSerializer(data=request.data)
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
		try:
			result = execute_action(
				user=request.user,
				request_id=request_id,
				action="cancel",
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
