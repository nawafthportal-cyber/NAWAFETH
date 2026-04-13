from django.shortcuts import get_object_or_404
from django.db.models import Avg, Count
from django.db.models import Q
from django.utils import timezone
from rest_framework import permissions, status, generics
from rest_framework.views import APIView
from rest_framework.response import Response

from apps.marketplace.models import ServiceRequest
from apps.messaging.models import Thread
from apps.messaging.views import _active_context_mode_from_request
from apps.providers.models import ProviderProfile
from apps.notifications.services import create_notification
from .models import Review, ReviewModerationStatus
from .services import sync_review_to_unified
from .serializers import (
	ReviewCreateSerializer, ReviewListSerializer, ProviderRatingSummarySerializer,
	ProviderReviewReplySerializer,
)

from apps.accounts.permissions import IsAtLeastClient, IsAtLeastProvider


class CreateReviewView(APIView):
	permission_classes = [IsAtLeastClient]

	def post(self, request, request_id):
		sr = get_object_or_404(ServiceRequest, id=request_id)

		s = ReviewCreateSerializer(
			data=request.data,
			context={"service_request": sr, "user": request.user},
		)
		s.is_valid(raise_exception=True)

		review = Review.objects.create(
			request=sr,
			provider=sr.provider,
			client=request.user,
			rating=s.validated_data["rating"],
			response_speed=s.validated_data.get("response_speed"),
			cost_value=s.validated_data.get("cost_value"),
			quality=s.validated_data.get("quality"),
			credibility=s.validated_data.get("credibility"),
			on_time=s.validated_data.get("on_time"),
			comment=s.validated_data.get("comment", ""),
		)
		sync_review_to_unified(review=review, changed_by=request.user, force_status="new")

		return Response(
			{"ok": True, "review_id": review.id},
			status=status.HTTP_201_CREATED
		)


class ProviderReviewsListView(generics.ListAPIView):
	permission_classes = [permissions.AllowAny]
	serializer_class = ReviewListSerializer

	def get_queryset(self):
		provider_id = self.kwargs["provider_id"]
		return (
			Review.objects.filter(
				provider_id=provider_id,
				moderation_status=ReviewModerationStatus.APPROVED,
			)
			.select_related("client")
			.order_by("-id")
		)


class ProviderReviewReplyView(APIView):
	permission_classes = [IsAtLeastProvider]

	def post(self, request, review_id):
		review = get_object_or_404(Review.objects.select_related("provider__user"), id=review_id)
		if review.provider.user_id != request.user.id:
			return Response({"detail": "غير مصرح"}, status=status.HTTP_403_FORBIDDEN)

		s = ProviderReviewReplySerializer(data=request.data)
		s.is_valid(raise_exception=True)

		now = timezone.now()
		new_reply = s.validated_data["provider_reply"]
		had_existing = bool((review.provider_reply or "").strip())
		previous_reply = (review.provider_reply or "").strip()

		is_edit = had_existing and previous_reply != new_reply
		review.provider_reply = new_reply
		if is_edit:
			review.provider_reply_edited_at = now
		elif not had_existing:
			review.provider_reply_edited_at = None
		review.provider_reply_at = now
		review.save(update_fields=["provider_reply", "provider_reply_at", "provider_reply_edited_at"])

		if review.client_id and (not had_existing or is_edit):
			create_notification(
				user=review.client,
				title="رد مقدم الخدمة على مراجعتك" if not is_edit else "تم تعديل رد مقدم الخدمة على مراجعتك",
				body=(
					"قام مقدم الخدمة بالرد على مراجعتك."
					if not is_edit
					else "قام مقدم الخدمة بتعديل رده على مراجعتك."
				),
				kind="review_reply",
				url=f"/requests/{review.request_id}/",
				actor=request.user,
				request_id=review.request_id,
				meta={
					"review_id": review.id,
					"provider_id": review.provider_id,
					"reply_action": "edit" if is_edit else "create",
				},
				pref_key="service_reply",
				audience_mode="client",
			)

		return Response(
			{
				"ok": True,
				"review_id": review.id,
				"provider_reply": review.provider_reply,
				"provider_reply_at": review.provider_reply_at,
				"provider_reply_edited_at": review.provider_reply_edited_at,
				"provider_reply_is_edited": bool(review.provider_reply_edited_at),
			},
			status=status.HTTP_200_OK,
		)

	def delete(self, request, review_id):
		review = get_object_or_404(Review.objects.select_related("provider__user", "client"), id=review_id)
		if review.provider.user_id != request.user.id:
			return Response({"detail": "غير مصرح"}, status=status.HTTP_403_FORBIDDEN)

		had_reply = bool((review.provider_reply or "").strip())
		if not had_reply:
			return Response({"detail": "لا يوجد رد لحذفه"}, status=status.HTTP_400_BAD_REQUEST)

		review.provider_reply = ""
		review.provider_reply_at = None
		review.provider_reply_edited_at = None
		review.save(update_fields=["provider_reply", "provider_reply_at", "provider_reply_edited_at"])

		if review.client_id:
			create_notification(
				user=review.client,
				title="تم حذف رد مقدم الخدمة على مراجعتك",
				body="قام مقدم الخدمة بحذف رده السابق على مراجعتك.",
				kind="review_reply",
				url=f"/requests/{review.request_id}/",
				actor=request.user,
				request_id=review.request_id,
				meta={
					"review_id": review.id,
					"provider_id": review.provider_id,
					"reply_action": "delete",
				},
				pref_key="service_reply",
				audience_mode="client",
			)

		return Response({"ok": True, "review_id": review.id}, status=status.HTTP_200_OK)


