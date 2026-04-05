from __future__ import annotations

from urllib.parse import quote

from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.views import APIView

from django.http import HttpResponse, HttpResponseBadRequest, HttpResponseForbidden
from django.shortcuts import get_object_or_404, redirect
from django.views import View

from .models import Invoice, PaymentAttempt, PaymentProvider
from .serializers import (
    InvoiceCreateSerializer,
    InvoiceDetailSerializer,
    InitPaymentSerializer,
    CompleteMockPaymentSerializer,
    PaymentAttemptSerializer,
)
from .permissions import IsInvoiceOwner
from .services import complete_mock_payment, init_payment, handle_webhook, sign_webhook_payload


def _safe_next_path(raw_next: str, default_path: str = "/verification/") -> str:
    value = (raw_next or "").strip()
    if value.startswith("/") and not value.startswith("//"):
        return value
    return default_path


class MockCheckoutView(View):
    """
    صفحة checkout تجريبية قابلة للفتح من المتصفح.
    - تتأكد من ملكية الفاتورة.
    - تكمل الدفع التجريبي عبر webhook mock آمن.
    - تعيد التوجيه إلى صفحة التوثيق/الوجهة المطلوبة.
    """

    def get(self, request, provider: str, attempt_id):
        normalized_provider = (provider or "").strip().lower()
        if normalized_provider != PaymentProvider.MOCK:
            return HttpResponseBadRequest("مزود الدفع غير مدعوم في صفحة checkout التجريبية.")

        attempt = get_object_or_404(
            PaymentAttempt.objects.select_related("invoice"),
            pk=attempt_id,
            provider=PaymentProvider.MOCK,
        )
        invoice = attempt.invoice

        if not request.user.is_authenticated:
            next_param = quote(request.get_full_path(), safe="/?=&%")
            return redirect(f"/login/?next={next_param}")

        if request.user.id != invoice.user_id:
            return HttpResponseForbidden("غير مصرح: لا يمكنك إتمام دفع فاتورة لا تخص حسابك.")

        next_path = _safe_next_path(request.GET.get("next"), default_path="/verification/")
        if invoice.is_payment_effective():
            sep = "&" if "?" in next_path else "?"
            return redirect(f"{next_path}{sep}payment=already_paid&invoice={invoice.code}")

        action = (request.GET.get("action") or "pay").strip().lower()
        status_value = "success"
        if action in {"cancel", "canceled", "cancelled"}:
            status_value = "cancelled"
        elif action in {"fail", "failed", "error"}:
            status_value = "failed"

        payload = {
            "provider_reference": attempt.provider_reference,
            "invoice_code": invoice.code,
            "status": status_value,
            "amount": str(invoice.total),
            "currency": invoice.currency,
        }
        event_id = f"mock-checkout-{status_value}-{attempt.id}"
        signature = sign_webhook_payload(
            provider=PaymentProvider.MOCK,
            payload=payload,
            event_id=event_id,
        )
        result = handle_webhook(
            provider=PaymentProvider.MOCK,
            payload=payload,
            signature=signature,
            event_id=event_id,
        )
        if not result.get("ok"):
            return HttpResponse(
                result.get("detail") or "تعذر إتمام عملية الدفع التجريبية.",
                status=int(result.get("http_status") or 400),
            )

        payment_flag = "success"
        if status_value == "cancelled":
            payment_flag = "cancelled"
        elif status_value == "failed":
            payment_flag = "failed"
        sep = "&" if "?" in next_path else "?"
        return redirect(f"{next_path}{sep}payment={payment_flag}&invoice={invoice.code}")


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
        payment_method = serializer.validated_data.get("payment_method") or ""

        try:
            attempt = init_payment(
                invoice=invoice,
                provider=provider,
                by_user=request.user,
                idempotency_key=idem,
                payment_method=payment_method,
            )
        except ValueError as e:
            return Response({"detail": str(e)}, status=status.HTTP_400_BAD_REQUEST)

        return Response(PaymentAttemptSerializer(attempt).data, status=status.HTTP_200_OK)


class CompleteMockPaymentView(APIView):
    """
    يكمل الدفع التجريبي (mock) لفاتورة يملكها المستخدم.
    """

    def post(self, request, pk: int):
        invoice = get_object_or_404(Invoice, pk=pk)
        if invoice.user_id != request.user.id:
            return Response({"detail": "غير مصرح"}, status=status.HTTP_403_FORBIDDEN)

        serializer = CompleteMockPaymentSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        try:
            invoice, attempt = complete_mock_payment(
                invoice=invoice,
                by_user=request.user,
                idempotency_key=serializer.validated_data.get("idempotency_key") or "",
                payment_method=serializer.validated_data.get("payment_method") or "",
            )
        except ValueError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        return Response(
            {
                "invoice": InvoiceDetailSerializer(invoice).data,
                "attempt": PaymentAttemptSerializer(attempt).data if attempt else None,
            },
            status=status.HTTP_200_OK,
        )


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
