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

# Bind the public port only once the real ASGI stack is ready. A temporary
# bootstrap listener can make Render declare the service healthy before Django
# is actually serving traffic, which creates a hand-off race on the same port.
# Migrations stay optional, but when enabled they must complete before the app
# starts serving traffic; otherwise schema drift can surface as runtime 500s.
RUN_MIGRATIONS_ON_START="${RUN_MIGRATIONS_ON_START:-1}"
RUN_COLLECTSTATIC_ON_START="${RUN_COLLECTSTATIC_ON_START:-1}"
MIGRATION_TIMEOUT_SECONDS="${MIGRATION_TIMEOUT_SECONDS:-120}"
COLLECTSTATIC_TIMEOUT_SECONDS="${COLLECTSTATIC_TIMEOUT_SECONDS:-120}"

# ── Migrations (optional, blocking) ─────────────────────────────────
if [ "${RUN_MIGRATIONS_ON_START}" = "1" ]; then
	echo "[start] Running migrations before startup (timeout ${MIGRATION_TIMEOUT_SECONDS}s)..."
	if ! timeout "${MIGRATION_TIMEOUT_SECONDS}" python manage.py migrate --noinput 2>&1; then
		echo "[start] ERROR: migrate failed or timed out; refusing to start with a potentially stale schema."
		exit 1
	fi
	echo "[start] Migrations completed."
else
	echo "[start] Skipping migrations on startup (RUN_MIGRATIONS_ON_START=${RUN_MIGRATIONS_ON_START})."
fi

# ── Static files recovery ───────────────────────────────────────────
MANIFEST_PATH="$(python scripts/print_static_manifest_path.py)"
echo "[start] Expecting static manifest at ${MANIFEST_PATH}"

if [ ! -f "${MANIFEST_PATH}" ]; then
	if [ "${RUN_COLLECTSTATIC_ON_START}" = "1" ]; then
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
	else
		echo "[start] ERROR: Static manifest missing and collectstatic is disabled (RUN_COLLECTSTATIC_ON_START=${RUN_COLLECTSTATIC_ON_START})."
		echo "[start] Refusing to start without a WhiteNoise manifest-backed static build."
		exit 1
	fi
else
	echo "[start] Static manifest OK."
fi

# ── Gunicorn ────────────────────────────────────────────────
echo "[start] Launching gunicorn on 0.0.0.0:${PORT_VALUE}"

exec gunicorn config.asgi:application \
	-k uvicorn.workers.UvicornWorker \
	--bind "0.0.0.0:${PORT_VALUE}" \
	--workers "${WEB_CONCURRENCY_VALUE}" \
	--log-level "${LOG_LEVEL_VALUE}" \
	--timeout "${TIMEOUT_VALUE}"
