from pathlib import Path

from django.contrib.staticfiles import finders
from django.db import DatabaseError, OperationalError
from django.http import HttpResponse
from django.views import View
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.permissions import IsAtLeastPhoneOnly

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
