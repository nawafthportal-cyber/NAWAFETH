#!/usr/bin/env sh
set -e

cd /app/backend

: "${DJANGO_SETTINGS_MODULE:=config.settings}"
: "${WAIT_FOR_DB:=1}"
: "${WAIT_FOR_REDIS:=1}"
: "${RUN_MIGRATIONS:=0}"
: "${RUN_COLLECTSTATIC:=0}"
: "${STARTUP_TIMEOUT_SECONDS:=60}"

export DJANGO_SETTINGS_MODULE

wait_for_db() {
  if [ -z "${DATABASE_URL:-}" ]; then
    echo "[entrypoint] DATABASE_URL is not set. Skipping DB wait."
    return 0
  fi

  echo "[entrypoint] Waiting for PostgreSQL..."
  python - <<'PY'
import os
import time
import sys
import psycopg

url = os.environ.get("DATABASE_URL", "")
timeout = int(os.environ.get("STARTUP_TIMEOUT_SECONDS", "60"))
start = time.time()
while True:
    try:
        with psycopg.connect(url, connect_timeout=5):
            print("[entrypoint] PostgreSQL is ready.")
            break
    except Exception as exc:
        if time.time() - start > timeout:
            print(f"[entrypoint] PostgreSQL wait timeout: {exc}", file=sys.stderr)
            raise
        time.sleep(2)
PY
}

wait_for_redis() {
  redis_url="${CELERY_BROKER_URL:-${REDIS_URL:-}}"
  if [ -z "${redis_url}" ]; then
    echo "[entrypoint] REDIS_URL/CELERY_BROKER_URL is not set. Skipping Redis wait."
    return 0
  fi

  echo "[entrypoint] Waiting for Redis..."
  python - <<'PY'
import os
import time
import sys
import redis

url = os.environ.get("CELERY_BROKER_URL") or os.environ.get("REDIS_URL")
timeout = int(os.environ.get("STARTUP_TIMEOUT_SECONDS", "60"))
start = time.time()
while True:
    try:
        client = redis.Redis.from_url(url)
        client.ping()
        print("[entrypoint] Redis is ready.")
        break
    except Exception as exc:
        if time.time() - start > timeout:
            print(f"[entrypoint] Redis wait timeout: {exc}", file=sys.stderr)
            raise
        time.sleep(2)
PY
}

if [ "${WAIT_FOR_DB}" = "1" ]; then
  wait_for_db
fi

if [ "${WAIT_FOR_REDIS}" = "1" ]; then
  wait_for_redis
fi

if [ "${RUN_MIGRATIONS}" = "1" ]; then
  echo "[entrypoint] Applying migrations..."
  python manage.py migrate --noinput
fi

if [ "${RUN_COLLECTSTATIC}" = "1" ]; then
  echo "[entrypoint] Collecting static files..."
  python manage.py collectstatic --noinput
fi

echo "[entrypoint] Starting: $*"
exec "$@"
