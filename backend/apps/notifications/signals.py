from django.db.models.signals import post_save
from django.dispatch import receiver

from apps.accounts.models import User
from apps.marketplace.models import (
    Offer,
    OfferStatus,
    RequestStatusLog,
)
from apps.marketplace.services.cancellation_copy import client_cancel_status_notification_text
from apps.messaging.models import Message

from .models import EventLog, EventType
from .services import create_notification


def _audience_mode_for_user(user: User, *, context_mode: str = "") -> str:
    """Determine audience_mode for a notification.

    If an explicit context_mode (from Thread.context_mode) is provided and
    is either 'client' or 'provider', it takes precedence over the user's
    global role_state — this correctly isolates notifications for users who
    hold both roles.
    """
    ctx = (context_mode or "").strip().lower()
    if ctx in ("client", "provider"):
        return ctx
    role_state = (getattr(user, "role_state", "") or "").strip().lower()
    if role_state == "provider":
        return "provider"
    return "client"


def _status_label(raw: str) -> str:
    s = (raw or "").strip().lower()
    if s == "new":
        return "جديد"
    if s == "in_progress":
        return "تحت التنفيذ"
    if s == "completed":
        return "مكتمل"
    if s in {"cancelled", "canceled"}:
        return "ملغي"
    return raw or "-"


@receiver(post_save, sender=Offer)
def notify_offer_created(sender, instance: Offer, created, **kwargs):
    if not created:
        return
    sr = instance.request
    # إشعار للعميل فقط
    create_notification(
        user=sr.client,
        title="وصل عرض جديد",
        body=f"تم تقديم عرض على طلبك: {sr.title}",
        kind="offer_created",
        url=f"/requests/{sr.id}",
        actor=instance.provider.user,
        event_type=EventType.OFFER_CREATED,
        pref_key="service_reply",
        request_id=sr.id,
        offer_id=instance.id,
        meta={"price": str(instance.price), "duration_days": instance.duration_days},
        audience_mode="client",
    )


@receiver(post_save, sender=Offer)
def notify_offer_selected(sender, instance: Offer, created, **kwargs):
    # نطلق إشعار فقط إذا أصبح SELECTED
    if instance.status != OfferStatus.SELECTED:
        return
    sr = instance.request
    if EventLog.objects.filter(
        event_type=EventType.OFFER_SELECTED,
        target_user_id=instance.provider.user_id,
        offer_id=instance.id,
    ).exists():
        return
    create_notification(
        user=instance.provider.user,
        title="تم اختيار عرضك",
        body=f"العميل اختار عرضك على الطلب: {sr.title}",
        kind="offer_selected",
        url=f"/requests/{sr.id}",
        actor=sr.client,
        event_type=EventType.OFFER_SELECTED,
        pref_key="service_reply",
        request_id=sr.id,
        offer_id=instance.id,
        audience_mode="provider",
    )


@receiver(post_save, sender=Message)
def notify_new_message(sender, instance: Message, created, **kwargs):
    if not created:
        return
    thread = instance.thread

    # Direct thread: notify the other participant.
    if thread.is_direct:
        if instance.sender_id == thread.participant_1_id:
            target_id = thread.participant_2_id
        elif instance.sender_id == thread.participant_2_id:
            target_id = thread.participant_1_id
        else:
            return

        if not target_id:
            return

        target = User.objects.filter(id=target_id).first()
        if not target:
            return

        target_mode = thread.participant_mode_for_user(target)
        if target_mode not in ("client", "provider"):
            target_mode = _audience_mode_for_user(target, context_mode=thread.context_mode)

        create_notification(
            user=target,
            title="رسالة جديدة",
            body="لديك رسالة جديدة في المحادثة.",
            kind="message_new",
            url=f"/threads/{thread.id}/chat",
            actor=instance.sender,
            event_type=EventType.MESSAGE_NEW,
            pref_key="new_chat_message",
            message_id=instance.id,
            meta={"thread_id": thread.id, "is_direct": True},
            audience_mode=target_mode,
        )
        return

    sr = thread.request
    if sr is None:
        return

    # Request thread: notify the opposite party only.
    if sr.provider_id and instance.sender_id == sr.client_id:
        target = sr.provider.user
    elif sr.provider_id and instance.sender_id == sr.provider.user_id:
        target = sr.client
    else:
        return

    create_notification(
        user=target,
        title="رسالة جديدة",
        body="لديك رسالة جديدة على طلبك.",
        kind="message_new",
        url=f"/requests/{sr.id}/chat",
        actor=instance.sender,
        event_type=EventType.MESSAGE_NEW,
        pref_key="new_chat_message",
        request_id=sr.id,
        message_id=instance.id,
        meta={"thread_id": thread.id, "is_direct": False},
        audience_mode="provider" if sr.provider_id and target.id == sr.provider.user_id else "client",
    )


@receiver(post_save, sender=RequestStatusLog)
def notify_request_status_changed(sender, instance: RequestStatusLog, created, **kwargs):
    if not created:
        return

    sr = instance.request
    recipients = []
    if sr.client_id:
        recipients.append(sr.client)
    if sr.provider_id and sr.provider.user_id:
        recipients.append(sr.provider.user)

    if not recipients:
        return

    status_label = _status_label(instance.to_status)
    note = (instance.note or "").strip()
    if instance.to_status == "new" and "اختيار عرض" in note:
        # Offer selection already emits OFFER_SELECTED notification.
        return
    for target in recipients:
        is_provider_target = bool(sr.provider_id and target.id == sr.provider.user_id)
        audience_mode = "provider" if is_provider_target else "client"
        is_self_action = bool(instance.actor_id and target.id == instance.actor_id)

        if instance.to_status == "completed" and is_provider_target and is_self_action:
            continue

        body = f"تم تحديث حالة طلبك ({sr.title}) إلى: {status_label}"
        if instance.to_status == "completed":
            if is_provider_target:
                if note and "يرجى مراجعة الطلب وتقييم الخدمة" not in note:
                    body = f"{body}. {note}"
            else:
                body = f"اكتمل طلبك ({sr.title}). يمكنك الآن مراجعة الطلب وتقييم الخدمة."
                if note and "يرجى مراجعة الطلب وتقييم الخدمة" not in note:
                    body = f"{body} {note}"
        elif instance.to_status in {"cancelled", "canceled"} and not is_provider_target:
            body = client_cancel_status_notification_text(
                sr=sr,
                actor=instance.actor,
                note_text=note,
            )
        elif note:
            body = f"{body}. {note}"

        create_notification(
            user=target,
            title=f"تحديث الطلب: {sr.title}",
            body=body,
            kind="request_status_change",
            url=f"/requests/{sr.id}",
            actor=instance.actor,
            event_type=EventType.STATUS_CHANGED,
            pref_key="request_status_change",
            request_id=sr.id,
            meta={
                "from_status": instance.from_status,
                "to_status": instance.to_status,
                "note": note,
            },
            audience_mode=audience_mode,
        )
