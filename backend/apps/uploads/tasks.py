"""Deferred media optimization tasks (Celery).

Video transcoding can block a web worker for up to 60 seconds.  By running
it as a background task we free the HTTP worker immediately.  The original
(un-optimised) file is saved first so the user sees their upload instantly;
the task replaces it in-place once the optimised version is ready.
"""
from __future__ import annotations

import logging

from celery import shared_task

logger = logging.getLogger("nawafeth.uploads")


@shared_task(
    bind=True,
    max_retries=2,
    default_retry_delay=30,
    time_limit=180,
    soft_time_limit=150,
    acks_late=True,
)
def optimize_stored_video(self, app_label: str, model_name: str, pk: int, field_name: str):
    """Download *field_name* from storage, transcode with FFmpeg, re-upload."""
    from django.apps import apps
    from django.core.files.base import ContentFile

    from .media_optimizer import _optimize_video, _safe_seek_start, infer_media_kind

    try:
        Model = apps.get_model(app_label, model_name)
    except LookupError:
        logger.error("optimize_stored_video: model %s.%s not found", app_label, model_name)
        return

    try:
        instance = Model.objects.get(pk=pk)
    except Model.DoesNotExist:
        logger.warning("optimize_stored_video: %s.%s pk=%s gone", app_label, model_name, pk)
        return

    file_field = getattr(instance, field_name, None)
    if not file_field or not file_field.name:
        return

    # Only process videos.
    from django.core.files.uploadedfile import SimpleUploadedFile

    try:
        file_field.open("rb")
        raw_bytes = file_field.read()
        file_field.close()
    except Exception:
        logger.exception("optimize_stored_video: failed to read %s", file_field.name)
        return

    original_name = file_field.name.rsplit("/", 1)[-1] if "/" in file_field.name else file_field.name
    uploaded = SimpleUploadedFile(
        name=original_name,
        content=raw_bytes,
        content_type="video/mp4",
    )

    kind = infer_media_kind(uploaded)
    if kind != "video":
        return

    optimized = _optimize_video(uploaded)

    # If the optimizer returned the same object, nothing improved – skip.
    if optimized is uploaded:
        return

    optimized_bytes = optimized.read()
    if not optimized_bytes or len(optimized_bytes) >= len(raw_bytes):
        return

    # Save optimised file back to storage, preserving the path prefix.
    storage_path = file_field.name
    storage = file_field.storage

    # Delete old file, save new one at the same logical path.
    try:
        storage.delete(storage_path)
    except Exception:
        pass

    new_name = storage.save(storage_path, ContentFile(optimized_bytes))
    if new_name != storage_path:
        # Storage may rename; update the model field.
        setattr(instance, field_name, new_name)
        instance.save(update_fields=[field_name])

    logger.info(
        "optimize_stored_video: %s.%s pk=%s %s: %d → %d bytes (%.0f%% saved)",
        app_label,
        model_name,
        pk,
        field_name,
        len(raw_bytes),
        len(optimized_bytes),
        (1 - len(optimized_bytes) / len(raw_bytes)) * 100,
    )


def schedule_video_optimization(instance, field_name: str) -> None:
    """Queue background video optimization for a model instance's file field.

    Safe to call for any media type – non-video files are silently skipped
    inside the task.  Must be called *after* the instance has been saved
    (needs a valid pk).
    """
    if instance.pk is None:
        return
    file_field = getattr(instance, field_name, None)
    if not file_field or not file_field.name:
        return

    meta = instance._meta
    optimize_stored_video.delay(
        meta.app_label,
        meta.model_name,
        instance.pk,
        field_name,
    )
