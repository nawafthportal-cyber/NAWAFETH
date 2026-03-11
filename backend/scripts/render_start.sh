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
BOOTSTRAP_LISTENER_ENABLED="${BOOTSTRAP_LISTENER_ENABLED:-1}"
BOOTSTRAP_SERVER_PID=""

# Keep boot fast on Render so the platform can detect the HTTP port.
# Migrations stay optional, but when enabled they must complete before the
# app starts serving traffic; otherwise schema drift can surface as runtime 500s.
# Collectstatic defaults to enabled when the manifest is missing because
# manifest storage otherwise returns 500.
RUN_MIGRATIONS_ON_START="${RUN_MIGRATIONS_ON_START:-1}"
RUN_COLLECTSTATIC_ON_START="${RUN_COLLECTSTATIC_ON_START:-1}"
MIGRATION_TIMEOUT_SECONDS="${MIGRATION_TIMEOUT_SECONDS:-120}"

cleanup_bootstrap_listener() {
	if [ -n "${BOOTSTRAP_SERVER_PID}" ] && kill -0 "${BOOTSTRAP_SERVER_PID}" 2>/dev/null; then
		kill "${BOOTSTRAP_SERVER_PID}" 2>/dev/null || true
		wait "${BOOTSTRAP_SERVER_PID}" 2>/dev/null || true
	fi
	BOOTSTRAP_SERVER_PID=""
}

start_bootstrap_listener() {
	if [ "${BOOTSTRAP_LISTENER_ENABLED}" != "1" ]; then
		return
	fi
	echo "[start] Opening temporary bootstrap listener on 0.0.0.0:${PORT_VALUE}"
	python - <<'PY' &
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port = int(os.environ.get("PORT", "8000"))


class Handler(BaseHTTPRequestHandler):
    def _write_response(self, head_only: bool = False):
        body = b"starting"
        self.send_response(503)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if not head_only:
            self.wfile.write(body)

    def do_GET(self):
        self._write_response()

    def do_HEAD(self):
        self._write_response(head_only=True)

    def do_POST(self):
        self._write_response()

    def log_message(self, format, *args):
        return


server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
server.serve_forever()
PY
	BOOTSTRAP_SERVER_PID=$!
}

trap cleanup_bootstrap_listener EXIT
start_bootstrap_listener

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
cleanup_bootstrap_listener
trap - EXIT

echo "[start] Launching gunicorn on 0.0.0.0:${PORT_VALUE}"

exec gunicorn config.asgi:application \
	-k uvicorn.workers.UvicornWorker \
	--bind "0.0.0.0:${PORT_VALUE}" \
	--workers "${WEB_CONCURRENCY_VALUE}" \
	--log-level "${LOG_LEVEL_VALUE}" \
	--timeout "${TIMEOUT_VALUE}"
