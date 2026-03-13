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

if [ ! -f "${MANIFEST_PATH}" ]; then
	echo "[build] ERROR: static manifest not found at ${MANIFEST_PATH}"
	exit 1
fi

echo "[build] static manifest generated at ${MANIFEST_PATH}"
echo "[build] staticfiles dir sample:"
ls -la "${STATIC_ROOT_PATH}" | head -20
echo "[build] Build script complete."
