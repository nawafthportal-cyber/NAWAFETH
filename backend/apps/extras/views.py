from __future__ import annotations

import uuid
from django.contrib import messages
from django.http import HttpResponseForbidden
from django.shortcuts import get_object_or_404, redirect
from django.urls import reverse
from django.views import View
from rest_framework import generics
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.billing.models import PaymentAttempt
from apps.unified_requests.models import UnifiedRequest, UnifiedRequestType
from apps.unified_requests.services import upsert_unified_request

from .option_catalog import build_summary_sections
from .permissions import IsOwnerOrBackofficeExtras
from .serializers import (
    ExtraCatalogItemSerializer,
    ExtraPurchaseSerializer,
    ExtrasBundleRequestInputSerializer,
)
from .services import (
    EXTRAS_BUNDLE_INVOICE_REFERENCE_TYPE,
    EXTRAS_BUNDLE_SOURCE_MODELS,
    _extras_bundle_specialist_user,
    create_extra_purchase_checkout,
    get_extra_catalog,
)
from .models import ExtraPurchase


EXTRAS_BUNDLE_SOURCE_MODEL = "ExtrasBundleRequest"


def _resolve_bundle_payment_link_redirect(*, user, attempt):
    invoice = attempt.invoice
    checkout_url = str(getattr(attempt, "checkout_url", "") or "").strip()

    request_code = str(getattr(invoice, "reference_id", "") or "").strip()
    request_obj = (
        UnifiedRequest.objects.select_related("requester", "assigned_user", "metadata_record")
        .filter(
            request_type=UnifiedRequestType.EXTRAS,
            code=request_code,
            source_model__in=EXTRAS_BUNDLE_SOURCE_MODELS,
        )
        .order_by("-id")
        .first()
    )

    if user and getattr(user, "id", None) == invoice.user_id:
        return {
            "kind": "owner",
            "redirect_url": checkout_url or reverse("billing:mock_checkout", kwargs={"provider": attempt.provider, "attempt_id": attempt.id}),
            "request_obj": request_obj,
        }

    if user and getattr(user, "id", None) and request_obj is not None and user.id == getattr(request_obj, "requester_id", None):
        if invoice.user_id != user.id:
            invoice.user = user
            invoice.save(update_fields=["user", "updated_at"])
        return {
            "kind": "requester-owner-corrected",
            "redirect_url": checkout_url or reverse("billing:mock_checkout", kwargs={"provider": attempt.provider, "attempt_id": attempt.id}),
            "request_obj": request_obj,
        }

    if not user or not getattr(user, "id", None):
        return {
            "kind": "public",
            "redirect_url": checkout_url or reverse("billing:mock_checkout", kwargs={"provider": attempt.provider, "attempt_id": attempt.id}),
            "request_obj": request_obj,
        }

    specialist_user = _extras_bundle_specialist_user(request_obj) if request_obj is not None else None

    if request_obj is not None and (user.id == getattr(request_obj, "assigned_user_id", None) or getattr(user, "is_staff", False)):
        return {
            "kind": "public-staff",
            "redirect_url": checkout_url or reverse("billing:mock_checkout", kwargs={"provider": attempt.provider, "attempt_id": attempt.id}),
            "request_obj": request_obj,
        }

    related_non_owner_ids = {
        getattr(request_obj, "requester_id", None),
        getattr(specialist_user, "id", None),
    }
    if user.id in related_non_owner_ids:
        return {
            "kind": "public-related-non-owner",
            "redirect_url": checkout_url or reverse("billing:mock_checkout", kwargs={"provider": attempt.provider, "attempt_id": attempt.id}),
            "request_obj": request_obj,
        }

    return {
        "kind": "public-fallback",
        "request_obj": request_obj,
        "redirect_url": checkout_url or reverse("billing:mock_checkout", kwargs={"provider": attempt.provider, "attempt_id": attempt.id}),
    }


class ExtrasBundlePaymentLinkView(View):
    def get(self, request, attempt_id):
        attempt = get_object_or_404(PaymentAttempt.objects.select_related("invoice", "invoice__user"), pk=attempt_id)
        invoice = attempt.invoice

        if str(getattr(invoice, "reference_type", "") or "") != EXTRAS_BUNDLE_INVOICE_REFERENCE_TYPE:
            return HttpResponseForbidden("غير مصرح: هذا الرابط غير مخصص لطلبات الخدمات الإضافية.")

        resolution = _resolve_bundle_payment_link_redirect(
            user=request.user if getattr(request.user, "is_authenticated", False) else None,
            attempt=attempt,
        )
        notice = str(resolution.get("notice") or "").strip()
        if notice:
            messages.info(request, notice)
        redirect_url = str(resolution.get("redirect_url") or "").strip()
        if redirect_url:
            return redirect(redirect_url)
        return HttpResponseForbidden(str(resolution.get("detail") or "غير مصرح."))


def _reports_payload(group: dict) -> dict:
    start_at = group.get("start_at")
    end_at = group.get("end_at")
    return {
        "enabled": bool(group.get("enabled", False)),
        "options": list(group.get("options", [])),
        "start_at": start_at.isoformat() if start_at else "",
        "end_at": end_at.isoformat() if end_at else "",
    }


