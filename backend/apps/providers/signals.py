from django.db import transaction
from django.db.models.signals import post_save
from django.dispatch import receiver

from apps.notifications.models import EventLog, EventType
from apps.notifications.services import create_notification

from .models import (
    ProviderContentComment,
    ProviderCategory,
    ProviderFollow,
    ProviderLike,
    ProviderPortfolioLike,
    ProviderPortfolioSave,
    ProviderSpotlightItem,
    ProviderSpotlightLike,
    ProviderSpotlightSave,
)


def _actor_label(user) -> str:
    if user is None:
        return "مستخدم"
    full_name = " ".join(
        part.strip()
        for part in [
            str(getattr(user, "first_name", "") or "").strip(),
            str(getattr(user, "last_name", "") or "").strip(),
        ]
        if part and part.strip()
    ).strip()
    if full_name:
        return full_name
    username = str(getattr(user, "username", "") or "").strip()
    if username:
        return username
    phone = str(getattr(user, "phone", "") or "").strip()
    if phone:
        return phone
    return "مستخدم"


def _provider_url(provider_id: int | None) -> str:
    if not provider_id:
        return "/providers/"
    return f"/provider/{provider_id}/"


def _same_category_provider_profiles(*, source_provider, category_ids: list[int]):
    if source_provider is None or not getattr(source_provider, "id", None) or not category_ids:
        return []

    return list(
        type(source_provider)
        .objects.select_related("user")
        .filter(
            providercategory__subcategory__category_id__in=category_ids,
        )
        .exclude(id=source_provider.id)
        .distinct()
    )


def _provider_display_label(provider) -> str:
    label = str(getattr(provider, "display_name", "") or "").strip()
    if label:
        return label
    return _actor_label(getattr(provider, "user", None))


def _schedule_same_category_notification(
    *,
    source_provider,
    category_ids: list[int],
    title: str,
    body: str,
    pref_key: str,
    event_type: str,
    request_id: int,
    offer_id: int | None = None,
    meta: dict | None = None,
):
    source_user = getattr(source_provider, "user", None)
    if source_provider is None or source_user is None or not category_ids:
        return

    payload = dict(meta or {})
    payload.setdefault("provider_id", getattr(source_provider, "id", None))
    payload.setdefault("category_ids", list(category_ids))

    def _send():
        recipients = _same_category_provider_profiles(
            source_provider=source_provider,
            category_ids=category_ids,
        )
        for recipient in recipients:
            recipient_user = getattr(recipient, "user", None)
            recipient_user_id = getattr(recipient_user, "id", None)
            if recipient_user is None or not recipient_user_id:
                continue
            if EventLog.objects.filter(
                event_type=event_type,
                target_user_id=recipient_user_id,
                request_id=request_id,
                offer_id=offer_id,
            ).exists():
                continue

            create_notification(
                user=recipient_user,
                title=title,
                body=body,
                kind="info",
                url=_provider_url(getattr(source_provider, "id", None)),
                actor=source_user,
                event_type=event_type,
                request_id=request_id,
                offer_id=offer_id,
                meta={
                    **payload,
                    "recipient_provider_id": getattr(recipient, "id", None),
                },
                pref_key=pref_key,
                audience_mode="provider",
            )

    transaction.on_commit(_send)


def _notify_provider_social_event(*, provider, actor, title: str, body: str, pref_key: str, meta: dict | None = None) -> None:
    provider_user = getattr(provider, "user", None)
    provider_user_id = getattr(provider_user, "id", None)
    actor_id = getattr(actor, "id", None)
    provider_id = getattr(provider, "id", None)
    if provider_user is None or not provider_user_id or actor_id == provider_user_id:
        return

    payload = {
        "provider_id": provider_id,
        **(meta or {}),
    }

    transaction.on_commit(
        lambda: create_notification(
            user=provider_user,
            title=title,
            body=body,
            kind="info",
            url=_provider_url(provider_id),
            actor=actor,
            meta=payload,
            pref_key=pref_key,
            audience_mode="provider",
        )
    )


