from __future__ import annotations

from rest_framework import generics, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.views import APIView

from django.db.models import Q, Case, When, Value, IntegerField
from django.shortcuts import get_object_or_404
from django.utils import timezone

from .models import PromoRequest, PromoAsset, PromoRequestStatus, PromoAdType
from .serializers import (
    PromoRequestCreateSerializer,
    PromoRequestDetailSerializer,
    PromoAssetSerializer,
    PromoQuoteSerializer,
    PromoRejectSerializer,
    PromoHomeBannerAssetSerializer,
    PromoActivePlacementSerializer,
)
from .permissions import IsOwnerOrBackofficePromo
from .services import quote_and_create_invoice, reject_request, _sync_promo_to_unified


def _position_rank_case(field_name: str = "position"):
    return Case(
        When(**{field_name: "first"}, then=Value(0)),
        When(**{field_name: "second"}, then=Value(1)),
        When(**{field_name: "top5"}, then=Value(2)),
        When(**{field_name: "top10"}, then=Value(3)),
        When(**{field_name: "normal"}, then=Value(4)),
        default=Value(9),
        output_field=IntegerField(),
    )


def _is_platform_banner_ad_type(ad_type: str) -> bool:
    return str(ad_type or "").strip().lower() in {
        PromoAdType.BANNER_HOME,
        PromoAdType.BANNER_CATEGORY,
        PromoAdType.BANNER_SEARCH,
    }


class PublicHomeBannersView(generics.ListAPIView):
    """Public list of active home banner assets.

    Only returns banner assets from activated promo requests managed by admin.
    """

    permission_classes = [AllowAny]
    serializer_class = PromoHomeBannerAssetSerializer
    pagination_class = None

    def get_queryset(self):
        now = timezone.now()
        qs = (
            PromoAsset.objects.select_related(
                "request",
                "request__requester",
                "request__requester__provider_profile",
            )
            .filter(
                request__status=PromoRequestStatus.ACTIVE,
                request__ad_type=PromoAdType.BANNER_HOME,
                request__start_at__lte=now,
                request__end_at__gte=now,
            )
            .annotate(
                _position_rank=_position_rank_case("request__position"),
            )
            .order_by("_position_rank", "-request__activated_at", "-uploaded_at", "-id")
        )

        limit_raw = self.request.query_params.get("limit")
        if limit_raw not in (None, ""):
            try:
                limit = int(limit_raw)
            except Exception:
                limit = 6
            limit = max(1, min(limit, 20))
            qs = qs[:limit]

        return qs


class PublicActivePromosView(generics.ListAPIView):
    """Public list of active promo placements.

    This is a generalized endpoint for all promo ad types.
    """

    permission_classes = [AllowAny]
    serializer_class = PromoActivePlacementSerializer
    pagination_class = None

    def get_queryset(self):
        now = timezone.now()
        qs = (
            PromoRequest.objects.select_related(
                "target_provider",
                "target_portfolio_item",
            )
            .prefetch_related("assets")
            .filter(
                status=PromoRequestStatus.ACTIVE,
                start_at__lte=now,
                end_at__gte=now,
            )
            .annotate(_position_rank=_position_rank_case("position"))
            .order_by("_position_rank", "-activated_at", "-id")
        )

        ad_type = (self.request.query_params.get("ad_type") or "").strip()
        if ad_type:
            qs = qs.filter(ad_type=ad_type)

        city = (self.request.query_params.get("city") or "").strip()
        if city:
            qs = qs.filter(Q(target_city__iexact=city) | Q(target_city=""))

        category = (self.request.query_params.get("category") or "").strip()
        if category:
            qs = qs.filter(Q(target_category__iexact=category) | Q(target_category=""))

        limit_raw = self.request.query_params.get("limit")
        if limit_raw not in (None, ""):
            try:
                limit = int(limit_raw)
            except Exception:
                limit = 20
            limit = max(1, min(limit, 50))
            qs = qs[:limit]

        return qs


# ---------- Client ----------

class PromoRequestCreateView(generics.CreateAPIView):
    permission_classes = [IsOwnerOrBackofficePromo]
    serializer_class = PromoRequestCreateSerializer

    def get_serializer_context(self):
        ctx = super().get_serializer_context()
        ctx["request"] = self.request
        return ctx


class MyPromoRequestsListView(generics.ListAPIView):
    permission_classes = [IsOwnerOrBackofficePromo]
    serializer_class = PromoRequestDetailSerializer

    def get_queryset(self):
        return PromoRequest.objects.filter(requester=self.request.user).order_by("-id")


class PromoRequestDetailView(generics.RetrieveAPIView):
    permission_classes = [IsOwnerOrBackofficePromo]
    serializer_class = PromoRequestDetailSerializer
    queryset = PromoRequest.objects.all()

    def get_object(self):
        obj = super().get_object()
        self.check_object_permissions(self.request, obj)
        return obj


