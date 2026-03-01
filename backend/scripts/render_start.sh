#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

# Keep runtime settings aligned with build-time collectstatic.
export DJANGO_ENV="${DJANGO_ENV:-prod}"

STATIC_ROOT_PATH="$(python - <<'PY'
import os
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
import django
django.setup()
from django.conf import settings
print(settings.STATIC_ROOT)
PY
)"
MANIFEST_PATH="${STATIC_ROOT_PATH%/}/staticfiles.json"

if [ ! -f "${MANIFEST_PATH}" ]; then
	echo "[start] Static manifest missing at ${MANIFEST_PATH} — running collectstatic..."
	python manage.py collectstatic --noinput
	if [ ! -f "${MANIFEST_PATH}" ]; then
		echo "[start] WARNING: manifest still missing after collectstatic. Static files may not work."
	fi
else
	echo "[start] Static manifest OK: ${MANIFEST_PATH}"
fi

if [ "${RUN_MIGRATIONS_ON_START:-1}" = "1" ]; then
	python manage.py migrate --noinput
fi

PORT_VALUE="${PORT:-8000}"
WEB_CONCURRENCY_VALUE="${WEB_CONCURRENCY:-2}"
LOG_LEVEL_VALUE="${GUNICORN_LOG_LEVEL:-info}"
TIMEOUT_VALUE="${GUNICORN_TIMEOUT:-60}"

exec gunicorn config.asgi:application \
	-k uvicorn.workers.UvicornWorker \
	--bind "0.0.0.0:${PORT_VALUE}" \
	--workers "${WEB_CONCURRENCY_VALUE}" \
	--log-level "${LOG_LEVEL_VALUE}" \
	--timeout "${TIMEOUT_VALUE}"
