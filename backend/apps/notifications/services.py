from django.db import transaction

from apps.subscriptions.models import Subscription, SubscriptionStatus

from .models import (
    Notification,
    EventLog,
    EventType,
    NotificationPreference,
    NotificationTier,
)
from .push import send_push_for_notification


NOTIFICATION_CATALOG = {
    # الباقة الأساسية
    "new_request": {
        "title": "إشعار طلب جديد",
        "tier": NotificationTier.BASIC,
        "default_enabled": True,
    },
    "request_status_change": {
        "title": "تغير في حالة/بيانات طلب",
        "tier": NotificationTier.BASIC,
        "default_enabled": True,
    },
    "urgent_request": {
        "title": "إشعار طلب خدمة عاجلة",
        "tier": NotificationTier.BASIC,
        "default_enabled": True,
    },
    "report_status_change": {
        "title": "تغير في حالة/بيانات بلاغ",
        "tier": NotificationTier.BASIC,
        "default_enabled": True,
    },
    "new_chat_message": {
        "title": "إشعار محادثة جديدة",
        "tier": NotificationTier.BASIC,
        "default_enabled": True,
    },
    "service_reply": {
        "title": "رد على طلب خدمة",
        "tier": NotificationTier.BASIC,
        "default_enabled": True,
    },
    "platform_recommendations": {
        "title": "توصيات منصة نوافذ",
        "tier": NotificationTier.BASIC,
        "default_enabled": True,
    },
    # الباقة الريادية
    "new_follow": {
        "title": "متابعة جديدة لمنصتك",
        "tier": NotificationTier.LEADING,
        "default_enabled": True,
    },
    "new_comment_services": {
        "title": "تعليق جديد على خدماتك",
        "tier": NotificationTier.LEADING,
        "default_enabled": True,
    },
    "new_like_profile": {
        "title": "تفضيل جديد لمنصتك",
        "tier": NotificationTier.LEADING,
        "default_enabled": True,
    },
    "new_like_services": {
        "title": "تفضيل جديد لخدماتك",
        "tier": NotificationTier.LEADING,
        "default_enabled": True,
    },
    "competitive_offer_request": {
        "title": "طلب عرض خدمة تنافسية",
        "tier": NotificationTier.LEADING,
        "default_enabled": True,
    },
    # الباقة الاحترافية
    "positive_review": {
        "title": "تقييم إيجابي لخدماتك",
        "tier": NotificationTier.PROFESSIONAL,
        "default_enabled": True,
    },
    "negative_review": {
        "title": "تقييم سلبي لخدماتك",
        "tier": NotificationTier.PROFESSIONAL,
        "default_enabled": True,
    },
    "new_provider_same_category": {
        "title": "مقدم خدمة جديد في نفس الفئة",
        "tier": NotificationTier.PROFESSIONAL,
        "default_enabled": True,
    },
    "highlight_same_category": {
        "title": "لمحة في نفس الفئة",
        "tier": NotificationTier.PROFESSIONAL,
        "default_enabled": True,
    },
    "ads_and_offers": {
        "title": "الإعلانات والعروض",
        "tier": NotificationTier.PROFESSIONAL,
        "default_enabled": True,
    },
    # الخدمات الإضافية
    "new_payment": {
        "title": "عملية سداد جديدة",
        "tier": NotificationTier.EXTRA,
        "default_enabled": True,
    },
    "new_ad_visit": {
        "title": "زيارة جديدة للإعلان",
        "tier": NotificationTier.EXTRA,
        "default_enabled": True,
    },
    "report_completed": {
        "title": "تقرير مكتمل",
        "tier": NotificationTier.EXTRA,
        "default_enabled": True,
    },
    "verification_completed": {
        "title": "اكتمال طلب توثيق",
        "tier": NotificationTier.EXTRA,
        "default_enabled": True,
    },
    "paid_subscription_completed": {
        "title": "اكتمال طلب اشتراك مدفوع",
        "tier": NotificationTier.EXTRA,
        "default_enabled": True,
    },
    "customer_service_package_completed": {
        "title": "اكتمال باقة خدمة عملاء",
        "tier": NotificationTier.EXTRA,
        "default_enabled": True,
    },
    "finance_package_completed": {
        "title": "اكتمال باقة إدارة مالية",
        "tier": NotificationTier.EXTRA,
        "default_enabled": True,
    },
    "scheduled_ticket_reminder": {
        "title": "تذاكر بخدمة مجدولة",
        "tier": NotificationTier.EXTRA,
        "default_enabled": True,
    },
}


