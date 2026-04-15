from __future__ import annotations

from django.db import transaction
from django.db.models.signals import post_save
from django.dispatch import receiver

from apps.notifications.models import EventLog, EventType
from apps.notifications.services import create_notification
from apps.providers.models import ProviderProfile

from .models import AnalyticsEvent


AD_VISIT_EVENT_NAMES = {
    "promo.banner_click",
    "promo.featured_specialist_click",
    "promo.portfolio_showcase_click",
    "promo.popup_click",
}


def _provider_profile_for_event(instance: AnalyticsEvent) -> ProviderProfile | None:
    payload = getattr(instance, "payload", None) or {}
    candidates = [
        payload.get("provider_id"),
        payload.get("provider_profile_id"),
        getattr(instance, "object_id", ""),
    ]

    for raw_value in candidates:
        try:
            numeric_id = int(str(raw_value or "").strip())
        except (TypeError, ValueError):
            continue

        provider = ProviderProfile.objects.select_related("user").filter(id=numeric_id).first()
        if provider is not None:
            return provider

        provider = ProviderProfile.objects.select_related("user").filter(user_id=numeric_id).first()
        if provider is not None:
            return provider

    return None


def _ad_visit_surface_label(instance: AnalyticsEvent) -> str:
    event_name = str(getattr(instance, "event_name", "") or "").strip().lower()
    if event_name == "promo.featured_specialist_click":
        return "بطاقة المختص المميز"
    if event_name == "promo.portfolio_showcase_click":
        return "معرض الأعمال"
    if event_name == "promo.popup_click":
        return "النافذة الترويجية"
    surface = str(getattr(instance, "surface", "") or "").strip()
    return surface or "إعلانك الترويجي"


@receiver(post_save, sender=AnalyticsEvent)
def notify_provider_ad_visit(sender, instance: AnalyticsEvent, created, **kwargs):
    if not created:
        return

    event_name = str(getattr(instance, "event_name", "") or "").strip().lower()
    if event_name not in AD_VISIT_EVENT_NAMES:
        return

    provider = _provider_profile_for_event(instance)
    provider_user = getattr(provider, "user", None)
    provider_user_id = getattr(provider_user, "id", None)
    actor_id = getattr(instance, "actor_id", None)
    if provider_user is None or not provider_user_id or provider_user_id == actor_id:
        return

    if EventLog.objects.filter(
        event_type=EventType.AD_VISIT,
        target_user_id=provider_user_id,
        request_id=instance.id,
    ).exists():
        return

    surface_label = _ad_visit_surface_label(instance)

    transaction.on_commit(
        lambda: create_notification(
            user=provider_user,
            title="تم تسجيل زيارة جديدة لإعلانك",
            body=f"تفاعل مستخدم مع {surface_label} الخاصة بك.",
            kind="info",
            url="/promotion/",
            actor=instance.actor,
            event_type=EventType.AD_VISIT,
            request_id=instance.id,
            meta={
                "analytics_event_id": instance.id,
                "event_name": event_name,
                "surface": str(getattr(instance, "surface", "") or ""),
                "object_type": str(getattr(instance, "object_type", "") or ""),
                "object_id": str(getattr(instance, "object_id", "") or ""),
                "provider_id": getattr(provider, "id", None),
            },
            pref_key="new_ad_visit",
            audience_mode="provider",
        )
    )