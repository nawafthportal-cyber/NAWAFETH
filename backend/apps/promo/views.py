from __future__ import annotations

from rest_framework import generics, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.views import APIView

from django.db.models import Q, Case, When, Value, IntegerField
from django.shortcuts import get_object_or_404
from django.utils import timezone

from apps.dashboard.access import dashboard_assignee_user

from .models import (
    HomeBanner,
    PromoAdType,
    PromoAsset,
    PromoPosition,
    PromoRequest,
    PromoRequestItem,
    PromoRequestStatus,
    PromoServiceType,
)
from .serializers import (
    PromoRequestCreateSerializer,
    PromoRequestDetailSerializer,
    PromoAssetSerializer,
    PromoQuoteSerializer,
    PromoRejectSerializer,
    PromoHomeBannerAssetSerializer,
    PromoActivePlacementSerializer,
    HomeBannerSerializer,
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


def _position_rank_value(position: str) -> int:
    return {
        PromoPosition.FIRST: 0,
        PromoPosition.SECOND: 1,
        PromoPosition.TOP5: 2,
        PromoPosition.TOP10: 3,
        PromoPosition.NORMAL: 4,
    }.get(str(position or "").strip().lower(), 9)


_SERVICE_TYPE_TO_LEGACY_AD_TYPES = {
    PromoServiceType.HOME_BANNER: {PromoAdType.BANNER_HOME},
    PromoServiceType.FEATURED_SPECIALISTS: {
        PromoAdType.FEATURED_TOP5,
        PromoAdType.FEATURED_TOP10,
        PromoAdType.BOOST_PROFILE,
    },
    PromoServiceType.PROMO_MESSAGES: {PromoAdType.PUSH_NOTIFICATION},
}

_LEGACY_AD_TYPE_TO_SERVICE_TYPES = {
    PromoAdType.BANNER_HOME: {PromoServiceType.HOME_BANNER},
    PromoAdType.FEATURED_TOP5: {PromoServiceType.FEATURED_SPECIALISTS},
    PromoAdType.FEATURED_TOP10: {PromoServiceType.FEATURED_SPECIALISTS},
    PromoAdType.BOOST_PROFILE: {PromoServiceType.FEATURED_SPECIALISTS},
    PromoAdType.PUSH_NOTIFICATION: {PromoServiceType.PROMO_MESSAGES},
}

_LEGACY_AD_TYPE_DEFAULT_SERVICE_TYPE = {
    PromoAdType.BANNER_HOME: PromoServiceType.HOME_BANNER,
    PromoAdType.FEATURED_TOP5: PromoServiceType.FEATURED_SPECIALISTS,
    PromoAdType.FEATURED_TOP10: PromoServiceType.FEATURED_SPECIALISTS,
    PromoAdType.BOOST_PROFILE: PromoServiceType.FEATURED_SPECIALISTS,
    PromoAdType.PUSH_NOTIFICATION: PromoServiceType.PROMO_MESSAGES,
}

_PUBLIC_ITEM_DEFERRED_FIELDS = (
    "message_sent_at",
    "message_recipients_count",
    "message_dispatch_error",
)


def _resolve_target_provider(*, promo_request: PromoRequest, item: PromoRequestItem | None = None):
    if item is not None and getattr(item, "target_provider", None) is not None:
        return item.target_provider
    if getattr(promo_request, "target_provider", None) is not None:
        return promo_request.target_provider
    try:
        return promo_request.requester.provider_profile
    except Exception:
        return None


def _resolve_target_portfolio_item(*, promo_request: PromoRequest, item: PromoRequestItem | None = None):
    if item is not None and getattr(item, "target_portfolio_item", None) is not None:
        return item.target_portfolio_item
    return getattr(promo_request, "target_portfolio_item", None)


def _resolve_assets(*, promo_request: PromoRequest, item: PromoRequestItem | None = None):
    if item is not None:
        item_assets = list(item.assets.all())
        if item_assets:
            return item_assets
        return [asset for asset in promo_request.assets.all() if getattr(asset, "item_id", None) is None]
    return list(promo_request.assets.all())


def _item_is_active_now(*, item: PromoRequestItem, now):
    if item.service_type == PromoServiceType.PROMO_MESSAGES:
        return bool(item.send_at and item.send_at <= now and item.request.end_at >= now)
    if item.start_at and item.end_at:
        return item.start_at <= now <= item.end_at
    if item.send_at:
        return item.send_at <= now
    return item.request.start_at <= now <= item.request.end_at


def _build_request_placement(pr: PromoRequest) -> dict:
    position = getattr(pr, "position", "") or PromoPosition.NORMAL
    return {
        "id": pr.id,
        "request_id": pr.id,
        "item_id": None,
        "code": pr.code or "",
        "title": pr.title or "",
        "ad_type": pr.ad_type,
        "service_type": _LEGACY_AD_TYPE_DEFAULT_SERVICE_TYPE.get(pr.ad_type, ""),
        "start_at": pr.start_at,
        "end_at": pr.end_at,
        "send_at": None,
        "frequency": pr.frequency or "",
        "position": position,
        "search_scope": "",
        "search_position": "",
        "target_category": pr.target_category or "",
        "target_city": pr.target_city or "",
        "redirect_url": pr.redirect_url or "",
        "message_title": pr.message_title or "",
        "message_body": pr.message_body or "",
        "sponsor_name": "",
        "sponsor_url": "",
        "sponsorship_months": 0,
        "attachment_specs": "",
        "target_provider": _resolve_target_provider(promo_request=pr),
        "target_portfolio_item": _resolve_target_portfolio_item(promo_request=pr),
        "assets": _resolve_assets(promo_request=pr),
        "_sort_rank": _position_rank_value(position),
        "_sort_order": 0,
        "_activated_at": pr.activated_at or pr.created_at,
    }


def _build_item_placement(item: PromoRequestItem) -> dict:
    pr = item.request
    position = item.search_position or pr.position or PromoPosition.NORMAL
    return {
        "id": item.id,
        "request_id": pr.id,
        "item_id": item.id,
        "code": pr.code or "",
        "title": item.title or pr.title or item.get_service_type_display(),
        "ad_type": pr.ad_type,
        "service_type": item.service_type,
        "start_at": item.start_at or pr.start_at,
        "end_at": item.end_at or pr.end_at,
        "send_at": item.send_at,
        "frequency": item.frequency or pr.frequency or "",
        "position": position,
        "search_scope": item.search_scope or "",
        "search_position": item.search_position or "",
        "target_category": item.target_category or pr.target_category or "",
        "target_city": item.target_city or pr.target_city or "",
        "redirect_url": item.redirect_url or pr.redirect_url or "",
        "message_title": item.message_title or pr.message_title or "",
        "message_body": item.message_body or pr.message_body or "",
        "sponsor_name": item.sponsor_name or "",
        "sponsor_url": item.sponsor_url or "",
        "sponsorship_months": int(item.sponsorship_months or 0),
        "attachment_specs": item.attachment_specs or "",
        "target_provider": _resolve_target_provider(promo_request=pr, item=item),
        "target_portfolio_item": _resolve_target_portfolio_item(promo_request=pr, item=item),
        "assets": _resolve_assets(promo_request=pr, item=item),
        "_sort_rank": _position_rank_value(position),
        "_sort_order": int(item.sort_order or 0),
        "_activated_at": pr.activated_at or pr.created_at,
    }


def _placement_matches_scope(*, placement: dict, city: str, category: str) -> bool:
    city_value = str(placement.get("target_city") or "").strip().lower()
    category_value = str(placement.get("target_category") or "").strip().lower()
    if city and city_value and city_value != city.strip().lower():
        return False
    if category and category_value and category_value != category.strip().lower():
        return False
    return True


def _public_home_banner_asset_queryset(*, now):
    return (
        PromoAsset.objects.select_related(
            "request",
            "request__requester",
            "request__requester__provider_profile",
            "request__target_provider",
            "item",
            "item__target_provider",
        )
        .defer(*(f"item__{field_name}" for field_name in _PUBLIC_ITEM_DEFERRED_FIELDS))
        .filter(
            request__status=PromoRequestStatus.ACTIVE,
        )
        .filter(
            Q(
                request__ad_type=PromoAdType.BANNER_HOME,
                request__start_at__lte=now,
                request__end_at__gte=now,
            )
            | Q(
                request__ad_type=PromoAdType.BUNDLE,
                item__service_type=PromoServiceType.HOME_BANNER,
                item__start_at__lte=now,
                item__end_at__gte=now,
            )
        )
        .annotate(
            _position_rank=_position_rank_case("request__position"),
        )
        .order_by("_position_rank", "item__sort_order", "-request__activated_at", "-uploaded_at", "-id")
    )


def _public_active_bundle_item_queryset():
    return (
        PromoRequestItem.objects.select_related(
            "request",
            "request__requester",
            "request__requester__provider_profile",
            "request__target_provider",
            "request__target_portfolio_item",
            "target_provider",
            "target_portfolio_item",
        )
        .prefetch_related("assets", "request__assets")
        .defer(*_PUBLIC_ITEM_DEFERRED_FIELDS)
        .filter(
            request__status=PromoRequestStatus.ACTIVE,
            request__ad_type=PromoAdType.BUNDLE,
        )
    )


class PublicHomeBannersView(generics.ListAPIView):
    """Public list of active home banner assets.

    Only returns banner assets from activated promo requests managed by admin.
    """

    permission_classes = [AllowAny]
    serializer_class = PromoHomeBannerAssetSerializer
    pagination_class = None

    def get_queryset(self):
        now = timezone.now()
        qs = _public_home_banner_asset_queryset(now=now)

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
        ad_type = (self.request.query_params.get("ad_type") or "").strip()
        service_type = (self.request.query_params.get("service_type") or "").strip()
        city = (self.request.query_params.get("city") or "").strip()
        category = (self.request.query_params.get("category") or "").strip()

        request_qs = (
            PromoRequest.objects.select_related(
                "requester",
                "requester__provider_profile",
                "target_provider",
                "target_portfolio_item",
            )
            .prefetch_related("assets")
            .filter(
                status=PromoRequestStatus.ACTIVE,
                start_at__lte=now,
                end_at__gte=now,
            )
        )

        legacy_types = None
        if service_type:
            legacy_types = _SERVICE_TYPE_TO_LEGACY_AD_TYPES.get(service_type, set())
        if ad_type:
            request_qs = request_qs.filter(ad_type=ad_type)
            if legacy_types is not None and ad_type not in legacy_types:
                request_qs = request_qs.none()
        elif legacy_types is not None:
            request_qs = request_qs.filter(ad_type__in=legacy_types) if legacy_types else request_qs.none()

        item_qs = _public_active_bundle_item_queryset()
        compatible_item_service_types = None
        if ad_type:
            compatible_item_service_types = _LEGACY_AD_TYPE_TO_SERVICE_TYPES.get(ad_type, set())
        if service_type:
            item_qs = item_qs.filter(service_type=service_type)
            if compatible_item_service_types is not None and service_type not in compatible_item_service_types:
                item_qs = item_qs.none()
        elif compatible_item_service_types is not None:
            item_qs = item_qs.filter(service_type__in=compatible_item_service_types) if compatible_item_service_types else item_qs.none()

        placements = []
        for request_obj in request_qs:
            placement = _build_request_placement(request_obj)
            if _placement_matches_scope(placement=placement, city=city, category=category):
                placements.append(placement)

        for item in item_qs:
            if not _item_is_active_now(item=item, now=now):
                continue
            placement = _build_item_placement(item)
            if _placement_matches_scope(placement=placement, city=city, category=category):
                placements.append(placement)

        placements.sort(
            key=lambda row: (
                int(row.get("_sort_rank", 9)),
                -(row.get("_activated_at").timestamp() if row.get("_activated_at") else 0),
                int(row.get("_sort_order", 0)),
                -int(row.get("id", 0)),
            )
        )

        limit_raw = self.request.query_params.get("limit")
        if limit_raw not in (None, ""):
            try:
                limit = int(limit_raw)
            except Exception:
                limit = 20
            limit = max(1, min(limit, 50))
            placements = placements[:limit]

        return placements


class PublicHomeCarouselView(generics.ListAPIView):
    """Public list of dashboard-managed homepage carousel banners.

    Returns active banners within their scheduled date range,
    ordered by display_order. Supports images and short videos.
    """

    permission_classes = [AllowAny]
    serializer_class = HomeBannerSerializer
    pagination_class = None

    def get_queryset(self):
        now = timezone.now()
        qs = HomeBanner.objects.select_related("provider").filter(is_active=True)
        qs = qs.filter(
            Q(start_at__isnull=True) | Q(start_at__lte=now),
            Q(end_at__isnull=True) | Q(end_at__gte=now),
        )
        limit_raw = self.request.query_params.get("limit")
        if limit_raw not in (None, ""):
            try:
                limit = max(1, min(int(limit_raw), 20))
            except Exception:
                limit = 10
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

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        if not serializer.is_valid():
            import logging
            logging.getLogger("apps.promo").warning(
                "PromoRequest create validation failed user=%s errors=%s data=%s",
                request.user.id,
                serializer.errors,
                {k: v for k, v in request.data.items() if k != "password"} if hasattr(request.data, "items") else str(request.data)[:500],
            )
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        return super().create(request, *args, **kwargs)


class MyPromoRequestsListView(generics.ListAPIView):
    permission_classes = [IsOwnerOrBackofficePromo]
    serializer_class = PromoRequestDetailSerializer

    def get_queryset(self):
        return PromoRequest.objects.filter(requester=self.request.user).prefetch_related("items", "items__assets", "assets").order_by("-id")


class PromoRequestDetailView(generics.RetrieveAPIView):
    permission_classes = [IsOwnerOrBackofficePromo]
    serializer_class = PromoRequestDetailSerializer
    queryset = PromoRequest.objects.prefetch_related("items", "items__assets", "assets").all()

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

        item = None
        item_id = request.data.get("item_id")
        if item_id not in (None, ""):
            try:
                item = PromoRequestItem.objects.get(id=int(item_id), request=pr)
            except Exception:
                return Response({"detail": "item_id غير صحيح"}, status=status.HTTP_400_BAD_REQUEST)
        elif pr.items.count() == 1:
            item = pr.items.first()

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
            item=item,
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
        qs = PromoRequest.objects.prefetch_related("items").all().order_by("-id")

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
            assigned_user = dashboard_assignee_user(user_id, "promo", write=True)
            if assigned_user is None:
                return Response({"detail": "assigned_to غير صالح لهذه اللوحة"}, status=status.HTTP_400_BAD_REQUEST)

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
