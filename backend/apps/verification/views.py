from __future__ import annotations

from rest_framework import generics, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.views import APIView

from django.db.models import Prefetch, Q
from django.shortcuts import get_object_or_404
from django.utils import timezone

from apps.billing.models import InvoiceLineItem

from .models import (
    VerificationRequest,
    VerificationDocument,
    VerificationStatus,
    VerificationRequirement,
    VerificationRequirementAttachment,
)
from .serializers import (
    VerificationRequestCreateSerializer,
    VerificationRequestDetailSerializer,
    VerificationDocumentSerializer,
    VerificationDocDecisionSerializer,
    VerificationRequirementDecisionSerializer,
    VerificationRequirementAttachmentSerializer,
)
from .permissions import IsOwnerOrBackofficeVerify
from .services import (
    decide_document,
    decide_requirement,
    finalize_request_and_create_invoice,
    get_public_badge_detail,
    get_public_badges_catalog,
    mark_request_in_review,
    mirror_document_to_requirement_attachments,
    verification_pricing_for_user,
    _sync_verification_to_unified,
)


def verification_request_queryset():
    return (
        VerificationRequest.objects.select_related("requester", "assigned_to", "invoice")
        .prefetch_related(
            Prefetch(
                "documents",
                queryset=VerificationDocument.objects.order_by("id"),
            ),
            Prefetch(
                "requirements",
                queryset=VerificationRequirement.objects.order_by("sort_order", "id").prefetch_related(
                    Prefetch(
                        "attachments",
                        queryset=VerificationRequirementAttachment.objects.order_by("id"),
                    )
                ),
            ),
            Prefetch(
                "invoice__lines",
                queryset=InvoiceLineItem.objects.order_by("sort_order", "id"),
            ),
        )
    )


class VerificationRequestCreateView(generics.CreateAPIView):
    permission_classes = [IsOwnerOrBackofficeVerify]
    serializer_class = VerificationRequestCreateSerializer

    def get_serializer_context(self):
        ctx = super().get_serializer_context()
        ctx["request"] = self.request
        return ctx


class MyVerificationPricingView(APIView):
    permission_classes = [IsOwnerOrBackofficeVerify]

    def get(self, request):
        return Response(verification_pricing_for_user(request.user), status=status.HTTP_200_OK)


class MyVerificationRequestsListView(generics.ListAPIView):
    permission_classes = [IsOwnerOrBackofficeVerify]
    serializer_class = VerificationRequestDetailSerializer

    def get_queryset(self):
        return verification_request_queryset().filter(requester=self.request.user).order_by("-id")


class VerificationRequestDetailView(generics.RetrieveAPIView):
    permission_classes = [IsOwnerOrBackofficeVerify]
    serializer_class = VerificationRequestDetailSerializer
    queryset = verification_request_queryset()

    def get_object(self):
        obj = super().get_object()
        self.check_object_permissions(self.request, obj)
        return obj


class VerificationAddDocumentView(generics.CreateAPIView):
    permission_classes = [IsOwnerOrBackofficeVerify]
    parser_classes = [MultiPartParser, FormParser]
    serializer_class = VerificationDocumentSerializer

    def create(self, request, *args, **kwargs):
        vr = get_object_or_404(VerificationRequest, pk=kwargs["pk"])
        self.check_object_permissions(request, vr)

        if vr.status not in (VerificationStatus.NEW, VerificationStatus.IN_REVIEW, VerificationStatus.REJECTED):
            return Response({"detail": "لا يمكن رفع مستندات في هذه المرحلة."}, status=status.HTTP_400_BAD_REQUEST)

        file_obj = request.FILES.get("file")
        if not file_obj:
            return Response({"detail": "file مطلوب"}, status=status.HTTP_400_BAD_REQUEST)

        from django.core.exceptions import ValidationError as DjangoValidationError
        from apps.features.upload_limits import user_max_upload_mb
        from apps.uploads.validators import validate_user_file_size
        from .validators import validate_extension

        try:
            validate_extension(file_obj)
            validate_user_file_size(file_obj, user_max_upload_mb(request.user))
        except DjangoValidationError as e:
            return Response({"detail": str(e)}, status=status.HTTP_400_BAD_REQUEST)

        doc_type = (request.data.get("doc_type") or "").strip()
        title = (request.data.get("title") or "").strip()

        if not doc_type:
            return Response({"detail": "doc_type مطلوب"}, status=status.HTTP_400_BAD_REQUEST)

        doc = VerificationDocument.objects.create(
            request=vr,
            doc_type=doc_type,
            title=title[:160],
            file=file_obj,
            uploaded_by=request.user,
        )
        mirror_document_to_requirement_attachments(doc=doc)
        mark_request_in_review(vr=vr, changed_by=request.user)

        return Response(VerificationDocumentSerializer(doc).data, status=status.HTTP_201_CREATED)


