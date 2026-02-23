from __future__ import annotations

from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.views import APIView

from django.db.models import Q
from django.shortcuts import get_object_or_404
from django.utils import timezone

from .models import VerificationRequest, VerificationDocument, VerificationStatus
from .serializers import (
    VerificationRequestCreateSerializer,
    VerificationRequestDetailSerializer,
    VerificationDocumentSerializer,
    VerificationDocDecisionSerializer,
)
from .permissions import IsOwnerOrBackofficeVerify
from .services import decide_document, finalize_request_and_create_invoice, _sync_verification_to_unified


class VerificationRequestCreateView(generics.CreateAPIView):
    permission_classes = [IsOwnerOrBackofficeVerify]
    serializer_class = VerificationRequestCreateSerializer

    def get_serializer_context(self):
        ctx = super().get_serializer_context()
        ctx["request"] = self.request
        return ctx


class MyVerificationRequestsListView(generics.ListAPIView):
    permission_classes = [IsOwnerOrBackofficeVerify]
    serializer_class = VerificationRequestDetailSerializer

    def get_queryset(self):
        return VerificationRequest.objects.filter(requester=self.request.user).order_by("-id")


class VerificationRequestDetailView(generics.RetrieveAPIView):
    permission_classes = [IsOwnerOrBackofficeVerify]
    serializer_class = VerificationRequestDetailSerializer
    queryset = VerificationRequest.objects.all()

    def get_object(self):
        obj = super().get_object()
        self.check_object_permissions(self.request, obj)
        return obj


class VerificationAddDocumentView(generics.CreateAPIView):
    permission_classes = [IsOwnerOrBackofficeVerify]
    parser_classes = [MultiPartParser, FormParser]
    serializer_class = VerificationDocumentSerializer

    def create(self, request, *args, **kwargs):
        vr = VerificationRequest.objects.get(pk=kwargs["pk"])
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

        # عند رفع جديد نعيد الطلب للمراجعة
        if vr.status == VerificationStatus.REJECTED:
            vr.status = VerificationStatus.IN_REVIEW
            vr.save(update_fields=["status", "updated_at"])
            _sync_verification_to_unified(vr=vr, changed_by=request.user)

        return Response(VerificationDocumentSerializer(doc).data, status=status.HTTP_201_CREATED)


# ---------------- Backoffice ----------------

class BackofficeVerificationRequestsListView(generics.ListAPIView):
    permission_classes = [IsOwnerOrBackofficeVerify]
    serializer_class = VerificationRequestDetailSerializer

    def get_queryset(self):
        user = self.request.user
        qs = VerificationRequest.objects.all().order_by("-id")

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
        vr = VerificationRequest.objects.get(pk=pk)
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

        return Response(VerificationRequestDetailSerializer(vr).data, status=status.HTTP_200_OK)


class BackofficeDecideDocumentView(APIView):
    permission_classes = [IsOwnerOrBackofficeVerify]

    def patch(self, request, doc_id: int):
        doc = VerificationDocument.objects.select_related("request").get(pk=doc_id)
        vr = doc.request
        self.check_object_permissions(request, vr)

        ser = VerificationDocDecisionSerializer(data=request.data)
        ser.is_valid(raise_exception=True)

        is_approved = ser.validated_data["is_approved"]
        note = ser.validated_data.get("decision_note", "")

        decide_document(doc=doc, is_approved=is_approved, note=note, by_user=request.user)

        return Response({"ok": True}, status=status.HTTP_200_OK)


class BackofficeFinalizeRequestView(APIView):
    permission_classes = [IsOwnerOrBackofficeVerify]

    def post(self, request, pk: int):
        vr = VerificationRequest.objects.get(pk=pk)
        self.check_object_permissions(request, vr)

        try:
            vr = finalize_request_and_create_invoice(vr=vr, by_user=request.user)
        except ValueError as e:
            return Response({"detail": str(e)}, status=status.HTTP_400_BAD_REQUEST)

        return Response(VerificationRequestDetailSerializer(vr).data, status=status.HTTP_200_OK)