class PromoAddAssetView(generics.CreateAPIView):
    permission_classes = [IsOwnerOrBackofficePromo]
    parser_classes = [MultiPartParser, FormParser]
    serializer_class = PromoAssetSerializer

    def create(self, request, *args, **kwargs):
        pr = PromoRequest.objects.get(pk=kwargs["pk"])
        self.check_object_permissions(request, pr)

        if pr.status not in (PromoRequestStatus.NEW, PromoRequestStatus.IN_REVIEW, PromoRequestStatus.REJECTED):
            return Response({"detail": "لا يمكن رفع مواد الإعلان في هذه المرحلة."}, status=status.HTTP_400_BAD_REQUEST)

        file_obj = request.FILES.get("file")
        if not file_obj:
            return Response({"detail": "file مطلوب"}, status=status.HTTP_400_BAD_REQUEST)

        from django.core.exceptions import ValidationError as DjangoValidationError
        from apps.features.upload_limits import user_max_upload_mb
        from apps.subscriptions.capabilities import banner_image_limit_for_user
        from apps.uploads.validators import validate_user_file_size
        from .validators import validate_extension

        if _is_platform_banner_ad_type(pr.ad_type):
            banner_limit = banner_image_limit_for_user(pr.requester)
            if pr.assets.count() >= banner_limit:
                return Response(
                    {"detail": f"الحد الأقصى لصور البانر في باقتك الحالية هو {banner_limit}."},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        try:
            validate_extension(file_obj)
            validate_user_file_size(file_obj, user_max_upload_mb(pr.requester))
        except DjangoValidationError as e:
            return Response({"detail": str(e)}, status=status.HTTP_400_BAD_REQUEST)

        asset_type = (request.data.get("asset_type") or "image").strip()
        title = (request.data.get("title") or "").strip()

        asset = PromoAsset.objects.create(
            request=pr,
            asset_type=asset_type,
            title=title[:160],
            file=file_obj,
            uploaded_by=request.user,
        )

        # عند رفع جديد بعد رفض نعيد للمراجعة
        if pr.status == PromoRequestStatus.REJECTED:
            pr.status = PromoRequestStatus.IN_REVIEW
            pr.save(update_fields=["status", "updated_at"])
            _sync_promo_to_unified(pr=pr, changed_by=request.user)

        return Response(PromoAssetSerializer(asset).data, status=status.HTTP_201_CREATED)


# ---------- Backoffice ----------

class BackofficePromoRequestsListView(generics.ListAPIView):
    permission_classes = [IsOwnerOrBackofficePromo]
    serializer_class = PromoRequestDetailSerializer

    def get_queryset(self):
        user = self.request.user
        qs = PromoRequest.objects.all().order_by("-id")

        ap = getattr(user, "access_profile", None)
        if not ap:
            return PromoRequest.objects.none()
        if ap and ap.level == "user":
            qs = qs.filter(Q(assigned_to=user) | Q(assigned_to__isnull=True))

        status_q = self.request.query_params.get("status")
        ad_type_q = self.request.query_params.get("ad_type")
        q = self.request.query_params.get("q")

        if status_q:
            qs = qs.filter(status=status_q)
        if ad_type_q:
            qs = qs.filter(ad_type=ad_type_q)
        if q:
            qs = qs.filter(Q(code__icontains=q) | Q(title__icontains=q) | Q(requester__phone__icontains=q))

        return qs


class BackofficePromoAssignView(APIView):
    """تعيين طلب إعلان لموظف تشغيل (User-level scoping)."""

    permission_classes = [IsOwnerOrBackofficePromo]

    def patch(self, request, pk: int):
        pr = get_object_or_404(PromoRequest, pk=pk)
        self.check_object_permissions(request, pr)

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

        # Only staff users can be assigned
        assigned_user = None
        if user_id is not None:
            from apps.accounts.models import User

            assigned_user = get_object_or_404(User, pk=user_id, is_staff=True)

        pr.assigned_to = assigned_user
        pr.assigned_at = timezone.now() if assigned_user else None
        pr.save(update_fields=["assigned_to", "assigned_at", "updated_at"])
        _sync_promo_to_unified(pr=pr, changed_by=request.user)

        return Response(PromoRequestDetailSerializer(pr).data, status=status.HTTP_200_OK)


class BackofficeQuoteView(APIView):
    permission_classes = [IsOwnerOrBackofficePromo]

    def post(self, request, pk: int):
        pr = get_object_or_404(PromoRequest, pk=pk)
        self.check_object_permissions(request, pr)

        ser = PromoQuoteSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        note = ser.validated_data.get("quote_note", "")

        try:
            pr = quote_and_create_invoice(pr=pr, by_user=request.user, quote_note=note)
        except ValueError as e:
            return Response({"detail": str(e)}, status=status.HTTP_400_BAD_REQUEST)

        return Response(PromoRequestDetailSerializer(pr).data, status=status.HTTP_200_OK)


class BackofficeRejectView(APIView):
    permission_classes = [IsOwnerOrBackofficePromo]

    def post(self, request, pk: int):
        pr = get_object_or_404(PromoRequest, pk=pk)
        self.check_object_permissions(request, pr)

        ser = PromoRejectSerializer(data=request.data)
        ser.is_valid(raise_exception=True)

        pr = reject_request(pr=pr, reason=ser.validated_data["reject_reason"], by_user=request.user)
        return Response(PromoRequestDetailSerializer(pr).data, status=status.HTTP_200_OK)
