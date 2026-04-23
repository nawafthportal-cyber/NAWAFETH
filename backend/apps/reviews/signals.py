import logging

from django.db import transaction
from django.db.models.signals import post_delete, post_save, pre_save
from django.dispatch import receiver

from apps.notifications.services import create_notification

from .models import Review, ReviewModerationStatus

logger = logging.getLogger("nawafeth.reviews")


def _provider_user_for_review(instance: Review):
    provider_user = getattr(getattr(instance, "provider", None), "user", None)
    provider_user_id = getattr(provider_user, "id", None)
    client_id = getattr(instance, "client_id", None)
    if provider_user is None or not provider_user_id or provider_user_id == client_id:
        return None
    return provider_user


def _comment_excerpt(value: str, *, limit: int = 140) -> str:
    excerpt = str(value or "").strip()
    if len(excerpt) > limit:
        excerpt = f"{excerpt[: limit - 3].rstrip()}..."
    return excerpt


def _schedule_review_notification(instance: Review, *, title: str, body: str, pref_key: str, kind: str = "info", actor=None, meta: dict | None = None):
    provider_user = _provider_user_for_review(instance)
    if provider_user is None:
        return

    payload = {
        "review_id": instance.id,
        "provider_id": instance.provider_id,
        "rating": int(getattr(instance, "rating", 0) or 0),
        **(meta or {}),
    }
    transaction.on_commit(
        lambda: create_notification(
            user=provider_user,
            title=title,
            body=body,
            kind=kind,
            url=f"/requests/{instance.request_id}/",
            actor=actor,
            request_id=instance.request_id,
            meta=payload,
            pref_key=pref_key,
            audience_mode="provider",
        )
    )


@receiver(pre_save, sender=Review)
def capture_review_previous_state(sender, instance: Review, **kwargs):
    if not getattr(instance, "pk", None):
        return

    instance._previous_notification_state = (
        Review.objects.filter(pk=instance.pk)
        .values("rating", "comment", "moderation_status", "moderation_note")
        .first()
    )


@receiver(post_save, sender=Review)
def update_provider_rating(sender, instance: Review, created, **kwargs):
    provider_id = instance.provider_id
    if not provider_id:
        return

    def _refresh_rating():
        from .services import refresh_provider_rating

        try:
            refresh_provider_rating(provider_id)
        except Exception:
            logger.exception("Failed to refresh provider rating for provider_id=%s", provider_id)

    transaction.on_commit(_refresh_rating)

    if not created:
        return

    rating = int(getattr(instance, "rating", 0) or 0)
    if rating >= 4:
        title = "تقييم إيجابي جديد على خدماتك"
        pref_key = "positive_review"
        kind = "success"
    elif rating <= 2:
        title = "تقييم سلبي جديد على خدماتك"
        pref_key = "negative_review"
        kind = "warn"
    else:
        title = "تقييم جديد على خدماتك"
        pref_key = "review_update"
        kind = "info"

    comment_excerpt = _comment_excerpt(getattr(instance, "comment", "") or "")
    body = f"تلقيت تقييماً جديداً بدرجة {rating}/5 على أحد طلباتك المكتملة."
    if comment_excerpt:
        body = f"{body} \"{comment_excerpt}\""

    _schedule_review_notification(
        instance,
        title=title,
        body=body,
        kind=kind,
        pref_key=pref_key,
        actor=instance.client,
        meta={"event": "review_created"},
    )


@receiver(post_save, sender=Review)
def notify_provider_review_updates(sender, instance: Review, created, **kwargs):
    if created:
        return

    previous = getattr(instance, "_previous_notification_state", None) or {}
    if not previous:
        return

    changed_fields = {
        field
        for field in ("rating", "comment", "moderation_status", "moderation_note")
        if previous.get(field) != getattr(instance, field)
    }
    if not changed_fields:
        return

    if "moderation_status" in changed_fields or "moderation_note" in changed_fields:
        status_label = instance.get_moderation_status_display()
        title = "تم تحديث حالة مراجعة على خدماتك"
        body = f"تم تحديث حالة مراجعة على أحد طلباتك إلى: {status_label}."
        moderation_note = str(getattr(instance, "moderation_note", "") or "").strip()
        if moderation_note:
            body = f"{body} {moderation_note}"
        actor = getattr(instance, "moderated_by", None) or instance.client
        kind = "warn" if instance.moderation_status in {ReviewModerationStatus.HIDDEN, ReviewModerationStatus.REJECTED} else "info"
        meta = {"event": "review_moderation_updated", "changed_fields": sorted(changed_fields), "moderation_status": instance.moderation_status}
    else:
        comment_excerpt = _comment_excerpt(getattr(instance, "comment", "") or "")
        title = "تم تحديث مراجعة على خدماتك"
        body = f"تم تحديث مراجعة على أحد طلباتك إلى درجة {int(getattr(instance, 'rating', 0) or 0)}/5."
        if comment_excerpt:
            body = f"{body} \"{comment_excerpt}\""
        actor = instance.client
        kind = "info"
        meta = {"event": "review_updated", "changed_fields": sorted(changed_fields)}

    _schedule_review_notification(
        instance,
        title=title,
        body=body,
        pref_key="review_update",
        kind=kind,
        actor=actor,
        meta=meta,
    )


@receiver(post_delete, sender=Review)
def update_provider_rating_on_delete(sender, instance: Review, **kwargs):
    provider_id = instance.provider_id
    if not provider_id:
        return

    def _refresh_rating():
        from .services import refresh_provider_rating

        try:
            refresh_provider_rating(provider_id)
        except Exception:
            logger.exception("Failed to refresh provider rating for provider_id=%s", provider_id)

    transaction.on_commit(_refresh_rating)
