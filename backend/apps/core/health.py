import importlib

from django.conf import settings
from django.db import connections
from django.db.utils import OperationalError
from django.http import JsonResponse
from rest_framework.response import Response
from rest_framework.views import APIView


def healthz(_request):
    return JsonResponse({"status": "ok"})


class HealthLiveView(APIView):
    authentication_classes = []
    permission_classes = []

    def get(self, request):
        return Response({"status": "ok"})


class HealthReadyView(APIView):
    authentication_classes = []
    permission_classes = []

    def get(self, request):
        components: dict[str, object] = {}
        overall_ok = True

        # DB check
        try:
            conn = connections["default"]
            with conn.cursor() as cursor:
                cursor.execute("SELECT 1")
                cursor.fetchone()
            components["db"] = {"ok": True}
        except OperationalError as e:
            overall_ok = False
            components["db"] = {"ok": False, "error": str(e)}
        except Exception as e:
            overall_ok = False
            components["db"] = {"ok": False, "error": str(e)}

        # Redis check (only if configured)
        redis_url = getattr(settings, "REDIS_URL", "") or ""
        if redis_url:
            try:
                redis_module = importlib.import_module("redis")
                client = redis_module.Redis.from_url(redis_url)
                client.ping()
                components["redis"] = {"ok": True}
            except Exception as e:
                overall_ok = False
                components["redis"] = {"ok": False, "error": str(e)}
        else:
            components["redis"] = {"ok": True, "skipped": True}

        status_code = 200 if overall_ok else 503
        return Response(
            {
                "status": "ok" if overall_ok else "degraded",
                "components": components,
            },
            status=status_code,
        )


class HealthCheckView(HealthLiveView):
    """Backward-compatible alias for the original /health/ endpoint."""
