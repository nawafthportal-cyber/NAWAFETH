from __future__ import annotations

from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.views import APIView

from django.shortcuts import get_object_or_404

from .models import SubscriptionPlan, Subscription
from .permissions import IsOwnerOrBackofficeSubscriptions
from .serializers import PlanSerializer, SubscriptionSerializer
from .services import start_subscription_checkout
from .bootstrap import ensure_subscription_plans_exist


class PlansListView(generics.ListAPIView):
    permission_classes = [IsOwnerOrBackofficeSubscriptions]
    serializer_class = PlanSerializer

    def get_queryset(self):
        ensure_subscription_plans_exist()
        return SubscriptionPlan.objects.filter(is_active=True).order_by("price", "id")


class MySubscriptionsView(generics.ListAPIView):
    permission_classes = [IsOwnerOrBackofficeSubscriptions]
    serializer_class = SubscriptionSerializer

    def get_queryset(self):
        return Subscription.objects.filter(user=self.request.user).order_by("-id")


class SubscribeView(APIView):
    """
    إنشاء اشتراك + فاتورة
    """
    permission_classes = [IsOwnerOrBackofficeSubscriptions]

    def post(self, request, plan_id: int):
        plan = get_object_or_404(SubscriptionPlan, pk=plan_id, is_active=True)

        sub = start_subscription_checkout(user=request.user, plan=plan)

        return Response(SubscriptionSerializer(sub).data, status=status.HTTP_201_CREATED)