@receiver(post_save, sender=ProviderFollow)
def notify_provider_follow(sender, instance: ProviderFollow, created, **kwargs):
    if not created:
        return

    actor_label = _actor_label(instance.user)
    _notify_provider_social_event(
        provider=instance.provider,
        actor=instance.user,
        title="متابعة جديدة لملفك الشخصي",
        body=f"قام {actor_label} بمتابعة ملفك الشخصي.",
        pref_key="new_follow",
        meta={"follower_id": instance.user_id, "role_context": instance.role_context},
    )


@receiver(post_save, sender=ProviderLike)
def notify_provider_like(sender, instance: ProviderLike, created, **kwargs):
    if not created:
        return

    actor_label = _actor_label(instance.user)
    _notify_provider_social_event(
        provider=instance.provider,
        actor=instance.user,
        title="إعجاب جديد بملفك الشخصي",
        body=f"أبدى {actor_label} إعجابه بملفك الشخصي.",
        pref_key="new_like_profile",
        meta={"liker_id": instance.user_id, "role_context": instance.role_context},
    )


@receiver(post_save, sender=ProviderPortfolioLike)
def notify_provider_portfolio_like(sender, instance: ProviderPortfolioLike, created, **kwargs):
    if not created:
        return

    actor_label = _actor_label(instance.user)
    _notify_provider_social_event(
        provider=instance.item.provider,
        actor=instance.user,
        title="إعجاب جديد على أحد أعمالك",
        body=f"أبدى {actor_label} إعجابه بأحد عناصر معرض أعمالك.",
        pref_key="new_like_services",
        meta={"liker_id": instance.user_id, "item_id": instance.item_id, "item_type": "portfolio", "role_context": instance.role_context},
    )


@receiver(post_save, sender=ProviderSpotlightLike)
def notify_provider_spotlight_like(sender, instance: ProviderSpotlightLike, created, **kwargs):
    if not created:
        return

    actor_label = _actor_label(instance.user)
    _notify_provider_social_event(
        provider=instance.item.provider,
        actor=instance.user,
        title="إعجاب جديد على أحد عناصر الأضواء",
        body=f"أبدى {actor_label} إعجابه بأحد عناصر الأضواء الخاصة بك.",
        pref_key="new_like_services",
        meta={"liker_id": instance.user_id, "item_id": instance.item_id, "item_type": "spotlight", "role_context": instance.role_context},
    )


@receiver(post_save, sender=ProviderPortfolioSave)
def notify_provider_portfolio_save(sender, instance: ProviderPortfolioSave, created, **kwargs):
    if not created:
        return

    actor_label = _actor_label(instance.user)
    _notify_provider_social_event(
        provider=instance.item.provider,
        actor=instance.user,
        title="تم حفظ أحد أعمالك في المفضلة",
        body=f"قام {actor_label} بحفظ أحد عناصر معرض أعمالك في المفضلة.",
        pref_key="new_like_services",
        meta={"saver_id": instance.user_id, "item_id": instance.item_id, "item_type": "portfolio", "role_context": instance.role_context, "interaction_type": "save"},
    )


@receiver(post_save, sender=ProviderSpotlightSave)
def notify_provider_spotlight_save(sender, instance: ProviderSpotlightSave, created, **kwargs):
    if not created:
        return

    actor_label = _actor_label(instance.user)
    _notify_provider_social_event(
        provider=instance.item.provider,
        actor=instance.user,
        title="تم حفظ أحد عناصر الأضواء في المفضلة",
        body=f"قام {actor_label} بحفظ أحد عناصر الأضواء الخاصة بك في المفضلة.",
        pref_key="new_like_services",
        meta={"saver_id": instance.user_id, "item_id": instance.item_id, "item_type": "spotlight", "role_context": instance.role_context, "interaction_type": "save"},
    )