def _clients_payload(group: dict) -> dict:
    return {
        "enabled": bool(group.get("enabled", False)),
        "options": list(group.get("options", [])),
        "subscription_years": int(group.get("subscription_years", 1) or 1),
        "bulk_message_count": int(group.get("bulk_message_count", 0) or 0),
    }


def _finance_payload(group: dict) -> dict:
    return {
        "enabled": bool(group.get("enabled", False)),
        "options": list(group.get("options", [])),
        "subscription_years": int(group.get("subscription_years", 1) or 1),
        "qr_first_name": str(group.get("qr_first_name") or "").strip(),
        "qr_last_name": str(group.get("qr_last_name") or "").strip(),
        "iban": str(group.get("iban") or "").strip().replace(" ", "").upper(),
    }


def _sections_from_bundle(bundle: dict) -> list[dict]:
    sections = bundle.get("summary_sections")
    if isinstance(sections, list):
        return sections
    reports = bundle.get("reports") if isinstance(bundle.get("reports"), dict) else {}
    clients = bundle.get("clients") if isinstance(bundle.get("clients"), dict) else {}
    finance = bundle.get("finance") if isinstance(bundle.get("finance"), dict) else {}
    return build_summary_sections(reports=reports, clients=clients, finance=finance)


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

        data = ExtraPurchaseSerializer(purchase).data
        try:
            from apps.unified_requests.models import UnifiedRequest

            ur = (
                UnifiedRequest.objects.filter(
                    source_app="extras",
                    source_model="ExtraPurchase",
                    source_object_id=str(purchase.id),
                )
                .only("id", "code")
                .first()
            )
            if ur:
                data["unified_request_id"] = ur.id
                data["unified_request_code"] = ur.code
        except Exception:
            # Best-effort only; keep response backward compatible.
            pass

        return Response(data, status=status.HTTP_201_CREATED)


class CreateExtrasBundleRequestView(APIView):
    permission_classes = [IsOwnerOrBackofficeExtras]

    def post(self, request):
        serializer = ExtrasBundleRequestInputSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        validated = serializer.validated_data

        reports = _reports_payload(validated.get("reports") or {})
        clients = _clients_payload(validated.get("clients") or {})
        finance = _finance_payload(validated.get("finance") or {})
        notes = str(validated.get("notes") or "").strip()

        summary_sections = build_summary_sections(reports=reports, clients=clients, finance=finance)
        selected_titles = [section["title"] for section in summary_sections if section.get("items")]
        summary_suffix = "، ".join(selected_titles) if selected_titles else "بدون تفاصيل"
        summary = f"طلب خدمات إضافية: {summary_suffix}"

        metadata = {
            "payload_version": 1,
            "source": "mobile_web_additional_services",
            "bundle": {
                "reports": reports,
                "clients": clients,
                "finance": finance,
                "summary_sections": summary_sections,
                "notes": notes,
            },
        }

        unified_request = upsert_unified_request(
            request_type=UnifiedRequestType.EXTRAS,
            requester=request.user,
            source_app="extras",
            source_model=EXTRAS_BUNDLE_SOURCE_MODEL,
            source_object_id=uuid.uuid4().hex,
            status="new",
            priority="normal",
            summary=summary,
            metadata=metadata,
            assigned_team_code="extras",
            assigned_team_name="فريق الخدمات الإضافية",
            changed_by=request.user,
        )

        response_payload = {
            "request_id": unified_request.id,
            "request_code": unified_request.code,
            "status": unified_request.status,
            "status_label": unified_request.get_status_display(),
            "summary": unified_request.summary,
            "submitted_at": unified_request.created_at,
            "summary_sections": summary_sections,
            "notes": notes,
        }
        return Response(response_payload, status=status.HTTP_201_CREATED)


class MyExtrasBundleRequestsView(APIView):
    permission_classes = [IsOwnerOrBackofficeExtras]

    def get(self, request):
        queryset = (
            UnifiedRequest.objects.filter(
                requester=request.user,
                request_type=UnifiedRequestType.EXTRAS,
                source_app="extras",
                source_model=EXTRAS_BUNDLE_SOURCE_MODEL,
            )
            .select_related("metadata_record")
            .order_by("-id")[:30]
        )

        results: list[dict] = []
        for row in queryset:
            payload = {}
            try:
                meta_record = row.metadata_record
            except UnifiedRequest.metadata_record.RelatedObjectDoesNotExist:
                meta_record = None
            if meta_record and isinstance(meta_record.payload, dict):
                payload = meta_record.payload
            bundle = payload.get("bundle") if isinstance(payload.get("bundle"), dict) else {}
            notes = str(bundle.get("notes") or "").strip()
            results.append(
                {
                    "request_id": row.id,
                    "request_code": row.code,
                    "status": row.status,
                    "status_label": row.get_status_display(),
                    "summary": row.summary,
                    "submitted_at": row.created_at,
                    "updated_at": row.updated_at,
                    "summary_sections": _sections_from_bundle(bundle),
                    "notes": notes,
                }
            )

        return Response({"results": results}, status=status.HTTP_200_OK)
