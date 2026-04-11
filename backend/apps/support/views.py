from __future__ import annotations

from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.views import APIView

from django.db.models import Q

from apps.backoffice.policies import SupportAssignPolicy, SupportResolvePolicy

from .models import SupportTicket, SupportAttachment, SupportComment, SupportTeam, SupportTicketEntrypoint
from .serializers import (
    SupportTicketCreateSerializer,
    SupportTicketDetailSerializer,
    SupportTicketUpdateSerializer,
    SupportAttachmentSerializer,
    SupportCommentSerializer,
    SupportTeamSerializer,
)
from .permissions import IsRequesterOrBackofficeSupport
from .services import change_ticket_status, assign_ticket, notify_ticket_requester_about_comment


class SupportTeamListView(generics.ListAPIView):
    permission_classes = [IsRequesterOrBackofficeSupport]
    serializer_class = SupportTeamSerializer

    def get_queryset(self):
        return SupportTeam.objects.filter(is_active=True).order_by("sort_order", "id")


class SupportTicketCreateView(generics.CreateAPIView):
    permission_classes = [IsRequesterOrBackofficeSupport]
    serializer_class = SupportTicketCreateSerializer


class MySupportTicketsListView(generics.ListAPIView):
    permission_classes = [IsRequesterOrBackofficeSupport]
    serializer_class = SupportTicketDetailSerializer

    def get_queryset(self):
        user = self.request.user
        qs = SupportTicket.objects.filter(requester=user).order_by("-id")

        status_q = self.request.query_params.get("status")
        type_q = self.request.query_params.get("type")
        if status_q:
            qs = qs.filter(status=status_q)
        if type_q:
            qs = qs.filter(ticket_type=type_q)

        return qs


class SupportTicketDetailView(generics.RetrieveAPIView):
    permission_classes = [IsRequesterOrBackofficeSupport]
    serializer_class = SupportTicketDetailSerializer
    queryset = SupportTicket.objects.all()


class SupportTicketBackofficeListView(generics.ListAPIView):
    """
    قائمة تشغيل لفريق الدعم
    """
    permission_classes = [IsRequesterOrBackofficeSupport]
    serializer_class = SupportTicketDetailSerializer

    def get_queryset(self):
        user = self.request.user
        qs = SupportTicket.objects.filter(entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM).order_by("-id")

        # لو ليس admin/power: قيد على المكلّف فقط (حسب مواصفات NAWAFETH)
        ap = getattr(user, "access_profile", None)
        if not ap:
            return SupportTicket.objects.none()
        if ap and ap.level == "user":
            qs = qs.filter(Q(assigned_to=user) | Q(assigned_to__isnull=True))

        status_q = self.request.query_params.get("status")
        type_q = self.request.query_params.get("type")
        priority_q = self.request.query_params.get("priority")
        q = self.request.query_params.get("q")

        if status_q:
            qs = qs.filter(status=status_q)
        if type_q:
            qs = qs.filter(ticket_type=type_q)
        if priority_q:
            qs = qs.filter(priority=priority_q)
        if q:
            qs = qs.filter(Q(code__icontains=q) | Q(description__icontains=q))

        return qs


class SupportTicketAssignView(APIView):
    permission_classes = [IsRequesterOrBackofficeSupport]

    def patch(self, request, pk: int):
        ticket = SupportTicket.objects.get(pk=pk)
        self.check_object_permissions(request, ticket)
        policy = SupportAssignPolicy.evaluate_and_log(
            request.user,
            request=request,
            reference_type="support.ticket",
            reference_id=str(ticket.id),
            extra={"surface": "api.support.assign"},
        )
        if not policy.allowed:
            return Response({"detail": "غير مصرح", "reason": policy.reason}, status=status.HTTP_403_FORBIDDEN)

        ap = getattr(request.user, "access_profile", None)

        team_id = request.data.get("assigned_team")
        user_id = request.data.get("assigned_to")
        note = request.data.get("note", "")

        # Action-level RBAC: user-level operators can only self-assign/unassign.
        if ap and ap.level == "user":
            try:
                parsed_user_id = int(user_id) if user_id not in (None, "") else None
            except Exception:
                parsed_user_id = None

            if parsed_user_id is not None and parsed_user_id != request.user.id:
                return Response({"detail": "لا يمكنك تعيين التذكرة لمستخدم آخر."}, status=status.HTTP_403_FORBIDDEN)

        ticket = assign_ticket(
            ticket=ticket,
            team_id=team_id,
            user_id=user_id,
            by_user=request.user,
            note=note,
        )
        return Response(SupportTicketDetailSerializer(ticket).data, status=status.HTTP_200_OK)


