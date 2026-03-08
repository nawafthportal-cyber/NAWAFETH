from rest_framework import generics, permissions

from .models import ExcellenceBadgeType
from .serializers import ExcellenceBadgeTypeSerializer


class ExcellenceBadgeCatalogView(generics.ListAPIView):
    permission_classes = [permissions.AllowAny]
    serializer_class = ExcellenceBadgeTypeSerializer
    queryset = ExcellenceBadgeType.objects.filter(is_active=True).order_by("sort_order", "id")
