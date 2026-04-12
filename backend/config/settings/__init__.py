"""Settings package.

This project uses settings modules under config/settings/ (base/dev/prod).
Some entrypoints (e.g. ASGI/WSGI) may reference DJANGO_SETTINGS_MODULE=config.settings,
so DJANGO_ENV must be set explicitly to one of: dev, prod, base.
"""

import os


_raw_env = (os.getenv("DJANGO_ENV", "") or "").strip()
if not _raw_env:
    raise RuntimeError(
        "DJANGO_ENV is required (expected one of: dev, prod, base). "
        "Set DJANGO_ENV explicitly before starting Django."
    )

env = _raw_env.lower()
if env not in {"dev", "prod", "base"}:
    raise RuntimeError(
        f"Unsupported DJANGO_ENV='{_raw_env}'. Expected one of: dev, prod, base."
    )

if env == "prod":
	from .prod import *  # noqa
elif env == "base":
	from .base import *  # noqa
else:
	from .dev import *  # noqa
