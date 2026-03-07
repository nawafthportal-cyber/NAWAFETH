#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

export DJANGO_ENV="${DJANGO_ENV:-prod}"

# Keep boot fast on Render so the platform can detect the HTTP port.
# Migrations stay optional, but collectstatic defaults to enabled when
# the manifest is missing because manifest storage otherwise returns 500.
RUN_MIGRATIONS_ON_START="${RUN_MIGRATIONS_ON_START:-0}"
RUN_COLLECTSTATIC_ON_START="${RUN_COLLECTSTATIC_ON_START:-1}"

# ── Migrations (optional, non-blocking) ─────────────────────────────
if [ "${RUN_MIGRATIONS_ON_START}" = "1" ]; then
	echo "[start] Running migrations in background (timeout 30s)..."
	(
		timeout 30 python manage.py migrate --noinput 2>&1 || echo "[start] WARNING: migrate timed out or failed."
	) &
else
	echo "[start] Skipping migrations on startup (RUN_MIGRATIONS_ON_START=${RUN_MIGRATIONS_ON_START})."
fi

# ── Static files (required when manifest is missing) ────────────────
if [ ! -f "staticfiles/staticfiles.json" ]; then
	if [ "${RUN_COLLECTSTATIC_ON_START}" = "1" ]; then
		echo "[start] Static manifest missing — running collectstatic (timeout 20s)..."
		if ! timeout 20 python manage.py collectstatic --noinput 2>&1; then
			echo "[start] ERROR: collectstatic failed while manifest is missing; aborting startup to avoid runtime 500 errors."
			exit 1
		fi
		echo "[start] collectstatic completed."
	else
		echo "[start] ERROR: Static manifest missing and collectstatic is disabled (RUN_COLLECTSTATIC_ON_START=${RUN_COLLECTSTATIC_ON_START})."
		echo "[start] Refusing to start with manifest storage because templates will return 500."
		exit 1
	fi
else
	echo "[start] Static manifest OK."
fi

# ── Gunicorn ────────────────────────────────────────────────
PORT_VALUE="${PORT:-8000}"
WEB_CONCURRENCY_VALUE="${WEB_CONCURRENCY:-2}"
LOG_LEVEL_VALUE="${GUNICORN_LOG_LEVEL:-info}"
TIMEOUT_VALUE="${GUNICORN_TIMEOUT:-60}"

echo "[start] Launching gunicorn on 0.0.0.0:${PORT_VALUE}"

exec gunicorn config.asgi:application \
	-k uvicorn.workers.UvicornWorker \
	--bind "0.0.0.0:${PORT_VALUE}" \
	--workers "${WEB_CONCURRENCY_VALUE}" \
	--log-level "${LOG_LEVEL_VALUE}" \
	--timeout "${TIMEOUT_VALUE}"
