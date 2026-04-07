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
RUN_COLLECTSTATIC_RECOVERY_ON_START="${RUN_COLLECTSTATIC_RECOVERY_ON_START:-1}"
MIGRATION_TIMEOUT_SECONDS="${MIGRATION_TIMEOUT_SECONDS:-180}"
COLLECTSTATIC_TIMEOUT_SECONDS="${COLLECTSTATIC_TIMEOUT_SECONDS:-300}"
RUN_STARTUP_SMOKE="${RUN_STARTUP_SMOKE:-0}"
STARTUP_SMOKE_TIMEOUT_SECONDS="${STARTUP_SMOKE_TIMEOUT_SECONDS:-60}"

STATIC_ROOT_DIR="${PROJECT_ROOT}/staticfiles"

ensure_static_ready() {
	if [ ! -d "${STATIC_ROOT_DIR}" ]; then
		return 1
	fi
	if [ -z "$(ls -A "${STATIC_ROOT_DIR}" 2>/dev/null || true)" ]; then
		return 1
	fi
	return 0
}

run_with_timeout() {
	local seconds="$1"
	shift
	if command -v timeout >/dev/null 2>&1; then
		timeout "${seconds}" "$@"
	else
		echo "[start] WARN: 'timeout' command is unavailable; running command without timeout: $*"
		"$@"
	fi
}

# ── Migrations (optional, blocking) ─────────────────────────────────
if [ "${RUN_MIGRATIONS_ON_START}" = "1" ]; then
	echo "[start] Running migrations before startup with retry support..."
	if ! bash scripts/render_migrate.sh 2>&1; then
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
	run_with_timeout "${COLLECTSTATIC_TIMEOUT_SECONDS}" python manage.py collectstatic --clear --noinput 2>&1 || true
	echo "[start] collectstatic best-effort done."
else
	if ensure_static_ready; then
		echo "[start] Skipping collectstatic on startup (RUN_COLLECTSTATIC_ON_START=${RUN_COLLECTSTATIC_ON_START}); staticfiles already present."
	elif [ "${RUN_COLLECTSTATIC_RECOVERY_ON_START}" = "1" ]; then
		echo "[start] staticfiles missing/empty at ${STATIC_ROOT_DIR}; running collectstatic recovery (timeout ${COLLECTSTATIC_TIMEOUT_SECONDS}s)..."
		run_with_timeout "${COLLECTSTATIC_TIMEOUT_SECONDS}" python manage.py collectstatic --clear --noinput 2>&1 || true
		echo "[start] collectstatic recovery done."
	else
		echo "[start] WARN: staticfiles missing/empty at ${STATIC_ROOT_DIR}; skipping collectstatic recovery to keep startup fast."
		echo "[start] WARN: Set RUN_COLLECTSTATIC_RECOVERY_ON_START=1 to enable runtime recovery."
	fi
fi

# ── Startup smoke checks (optional, blocking) ─────────────────────
if [ "${RUN_STARTUP_SMOKE}" = "1" ]; then
	echo "[start] Running startup smoke checks (timeout ${STARTUP_SMOKE_TIMEOUT_SECONDS}s)..."
	if ! run_with_timeout "${STARTUP_SMOKE_TIMEOUT_SECONDS}" python scripts/startup_smoke.py 2>&1; then
		echo "[start] ERROR: startup smoke checks failed; refusing to start."
		exit 1
	fi
	echo "[start] Startup smoke checks passed."
else
	echo "[start] Skipping startup smoke checks (RUN_STARTUP_SMOKE=${RUN_STARTUP_SMOKE})."
fi

# ── Gunicorn ────────────────────────────────────────────────
WORKER_CLASS=""
if python -c "from uvicorn_worker import UvicornWorker" >/dev/null 2>&1; then
	WORKER_CLASS="uvicorn_worker.UvicornWorker"
elif python -c "from uvicorn.workers import UvicornWorker" >/dev/null 2>&1; then
	WORKER_CLASS="uvicorn.workers.UvicornWorker"
fi

if [ -n "${WORKER_CLASS}" ] && command -v gunicorn >/dev/null 2>&1; then
	echo "[start] Launching gunicorn on 0.0.0.0:${PORT_VALUE} with worker ${WORKER_CLASS}"
	exec gunicorn config.asgi:application \
		-k "${WORKER_CLASS}" \
		--bind "0.0.0.0:${PORT_VALUE}" \
		--workers "${WEB_CONCURRENCY_VALUE}" \
		--log-level "${LOG_LEVEL_VALUE}" \
		--timeout "${TIMEOUT_VALUE}"
fi

if [ -n "${WORKER_CLASS}" ]; then
	echo "[start] WARN: Gunicorn is unavailable in PATH. Falling back to uvicorn directly."
else
	echo "[start] WARN: Uvicorn gunicorn worker class is unavailable. Falling back to uvicorn directly."
fi
exec python -m uvicorn config.asgi:application \
	--host "0.0.0.0" \
	--port "${PORT_VALUE}" \
	--workers "${WEB_CONCURRENCY_VALUE}" \
	--log-level "${LOG_LEVEL_VALUE}"
