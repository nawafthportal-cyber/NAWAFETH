from pathlib import Path

from django.core.cache import cache
from django.contrib.staticfiles import finders
from django.db import DatabaseError, OperationalError
from django.http import QueryDict
from django.http import HttpResponse
from django.views import View
from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.views import _me_payload
from apps.accounts.permissions import IsAtLeastPhoneOnly
from apps.content.services import public_content_payload
from apps.promo.views import (
    PublicActivePromosView,
    PublicHomeBannersView,
    PublicHomeCarouselView,
)
from apps.providers.views import CategoryListView, ProviderListView, ProviderSpotlightFeedView

from .unread_badges import get_unread_badges_snapshot


_DEFAULT_FAVICON_SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
<rect width="64" height="64" rx="14" fill="#673AB7"/>
<path d="M18 45V19h8l10 14 10-14h8v26h-8V31L36 45h-8L18 31v14z" fill="#ffffff"/>
</svg>
"""

_DEFAULT_ROBOTS_TXT = "User-agent: *\nAllow: /\n"
_DEFAULT_SERVICE_WORKER_JS = """self.addEventListener('install', function () {
  self.skipWaiting();
});
self.addEventListener('activate', function (event) {
  event.waitUntil(self.clients.claim());
});
"""


class UnreadBadgesView(APIView):
    permission_classes = [IsAtLeastPhoneOnly]

    def get(self, request):
        mode = request.query_params.get("mode")
        try:
            payload = get_unread_badges_snapshot(user=request.user, mode=mode)
        except (OperationalError, DatabaseError):
            return Response(
                {
                    "notifications": 0,
                    "chats": 0,
                    "mode": (mode or "shared").strip().lower() or "shared",
                    "degraded": True,
                    "stale": False,
                    "detail": "عدادات العناصر غير متاحة مؤقتًا.",
                },
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        return Response(payload, status=status.HTTP_200_OK)


class _RequestShim:
    def __init__(self, *, user, query_params, meta):
        self.user = user
        self.query_params = query_params
        self.data = {}
        self.META = meta


class HomeAggregateView(APIView):
    permission_classes = [AllowAny]

    def get(self, request):
        cache_key = self._cache_key(request)
        cached = cache.get(cache_key)
        if cached is not None:
            return Response(cached, status=status.HTTP_200_OK)

        payload = {
            "user": self._user_payload(request),
            "badges": self._badges_payload(request),
            "content": public_content_payload(),
            "categories": self._serialize_view(
                CategoryListView,
                request=request,
            ),
            "providers": self._serialize_view(
                ProviderListView,
                request=request,
                params={"page_size": str(self._bounded_int(request, "providers_limit", 10, 1, 24))},
            ),
            "home_banners": self._serialize_view(
                PublicHomeBannersView,
                request=request,
                params={"limit": str(self._bounded_int(request, "home_banners_limit", 6, 1, 20))},
            ),
            "carousel_banners": self._serialize_view(
                PublicHomeCarouselView,
                request=request,
                params={"limit": str(self._bounded_int(request, "carousel_limit", 10, 1, 20))},
            ),
            "spotlights": self._serialize_view(
                ProviderSpotlightFeedView,
                request=request,
                params={"limit": str(self._bounded_int(request, "spotlights_limit", 16, 1, 32))},
            ),
            "promos": {
                "featured_specialists": self._serialize_view(
                    PublicActivePromosView,
                    request=request,
                    params={
                        "service_type": "featured_specialists",
                        "limit": str(self._bounded_int(request, "featured_limit", 10, 1, 24)),
                    },
                ),
                "portfolio_showcase": self._serialize_view(
                    PublicActivePromosView,
                    request=request,
                    params={
                        "service_type": "portfolio_showcase",
                        "limit": str(self._bounded_int(request, "portfolio_limit", 16, 1, 32)),
                    },
                ),
                "snapshots": self._serialize_view(
                    PublicActivePromosView,
                    request=request,
                    params={
                        "service_type": "snapshots",
                        "limit": str(self._bounded_int(request, "snapshots_limit", 16, 1, 32)),
                    },
                ),
                "popup_home": self._serialize_view(
                    PublicActivePromosView,
                    request=request,
                    params={"ad_type": "popup_home", "limit": "1"},
                ),
                "promo_messages": self._serialize_view(
                    PublicActivePromosView,
                    request=request,
                    params={"service_type": "promo_messages", "limit": "1"},
                ),
            },
        }
        cache.set(cache_key, payload, self._cache_ttl(request))
        return Response(payload, status=status.HTTP_200_OK)

    def _user_payload(self, request):
        user = getattr(request, "user", None)
        if not user or not getattr(user, "is_authenticated", False):
            return None
        return _me_payload(user, request=request)

    def _badges_payload(self, request):
        user = getattr(request, "user", None)
        if not user or not getattr(user, "is_authenticated", False):
            return {
                "notifications": 0,
                "chats": 0,
                "mode": (request.query_params.get("mode") or "shared").strip().lower() or "shared",
                "degraded": False,
                "stale": False,
            }
        mode = request.query_params.get("mode")
        try:
            return get_unread_badges_snapshot(user=user, mode=mode)
        except (OperationalError, DatabaseError):
            return {
                "notifications": 0,
                "chats": 0,
                "mode": (mode or "shared").strip().lower() or "shared",
                "degraded": True,
                "stale": False,
            }

    def _serialize_view(self, view_cls, *, request, params=None):
        params = params or {}
        shim = _RequestShim(
            user=getattr(request, "user", None),
            query_params=self._query_params(params),
            meta=getattr(request, "META", {}),
        )
        view = view_cls()
        view.request = shim
        queryset = view.get_queryset() if hasattr(view, "get_queryset") else []
        serializer_class = getattr(view, "serializer_class", None)
        if serializer_class is None:
            return []
        serializer = serializer_class(queryset, many=True, context={"request": request})
        return serializer.data

    def _cache_key(self, request) -> str:
        mode = (request.query_params.get("mode") or "shared").strip().lower() or "shared"
        user_id = getattr(getattr(request, "user", None), "id", 0) or 0
        providers_limit = self._bounded_int(request, "providers_limit", 10, 1, 24)
        home_banners_limit = self._bounded_int(request, "home_banners_limit", 6, 1, 20)
        carousel_limit = self._bounded_int(request, "carousel_limit", 10, 1, 20)
        spotlights_limit = self._bounded_int(request, "spotlights_limit", 16, 1, 32)
        featured_limit = self._bounded_int(request, "featured_limit", 10, 1, 24)
        portfolio_limit = self._bounded_int(request, "portfolio_limit", 16, 1, 32)
        snapshots_limit = self._bounded_int(request, "snapshots_limit", 16, 1, 32)
        return (
            "home:aggregate:v1:"
            f"user:{user_id}:mode:{mode}:providers:{providers_limit}:"
            f"home_banners:{home_banners_limit}:carousel:{carousel_limit}:"
            f"spotlights:{spotlights_limit}:featured:{featured_limit}:"
            f"portfolio:{portfolio_limit}:snapshots:{snapshots_limit}"
        )

    def _cache_ttl(self, request) -> int:
        user = getattr(request, "user", None)
        if user and getattr(user, "is_authenticated", False):
            return 20
        return 60

    @staticmethod
    def _query_params(params) -> QueryDict:
        qd = QueryDict(mutable=True)
        for key, value in (params or {}).items():
            if value is None:
                continue
            qd[str(key)] = str(value)
        return qd

    @staticmethod
    def _bounded_int(request, key: str, default: int, minimum: int, maximum: int) -> int:
        raw = (request.query_params.get(key) or "").strip()
        try:
            return max(minimum, min(maximum, int(raw or default)))
        except (TypeError, ValueError):
            return default


class RootFaviconView(View):
    def get(self, request):
        asset_path = finders.find("icons/favicon.svg")
        if asset_path:
            content = Path(asset_path).read_text(encoding="utf-8")
            response = HttpResponse(content, content_type="image/svg+xml")
        else:
            response = HttpResponse(_DEFAULT_FAVICON_SVG, content_type="image/svg+xml")
        response["Cache-Control"] = "public, max-age=86400"
        return response


class RootRobotsTxtView(View):
    def get(self, request):
        asset_path = finders.find("robots.txt")
        if asset_path:
            content = Path(asset_path).read_text(encoding="utf-8")
            response = HttpResponse(content, content_type="text/plain; charset=utf-8")
        else:
            response = HttpResponse(_DEFAULT_ROBOTS_TXT, content_type="text/plain; charset=utf-8")
        response["Cache-Control"] = "public, max-age=3600"
        return response


class RootServiceWorkerView(View):
    def get(self, request):
        asset_path = finders.find("sw.js")
        if asset_path:
            content = Path(asset_path).read_text(encoding="utf-8")
        else:
            content = _DEFAULT_SERVICE_WORKER_JS
        response = HttpResponse(content, content_type="application/javascript; charset=utf-8")
        response["Cache-Control"] = "no-cache"
        response["Service-Worker-Allowed"] = "/"
        return response
