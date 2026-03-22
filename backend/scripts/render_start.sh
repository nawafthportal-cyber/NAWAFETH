#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

export DJANGO_ENV="${DJANGO_ENV:-prod}"
PORT_VALUE="${PORT:-8000}"
WEB_CONCURRENCY_VALUE="${WEB_CONCURRENCY:-2}"
LOG_LEVEL_VALUE="${GUNICORN_LOG_LEVEL:-info}"
TIMEOUT_VALUE="${GUNICORN_TIMEOUT:-60}"

# Render should open the public port as quickly as possible. Heavy startup work
# such as migrations and collectstatic is expected to happen in pre-deploy/build
# stages. The start script keeps optional fallbacks, but they are disabled by
# default so startup stays deterministic and avoids port-scan timeouts.
RUN_MIGRATIONS_ON_START="${RUN_MIGRATIONS_ON_START:-0}"
RUN_COLLECTSTATIC_ON_START="${RUN_COLLECTSTATIC_ON_START:-0}"
MIGRATION_TIMEOUT_SECONDS="${MIGRATION_TIMEOUT_SECONDS:-180}"
COLLECTSTATIC_TIMEOUT_SECONDS="${COLLECTSTATIC_TIMEOUT_SECONDS:-300}"

# ── Migrations (optional, blocking) ─────────────────────────────────
if [ "${RUN_MIGRATIONS_ON_START}" = "1" ]; then
	echo "[start] Running migrations before startup (timeout ${MIGRATION_TIMEOUT_SECONDS}s)..."
	if ! timeout "${MIGRATION_TIMEOUT_SECONDS}" python manage.py migrate --noinput 2>&1; then
		echo "[start] ERROR: migrate failed or timed out; refusing to start with a potentially stale schema."
		exit 1
	fi
	echo "[start] Migrations completed."
else
	echo "[start] Skipping migrations on startup (RUN_MIGRATIONS_ON_START=${RUN_MIGRATIONS_ON_START}); expect pre-deploy migration to have completed."
fi

# ── Static files recovery ───────────────────────────────────────────
MANIFEST_PATH="$(python scripts/print_static_manifest_path.py)"
STATIC_ROOT_PATH="$(dirname "${MANIFEST_PATH}")"
STATIC_BACKEND="$(python - <<'PY'
import os
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
import django
django.setup()
from django.conf import settings

backend = ""
try:
    backend = settings.STORAGES["staticfiles"]["BACKEND"]
except Exception:
    backend = getattr(settings, "STATICFILES_BACKEND", "")

print(backend)
PY
)"

IS_MANIFEST_BACKEND=0
if [[ "${STATIC_BACKEND}" == *"ManifestStaticFilesStorage"* ]]; then
	IS_MANIFEST_BACKEND=1
fi

echo "[start] Expecting static manifest at ${MANIFEST_PATH}"
echo "[start] Static backend: ${STATIC_BACKEND}"

if [ "${IS_MANIFEST_BACKEND}" = "1" ]; then
	# Manifest-based backend requires staticfiles.json to avoid runtime template 500 errors.
	if [ ! -f "${MANIFEST_PATH}" ]; then
		echo "[start] Static manifest missing — running collectstatic (timeout ${COLLECTSTATIC_TIMEOUT_SECONDS}s)..."
		if ! timeout "${COLLECTSTATIC_TIMEOUT_SECONDS}" python manage.py collectstatic --clear --noinput 2>&1; then
			echo "[start] ERROR: collectstatic failed while manifest is missing; aborting startup to avoid runtime 500 errors."
			exit 1
		fi
		if [ ! -f "${MANIFEST_PATH}" ]; then
			echo "[start] ERROR: collectstatic completed but manifest is still missing at ${MANIFEST_PATH}."
			exit 1
		fi
		echo "[start] collectstatic completed."
	elif [ "${RUN_COLLECTSTATIC_ON_START}" = "1" ]; then
		echo "[start] RUN_COLLECTSTATIC_ON_START=1 — refreshing static files in best-effort mode..."
		timeout "${COLLECTSTATIC_TIMEOUT_SECONDS}" python manage.py collectstatic --clear --noinput 2>&1 || true
		echo "[start] collectstatic refresh done."
	else
		echo "[start] Static manifest OK."
	fi
else
	# Non-manifest backend does not generate staticfiles.json; ensure static root is populated.
	if [ ! -d "${STATIC_ROOT_PATH}" ] || [ -z "$(ls -A "${STATIC_ROOT_PATH}" 2>/dev/null || true)" ]; then
		echo "[start] Static root missing/empty — running collectstatic (timeout ${COLLECTSTATIC_TIMEOUT_SECONDS}s)..."
		if ! timeout "${COLLECTSTATIC_TIMEOUT_SECONDS}" python manage.py collectstatic --clear --noinput 2>&1; then
			echo "[start] ERROR: collectstatic failed while static root is missing; aborting startup."
			exit 1
		fi
		echo "[start] collectstatic completed for non-manifest backend."
	elif [ "${RUN_COLLECTSTATIC_ON_START}" = "1" ]; then
		echo "[start] RUN_COLLECTSTATIC_ON_START=1 — refreshing static files in best-effort mode..."
		timeout "${COLLECTSTATIC_TIMEOUT_SECONDS}" python manage.py collectstatic --clear --noinput 2>&1 || true
		echo "[start] collectstatic refresh done."
	else
		echo "[start] Static root OK (non-manifest backend)."
	fi
fi

# ── Gunicorn ────────────────────────────────────────────────
echo "[start] Launching gunicorn on 0.0.0.0:${PORT_VALUE}"

exec gunicorn config.asgi:application \
	-k uvicorn.workers.UvicornWorker \
	--bind "0.0.0.0:${PORT_VALUE}" \
	--workers "${WEB_CONCURRENCY_VALUE}" \
	--log-level "${LOG_LEVEL_VALUE}" \
	--timeout "${TIMEOUT_VALUE}"
