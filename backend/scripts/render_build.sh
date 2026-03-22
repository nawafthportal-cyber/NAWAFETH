#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

# Use production settings during build to generate the same static manifest
# expected at runtime.
export DJANGO_ENV="${DJANGO_ENV:-prod}"

python -m pip install --upgrade pip
pip install -r requirements/prod.txt


echo "[build] Running collectstatic (--clear to remove stale files)..."
python manage.py collectstatic --clear --noinput

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

if [ "${IS_MANIFEST_BACKEND}" = "1" ]; then
	if [ ! -f "${MANIFEST_PATH}" ]; then
		echo "[build] ERROR: static manifest not found at ${MANIFEST_PATH}"
		exit 1
	fi
	echo "[build] static manifest generated at ${MANIFEST_PATH}"
else
	if [ ! -d "${STATIC_ROOT_PATH}" ] || [ -z "$(ls -A "${STATIC_ROOT_PATH}" 2>/dev/null || true)" ]; then
		echo "[build] ERROR: static root is missing/empty at ${STATIC_ROOT_PATH}"
		exit 1
	fi
	echo "[build] Non-manifest static backend detected: ${STATIC_BACKEND}"
fi

echo "[build] staticfiles dir sample:"
ls -la "${STATIC_ROOT_PATH}" | head -20
echo "[build] Build script complete."
