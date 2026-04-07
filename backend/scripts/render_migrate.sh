#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

export DJANGO_ENV="${DJANGO_ENV:-prod}"

MIGRATION_TIMEOUT_SECONDS="${MIGRATION_TIMEOUT_SECONDS:-300}"
MIGRATION_RETRY_ATTEMPTS="${MIGRATION_RETRY_ATTEMPTS:-6}"
MIGRATION_RETRY_DELAY_SECONDS="${MIGRATION_RETRY_DELAY_SECONDS:-10}"

run_with_timeout() {
	local seconds="$1"
	shift
	if command -v timeout >/dev/null 2>&1; then
		timeout "${seconds}" "$@"
	else
		echo "[migrate] WARN: 'timeout' command is unavailable; running command without timeout: $*"
		"$@"
	fi
}

attempt=1
while [ "${attempt}" -le "${MIGRATION_RETRY_ATTEMPTS}" ]; do
	echo "[migrate] Attempt ${attempt}/${MIGRATION_RETRY_ATTEMPTS}: python manage.py migrate --noinput"
	if run_with_timeout "${MIGRATION_TIMEOUT_SECONDS}" python manage.py migrate --noinput; then
		echo "[migrate] Migrations completed successfully."
		exit 0
	fi

	if [ "${attempt}" -ge "${MIGRATION_RETRY_ATTEMPTS}" ]; then
		echo "[migrate] ERROR: migrate failed after ${MIGRATION_RETRY_ATTEMPTS} attempts."
		exit 1
	fi

	echo "[migrate] WARN: migration attempt ${attempt} failed; retrying in ${MIGRATION_RETRY_DELAY_SECONDS}s..."
	sleep "${MIGRATION_RETRY_DELAY_SECONDS}"
	attempt=$((attempt + 1))
done