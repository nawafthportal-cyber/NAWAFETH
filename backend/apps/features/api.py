from __future__ import annotations

from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status

from .checks import has_feature
from .upload_limits import user_max_upload_mb
from apps.subscriptions.capabilities import plan_capabilities_for_user


class MyFeaturesView(APIView):
    def get(self, request):
        user = request.user
        capabilities = plan_capabilities_for_user(user)
        data = {
            "verify_blue": has_feature(user, "verify_blue"),
            "verify_green": has_feature(user, "verify_green"),
            "promo_ads": has_feature(user, "promo_ads"),
            "priority_support": has_feature(user, "priority_support"),
            "max_upload_mb": user_max_upload_mb(user),
            "current_tier": capabilities["tier"],
            "current_tier_label": capabilities["tier_label"],
            "capabilities": capabilities,
        }
        return Response(data, status=status.HTTP_200_OK)
