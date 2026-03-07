#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

export DJANGO_ENV="${DJANGO_ENV:-prod}"

# Keep boot fast on Render so the platform can detect the HTTP port.
# These tasks can be enabled explicitly per service if needed.
RUN_MIGRATIONS_ON_START="${RUN_MIGRATIONS_ON_START:-0}"
RUN_COLLECTSTATIC_ON_START="${RUN_COLLECTSTATIC_ON_START:-0}"

# ── Migrations (optional, non-blocking) ─────────────────────────────
if [ "${RUN_MIGRATIONS_ON_START}" = "1" ]; then
	echo "[start] Running migrations in background (timeout 30s)..."
	(
		timeout 30 python manage.py migrate --noinput 2>&1 || echo "[start] WARNING: migrate timed out or failed."
	) &
else
	echo "[start] Skipping migrations on startup (RUN_MIGRATIONS_ON_START=${RUN_MIGRATIONS_ON_START})."
fi

# ── Static files (optional, non-blocking) ───────────────────────────
if [ ! -f "staticfiles/staticfiles.json" ]; then
	if [ "${RUN_COLLECTSTATIC_ON_START}" = "1" ]; then
		echo "[start] Static manifest missing — running collectstatic in background (timeout 30s)..."
		(
			timeout 30 python manage.py collectstatic --noinput 2>&1 || echo "[start] WARNING: collectstatic failed."
		) &
	else
		echo "[start] Static manifest missing, but collectstatic on startup is disabled (RUN_COLLECTSTATIC_ON_START=${RUN_COLLECTSTATIC_ON_START})."
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
