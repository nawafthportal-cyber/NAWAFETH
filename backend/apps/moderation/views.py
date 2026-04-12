from __future__ import annotations

from django.http import Http404
from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.backoffice.policies import ModerationAssignPolicy, ModerationResolvePolicy
from apps.core.feature_flags import moderation_center_enabled

from .models import ModerationCase
from .permissions import IsBackofficeModeration, IsModerationReporterOrBackoffice
from .serializers import (
    ModerationCaseAssignSerializer,
    ModerationCaseCreateSerializer,
    ModerationCaseDecisionWriteSerializer,
    ModerationCaseDetailSerializer,
    ModerationCaseListSerializer,
    ModerationCaseStatusSerializer,
)
from .services import assign_case, change_case_status, create_case, record_decision


class ModerationFeatureFlagMixin:
    def initial(self, request, *args, **kwargs):
        if not moderation_center_enabled():
            raise Http404
        return super().initial(request, *args, **kwargs)


class ModerationReportCreateView(ModerationFeatureFlagMixin, generics.CreateAPIView):
    permission_classes = [IsModerationReporterOrBackoffice]
    serializer_class = ModerationCaseCreateSerializer

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        case = create_case(
            reporter=request.user,
            payload=serializer.validated_data,
            request=request,
        )
        return Response(ModerationCaseDetailSerializer(case).data, status=status.HTTP_201_CREATED)


class MyModerationCasesListView(ModerationFeatureFlagMixin, generics.ListAPIView):
    permission_classes = [IsModerationReporterOrBackoffice]
    serializer_class = ModerationCaseListSerializer

    def get_queryset(self):
        return ModerationCase.objects.filter(reporter=self.request.user).select_related(
            "reporter",
            "reported_user",
            "assigned_to",
        )


class ModerationCaseDetailView(ModerationFeatureFlagMixin, generics.RetrieveAPIView):
    permission_classes = [IsModerationReporterOrBackoffice]
    serializer_class = ModerationCaseDetailSerializer
    queryset = ModerationCase.objects.select_related(
        "reporter",
        "reported_user",
        "assigned_to",
    ).prefetch_related("action_logs", "decisions")


class BackofficeModerationCasesListView(ModerationFeatureFlagMixin, generics.ListAPIView):
    permission_classes = [IsBackofficeModeration]
    serializer_class = ModerationCaseListSerializer

    def get_queryset(self):
        qs = ModerationCase.objects.select_related("reporter", "reported_user", "assigned_to").order_by("-id")
        access_profile = getattr(self.request.user, "access_profile", None)
        if not access_profile:
            return ModerationCase.objects.none()
        if access_profile.level == "user":
            qs = qs.filter(Q(assigned_to=self.request.user) | Q(assigned_to__isnull=True))
        status_q = (self.request.query_params.get("status") or "").strip()
        severity_q = (self.request.query_params.get("severity") or "").strip()
        source_q = (self.request.query_params.get("source") or "").strip()
        if status_q:
            qs = qs.filter(status=status_q)
        if severity_q:
            qs = qs.filter(severity=severity_q)
        if source_q:
            qs = qs.filter(source_app__iexact=source_q)
        return qs


class BackofficeModerationCaseDetailView(ModerationFeatureFlagMixin, generics.RetrieveAPIView):
    permission_classes = [IsBackofficeModeration]
    serializer_class = ModerationCaseDetailSerializer
    queryset = ModerationCase.objects.select_related(
        "reporter",
        "reported_user",
        "assigned_to",
    ).prefetch_related("action_logs", "decisions")


class BackofficeModerationAssignView(ModerationFeatureFlagMixin, APIView):
    permission_classes = [IsBackofficeModeration]

    def patch(self, request, pk: int):
        result = ModerationAssignPolicy.evaluate_and_log(
            request.user,
            request=request,
            reference_type="moderation.case",
            reference_id=str(pk),
            extra={"surface": "api.moderation.assign"},
        )
        if not result.allowed:
            return Response({"detail": "غير مصرح", "reason": result.reason}, status=status.HTTP_403_FORBIDDEN)
        case = get_object_or_404(ModerationCase, pk=pk)
        serializer = ModerationCaseAssignSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        case = assign_case(
            case=case,
            assigned_team_code=serializer.validated_data.get("assigned_team_code", ""),
            assigned_team_name=serializer.validated_data.get("assigned_team_name", ""),
            assigned_to_id=serializer.validated_data.get("assigned_to"),
            note=serializer.validated_data.get("note", ""),
            by_user=request.user,
            request=request,
        )
        return Response(ModerationCaseDetailSerializer(case).data, status=status.HTTP_200_OK)


class BackofficeModerationStatusView(ModerationFeatureFlagMixin, APIView):
    permission_classes = [IsBackofficeModeration]

    def patch(self, request, pk: int):
        result = ModerationResolvePolicy.evaluate_and_log(
            request.user,
            request=request,
            reference_type="moderation.case",
            reference_id=str(pk),
            extra={"surface": "api.moderation.status"},
        )
        if not result.allowed:
            return Response({"detail": "غير مصرح", "reason": result.reason}, status=status.HTTP_403_FORBIDDEN)
        case = get_object_or_404(ModerationCase, pk=pk)
        serializer = ModerationCaseStatusSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        case = change_case_status(
            case=case,
            new_status=serializer.validated_data["status"],
            note=serializer.validated_data.get("note", ""),
            by_user=request.user,
            request=request,
        )
        return Response(ModerationCaseDetailSerializer(case).data, status=status.HTTP_200_OK)


class BackofficeModerationDecisionView(ModerationFeatureFlagMixin, APIView):
    permission_classes = [IsBackofficeModeration]

    def post(self, request, pk: int):
        result = ModerationResolvePolicy.evaluate_and_log(
            request.user,
            request=request,
            reference_type="moderation.case",
            reference_id=str(pk),
            extra={"surface": "api.moderation.decision"},
        )
        if not result.allowed:
            return Response({"detail": "غير مصرح", "reason": result.reason}, status=status.HTTP_403_FORBIDDEN)
        case = get_object_or_404(ModerationCase, pk=pk)
        serializer = ModerationCaseDecisionWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        record_decision(
            case=case,
            decision_code=serializer.validated_data["decision_code"],
            note=serializer.validated_data.get("note", ""),
            outcome=serializer.validated_data.get("outcome") or {},
            is_final=serializer.validated_data.get("is_final", True),
            by_user=request.user,
            request=request,
        )
        case.refresh_from_db()
        return Response(ModerationCaseDetailSerializer(case).data, status=status.HTTP_200_OK)