@receiver(post_save, sender=ProviderContentComment)
def notify_provider_content_comment(sender, instance: ProviderContentComment, created, **kwargs):
    if not created or not instance.is_approved:
        return

    actor_label = _actor_label(instance.user)
    comment_excerpt = str(instance.body or "").strip()
    if len(comment_excerpt) > 120:
        comment_excerpt = f"{comment_excerpt[:117].rstrip()}..."
    target_label = "معرض أعمالك" if instance.portfolio_item_id else "أحد عناصر الأضواء"
    body = f"أضاف {actor_label} تعليقاً جديداً على {target_label}."
    if comment_excerpt:
        body = f"{body} \"{comment_excerpt}\""

    _notify_provider_social_event(
        provider=instance.provider,
        actor=instance.user,
        title="تعليق جديد على خدماتك",
        body=body,
        pref_key="new_comment_services",
        meta={
            "comment_id": instance.id,
            "commenter_id": instance.user_id,
            "portfolio_item_id": instance.portfolio_item_id,
            "spotlight_item_id": instance.spotlight_item_id,
        },
    )


@receiver(post_save, sender=ProviderCategory)
def notify_new_provider_same_category(sender, instance: ProviderCategory, created, **kwargs):
    if not created:
        return

    provider = getattr(instance, "provider", None)
    subcategory = getattr(instance, "subcategory", None)
    category = getattr(subcategory, "category", None)
    category_id = getattr(category, "id", None)
    if provider is None or category_id is None:
        return

    provider_label = _provider_display_label(provider)
    category_label = str(getattr(category, "name", "") or "").strip() or "فئتك"
    _schedule_same_category_notification(
        source_provider=provider,
        category_ids=[category_id],
        title="انضم مقدم خدمة جديد إلى فئتك",
        body=f"انضم {provider_label} إلى فئة {category_label}.",
        pref_key="new_provider_same_category",
        event_type=EventType.PROVIDER_JOINED_CATEGORY,
        request_id=getattr(provider, "id", 0) or 0,
        offer_id=category_id,
        meta={
            "subcategory_id": getattr(subcategory, "id", None),
            "subcategory_name": str(getattr(subcategory, "name", "") or ""),
            "category_id": category_id,
            "category_name": category_label,
        },
    )


@receiver(post_save, sender=ProviderSpotlightItem)
def notify_highlight_same_category(sender, instance: ProviderSpotlightItem, created, **kwargs):
    if not created:
        return

    provider = getattr(instance, "provider", None)
    if provider is None:
        return

    category_rows = list(
        ProviderCategory.objects.filter(provider=provider)
        .select_related("subcategory__category")
        .values_list("subcategory__category_id", "subcategory__category__name")
        .distinct()
    )
    category_ids = [row[0] for row in category_rows if row[0]]
    if not category_ids:
        return

    provider_label = _provider_display_label(provider)
    primary_category_label = str(category_rows[0][1] or "").strip() if category_rows else "فئتك"
    caption = str(getattr(instance, "caption", "") or "").strip()
    if len(caption) > 120:
        caption = f"{caption[:117].rstrip()}..."
    body = f"نشر {provider_label} لمحة جديدة ضمن فئة {primary_category_label}."
    if caption:
        body = f"{body} \"{caption}\""

    _schedule_same_category_notification(
        source_provider=provider,
        category_ids=category_ids,
        title="تم نشر لمحة جديدة في نفس الفئة",
        body=body,
        pref_key="highlight_same_category",
        event_type=EventType.CATEGORY_HIGHLIGHT_PUBLISHED,
        request_id=getattr(instance, "id", 0) or 0,
        meta={
            "spotlight_item_id": getattr(instance, "id", None),
            "caption": caption,
            "category_names": [str(row[1] or "").strip() for row in category_rows if row[1]],
        },
    )