class SupportTicketStatusView(APIView):
    permission_classes = [IsRequesterOrBackofficeSupport]

    def patch(self, request, pk: int):
        ticket = SupportTicket.objects.get(pk=pk)
        self.check_object_permissions(request, ticket)
        policy = SupportResolvePolicy.evaluate_and_log(
            request.user,
            request=request,
            reference_type="support.ticket",
            reference_id=str(ticket.id),
            extra={"surface": "api.support.status"},
        )
        if not policy.allowed:
            return Response({"detail": "غير مصرح", "reason": policy.reason}, status=status.HTTP_403_FORBIDDEN)

        new_status = request.data.get("status")
        note = request.data.get("note", "")

        if not new_status:
            return Response({"detail": "status مطلوب"}, status=status.HTTP_400_BAD_REQUEST)

        ticket = change_ticket_status(ticket=ticket, new_status=new_status, by_user=request.user, note=note)
        return Response(SupportTicketDetailSerializer(ticket).data, status=status.HTTP_200_OK)


class SupportTicketAddCommentView(generics.CreateAPIView):
    permission_classes = [IsRequesterOrBackofficeSupport]
    serializer_class = SupportCommentSerializer

    def create(self, request, *args, **kwargs):
        ticket = SupportTicket.objects.get(pk=kwargs["pk"])
        self.check_object_permissions(request, ticket)

        text = (request.data.get("text") or "").strip()
        if not text:
            return Response({"detail": "التعليق مطلوب"}, status=status.HTTP_400_BAD_REQUEST)

        is_internal = bool(request.data.get("is_internal", False))

        # العميل لا يسمح له بعمل تعليق داخلي
        if ticket.requester_id == request.user.id:
            is_internal = False

        obj = SupportComment.objects.create(
            ticket=ticket,
            text=text[:300],
            is_internal=is_internal,
            created_by=request.user,
        )
        notify_ticket_requester_about_comment(ticket=ticket, comment=obj, by_user=request.user)
        return Response(SupportCommentSerializer(obj).data, status=status.HTTP_201_CREATED)


class SupportTicketAddAttachmentView(generics.CreateAPIView):
    permission_classes = [IsRequesterOrBackofficeSupport]
    parser_classes = [MultiPartParser, FormParser]
    serializer_class = SupportAttachmentSerializer

    def create(self, request, *args, **kwargs):
        ticket = SupportTicket.objects.get(pk=kwargs["pk"])
        self.check_object_permissions(request, ticket)

        file_obj = request.FILES.get("file")
        if not file_obj:
            return Response({"detail": "file مطلوب"}, status=status.HTTP_400_BAD_REQUEST)

        from django.core.exceptions import ValidationError as DjangoValidationError
        from apps.features.upload_limits import user_max_upload_mb
        from apps.uploads.media_optimizer import optimize_upload_for_storage
        from apps.uploads.validators import validate_user_file_size
        from .validators import validate_file_size

        try:
            validate_file_size(file_obj)
            validate_user_file_size(file_obj, user_max_upload_mb(request.user))
            file_obj = optimize_upload_for_storage(file_obj)
        except DjangoValidationError as e:
            return Response({"detail": str(e)}, status=status.HTTP_400_BAD_REQUEST)

        att = SupportAttachment.objects.create(
            ticket=ticket,
            file=file_obj,
            uploaded_by=request.user,
        )
        return Response(SupportAttachmentSerializer(att).data, status=status.HTTP_201_CREATED)
