from __future__ import annotations

from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.views import APIView

from django.shortcuts import get_object_or_404

from .models import Invoice
from .serializers import (
    InvoiceCreateSerializer,
    InvoiceDetailSerializer,
    InitPaymentSerializer,
    PaymentAttemptSerializer,
)
from .permissions import IsInvoiceOwner
from .services import init_payment, handle_webhook


class InvoiceCreateView(generics.CreateAPIView):
    serializer_class = InvoiceCreateSerializer

    def get_serializer_context(self):
        ctx = super().get_serializer_context()
        ctx["request"] = self.request
        return ctx


class MyInvoicesListView(generics.ListAPIView):
    serializer_class = InvoiceDetailSerializer

    def get_queryset(self):
        return Invoice.objects.filter(user=self.request.user).order_by("-id")


class InvoiceDetailView(generics.RetrieveAPIView):
    serializer_class = InvoiceDetailSerializer
    permission_classes = [IsInvoiceOwner]
    queryset = Invoice.objects.all()

    def get_object(self):
        obj = super().get_object()
        self.check_object_permissions(self.request, obj)
        return obj


class InitPaymentView(APIView):
    """
    يبدأ الدفع للفواتير (يرجع PaymentAttempt + checkout_url)
    """
    def post(self, request, pk: int):
        invoice = get_object_or_404(Invoice, pk=pk)
        if invoice.user_id != request.user.id:
            return Response({"detail": "غير مصرح"}, status=status.HTTP_403_FORBIDDEN)

        serializer = InitPaymentSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        provider = serializer.validated_data["provider"]
        idem = serializer.validated_data.get("idempotency_key") or ""

        try:
            attempt = init_payment(invoice=invoice, provider=provider, by_user=request.user, idempotency_key=idem)
        except ValueError as e:
            return Response({"detail": str(e)}, status=status.HTTP_400_BAD_REQUEST)

        return Response(PaymentAttemptSerializer(attempt).data, status=status.HTTP_200_OK)


class WebhookReceiverView(APIView):
    """
    مستقبل webhook عام:
    POST /api/billing/webhooks/<provider>/
    """
    authentication_classes = []  # webhooks غالبًا بدون JWT
    permission_classes = []

    def post(self, request, provider: str):
        payload = request.data if isinstance(request.data, dict) else {}
        signature = request.headers.get("X-Signature", "")
        event_id = request.headers.get("X-Event-Id", "")

        result = handle_webhook(provider=provider, payload=payload, signature=signature, event_id=event_id)
        http_status = int(result.pop("http_status", status.HTTP_200_OK))
        return Response(result, status=http_status)
