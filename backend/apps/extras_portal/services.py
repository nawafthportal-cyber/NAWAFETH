from __future__ import annotations

from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from apps.messaging.models import Message, Thread
from apps.notifications.models import EventLog, EventType
from apps.notifications.services import create_notification

from .models import ExtrasPortalScheduledMessage, ScheduledMessageStatus


def get_or_create_direct_thread(user_a, user_b) -> Thread:
    if user_a.id == user_b.id:
        raise ValueError("cannot chat self")
    thread = (
        Thread.objects.filter(is_direct=True)
        .filter(
            Q(participant_1=user_a, participant_2=user_b)
            | Q(participant_1=user_b, participant_2=user_a)
        )
        .first()
    )
    if thread:
        return thread
    return Thread.objects.create(is_direct=True, participant_1=user_a, participant_2=user_b)


def _scheduled_message_notification_body(*, recipient_count: int) -> str:
    if recipient_count == 1:
        return "تم إرسال رسالتك المجدولة إلى عميل واحد عبر بوابة إدارة العملاء."
    return f"تم إرسال رسالتك المجدولة إلى {recipient_count} عملاء عبر بوابة إدارة العملاء."


def _notify_scheduled_message_sent(scheduled: ExtrasPortalScheduledMessage, *, recipient_count: int):
    provider_user = getattr(getattr(scheduled, "provider", None), "user", None)
    provider_user_id = getattr(provider_user, "id", None)
    if provider_user is None or not provider_user_id:
        return
    if EventLog.objects.filter(
        event_type=EventType.SCHEDULED_MESSAGE_SENT,
        target_user_id=provider_user_id,
        request_id=scheduled.id,
    ).exists():
        return

    create_notification(
        user=provider_user,
        title="تم تنفيذ التذكير المجدول",
        body=_scheduled_message_notification_body(recipient_count=recipient_count),
        kind="success",
        url="/portal/extras/clients/",
        event_type=EventType.SCHEDULED_MESSAGE_SENT,
        request_id=scheduled.id,
        meta={
            "scheduled_message_id": scheduled.id,
            "recipient_count": recipient_count,
            "send_at": scheduled.send_at.isoformat() if scheduled.send_at else "",
            "sent_at": scheduled.sent_at.isoformat() if scheduled.sent_at else "",
        },
        pref_key="scheduled_ticket_reminder",
        audience_mode="provider",
    )


def process_due_scheduled_messages(*, now=None, limit: int | None = None) -> dict[str, int]:
    now = now or timezone.now()
    qs = (
        ExtrasPortalScheduledMessage.objects.select_related("provider", "provider__user")
        .prefetch_related("recipients", "recipients__user")
        .filter(status=ScheduledMessageStatus.PENDING, send_at__isnull=False, send_at__lte=now)
        .order_by("id")
    )
    if limit is not None:
        qs = qs[:limit]

    totals = {
        "due": 0,
        "sent": 0,
        "failed": 0,
        "cancelled": 0,
    }

    for scheduled in qs:
        totals["due"] += 1
        provider_user = scheduled.provider.user
        recipients = [recipient.user for recipient in scheduled.recipients.all()]
        if not recipients:
            scheduled.status = ScheduledMessageStatus.CANCELLED
            scheduled.error = "no recipients"
            scheduled.save(update_fields=["status", "error"])
            totals["cancelled"] += 1
            continue

        try:
            with transaction.atomic():
                for recipient in recipients:
                    thread = get_or_create_direct_thread(provider_user, recipient)
                    Message.objects.create(
                        thread=thread,
                        sender=provider_user,
                        body=scheduled.body,
                        attachment=scheduled.attachment,
                        attachment_type="",
                        attachment_name="",
                        created_at=now,
                    )
                scheduled.status = ScheduledMessageStatus.SENT
                scheduled.sent_at = now
                scheduled.error = ""
                scheduled.save(update_fields=["status", "sent_at", "error"])
                transaction.on_commit(
                    lambda scheduled_id=scheduled.id, recipient_count=len(recipients): _notify_scheduled_message_sent(
                        ExtrasPortalScheduledMessage.objects.select_related("provider", "provider__user").get(id=scheduled_id),
                        recipient_count=recipient_count,
                    )
                )
            totals["sent"] += 1
        except Exception as exc:
            scheduled.status = ScheduledMessageStatus.FAILED
            scheduled.error = str(exc)[:255]
            scheduled.save(update_fields=["status", "error"])
            totals["failed"] += 1

    return totals


def expire_due_portal_subscriptions(*, now=None, limit: int = 500) -> dict[str, int]:
    """Mark ACTIVE subscriptions whose ends_at has passed as INACTIVE."""
    from .models import ExtrasPortalSubscription, ExtrasPortalSubscriptionStatus

    now = now or timezone.now()
    expired_qs = (
        ExtrasPortalSubscription.objects
        .filter(
            status=ExtrasPortalSubscriptionStatus.ACTIVE,
            ends_at__isnull=False,
            ends_at__lte=now,
        )
        .order_by("id")[:limit]
    )
    count = 0
    for subscription in expired_qs:
        subscription.status = ExtrasPortalSubscriptionStatus.INACTIVE
        subscription.save(update_fields=["status", "updated_at"])
        count += 1
    return {"expired": count}