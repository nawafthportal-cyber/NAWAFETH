from django.shortcuts import get_object_or_404
from django.db.models import Avg
from django.utils import timezone
from rest_framework import permissions, status, generics
from rest_framework.views import APIView
from rest_framework.response import Response

from apps.marketplace.models import ServiceRequest
from apps.providers.models import ProviderProfile
from apps.notifications.services import create_notification
from .models import Review, ReviewModerationStatus
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
				audience_mode="client",
			)

		return Response({"ok": True, "review_id": review.id}, status=status.HTTP_200_OK)


class ProviderRatingSummaryView(APIView):
	permission_classes = [permissions.AllowAny]

	def get(self, request, provider_id):
		provider = get_object_or_404(ProviderProfile, id=provider_id)

		# تفصيل متوسطات التقييم من جدول المراجعات (قد تكون None إذا لم تُستخدم المحاور)
		breakdown = Review.objects.filter(
			provider_id=provider_id,
			moderation_status=ReviewModerationStatus.APPROVED,
		).aggregate(
			response_speed_avg=Avg("response_speed"),
			cost_value_avg=Avg("cost_value"),
			quality_avg=Avg("quality"),
			credibility_avg=Avg("credibility"),
			on_time_avg=Avg("on_time"),
		)

		data = {
			"provider_id": provider.id,
			"rating_avg": provider.rating_avg,
			"rating_count": provider.rating_count,
			**breakdown,
		}
		return Response(ProviderRatingSummarySerializer(data).data, status=status.HTTP_200_OK)
