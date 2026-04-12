#!/usr/bin/env python
"""
Django's command-line utility for administrative tasks.

✅ Notes:
- We default to development settings to make local work smooth.
- Production should explicitly set DJANGO_SETTINGS_MODULE=config.settings.prod
  via environment variables on the server.
"""
import os
import sys


def main() -> None:
    """
    Run administrative tasks.
    """
    # ✅ Use the settings package (config/settings/) which selects dev/prod via DJANGO_ENV
    # Render should set DJANGO_ENV=prod.
    os.environ.setdefault("DJANGO_ENV", "dev")
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

    try:
        from django.core.management import execute_from_command_line
    except ImportError as exc:
        raise ImportError(
            "Couldn't import Django. Are you sure it's installed and "
            "available on your PYTHONPATH environment variable? Did you "
            "forget to activate a virtual environment?"
        ) from exc

    execute_from_command_line(sys.argv)


if __name__ == "__main__":
    main()
