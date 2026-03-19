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
	echo "[start] Skipping migrations on startup (RUN_MIGRATIONS_ON_START=${RUN_MIGRATIONS_ON_START}); expect pre-deploy migration to have completed."
fi

# ── Static files recovery ───────────────────────────────────────────
MANIFEST_PATH="$(python scripts/print_static_manifest_path.py)"
echo "[start] Expecting static manifest at ${MANIFEST_PATH}"

if [ ! -f "${MANIFEST_PATH}" ]; then
	# Manifest is missing — always regenerate it so the service can boot.
	# This covers Render free-tier slug-transfer issues where build artifacts
	# are not preserved between the build and deploy containers.
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
	echo "[start] Manifest exists but RUN_COLLECTSTATIC_ON_START=1 — refreshing static files..."
	timeout "${COLLECTSTATIC_TIMEOUT_SECONDS}" python manage.py collectstatic --clear --noinput 2>&1 || true
	echo "[start] collectstatic refresh done."
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
