#!/usr/bin/env bash
set -euo pipefail

python -m pip install --upgrade pip
pip install -r requirements/prod.txt

echo "[build] Running collectstatic (--clear to remove stale files)..."
python manage.py collectstatic --clear --noinput

echo "[build] staticfiles dir contents:"
ls -la staticfiles/ 2>/dev/null | head -20 || echo "[build] WARNING: staticfiles/ not found after collectstatic!"
echo "[build] Build script complete."