class VerificationAddRequirementAttachmentView(generics.CreateAPIView):
    permission_classes = [IsOwnerOrBackofficeVerify]
    parser_classes = [MultiPartParser, FormParser]
    serializer_class = VerificationRequirementAttachmentSerializer

    def create(self, request, *args, **kwargs):
        vr = get_object_or_404(VerificationRequest, pk=kwargs["pk"])
        self.check_object_permissions(request, vr)

        if vr.status not in (VerificationStatus.NEW, VerificationStatus.IN_REVIEW, VerificationStatus.REJECTED):
            return Response({"detail": "لا يمكن رفع مرفقات في هذه المرحلة."}, status=status.HTTP_400_BAD_REQUEST)

        req = get_object_or_404(VerificationRequirement, pk=kwargs["req_id"], request=vr)

        file_obj = request.FILES.get("file")
        if not file_obj:
            return Response({"detail": "file مطلوب"}, status=status.HTTP_400_BAD_REQUEST)

        from django.core.exceptions import ValidationError as DjangoValidationError
        from apps.features.upload_limits import user_max_upload_mb
        from apps.uploads.validators import validate_user_file_size
        from .validators import validate_extension

        try:
            validate_extension(file_obj)
            validate_user_file_size(file_obj, user_max_upload_mb(request.user))
        except DjangoValidationError as e:
            return Response({"detail": str(e)}, status=status.HTTP_400_BAD_REQUEST)

        att = VerificationRequirementAttachment.objects.create(
            requirement=req,
            file=file_obj,
            uploaded_by=request.user,
        )
        mark_request_in_review(vr=vr, changed_by=request.user)

        return Response(VerificationRequirementAttachmentSerializer(att).data, status=status.HTTP_201_CREATED)


# ---------------- Backoffice ----------------

class BackofficeVerificationRequestsListView(generics.ListAPIView):
    permission_classes = [IsOwnerOrBackofficeVerify]
    serializer_class = VerificationRequestDetailSerializer

    def get_queryset(self):
        user = self.request.user
        qs = verification_request_queryset().order_by("-id")

        ap = getattr(user, "access_profile", None)
        if not ap:
            return VerificationRequest.objects.none()
        if ap and ap.level == "user":
            qs = qs.filter(Q(assigned_to=user) | Q(assigned_to__isnull=True))

        status_q = self.request.query_params.get("status")
        q = self.request.query_params.get("q")
        if status_q:
            qs = qs.filter(status=status_q)
        if q:
            qs = qs.filter(Q(code__icontains=q) | Q(requester__phone__icontains=q))

        return qs


