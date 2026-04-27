# =============================
# IMPORTANT: Health Endpoints
# =============================
# /api/health and /api/core/health (no DB query):
#   Use these for load balancer and uptime checks.
# /api/core/health/ready (DB + migrations):
#   Use ONLY for manual readiness checks, not for frequent polling.
# =============================
import importlib

from django.conf import settings
from django.db import connections
from django.db.utils import OperationalError
from django.db.migrations.executor import MigrationExecutor
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

        if components.get("db", {}).get("ok"):
            try:
                conn = connections["default"]
                executor = MigrationExecutor(conn)
                plan = executor.migration_plan(executor.loader.graph.leaf_nodes())
                pending = [f"{migration.app_label}.{migration.name}" for migration, _ in plan]
                if pending:
                    overall_ok = False
                    components["migrations"] = {
                        "ok": False,
                        "pending": pending,
                    }
                else:
                    components["migrations"] = {"ok": True}
            except Exception as e:
                overall_ok = False
                components["migrations"] = {"ok": False, "error": str(e)}
        else:
            components["migrations"] = {"ok": False, "skipped": True}

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
