#!/usr/bin/env python
from __future__ import annotations

import os
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
os.environ.setdefault("DJANGO_ENV", "dev")

import django


def _check(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def _static_exists(asset_path: str) -> bool:
    from django.conf import settings
    from django.contrib.staticfiles import finders

    static_root = Path(getattr(settings, "STATIC_ROOT", ""))
    if static_root:
        direct = static_root / asset_path
        if direct.exists():
            return True

    return bool(finders.find(asset_path))


def main() -> int:
    django.setup()

    from django.conf import settings
    from django.urls import resolve

    critical_paths = [
        "/api/analytics/events/",
        "/dashboard/promo/",
        "/dashboard/analytics/insights/",
    ]

    critical_assets = [
        "dashboard/css/admin.css",
        "dashboard/js/promo.js",
        "mobile_web/css/app.css",
        "mobile_web/js/homePage.js",
        "mobile_web/js/nav.js",
        "mobile_web/js/analytics.js",
    ]

    # Route existence checks (guards against accidental URL removals).
    for path in critical_paths:
        match = resolve(path)
        _check(bool(match.func), f"Route is not resolvable: {path}")

    # Feature-flag checks in production-like environments.
    env = (os.getenv("DJANGO_ENV", "").strip() or "dev").lower()
    if env in {"prod", "production"}:
        _check(bool(getattr(settings, "FEATURE_MODERATION_CENTER", False)), "FEATURE_MODERATION_CENTER must be enabled in prod")
        _check(bool(getattr(settings, "FEATURE_ANALYTICS_EVENTS", False)), "FEATURE_ANALYTICS_EVENTS must be enabled in prod")
        _check(
            bool(getattr(settings, "FEATURE_ANALYTICS_KPI_SURFACES", False)),
            "FEATURE_ANALYTICS_KPI_SURFACES must be enabled in prod",
        )

    # Static availability checks (guards against missing collectstatic artifacts).
    missing = [asset for asset in critical_assets if not _static_exists(asset)]
    _check(not missing, f"Missing critical static assets: {', '.join(missing)}")

    print("[smoke] Startup smoke checks passed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # pragma: no cover - startup guard
        print(f"[smoke] Startup smoke checks failed: {exc}", file=sys.stderr)
        raise