class BackofficeVerificationAssignView(APIView):
    """تعيين طلب توثيق لموظف تشغيل (User-level scoping)."""

    permission_classes = [IsOwnerOrBackofficeVerify]

    def patch(self, request, pk: int):
        vr = get_object_or_404(VerificationRequest, pk=pk)
        self.check_object_permissions(request, vr)

        ap = getattr(request.user, "access_profile", None)

        user_id = request.data.get("assigned_to")
        try:
            user_id = int(user_id) if user_id not in (None, "") else None
        except Exception:
            return Response({"detail": "assigned_to غير صالح"}, status=status.HTTP_400_BAD_REQUEST)

        # Action-level RBAC: user-level operators can only self-assign/unassign.
        if ap and ap.level == "user":
            if user_id is not None and user_id != request.user.id:
                return Response({"detail": "لا يمكنك تعيين الطلب لمستخدم آخر."}, status=status.HTTP_403_FORBIDDEN)

        assigned_user = None
        if user_id is not None:
            from apps.accounts.models import User

            assigned_user = get_object_or_404(User, pk=user_id, is_staff=True)

        vr.assigned_to = assigned_user
        vr.assigned_at = timezone.now() if assigned_user else None
        vr.save(update_fields=["assigned_to", "assigned_at", "updated_at"])
        _sync_verification_to_unified(vr=vr, changed_by=request.user)

        vr = verification_request_queryset().get(pk=vr.pk)
        return Response(VerificationRequestDetailSerializer(vr).data, status=status.HTTP_200_OK)


class BackofficeDecideDocumentView(APIView):
    permission_classes = [IsOwnerOrBackofficeVerify]

    def patch(self, request, doc_id: int):
        doc = get_object_or_404(VerificationDocument.objects.select_related("request"), pk=doc_id)
        vr = doc.request
        self.check_object_permissions(request, vr)

        if vr.requirements.exists():
            return Response(
                {"detail": "اعتماد التوثيق يتم عبر بنود التوثيق ومرفقاتها، وليس عبر المستندات legacy."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        ser = VerificationDocDecisionSerializer(data=request.data)
        ser.is_valid(raise_exception=True)

        is_approved = ser.validated_data["is_approved"]
        note = ser.validated_data.get("decision_note", "")

        decide_document(doc=doc, is_approved=is_approved, note=note, by_user=request.user)

        return Response({"ok": True}, status=status.HTTP_200_OK)


class BackofficeDecideRequirementView(APIView):
    permission_classes = [IsOwnerOrBackofficeVerify]

    def patch(self, request, req_id: int):
        req = get_object_or_404(VerificationRequirement.objects.select_related("request"), pk=req_id)
        vr = req.request
        self.check_object_permissions(request, vr)

        ser = VerificationRequirementDecisionSerializer(data=request.data)
        ser.is_valid(raise_exception=True)

        is_approved = ser.validated_data["is_approved"]
        note = ser.validated_data.get("decision_note", "")

        decide_requirement(req=req, is_approved=is_approved, note=note, by_user=request.user)
        return Response({"ok": True}, status=status.HTTP_200_OK)


class BackofficeFinalizeRequestView(APIView):
    permission_classes = [IsOwnerOrBackofficeVerify]

    def post(self, request, pk: int):
        vr = get_object_or_404(VerificationRequest, pk=pk)
        self.check_object_permissions(request, vr)

        try:
            vr = finalize_request_and_create_invoice(vr=vr, by_user=request.user)
        except ValueError as e:
            return Response({"detail": str(e)}, status=status.HTTP_400_BAD_REQUEST)

        vr = verification_request_queryset().get(pk=vr.pk)
        return Response(VerificationRequestDetailSerializer(vr).data, status=status.HTTP_200_OK)


class PublicVerificationBadgesView(APIView):
    permission_classes = [AllowAny]

    def get(self, request):
        return Response(get_public_badges_catalog(), status=status.HTTP_200_OK)


class PublicVerificationBadgeDetailView(APIView):
    permission_classes = [AllowAny]

    def get(self, request, badge_type: str):
        detail = get_public_badge_detail(badge_type)
        if not detail:
            return Response({"detail": "badge_type غير صالح"}, status=status.HTTP_404_NOT_FOUND)
        return Response(detail, status=status.HTTP_200_OK)