class ProviderRatingSummaryView(APIView):
	permission_classes = [permissions.AllowAny]

	def get(self, request, provider_id):
		provider = get_object_or_404(ProviderProfile, id=provider_id)
		reviews_qs = Review.objects.filter(
			provider_id=provider_id,
			moderation_status=ReviewModerationStatus.APPROVED,
		)

		# تفصيل متوسطات التقييم من جدول المراجعات (قد تكون None إذا لم تُستخدم المحاور)
		breakdown = reviews_qs.aggregate(
			rating_avg=Avg("rating"),
			rating_count=Count("id"),
			response_speed_avg=Avg("response_speed"),
			cost_value_avg=Avg("cost_value"),
			quality_avg=Avg("quality"),
			credibility_avg=Avg("credibility"),
			on_time_avg=Avg("on_time"),
		)
		distribution_raw = reviews_qs.values("rating").annotate(count=Count("id")).order_by()
		distribution = {str(i): 0 for i in range(1, 6)}
		for row in distribution_raw:
			rating_value = int(row.get("rating") or 0)
			if 1 <= rating_value <= 5:
				distribution[str(rating_value)] = int(row.get("count") or 0)

		data = {
			"provider_id": provider.id,
			"rating_avg": breakdown.get("rating_avg") or 0,
			"rating_count": int(breakdown.get("rating_count") or 0),
			"distribution": distribution,
			**breakdown,
		}
		return Response(ProviderRatingSummarySerializer(data).data, status=status.HTTP_200_OK)


class ProviderReviewLikeToggleView(APIView):
	permission_classes = [IsAtLeastProvider]

	def post(self, request, review_id):
		review = get_object_or_404(Review.objects.select_related("provider__user"), id=review_id)
		if review.provider.user_id != request.user.id:
			return Response({"detail": "غير مصرح"}, status=status.HTTP_403_FORBIDDEN)

		incoming_liked = request.data.get("liked", None)
		if incoming_liked is None:
			liked = not bool(review.provider_liked)
		else:
			liked = str(incoming_liked).strip().lower() in {"1", "true", "yes", "on"}

		review.provider_liked = liked
		review.provider_liked_at = timezone.now() if liked else None
		review.save(update_fields=["provider_liked", "provider_liked_at"])

		return Response(
			{
				"ok": True,
				"review_id": review.id,
				"provider_liked": review.provider_liked,
				"provider_liked_at": review.provider_liked_at,
			},
			status=status.HTTP_200_OK,
		)


class ProviderReviewChatThreadView(APIView):
	permission_classes = [IsAtLeastProvider]

	def post(self, request, review_id):
		review = get_object_or_404(Review.objects.select_related("provider__user", "client"), id=review_id)
		if review.provider.user_id != request.user.id:
			return Response({"detail": "غير مصرح"}, status=status.HTTP_403_FORBIDDEN)

		if not review.client_id:
			return Response({"detail": "لا يوجد عميل مرتبط بهذا التقييم"}, status=status.HTTP_400_BAD_REQUEST)

		mode = _active_context_mode_from_request(request)
		desired_mode = (
			mode
			if mode in {Thread.ContextMode.CLIENT, Thread.ContextMode.PROVIDER}
			else Thread.ContextMode.SHARED
		)

		candidates = list(
			Thread.objects.filter(is_direct=True)
			.filter(
				Q(participant_1_id=request.user.id, participant_2_id=review.client_id)
				| Q(participant_1_id=review.client_id, participant_2_id=request.user.id)
			)
			.order_by("-id")
		)
		thread = None
		for candidate in candidates:
			if candidate.participant_mode_for_user(request.user) != Thread.ContextMode.PROVIDER:
				continue
			if candidate.participant_mode_for_user(review.client) != Thread.ContextMode.CLIENT:
				continue
			thread = candidate
			break
		if thread is None:
			for candidate in candidates:
				if candidate.context_mode in [desired_mode, Thread.ContextMode.SHARED]:
					thread = candidate
					break

		if thread:
			if thread.participant_1_id == request.user.id:
				thread.set_participant_modes(
					participant_1_mode=Thread.ContextMode.PROVIDER,
					participant_2_mode=Thread.ContextMode.CLIENT,
					save=True,
				)
			else:
				thread.set_participant_modes(
					participant_1_mode=Thread.ContextMode.CLIENT,
					participant_2_mode=Thread.ContextMode.PROVIDER,
					save=True,
				)
		else:
			thread = Thread.objects.create(
				is_direct=True,
				context_mode=desired_mode,
				participant_1=request.user,
				participant_2=review.client,
				participant_1_mode=Thread.ContextMode.PROVIDER,
				participant_2_mode=Thread.ContextMode.CLIENT,
			)

		return Response(
			{
				"ok": True,
				"review_id": review.id,
				"thread_id": thread.id,
			},
			status=status.HTTP_200_OK,
		)
