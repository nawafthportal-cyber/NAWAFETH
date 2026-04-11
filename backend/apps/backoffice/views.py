from __future__ import annotations

from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status

from .bootstrap import ensure_backoffice_access_catalog
from .models import Dashboard
from .serializers import DashboardSerializer, MyAccessSerializer
from .permissions import BackofficeAccessPermission


class DashboardsListView(APIView):
    permission_classes = [BackofficeAccessPermission]

    def get(self, request):
        ensure_backoffice_access_catalog()
        qs = Dashboard.objects.filter(is_active=True).order_by("sort_order", "id")
        return Response(DashboardSerializer(qs, many=True).data, status=status.HTTP_200_OK)


class MyAccessView(APIView):
    permission_classes = [BackofficeAccessPermission]

    def get(self, request):
        ensure_backoffice_access_catalog()
        access_profile = request.user.access_profile
        return Response(MyAccessSerializer(access_profile).data, status=status.HTTP_200_OK)
