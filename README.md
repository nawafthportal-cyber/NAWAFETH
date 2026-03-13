# NAWAFETH

[![Mobile Flutter Tests](https://github.com/nawafthportal-cyber/NAWAFETH/actions/workflows/mobile-flutter-tests.yml/badge.svg)](https://github.com/nawafthportal-cyber/NAWAFETH/actions/workflows/mobile-flutter-tests.yml)

## Backend (Django) on Render

This repo contains:
- `backend/`: Django + DRF + Channels (WebSockets)
- `mobile/`: Flutter app

## Backend: local vs Render database

Backend settings already switch automatically by environment variables:
- local (default): SQLite (`backend/db.sqlite3`) when `DATABASE_URL` is not set
- local PostgreSQL: set `DATABASE_URL` in `backend/.env`
- Render PostgreSQL: set `DATABASE_URL` from Render database connection string

Redis/Channels:
- local dev: in-memory channel layer when `REDIS_URL` is empty
- Render: set `REDIS_URL` from Render Key Value service

## Mobile API target selection

Flutter app API base URL is now controlled by `--dart-define`:
- local API: `flutter run --dart-define=API_TARGET=local`
- Render API: `flutter run --dart-define=API_TARGET=render`
- explicit URL: `flutter run --dart-define=API_BASE_URL=https://www.nawafthportal.com`

### Render deployment
A Render Blueprint is provided in `render.yaml`.

**Required Render environment variables**
- `DJANGO_SECRET_KEY`
- `DATABASE_URL` (Render Postgres)
- `REDIS_URL` (Render Redis) — required for Channels/WebSockets in production

**Recommended**
- `DJANGO_ALLOWED_HOSTS` (comma-separated) e.g. `nawafeth-2290.onrender.com,nawafthportal.com,www.nawafthportal.com`
- `CORS_ALLOW_ALL=0`
- `CORS_ALLOWED_ORIGINS=https://nawafthportal.com,https://www.nawafthportal.com`
- `DJANGO_CSRF_TRUSTED_ORIGINS=https://nawafthportal.com,https://www.nawafthportal.com,https://*.onrender.com`

**Notes**
- Static files are served via WhiteNoise (collectstatic runs at build time).
- Media uploads in `backend/media/` are ephemeral on Render; use object storage (e.g. S3) for persistent media.
