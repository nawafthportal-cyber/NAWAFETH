from __future__ import annotations

from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.views import APIView

from django.shortcuts import get_object_or_404

from .models import SubscriptionPlan, Subscription
from .permissions import IsOwnerOrBackofficeSubscriptions
from .serializers import PlanSerializer, SubscriptionSerializer
from .services import cancel_pending_subscription_checkout, start_subscription_checkout
from .tiering import canonical_tier_order


class PlansListView(generics.ListAPIView):
    permission_classes = [IsOwnerOrBackofficeSubscriptions]
    serializer_class = PlanSerializer

    def get_queryset(self):
        plans = list(SubscriptionPlan.objects.filter(is_active=True))
        plans.sort(key=lambda plan: (canonical_tier_order(plan.normalized_tier()), plan.price, plan.id))
        return plans


class MySubscriptionsView(generics.ListAPIView):
    permission_classes = [IsOwnerOrBackofficeSubscriptions]
    serializer_class = SubscriptionSerializer

    def get_queryset(self):
        return Subscription.objects.filter(user=self.request.user).select_related("plan", "invoice").order_by("-id")


class SubscribeView(APIView):
    """
    إنشاء اشتراك + فاتورة
    """
    permission_classes = [IsOwnerOrBackofficeSubscriptions]

    def post(self, request, plan_id: int):
        plan = get_object_or_404(SubscriptionPlan, pk=plan_id, is_active=True)
        raw_duration = request.data.get("duration_count", 1)
        try:
            sub = start_subscription_checkout(
                user=request.user,
                plan=plan,
                duration_count=raw_duration,
            )
        except ValueError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        return Response(SubscriptionSerializer(sub).data, status=status.HTTP_201_CREATED)


class CancelSubscriptionCheckoutView(APIView):
    permission_classes = [IsOwnerOrBackofficeSubscriptions]

    def post(self, request, subscription_id: int):
        sub = get_object_or_404(
            Subscription.objects.select_related("plan", "invoice"),
            pk=subscription_id,
            user=request.user,
        )

        try:
            result = cancel_pending_subscription_checkout(sub=sub, changed_by=request.user)
        except ValueError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        plan_id = int(result.get("plan_id") or 0)
        redirect_url = f"/plans/summary/?plan_id={plan_id}" if plan_id > 0 else "/plans/"
        return Response(
            {
                "detail": "تم إلغاء طلب الاشتراك المعلق بنجاح.",
                "redirect_url": redirect_url,
                **result,
            },
            status=status.HTTP_200_OK,
        )
