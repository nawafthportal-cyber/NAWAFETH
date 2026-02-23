from __future__ import annotations

from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework import generics

from .permissions import IsOwnerOrBackofficeExtras
from .serializers import ExtraCatalogItemSerializer, ExtraPurchaseSerializer
from .services import get_extra_catalog, create_extra_purchase_checkout
from .models import ExtraPurchase


class ExtrasCatalogView(APIView):
    """
    عرض كتالوج الإضافات
    """
    permission_classes = [IsOwnerOrBackofficeExtras]

    def get(self, request):
        catalog = get_extra_catalog()
        items = []
        for sku, info in catalog.items():
            items.append({
                "sku": sku,
                "title": info.get("title", sku),
                "price": info.get("price", 0),
            })
        ser = ExtraCatalogItemSerializer(items, many=True)
        return Response(ser.data, status=status.HTTP_200_OK)


class MyExtrasListView(generics.ListAPIView):
    permission_classes = [IsOwnerOrBackofficeExtras]
    serializer_class = ExtraPurchaseSerializer

    def get_queryset(self):
        return ExtraPurchase.objects.filter(user=self.request.user).order_by("-id")


class BuyExtraView(APIView):
    """
    شراء إضافة -> ينشئ purchase + invoice
    """
    permission_classes = [IsOwnerOrBackofficeExtras]

    def post(self, request, sku: str):
        try:
            purchase = create_extra_purchase_checkout(user=request.user, sku=sku)
        except ValueError as e:
            return Response({"detail": str(e)}, status=status.HTTP_400_BAD_REQUEST)

        return Response(ExtraPurchaseSerializer(purchase).data, status=status.HTTP_201_CREATED)
