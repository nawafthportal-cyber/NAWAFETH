FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app/backend

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        curl \
        ffmpeg \
        libpq-dev \
        netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --system app && useradd --system --create-home --gid app app

COPY backend/requirements.txt /tmp/requirements.txt
COPY backend/requirements /tmp/requirements
RUN python -m pip install --upgrade pip \
    && pip install -r /tmp/requirements.txt \
    && rm -rf /tmp/requirements

COPY backend /app/backend

RUN mkdir -p /app/backend/staticfiles /app/backend/media \
    && chown -R app:app /app/backend \
    && chmod 0755 /app/backend/entrypoint.sh

USER app

ENTRYPOINT ["/app/backend/entrypoint.sh"]
CMD ["gunicorn", "config.asgi:application", "-k", "uvicorn_worker.UvicornWorker", "--bind", "0.0.0.0:8000", "--workers", "3", "--threads", "2", "--worker-tmp-dir", "/dev/shm", "--max-requests", "1000", "--max-requests-jitter", "100", "--timeout", "120", "--graceful-timeout", "30", "--access-logfile", "-", "--error-logfile", "-"]
