from __future__ import annotations

from celery import shared_task

from .services import expire_due_portal_subscriptions, process_due_scheduled_messages


@shared_task(name="extras_portal.send_due_scheduled_messages")
def send_due_scheduled_messages_task(limit: int = 200):
    return process_due_scheduled_messages(limit=limit)


@shared_task(name="extras_portal.expire_due_subscriptions")
def expire_due_subscriptions_task(limit: int = 500):
    return expire_due_portal_subscriptions(limit=limit)