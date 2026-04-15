from django.db import transaction
from django.db.models.signals import post_save, post_delete
from django.dispatch import receiver

from apps.notifications.services import create_notification

from .models import Review


@receiver(post_save, sender=Review)
def update_provider_rating(sender, instance: Review, created, **kwargs):
    provider_id = instance.provider_id
    if not provider_id:
        return
    from .tasks import recalculate_provider_rating
    transaction.on_commit(lambda: recalculate_provider_rating.delay(provider_id))

    if not created:
        return

    provider_user = getattr(getattr(instance, "provider", None), "user", None)
    provider_user_id = getattr(provider_user, "id", None)
    client_id = getattr(instance, "client_id", None)
    if provider_user is None or not provider_user_id or provider_user_id == client_id:
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
        return

    comment_excerpt = str(getattr(instance, "comment", "") or "").strip()
    if len(comment_excerpt) > 140:
        comment_excerpt = f"{comment_excerpt[:137].rstrip()}..."
    body = f"تلقيت تقييماً جديداً بدرجة {rating}/5 على أحد طلباتك المكتملة."
    if comment_excerpt:
        body = f"{body} \"{comment_excerpt}\""

    transaction.on_commit(
        lambda: create_notification(
            user=provider_user,
            title=title,
            body=body,
            kind=kind,
            url=f"/requests/{instance.request_id}/",
            actor=instance.client,
            request_id=instance.request_id,
            meta={
                "review_id": instance.id,
                "provider_id": instance.provider_id,
                "rating": rating,
            },
            pref_key=pref_key,
            audience_mode="provider",
        )
    )


@receiver(post_delete, sender=Review)
def update_provider_rating_on_delete(sender, instance: Review, **kwargs):
    provider_id = instance.provider_id
    if not provider_id:
        return
    from .tasks import recalculate_provider_rating
    transaction.on_commit(lambda: recalculate_provider_rating.delay(provider_id))
