from __future__ import annotations

import logging
import posixpath
import uuid
from importlib import import_module
from pathlib import Path

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.files.uploadedfile import SimpleUploadedFile
from django.utils.decorators import method_decorator
from django.views.decorators.cache import cache_page

from rest_framework import generics, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.views import APIView

from django.db.models import Q, Case, When, Value, IntegerField
from django.shortcuts import get_object_or_404
from django.utils import timezone
from apps.uploads.media_optimizer import optimize_upload_for_storage

from apps.backoffice.policies import PromoQuoteActivatePolicy
from apps.dashboard.access import dashboard_assignee_user

from .models import (
    HomeBanner,
    PromoAdType,
    PromoAsset,
    PromoPosition,
    PromoPricingRule,
    PromoRequest,
    PromoRequestItem,
    PromoRequestStatus,
    PromoSearchScope,
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
from .home_banner_media import (
    maybe_autofit_home_banner_image as _maybe_autofit_home_banner_image,
    maybe_autofit_home_banner_video as _maybe_autofit_home_banner_video,
    transcode_home_banner_video_to_required_dims as _transcode_home_banner_video_to_required_dims,
)
from .services import (
    preview_promo_request,
    quote_and_create_invoice,
    reject_request,
    discard_incomplete_promo_request,
    ensure_default_pricing_rules,
    promo_min_campaign_hours,
    _sync_promo_to_unified,
)
from .validators import (
    promo_asset_upload_limit_mb,
    promo_asset_upload_limits_payload,
    validate_home_banner_media_dimensions,
)

logger = logging.getLogger("apps.promo")
PUBLIC_PROMO_CACHE_SECONDS = max(
    15,
    int(getattr(settings, "PROMO_PUBLIC_ENDPOINT_CACHE_SECONDS", 60) or 60),
)
PROMO_DIRECT_UPLOAD_EXPIRES_SECONDS = max(
    60,
    min(int(getattr(settings, "PROMO_DIRECT_UPLOAD_EXPIRES_SECONDS", 900) or 900), 3600),
)
PROMO_DIRECT_UPLOAD_SIGN_CONTENT_TYPE = bool(
    getattr(settings, "PROMO_DIRECT_UPLOAD_SIGN_CONTENT_TYPE", False)
)


class _UploadDescriptor:
    def __init__(self, *, name: str, size: int, content_type: str = ""):
        self.name = str(name or "")
        self.size = int(size or 0)
        self.content_type = str(content_type or "")


def _promo_direct_upload_storage_ready() -> bool:
    if not bool(getattr(settings, "USE_R2_MEDIA", False)):
        return False
    bucket = str(getattr(settings, "AWS_STORAGE_BUCKET_NAME", "") or "").strip()
    endpoint = str(getattr(settings, "AWS_S3_ENDPOINT_URL", "") or "").strip()
    access_key = str(getattr(settings, "AWS_ACCESS_KEY_ID", "") or "").strip()
    secret_key = str(getattr(settings, "AWS_SECRET_ACCESS_KEY", "") or "").strip()
    if not all([bucket, endpoint, access_key, secret_key]):
        return False
    default_backend = ""
    try:
        default_backend = str((getattr(settings, "STORAGES", {}) or {}).get("default", {}).get("BACKEND", "") or "")
    except Exception:
        default_backend = ""
    return default_backend == "storages.backends.s3.S3Storage"


def _promo_build_s3_client():
    boto3 = import_module("boto3")
    BotoConfig = import_module("botocore.config").Config
    return boto3.client(
        "s3",
        endpoint_url=str(getattr(settings, "AWS_S3_ENDPOINT_URL", "") or "").strip(),
        aws_access_key_id=str(getattr(settings, "AWS_ACCESS_KEY_ID", "") or "").strip(),
        aws_secret_access_key=str(getattr(settings, "AWS_SECRET_ACCESS_KEY", "") or "").strip(),
        region_name=str(getattr(settings, "AWS_S3_REGION_NAME", "auto") or "auto").strip(),
        config=BotoConfig(
            signature_version=str(getattr(settings, "AWS_S3_SIGNATURE_VERSION", "s3v4") or "s3v4").strip(),
            s3={"addressing_style": str(getattr(settings, "AWS_S3_ADDRESSING_STYLE", "path") or "path").strip()},
            connect_timeout=5,
            read_timeout=20,
            retries={"max_attempts": 2, "mode": "standard"},
        ),
    )


def _promo_safe_upload_ext(file_name: str) -> str:
    return Path(str(file_name or "").strip()).suffix.lower()


def _promo_upload_is_video(*, file_obj, asset_type: str) -> bool:
    if str(asset_type or "").strip().lower() == "video":
        return True
    content_type = str(getattr(file_obj, "content_type", "") or "").strip().lower()
    if content_type.startswith("video/"):
        return True
    return _promo_safe_upload_ext(str(getattr(file_obj, "name", "") or "")) in {".mp4", ".mov", ".avi", ".mkv", ".webm"}


def _promo_guess_content_type(*, file_name: str, asset_type: str, fallback: str) -> str:
    inferred = str(fallback or "").strip().lower()
    if inferred:
        return inferred
    ext = _promo_safe_upload_ext(file_name)
    if ext in {".jpg", ".jpeg"}:
        return "image/jpeg"
    if ext == ".png":
        return "image/png"
    if ext == ".gif":
        return "image/gif"
    if ext == ".mp4":
        return "video/mp4"
    if ext == ".pdf":
        return "application/pdf"
    if str(asset_type or "").strip().lower() == "video":
        return "video/mp4"
    if str(asset_type or "").strip().lower() == "image":
        return "image/jpeg"
    return "application/octet-stream"


def _promo_build_direct_upload_key(*, promo_request: PromoRequest, item: PromoRequestItem | None, user_id: int, file_name: str) -> str:
    now = timezone.now()
    ext = _promo_safe_upload_ext(file_name)
    item_marker = f"item-{int(getattr(item, 'id', 0) or 0)}" if item is not None else "item-0"
    return posixpath.join(
        "promo",
        "assets",
        f"{now:%Y}",
        f"{now:%m}",
        f"req-{int(promo_request.id)}",
        f"user-{int(user_id)}",
        item_marker,
        f"{uuid.uuid4().hex}{ext}",
    )


def _promo_delete_object_quietly(*, client, bucket: str, key: str):
    try:
        client.delete_object(Bucket=bucket, Key=key)
    except Exception:
        pass


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


def _requires_home_banner_dimensions_validation(pr: PromoRequest, item: PromoRequestItem | None) -> bool:
    if item is not None and str(getattr(item, "service_type", "") or "").strip() == PromoServiceType.HOME_BANNER:
        return True
    return str(getattr(pr, "ad_type", "") or "").strip() == PromoAdType.BANNER_HOME


def _parse_multi_query_param(query_params, key: str) -> list[str]:
    values: list[str] = []
    raw_values = []
    try:
        raw_values = list(query_params.getlist(key))
    except Exception:
        raw_single = query_params.get(key)
        if raw_single not in (None, ""):
            raw_values = [raw_single]
    for raw in raw_values:
        for part in str(raw or "").split(","):
            token = str(part or "").strip()
            if token:
                values.append(token)
    return list(dict.fromkeys(values))


_SERVICE_TYPE_TO_LEGACY_AD_TYPES = {
    PromoServiceType.HOME_BANNER: {PromoAdType.BANNER_HOME},
    PromoServiceType.FEATURED_SPECIALISTS: {
        PromoAdType.FEATURED_TOP5,
        PromoAdType.FEATURED_TOP10,
        PromoAdType.BOOST_PROFILE,
    },
}

_LEGACY_AD_TYPE_TO_SERVICE_TYPES = {
    PromoAdType.BANNER_HOME: {PromoServiceType.HOME_BANNER},
    PromoAdType.FEATURED_TOP5: {PromoServiceType.FEATURED_SPECIALISTS},
    PromoAdType.FEATURED_TOP10: {PromoServiceType.FEATURED_SPECIALISTS},
    PromoAdType.BOOST_PROFILE: {PromoServiceType.FEATURED_SPECIALISTS},
}

_LEGACY_AD_TYPE_DEFAULT_SERVICE_TYPE = {
    PromoAdType.BANNER_HOME: PromoServiceType.HOME_BANNER,
    PromoAdType.FEATURED_TOP5: PromoServiceType.FEATURED_SPECIALISTS,
    PromoAdType.FEATURED_TOP10: PromoServiceType.FEATURED_SPECIALISTS,
    PromoAdType.BOOST_PROFILE: PromoServiceType.FEATURED_SPECIALISTS,
}

_PUBLIC_ITEM_DEFERRED_FIELDS = (
    "message_sent_at",
    "message_recipients_count",
    "message_dispatch_error",
)

# Ops completion can happen while campaign window is still running.
# Keep completed-in-ops requests publicly visible until their schedule ends.
_PUBLIC_VISIBLE_REQUEST_STATUSES = (
    PromoRequestStatus.ACTIVE,
    PromoRequestStatus.COMPLETED,
)

_PRICING_SERVICE_ORDER = (
    PromoServiceType.HOME_BANNER,
    PromoServiceType.FEATURED_SPECIALISTS,
    PromoServiceType.PORTFOLIO_SHOWCASE,
    PromoServiceType.SNAPSHOTS,
    PromoServiceType.SEARCH_RESULTS,
    PromoServiceType.PROMO_MESSAGES,
    PromoServiceType.SPONSORSHIP,
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


def _resolve_target_spotlight_item(*, promo_request: PromoRequest, item: PromoRequestItem | None = None):
    if item is not None and getattr(item, "target_spotlight_item", None) is not None:
        return item.target_spotlight_item
    return getattr(promo_request, "target_spotlight_item", None)


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
    service_type = _LEGACY_AD_TYPE_DEFAULT_SERVICE_TYPE.get(pr.ad_type, "")
    return {
        "id": pr.id,
        "request_id": pr.id,
        "item_id": None,
        "code": pr.code or "",
        "title": pr.title or "",
        "ad_type": pr.ad_type,
        "service_type": service_type,
        "start_at": pr.start_at,
        "end_at": pr.end_at,
        "send_at": None,
        "position": position,
        "search_scope": "",
        "search_position": "",
        "target_category": pr.target_category or "",
        "target_city": "" if service_type == PromoServiceType.SEARCH_RESULTS else (pr.target_city or ""),
        "redirect_url": pr.redirect_url or "",
        "message_title": pr.message_title or "",
        "message_body": pr.message_body or "",
        "sponsor_name": "",
        "sponsor_url": "",
        "sponsorship_months": 0,
        "attachment_specs": "",
        "target_provider": _resolve_target_provider(promo_request=pr),
        "target_portfolio_item": _resolve_target_portfolio_item(promo_request=pr),
        "target_spotlight_item": _resolve_target_spotlight_item(promo_request=pr),
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
        "position": position,
        "search_scope": item.search_scope or "",
        "search_position": item.search_position or "",
        "target_category": item.target_category or pr.target_category or "",
        "target_city": "" if item.service_type == PromoServiceType.SEARCH_RESULTS else (item.target_city or pr.target_city or ""),
        "redirect_url": item.redirect_url or pr.redirect_url or "",
        "message_title": item.message_title or pr.message_title or "",
        "message_body": item.message_body or pr.message_body or "",
        "sponsor_name": item.sponsor_name or "",
        "sponsor_url": item.sponsor_url or "",
        "sponsorship_months": int(item.sponsorship_months or 0),
        "attachment_specs": item.attachment_specs or "",
        "target_provider": _resolve_target_provider(promo_request=pr, item=item),
        "target_portfolio_item": _resolve_target_portfolio_item(promo_request=pr, item=item),
        "target_spotlight_item": _resolve_target_spotlight_item(promo_request=pr, item=item),
        "assets": _resolve_assets(promo_request=pr, item=item),
        "_sort_rank": _position_rank_value(position),
        "_sort_order": int(item.sort_order or 0),
        "_activated_at": pr.activated_at or pr.created_at,
    }


def _placement_matches_scope(*, placement: dict, city: str, category: str) -> bool:
    service_type = str(placement.get("service_type") or "").strip()
    city_value = str(placement.get("target_city") or "").strip().lower()
    category_value = str(placement.get("target_category") or "").strip().lower()
    if service_type != PromoServiceType.SEARCH_RESULTS and city and city_value and city_value != city.strip().lower():
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
            request__status__in=_PUBLIC_VISIBLE_REQUEST_STATUSES,
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
            "request__target_spotlight_item",
            "target_provider",
            "target_portfolio_item",
            "target_spotlight_item",
        )
        .prefetch_related("assets", "request__assets")
        .defer(*_PUBLIC_ITEM_DEFERRED_FIELDS)
        .filter(
            request__status__in=_PUBLIC_VISIBLE_REQUEST_STATUSES,
            request__ad_type=PromoAdType.BUNDLE,
        )
    )


