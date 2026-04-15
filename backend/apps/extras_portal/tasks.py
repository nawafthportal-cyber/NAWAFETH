from __future__ import annotations

from celery import shared_task

from .services import process_due_scheduled_messages


@shared_task(name="extras_portal.send_due_scheduled_messages")
def send_due_scheduled_messages_task(limit: int = 200):
    return process_due_scheduled_messages(limit=limit)