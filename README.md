# NAWAFETH

[![Mobile Flutter Tests](https://github.com/nawafthportal-cyber/NAWAFETH/actions/workflows/mobile-flutter-tests.yml/badge.svg)](https://github.com/nawafthportal-cyber/NAWAFETH/actions/workflows/mobile-flutter-tests.yml)

NAWAFETH is a monorepo that contains:
- `backend/`: Django + DRF + Channels (WebSockets) + Celery-ready settings.
- `mobile/`: Flutter client app.

## Project Structure

- `backend/`: API, dashboard, mobile-web pages, auth, business modules.
- `mobile/`: Flutter application and platform targets.
- `render.yaml`: Render Blueprint for backend service + Redis + Postgres.
- `.github/workflows/`: CI for backend critical suites and Flutter tests.

## Tech Stack

- Backend: Django, Django REST Framework, Channels, WhiteNoise, Gunicorn/Uvicorn worker.
- Mobile: Flutter (Dart 3), HTTP client based integration with backend APIs.
- Data: SQLite (local default) or PostgreSQL via `DATABASE_URL`.
- Realtime/cache: Redis (`REDIS_URL`) in production, in-memory fallback locally.

## Prerequisites

- Python 3.12 recommended (matches CI).
- Flutter stable channel.
- PowerShell (Windows) or Bash (Linux/macOS) for scripts.
- Optional locally: Redis and PostgreSQL.

## Local Setup (Backend)

### 1) Create virtual environment (repo root)

Windows PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
```

### 2) Install dependencies

```powershell
cd backend
python -m pip install --upgrade pip
python -m pip install -r requirements.txt -r requirements/dev.txt
```

`requirements.txt` points to production requirements, while `requirements/dev.txt` adds test/lint tools.

### 3) Configure environment

Create `backend/.env` from `backend/env.example` and adjust values.

Minimal local example:

```env
DJANGO_ENV=dev
DJANGO_DEBUG=1
DJANGO_SECRET_KEY=dev-secret-key-change-me
DJANGO_ALLOWED_HOSTS=127.0.0.1,localhost,10.0.2.2
```

Database behavior:
- If `DATABASE_URL` is empty: SQLite at `backend/db.sqlite3`.
- If `DATABASE_URL` is set: PostgreSQL connection is used.

Channels/cache behavior:
- If `REDIS_URL` is empty: in-memory channel layer + local memory cache.
- If `REDIS_URL` is set: Redis channel layer + Redis cache.

### 4) Run migrations and start server

```powershell
python manage.py migrate
python manage.py runserver 0.0.0.0:8000
```

Or use helper script from repo root:

```powershell
backend\runserver_local.ps1
```

## Health and Core URLs

- Liveness: `/healthz/`
- Health details: `/health/`
- Live/ready checks: `/health/live/`, `/health/ready/`
- Django admin: `/admin-panel/`
- Dashboard namespace: `/dashboard/`
- API namespaces include `/api/accounts/`, `/api/providers/`, `/api/marketplace/`, `/api/messaging/`, and others.

## Mobile Setup (Flutter)

### 1) Install packages

```powershell
cd mobile
flutter pub get
```

### 2) Run app against backend

Use `--dart-define` values from `mobile/lib/config/app_env.dart`:

- Local backend:

```bash
flutter run --dart-define=API_TARGET=local
```

- Render backend:

```bash
flutter run --dart-define=API_TARGET=render
```

- Explicit custom URL (requires `API_TARGET=auto`):

```bash
flutter run --dart-define=API_TARGET=auto --dart-define=API_BASE_URL=https://example.com
```

- Override local target URL directly:

```bash
flutter run --dart-define=API_TARGET=local --dart-define=API_LOCAL_BASE_URL=http://192.168.1.10:8000
```

Default behavior note:
- `API_TARGET` defaults to `render` in code.

## Testing

### Backend

From `backend/`:

```powershell
python manage.py check
python manage.py makemigrations --check --dry-run
pytest -q
```

CI also runs a critical regression subset (analytics, moderation, dashboard, notifications, messaging, support, promo, subscriptions, extras).

### Mobile

From `mobile/`:

```bash
flutter test
```

CI includes full Flutter tests and `test/badge_heuristics_guard_test.dart`.

## Deployment on Render

Render Blueprint is defined in `render.yaml` with:
- Web service `nawafeth-backend` (`rootDir: backend`).
- Managed Redis key-value service (`nawafeth-redis`).
- Managed PostgreSQL database (`nawafeth-db`).

Build/start pipeline:
- Build: `bash scripts/render_build.sh`
- Pre-deploy: migrations + collectstatic + startup smoke check
- Start: `bash scripts/render_start.sh`

Required environment variables:
- `DJANGO_SECRET_KEY`
- `DATABASE_URL`
- `REDIS_URL`

Important production defaults:
- `DJANGO_ENV=prod`
- `DJANGO_DEBUG=0`
- HTTPS/security headers and CORS/CSRF constraints are enforced in prod settings.

## Static and Media Files

- Static assets are collected to `backend/staticfiles` and served with WhiteNoise.
- Local media default path is `backend/media`.
- On Render, local filesystem is ephemeral unless a persistent disk is configured.
- Optional object storage is supported via R2/S3-compatible environment variables (`USE_R2_MEDIA=1` and related keys in `backend/env.example`).

## Common Operational Notes

- Settings module auto-selects by `DJANGO_ENV`:
	- `dev` -> `config.settings.dev`
	- `prod` -> `config.settings.prod`
- OTP dev bypass is enabled only in dev settings and explicitly disabled in prod.
- If static/media behavior is inconsistent in a deploy, verify the corresponding env flags in `render.yaml` and `backend/config/settings/prod.py`.

## CI Workflows

- Backend critical checks: `.github/workflows/backend-critical-tests.yml`
- Mobile Flutter tests: `.github/workflows/mobile-flutter-tests.yml`

## Cleanup Guidance (Important)

Do not commit generated/runtime artifacts such as virtualenvs, local DB files, build outputs, and temporary browser profiles.

Examples to keep out of version control:
- `.venv/`, `backend/.venv/`
- `backend/db.sqlite3`
- `backend/staticfiles/`
- `mobile/build/`
- temporary debug/output files and browser profile dumps
