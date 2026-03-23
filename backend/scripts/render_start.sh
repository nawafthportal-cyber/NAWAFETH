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
RUN_MIGRATIONS_ON_START="${RUN_MIGRATIONS_ON_START:-1}"
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

# ── Static files (optional on startup) ─────────────────────────────
# Keep startup port-first. Static recovery is handled during build by default.
if [ "${RUN_COLLECTSTATIC_ON_START}" = "1" ]; then
	echo "[start] RUN_COLLECTSTATIC_ON_START=1 — running collectstatic (best-effort, timeout ${COLLECTSTATIC_TIMEOUT_SECONDS}s)..."
	timeout "${COLLECTSTATIC_TIMEOUT_SECONDS}" python manage.py collectstatic --clear --noinput 2>&1 || true
	echo "[start] collectstatic best-effort done."
else
	echo "[start] Skipping collectstatic on startup (RUN_COLLECTSTATIC_ON_START=${RUN_COLLECTSTATIC_ON_START}); expect build-time collectstatic to be available."
fi

# ── Gunicorn ────────────────────────────────────────────────
echo "[start] Launching gunicorn on 0.0.0.0:${PORT_VALUE}"

exec gunicorn config.asgi:application \
	-k uvicorn.workers.UvicornWorker \
	--bind "0.0.0.0:${PORT_VALUE}" \
	--workers "${WEB_CONCURRENCY_VALUE}" \
	--log-level "${LOG_LEVEL_VALUE}" \
	--timeout "${TIMEOUT_VALUE}"
