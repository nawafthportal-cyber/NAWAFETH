from django.db import DatabaseError, OperationalError
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.permissions import IsAtLeastPhoneOnly

from .unread_badges import get_unread_badges_snapshot


class UnreadBadgesView(APIView):
    permission_classes = [IsAtLeastPhoneOnly]

    def get(self, request):
        mode = request.query_params.get("mode")
        try:
            payload = get_unread_badges_snapshot(user=request.user, mode=mode)
        except (OperationalError, DatabaseError):
            return Response(
                {
                    "notifications": 0,
                    "chats": 0,
                    "mode": (mode or "shared").strip().lower() or "shared",
                    "degraded": True,
                    "stale": False,
                    "detail": "عدادات العناصر غير متاحة مؤقتًا.",
                },
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        return Response(payload, status=status.HTTP_200_OK)