@method_decorator(cache_page(PUBLIC_PROMO_CACHE_SECONDS), name="dispatch")
class PublicHomeBannersView(generics.ListAPIView):
    """Public list of active home banner assets.

    Only returns banner assets from activated promo requests managed by admin.
    """

    authentication_classes = []
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


@method_decorator(cache_page(PUBLIC_PROMO_CACHE_SECONDS), name="dispatch")
class PublicActivePromosView(generics.ListAPIView):
    """Public list of active promo placements.

    This is a generalized endpoint for all promo ad types.
    """

    authentication_classes = []
    permission_classes = [AllowAny]
    serializer_class = PromoActivePlacementSerializer
    pagination_class = None

    def get_queryset(self):
        now = timezone.now()
        ad_type = (self.request.query_params.get("ad_type") or "").strip()
        service_type = (self.request.query_params.get("service_type") or "").strip()
        city = (self.request.query_params.get("city") or "").strip()
        category = (self.request.query_params.get("category") or "").strip()
        requested_search_scopes = _parse_multi_query_param(self.request.query_params, "search_scope")
        search_scope_filter = {
            scope for scope in requested_search_scopes if scope in set(PromoSearchScope.values)
        }

        request_qs = (
            PromoRequest.objects.select_related(
                "requester",
                "requester__provider_profile",
                "target_provider",
                "target_portfolio_item",
            )
            .prefetch_related("assets")
            .filter(
                status__in=_PUBLIC_VISIBLE_REQUEST_STATUSES,
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
        elif service_type:
            # Request-level placements only exist for legacy ad types that map directly
            # to a public service type. Item-based services such as sponsorship must not
            # leak their parent bundle request into the filtered response.
            request_qs = request_qs.none()

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
            if (
                search_scope_filter
                and placement.get("service_type") == PromoServiceType.SEARCH_RESULTS
                and str(placement.get("search_scope") or "").strip() not in search_scope_filter
            ):
                continue
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


@method_decorator(cache_page(PUBLIC_PROMO_CACHE_SECONDS), name="dispatch")
class PublicHomeCarouselView(generics.ListAPIView):
    """Public list of dashboard-managed homepage carousel banners.

    Returns active banners within their scheduled date range,
    ordered by display_order. Supports images and short videos.
    """

    authentication_classes = []
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


class PromoRequestPreviewView(APIView):
    permission_classes = [IsOwnerOrBackofficePromo]

    def post(self, request):
        serializer = PromoRequestCreateSerializer(data=request.data, context={"request": request})
        if not serializer.is_valid():
            import logging

            logging.getLogger("apps.promo").warning(
                "PromoRequest preview validation failed user=%s errors=%s data=%s",
                request.user.id,
                serializer.errors,
                {k: v for k, v in request.data.items() if k != "password"}
                if hasattr(request.data, "items")
                else str(request.data)[:500],
            )
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        try:
            payload = preview_promo_request(
                requester=request.user,
                validated_data=serializer.validated_data,
            )
        except ValueError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return Response(payload, status=status.HTTP_200_OK)


@method_decorator(cache_page(PUBLIC_PROMO_CACHE_SECONDS), name="dispatch")
class PromoPricingGuideView(APIView):
    permission_classes = [AllowAny]

    def get(self, request):
        ensure_default_pricing_rules()
        service_labels = dict(PromoServiceType.choices)
        grouped: dict[str, list[dict]] = {}

        rules = (
            PromoPricingRule.objects.filter(is_active=True)
            .order_by("sort_order", "id")
        )
        for rule in rules:
            display_key = (
                (rule.get_search_position_display() if rule.search_position else "")
                or (rule.get_message_channel_display() if rule.message_channel else "")
                or rule.title
            )
            grouped.setdefault(rule.service_type, []).append(
                {
                    "id": rule.id,
                    "code": rule.code,
                    "title": rule.title,
                    "display_key": display_key,
                    "amount": f"{rule.amount:.2f}",
                    "unit": rule.unit,
                    "unit_label": rule.get_unit_display(),
                    "search_position": rule.search_position or "",
                    "search_position_label": rule.get_search_position_display() if rule.search_position else "",
                    "message_channel": rule.message_channel or "",
                    "message_channel_label": rule.get_message_channel_display() if rule.message_channel else "",
                }
            )

        ordered_service_types: list[str] = list(_PRICING_SERVICE_ORDER)
        for service_type in grouped.keys():
            if service_type not in ordered_service_types:
                ordered_service_types.append(service_type)

        services_payload = [
            {
                "service_type": service_type,
                "service_label": service_labels.get(service_type, service_type),
                "rules": grouped.get(service_type, []),
            }
            for service_type in ordered_service_types
        ]

        return Response(
            {
                "generated_at": timezone.now().isoformat(),
                "currency": "SAR",
                "currency_label": "ريال سعودي",
                "min_campaign_hours": promo_min_campaign_hours(),
                "asset_upload_limits_mb": promo_asset_upload_limits_payload(),
                "service_order": ordered_service_types,
                "services": services_payload,
            },
            status=status.HTTP_200_OK,
        )


class MyPromoRequestsListView(generics.ListAPIView):
    permission_classes = [IsOwnerOrBackofficePromo]
    serializer_class = PromoRequestDetailSerializer

    def get_queryset(self):
        return (
            PromoRequest.objects.select_related("requester", "requester__provider_profile", "invoice")
            .filter(requester=self.request.user)
            .prefetch_related("items", "items__assets", "assets")
            .order_by("-updated_at", "-id")
        )


class PromoRequestDetailView(generics.RetrieveAPIView):
    permission_classes = [IsOwnerOrBackofficePromo]
    serializer_class = PromoRequestDetailSerializer
    queryset = PromoRequest.objects.select_related("requester", "requester__provider_profile", "invoice").prefetch_related("items", "items__assets", "assets").all()

    def get_object(self):
        obj = super().get_object()
        self.check_object_permissions(self.request, obj)
        return obj


class PromoRequestDiscardView(APIView):
    permission_classes = [IsOwnerOrBackofficePromo]

    def delete(self, request, pk: int):
        pr = get_object_or_404(PromoRequest.objects.select_related("invoice"), pk=pk)
        self.check_object_permissions(request, pr)
        reason = str(request.data.get("reason") or request.query_params.get("reason") or "manual_discard").strip()[:120]

        deleted = discard_incomplete_promo_request(
            pr=pr,
            by_user=request.user,
            reason=reason,
        )
        if not deleted:
            return Response(
                {"detail": "لا يمكن حذف هذا الطلب لأنه مكتمل أو مرتبط بدفع معتمد."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        return Response(
            {"detail": "تم حذف الطلب غير المكتمل بنجاح."},
            status=status.HTTP_200_OK,
        )


class _PromoAssetUploadContextMixin:
    _ALLOWED_UPLOAD_STATUSES = (
        PromoRequestStatus.NEW,
        PromoRequestStatus.IN_REVIEW,
        PromoRequestStatus.REJECTED,
    )

    def _get_promo_request_for_upload(self, request, *, pk: int):
        pr = get_object_or_404(PromoRequest.objects.prefetch_related("items"), pk=pk)
        self.check_object_permissions(request, pr)
        if pr.status not in self._ALLOWED_UPLOAD_STATUSES:
            return None, Response(
                {"detail": "لا يمكن رفع مواد الإعلان في هذه المرحلة."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        return pr, None

    def _resolve_upload_item(self, request, *, promo_request: PromoRequest):
        item_id_raw = str(request.data.get("item_id") or "").strip()
        if item_id_raw:
            try:
                item_id = int(item_id_raw)
            except (TypeError, ValueError):
                return None, Response(
                    {"detail": "معرف بند الخدمة غير صالح."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            item = PromoRequestItem.objects.filter(id=item_id, request=promo_request).first()
            if item is None:
                return None, Response(
                    {"detail": "بند الخدمة المحدد غير موجود أو لا يتبع هذا الطلب."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            return item, None

        request_items = list(promo_request.items.all())
        if len(request_items) == 1:
            return request_items[0], None
        return None, Response(
            {
                "detail": (
                    "يجب اختيار بند الخدمة قبل رفع المرفق. "
                    "هذا الطلب يحتوي على خدمات متعددة، وكل مرفق يجب أن يُربط ببند محدد."
                )
            },
            status=status.HTTP_400_BAD_REQUEST,
        )

    def _ensure_item_upload_capacity(self, *, promo_request: PromoRequest, item: PromoRequestItem):
        if not _is_platform_banner_ad_type(promo_request.ad_type):
            return None
        if item.service_type != PromoServiceType.HOME_BANNER:
            return None
        from apps.subscriptions.capabilities import banner_image_limit_for_user

        banner_limit = banner_image_limit_for_user(promo_request.requester)
        item_asset_count = item.assets.count()
        if item_asset_count >= banner_limit:
            return Response(
                {
                    "detail": (
                        f"تم الوصول إلى الحد الأقصى لمرفقات بند "
                        f"\"{item.get_service_type_display()}\" في باقتك الحالية ({banner_limit})."
                    )
                },
                status=status.HTTP_400_BAD_REQUEST,
            )
        return None

    def _normalized_asset_type(self, request) -> str:
        return str(request.data.get("asset_type") or "image").strip().lower()

    def _validate_descriptor_limits(self, *, file_obj, promo_request: PromoRequest, item: PromoRequestItem, asset_type: str):
        from apps.uploads.validators import validate_user_file_size
        from .validators import validate_extension

        requires_home_banner_dims = _requires_home_banner_dimensions_validation(promo_request, item)
        effective_upload_limit_mb = promo_asset_upload_limit_mb(
            asset_type=asset_type,
            requires_home_banner_dims=requires_home_banner_dims,
        )
        validate_extension(file_obj)
        validate_user_file_size(file_obj, effective_upload_limit_mb)
        return requires_home_banner_dims, effective_upload_limit_mb


class PromoAssetDirectUploadInitView(_PromoAssetUploadContextMixin, APIView):
    permission_classes = [IsOwnerOrBackofficePromo]

    def post(self, request, pk: int):
        if not _promo_direct_upload_storage_ready():
            return Response(
                {"detail": "الرفع المباشر غير متاح حالياً على بيئة التخزين."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        promo_request, error_response = self._get_promo_request_for_upload(request, pk=pk)
        if error_response is not None:
            return error_response

        item, error_response = self._resolve_upload_item(request, promo_request=promo_request)
        if error_response is not None:
            return error_response

        capacity_error = self._ensure_item_upload_capacity(promo_request=promo_request, item=item)
        if capacity_error is not None:
            return capacity_error

        asset_type = self._normalized_asset_type(request)
        file_name = str(request.data.get("file_name") or "").strip()
        if not file_name:
            return Response(
                {"detail": "اسم الملف مطلوب لتهيئة الرفع المباشر."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            file_size = int(request.data.get("file_size") or 0)
        except Exception:
            file_size = 0
        file_size = max(0, file_size)
        content_type = _promo_guess_content_type(
            file_name=file_name,
            asset_type=asset_type,
            fallback=str(request.data.get("content_type") or ""),
        )
        descriptor = _UploadDescriptor(
            name=file_name,
            size=file_size,
            content_type=content_type,
        )
        try:
            self._validate_descriptor_limits(
                file_obj=descriptor,
                promo_request=promo_request,
                item=item,
                asset_type=asset_type,
            )
        except ValidationError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        bucket = str(getattr(settings, "AWS_STORAGE_BUCKET_NAME", "") or "").strip()
        object_key = _promo_build_direct_upload_key(
            promo_request=promo_request,
            item=item,
            user_id=int(getattr(request.user, "id", 0) or 0),
            file_name=file_name,
        )

        try:
            s3_client = _promo_build_s3_client()
            put_params = {"Bucket": bucket, "Key": object_key}
            if PROMO_DIRECT_UPLOAD_SIGN_CONTENT_TYPE and content_type:
                put_params["ContentType"] = content_type
            presigned_url = s3_client.generate_presigned_url(
                "put_object",
                Params=put_params,
                ExpiresIn=PROMO_DIRECT_UPLOAD_EXPIRES_SECONDS,
                HttpMethod="PUT",
            )
        except Exception as exc:
            logger.exception("promo_direct_upload_init_failed request_id=%s error=%s", getattr(request, "request_id", "-"), exc)
            return Response(
                {"detail": "تعذر تجهيز رابط رفع مباشر حالياً. حاول مرة أخرى."},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )

        upload_headers = (
            {"Content-Type": content_type}
            if PROMO_DIRECT_UPLOAD_SIGN_CONTENT_TYPE and content_type
            else {}
        )
        return Response(
            {
                "upload": {
                    "method": "PUT",
                    "url": presigned_url,
                    "headers": upload_headers,
                    "object_key": object_key,
                    "expires_in": PROMO_DIRECT_UPLOAD_EXPIRES_SECONDS,
                },
                "item_id": int(item.id),
                "asset_type": asset_type,
            },
            status=status.HTTP_200_OK,
        )


class PromoAssetDirectUploadCompleteView(_PromoAssetUploadContextMixin, APIView):
    permission_classes = [IsOwnerOrBackofficePromo]

    def post(self, request, pk: int):
        if not _promo_direct_upload_storage_ready():
            return Response(
                {"detail": "الرفع المباشر غير متاح حالياً على بيئة التخزين."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        promo_request, error_response = self._get_promo_request_for_upload(request, pk=pk)
        if error_response is not None:
            return error_response

        item, error_response = self._resolve_upload_item(request, promo_request=promo_request)
        if error_response is not None:
            return error_response

        capacity_error = self._ensure_item_upload_capacity(promo_request=promo_request, item=item)
        if capacity_error is not None:
            return capacity_error

        asset_type = self._normalized_asset_type(request)
        object_key = str(request.data.get("object_key") or request.data.get("key") or "").strip()
        if not object_key:
            return Response({"detail": "مفتاح الملف المرفوع غير موجود."}, status=status.HTTP_400_BAD_REQUEST)
        if not object_key.startswith("promo/assets/"):
            return Response({"detail": "مسار الملف المرفوع غير صالح."}, status=status.HTTP_400_BAD_REQUEST)
        expected_request_marker = f"/req-{int(promo_request.id)}/"
        expected_user_marker = f"/user-{int(getattr(request.user, 'id', 0) or 0)}/"
        if expected_request_marker not in object_key or expected_user_marker not in object_key:
            return Response({"detail": "الملف المرفوع لا يطابق هذا الطلب."}, status=status.HTTP_400_BAD_REQUEST)

        bucket = str(getattr(settings, "AWS_STORAGE_BUCKET_NAME", "") or "").strip()
        s3_client = None
        delete_on_validation_failure = False
        try:
            s3_client = _promo_build_s3_client()
            head = s3_client.head_object(Bucket=bucket, Key=object_key)
            delete_on_validation_failure = True
        except Exception:
            return Response(
                {"detail": "تعذر التحقق من الملف المرفوع. حاول إعادة الرفع."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        file_size = int(head.get("ContentLength") or 0)
        content_type = str(head.get("ContentType") or request.data.get("content_type") or "")
        descriptor = _UploadDescriptor(
            name=Path(object_key).name,
            size=file_size,
            content_type=content_type,
        )
        effective_upload_limit_mb = 0
        try:
            requires_home_banner_dims, effective_upload_limit_mb = self._validate_descriptor_limits(
                file_obj=descriptor,
                promo_request=promo_request,
                item=item,
                asset_type=asset_type,
            )
            if requires_home_banner_dims and asset_type in {"image", "video"}:
                max_validation_bytes = int(
                    max(
                        1,
                        min(
                            int(getattr(settings, "PROMO_DIRECT_UPLOAD_DIMENSION_CHECK_MAX_MB", 30) or 30),
                            100,
                        ),
                    )
                    * 1024
                    * 1024
                )
                if file_size > max_validation_bytes:
                    raise ValidationError(
                        "تعذر التحقق من أبعاد الملف المرفوع لأن حجمه كبير جدًا للمعالجة الآمنة. "
                        "يرجى رفع ملف بالأبعاد المعتمدة 1920x840 وحجم أصغر."
                    )
                obj = s3_client.get_object(Bucket=bucket, Key=object_key)
                body = obj.get("Body")
                payload = body.read(max_validation_bytes + 1)
                try:
                    body.close()
                except Exception:
                    pass
                if len(payload) > max_validation_bytes:
                    raise ValidationError(
                        "تعذر التحقق من أبعاد الملف المرفوع لأن حجمه يتجاوز حد الفحص الآمن."
                    )
                uploaded = SimpleUploadedFile(
                    Path(object_key).name,
                    payload,
                    content_type=content_type or "application/octet-stream",
                )
                validate_home_banner_media_dimensions(uploaded, asset_type=asset_type)
            title = str(request.data.get("title") or "").strip()[:160]
        except ValidationError as exc:
            if delete_on_validation_failure and s3_client is not None:
                _promo_delete_object_quietly(client=s3_client, bucket=bucket, key=object_key)
            logger.warning(
                "promo_direct_upload_validation_failed request_id=%s user_id=%s promo_id=%s item_id=%s "
                "asset_type=%s object_key=%s file_size=%s upload_limit_mb=%s error=%s",
                getattr(request, "request_id", "-"),
                getattr(request.user, "id", None),
                promo_request.id,
                getattr(item, "id", None),
                asset_type,
                object_key,
                file_size,
                int(effective_upload_limit_mb or 0),
                str(exc),
            )
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        except Exception as exc:
            if delete_on_validation_failure and s3_client is not None:
                _promo_delete_object_quietly(client=s3_client, bucket=bucket, key=object_key)
            logger.exception(
                "promo_direct_upload_finalize_failed request_id=%s promo_id=%s item_id=%s object_key=%s error=%s",
                getattr(request, "request_id", "-"),
                promo_request.id,
                getattr(item, "id", None),
                object_key,
                exc,
            )
            return Response(
                {"detail": "تعذر إكمال التحقق من الملف المرفوع. حاول مرة أخرى."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        asset = PromoAsset.objects.create(
            request=promo_request,
            item=item,
            asset_type=asset_type,
            title=title,
            file=object_key,
            uploaded_by=request.user,
        )
        serializer = PromoAssetSerializer(asset)
        return Response(
            {
                "detail": f"تم حفظ المرفق وربطه ببند الخدمة: {item.get_service_type_display()}",
                "asset": serializer.data,
            },
            status=status.HTTP_201_CREATED,
        )


class PromoAddAssetView(_PromoAssetUploadContextMixin, generics.CreateAPIView):
    permission_classes = [IsOwnerOrBackofficePromo]
    parser_classes = [MultiPartParser, FormParser]
    serializer_class = PromoAssetSerializer

    def create(self, request, *args, **kwargs):
        pr, error_response = self._get_promo_request_for_upload(request, pk=kwargs["pk"])
        if error_response is not None:
            return error_response

        from apps.uploads.validators import validate_user_file_size

        file_obj = request.FILES.get("file")
        if not file_obj:
            return Response(
                {"detail": "يرجى اختيار ملف قبل الرفع."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        asset_type = self._normalized_asset_type(request)
        if _promo_upload_is_video(file_obj=file_obj, asset_type=asset_type):
            return Response(
                {
                    "detail": (
                        "رفع فيديوهات الترويج عبر هذا المسار غير مسموح. "
                        "يجب استخدام الرفع المباشر إلى التخزين السحابي."
                    ),
                    "error_code": "direct_upload_required_for_video",
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        item, error_response = self._resolve_upload_item(request, promo_request=pr)
        if error_response is not None:
            return error_response
        capacity_error = self._ensure_item_upload_capacity(promo_request=pr, item=item)
        if capacity_error is not None:
            return capacity_error

        try:
            requires_home_banner_dims, effective_upload_limit_mb = self._validate_descriptor_limits(
                file_obj=file_obj,
                promo_request=pr,
                item=item,
                asset_type=asset_type,
            )
            file_obj = _maybe_autofit_home_banner_image(
                file_obj,
                asset_type=asset_type,
                required_validation=requires_home_banner_dims,
            )
            file_obj = _maybe_autofit_home_banner_video(
                file_obj,
                asset_type=asset_type,
                required_validation=requires_home_banner_dims,
            )
            if requires_home_banner_dims:
                validate_user_file_size(file_obj, effective_upload_limit_mb)
                validate_home_banner_media_dimensions(file_obj, asset_type=asset_type)
            # Home-banner videos already pass through strict normalization/validation.
            # Skip generic optimizer to avoid a second ffmpeg pass in request lifecycle.
            if not (requires_home_banner_dims and asset_type == "video"):
                file_obj = optimize_upload_for_storage(file_obj, declared_type=asset_type)
            if requires_home_banner_dims:
                validate_home_banner_media_dimensions(file_obj, asset_type=asset_type)
        except ValidationError as exc:
            logger.warning(
                "promo_asset_upload_validation_failed request_id=%s user_id=%s promo_id=%s item_id=%s "
                "asset_type=%s file_name=%s content_type=%s file_size=%s upload_limit_mb=%s error=%s",
                getattr(request, "request_id", "-"),
                getattr(request.user, "id", None),
                pr.id,
                getattr(item, "id", None),
                asset_type,
                str(getattr(file_obj, "name", "") or ""),
                str(getattr(file_obj, "content_type", "") or ""),
                int(getattr(file_obj, "size", 0) or 0),
                int(effective_upload_limit_mb),
                str(exc),
            )
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        title = (request.data.get("title") or "").strip()

        asset = PromoAsset.objects.create(
            request=pr,
            item=item,
            asset_type=asset_type,
            title=title[:160],
            file=file_obj,
            uploaded_by=request.user,
        )

        serializer = self.get_serializer(asset)
        return Response(
            {
                "detail": f"تم رفع المرفق وربطه ببند الخدمة: {item.get_service_type_display()}",
                "asset": serializer.data,
            },
            status=status.HTTP_201_CREATED,
        )


class PromoPreparePaymentView(APIView):
    permission_classes = [IsOwnerOrBackofficePromo]

    def post(self, request, pk: int):
        pr = get_object_or_404(
            PromoRequest.objects.prefetch_related("items", "assets", "items__assets"),
            pk=pk,
        )
        self.check_object_permissions(request, pr)

        if pr.status in (
            PromoRequestStatus.CANCELLED,
            PromoRequestStatus.COMPLETED,
            PromoRequestStatus.EXPIRED,
        ):
            return Response(
                {"detail": "لا يمكن تجهيز الدفع لهذا الطلب في حالته الحالية."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        invoice = getattr(pr, "invoice", None)
        if invoice is not None and invoice.is_payment_effective():
            return Response(PromoRequestDetailSerializer(pr).data, status=status.HTTP_200_OK)

        note = str(request.data.get("quote_note") or "").strip()
        try:
            pr = quote_and_create_invoice(pr=pr, by_user=request.user, quote_note=note)
        except ValueError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        return Response(PromoRequestDetailSerializer(pr).data, status=status.HTTP_200_OK)
# ---------- Backoffice ----------

class BackofficePromoRequestsListView(generics.ListAPIView):
    permission_classes = [IsOwnerOrBackofficePromo]
    serializer_class = PromoRequestDetailSerializer

    def get_queryset(self):
        user = self.request.user
        qs = PromoRequest.objects.prefetch_related("items").all().order_by("-updated_at", "-id")

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
        policy = PromoQuoteActivatePolicy.evaluate_and_log(
            request.user,
            request=request,
            reference_type="promo.request",
            reference_id=str(pr.id),
            extra={"surface": "api.promo.quote"},
        )
        if not policy.allowed:
            return Response({"detail": "غير مصرح", "reason": policy.reason}, status=status.HTTP_403_FORBIDDEN)

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