EVENT_TO_PREF_KEY = {
    EventType.REQUEST_CREATED: "new_request",
    EventType.OFFER_CREATED: "service_reply",
    EventType.OFFER_SELECTED: "service_reply",
    EventType.STATUS_CHANGED: "request_status_change",
    EventType.MESSAGE_NEW: "new_chat_message",
}


def _user_tier_level(user) -> int:
    """
    1=basic, 2=leading, 3=professional
    """
    active = (
        Subscription.objects.filter(
            user=user,
            status=SubscriptionStatus.ACTIVE,
        )
        .select_related("plan")
        .order_by("-id")
        .first()
    )
    if not active:
        return 1

    code = (active.plan.code or "").strip().upper()
    title = (active.plan.title or "").strip()
    features = set(active.plan.features or [])

    if (
        "PROFESSIONAL" in code
        or "احتراف" in title
        or "advanced_analytics" in features
    ):
        return 3
    if "PRO" in code or "رائد" in title or "priority_support" in features:
        return 2
    return 1


def _is_pref_locked(user, pref_key: str) -> bool:
    config = NOTIFICATION_CATALOG.get(pref_key)
    if not config:
        return False
    tier = config["tier"]
    if tier == NotificationTier.BASIC:
        return False
    user_level = _user_tier_level(user)
    if tier == NotificationTier.LEADING:
        return user_level < 2
    if tier in {NotificationTier.PROFESSIONAL, NotificationTier.EXTRA}:
        return user_level < 3
    return False


def get_or_create_notification_preferences(user):
    existing = {
        p.key: p
        for p in NotificationPreference.objects.filter(user=user)
    }
    creates = []
    for key, cfg in NOTIFICATION_CATALOG.items():
        if key in existing:
            continue
        creates.append(
            NotificationPreference(
                user=user,
                key=key,
                enabled=bool(cfg.get("default_enabled", True)),
                tier=cfg["tier"],
            )
        )
    if creates:
        NotificationPreference.objects.bulk_create(creates)
    return list(NotificationPreference.objects.filter(user=user).order_by("tier", "id"))


def should_send_notification(*, user, pref_key: str | None) -> bool:
    if not pref_key:
        return True
    if pref_key not in NOTIFICATION_CATALOG:
        return True
    if _is_pref_locked(user, pref_key):
        return False
    pref = NotificationPreference.objects.filter(user=user, key=pref_key).first()
    if pref is None:
        cfg = NOTIFICATION_CATALOG[pref_key]
        pref = NotificationPreference.objects.create(
            user=user,
            key=pref_key,
            enabled=bool(cfg.get("default_enabled", True)),
            tier=cfg["tier"],
        )
    return bool(pref.enabled)


def create_notification(
    *,
    user,
    title: str,
    body: str,
    kind: str = "info",
    url: str = "",
    actor=None,
    event_type: str | None = None,
    request_id: int | None = None,
    offer_id: int | None = None,
    message_id: int | None = None,
    meta: dict | None = None,
    is_urgent: bool = False,
    pref_key: str | None = None,
    audience_mode: str = "shared",
):
    meta = meta or {}
    derived_pref_key = pref_key or EVENT_TO_PREF_KEY.get(event_type or "")
    if not should_send_notification(user=user, pref_key=derived_pref_key):
        return None

    with transaction.atomic():
        notif = Notification.objects.create(
            user=user,
            title=title,
            body=body,
            kind=kind,
            url=url,
            audience_mode=(audience_mode or "shared"),
            is_urgent=bool(is_urgent or kind == "urgent"),
        )
        if event_type:
            EventLog.objects.create(
                event_type=event_type,
                actor=actor,
                target_user=user,
                request_id=request_id,
                offer_id=offer_id,
                message_id=message_id,
                meta=meta,
            )

    try:
        send_push_for_notification(notif)
    except Exception:
        # Fail-open: in-app notifications must still be persisted.
        pass

    return notif
