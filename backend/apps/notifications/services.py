from django.db import transaction
from django.utils import timezone

from apps.extras.services import user_has_active_extra
from apps.extras_portal.models import ExtrasPortalSubscription, ExtrasPortalSubscriptionStatus
from apps.subscriptions.capabilities import plan_capabilities_for_user
from apps.subscriptions.services import user_plan_tier
from apps.subscriptions.tiering import CanonicalPlanTier, canonical_tier_from_value, canonical_tier_order

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
        "audience_modes": ("provider",),
        "required_tier": CanonicalPlanTier.BASIC,
    },
    "request_status_change": {
        "title": "تغير في حالة/بيانات طلب",
        "tier": NotificationTier.BASIC,
        "default_enabled": True,
        "audience_modes": ("client", "provider", "shared"),
        "required_tier": CanonicalPlanTier.BASIC,
    },
    "promo_status_change": {
        "title": "تحديث حالة طلب ترويج",
        "tier": NotificationTier.BASIC,
        "default_enabled": True,
        "audience_modes": ("provider", "shared"),
        "expose_in_settings": False,
        "required_tier": CanonicalPlanTier.BASIC,
    },
    "urgent_request": {
        "title": "إشعار طلب خدمة عاجلة",
        "tier": NotificationTier.BASIC,
        "default_enabled": True,
        "audience_modes": ("provider",),
        "required_tier": CanonicalPlanTier.BASIC,
    },
    "report_status_change": {
        "title": "تغير في حالة/بيانات بلاغ",
        "tier": NotificationTier.BASIC,
        "default_enabled": True,
        "audience_modes": ("client", "provider", "shared"),
        "required_tier": CanonicalPlanTier.BASIC,
    },
    "new_chat_message": {
        "title": "إشعار محادثة جديدة",
        "tier": NotificationTier.BASIC,
        "default_enabled": True,
        "audience_modes": ("client", "provider", "shared"),
        "required_tier": CanonicalPlanTier.BASIC,
    },
    "service_reply": {
        "title": "رد على طلب خدمة",
        "tier": NotificationTier.BASIC,
        "default_enabled": True,
        "audience_modes": ("client", "provider", "shared"),
        "required_tier": CanonicalPlanTier.BASIC,
    },
    "platform_recommendations": {
        "title": "توصيات منصة نوافذ",
        "tier": NotificationTier.BASIC,
        "default_enabled": True,
        "audience_modes": ("client", "provider", "shared"),
        "required_tier": CanonicalPlanTier.BASIC,
    },
    # الباقة الريادية
    "new_follow": {
        "title": "متابعة جديدة لمنصتك",
        "tier": NotificationTier.LEADING,
        "default_enabled": True,
        "audience_modes": ("provider",),
        "required_tier": CanonicalPlanTier.PIONEER,
    },
    "new_comment_services": {
        "title": "تعليق جديد على خدماتك",
        "tier": NotificationTier.LEADING,
        "default_enabled": True,
        "audience_modes": ("provider",),
        "required_tier": CanonicalPlanTier.PIONEER,
    },
    "new_like_profile": {
        "title": "تفضيل جديد لمنصتك",
        "tier": NotificationTier.LEADING,
        "default_enabled": True,
        "audience_modes": ("provider",),
        "required_tier": CanonicalPlanTier.PIONEER,
    },
    "new_like_services": {
        "title": "تفضيل جديد لخدماتك",
        "tier": NotificationTier.LEADING,
        "default_enabled": True,
        "audience_modes": ("provider",),
        "required_tier": CanonicalPlanTier.PIONEER,
    },
    "competitive_offer_request": {
        "title": "طلب عرض خدمة تنافسية",
        "tier": NotificationTier.LEADING,
        "default_enabled": True,
        "audience_modes": ("provider",),
        "required_tier": CanonicalPlanTier.PIONEER,
    },
    # الباقة الاحترافية
    "positive_review": {
        "title": "تقييم إيجابي لخدماتك",
        "tier": NotificationTier.PROFESSIONAL,
        "default_enabled": True,
        "audience_modes": ("provider",),
        "required_tier": CanonicalPlanTier.PROFESSIONAL,
    },
    "negative_review": {
        "title": "تقييم سلبي لخدماتك",
        "tier": NotificationTier.PROFESSIONAL,
        "default_enabled": True,
        "audience_modes": ("provider",),
        "required_tier": CanonicalPlanTier.PROFESSIONAL,
    },
    "new_provider_same_category": {
        "title": "مقدم خدمة جديد في نفس الفئة",
        "tier": NotificationTier.PROFESSIONAL,
        "default_enabled": True,
        "audience_modes": ("provider",),
        "required_tier": CanonicalPlanTier.PROFESSIONAL,
    },
    "highlight_same_category": {
        "title": "لمحة في نفس الفئة",
        "tier": NotificationTier.PROFESSIONAL,
        "default_enabled": True,
        "audience_modes": ("provider",),
        "required_tier": CanonicalPlanTier.PROFESSIONAL,
    },
    "ads_and_offers": {
        "title": "الإعلانات والعروض",
        "tier": NotificationTier.PROFESSIONAL,
        "default_enabled": True,
        "audience_modes": ("provider",),
        "required_tier": CanonicalPlanTier.PROFESSIONAL,
        "required_capabilities": ("promotional_controls.notification_messages",),
        "missing_capability_reason": "يتطلب نوع اشتراك يسمح بالإشعارات الدعائية.",
    },
    # الخدمات الإضافية
    "new_payment": {
        "title": "عملية سداد جديدة",
        "tier": NotificationTier.EXTRA,
        "default_enabled": True,
        "audience_modes": ("provider",),
        "required_tier": CanonicalPlanTier.BASIC,
    },
    "new_ad_visit": {
        "title": "زيارة جديدة للإعلان",
        "tier": NotificationTier.EXTRA,
        "default_enabled": True,
        "audience_modes": ("provider",),
        "required_tier": CanonicalPlanTier.BASIC,
        "required_extra_prefixes": ("promo_boost_",),
        "missing_extra_reason": "يتطلب إضافة ترويج فعالة.",
    },
    "report_completed": {
        "title": "تقرير مكتمل",
        "tier": NotificationTier.EXTRA,
        "default_enabled": True,
        "audience_modes": ("provider",),
        "required_tier": CanonicalPlanTier.BASIC,
        "requires_extras_portal": True,
        "missing_portal_reason": "يتطلب اشتراكًا فعالًا في بوابة التقارير.",
    },
    "verification_completed": {
        "title": "اكتمال طلب توثيق",
        "tier": NotificationTier.EXTRA,
        "default_enabled": True,
        "audience_modes": ("provider",),
        "required_tier": CanonicalPlanTier.BASIC,
    },
    "paid_subscription_completed": {
        "title": "اكتمال طلب اشتراك مدفوع",
        "tier": NotificationTier.EXTRA,
        "default_enabled": True,
        "audience_modes": ("provider",),
        "required_tier": CanonicalPlanTier.BASIC,
    },
    "customer_service_package_completed": {
        "title": "اكتمال باقة خدمة عملاء",
        "tier": NotificationTier.EXTRA,
        "default_enabled": True,
        "audience_modes": ("provider",),
        "required_tier": CanonicalPlanTier.BASIC,
        "requires_extras_portal": True,
        "missing_portal_reason": "يتطلب اشتراكًا فعالًا في بوابة إدارة العملاء.",
    },
    "finance_package_completed": {
        "title": "اكتمال باقة إدارة مالية",
        "tier": NotificationTier.EXTRA,
        "default_enabled": True,
        "audience_modes": ("provider",),
        "required_tier": CanonicalPlanTier.BASIC,
        "requires_extras_portal": True,
        "missing_portal_reason": "يتطلب اشتراكًا فعالًا في بوابة الإدارة المالية.",
    },
    "scheduled_ticket_reminder": {
        "title": "تذكير بخدمة مجدولة",
        "tier": NotificationTier.EXTRA,
        "default_enabled": True,
        "audience_modes": ("provider",),
        "required_tier": CanonicalPlanTier.BASIC,
        "requires_extras_portal": True,
        "missing_portal_reason": "يتطلب اشتراكًا فعالًا في بوابة إدارة العملاء.",
    },
    "excellence_badge_awarded": {
        "title": "شارة تميز جديدة",
        "tier": NotificationTier.PROFESSIONAL,
        "default_enabled": True,
        "audience_modes": ("provider",),
        "expose_in_settings": False,
        "required_tier": CanonicalPlanTier.PROFESSIONAL,
    },
}


EVENT_TO_PREF_KEY = {
    EventType.REQUEST_CREATED: "new_request",
    EventType.OFFER_CREATED: "service_reply",
    EventType.OFFER_SELECTED: "service_reply",
    EventType.STATUS_CHANGED: "request_status_change",
    EventType.MESSAGE_NEW: "new_chat_message",
}


def notification_tier_to_canonical(tier: str) -> str:
    normalized = str(tier or "").strip().lower()
    if normalized == NotificationTier.EXTRA:
        return NotificationTier.EXTRA
    return canonical_tier_from_value(normalized, fallback=CanonicalPlanTier.BASIC) or CanonicalPlanTier.BASIC


def normalize_preference_mode(mode: str | None) -> str:
    raw = str(mode or "").strip().lower()
    if raw == NotificationPreference.AudienceMode.CLIENT:
        return NotificationPreference.AudienceMode.CLIENT
    if raw == NotificationPreference.AudienceMode.PROVIDER:
        return NotificationPreference.AudienceMode.PROVIDER
    return NotificationPreference.AudienceMode.SHARED


def _pref_supported_modes(pref_key: str) -> tuple[str, ...]:
    cfg = NOTIFICATION_CATALOG.get(pref_key, {})
    modes = cfg.get("audience_modes") or (NotificationPreference.AudienceMode.SHARED,)
    return tuple(normalize_preference_mode(mode) for mode in modes)


def _pref_is_exposed(pref_key: str) -> bool:
    cfg = NOTIFICATION_CATALOG.get(pref_key, {})
    return bool(cfg.get("expose_in_settings", True))


def _user_has_provider_profile(user) -> bool:
    try:
        return bool(getattr(user, "provider_profile", None))
    except Exception:
        return False


def _capability_value(capabilities: dict, path: str):
    current = capabilities
    for part in str(path or "").split("."):
        if not isinstance(current, dict) or part not in current:
            return None
        current = current.get(part)
    return current


def _has_active_extras_portal_subscription(user) -> bool:
    if not _user_has_provider_profile(user):
        return False
    now = timezone.now()
    portal = (
        ExtrasPortalSubscription.objects.filter(
            provider=getattr(user, "provider_profile", None),
            status=ExtrasPortalSubscriptionStatus.ACTIVE,
        )
        .only("id", "ends_at")
        .first()
    )
    if portal is None:
        return False
    if portal.ends_at and portal.ends_at <= now:
        return False
    return True


def _notification_entitlement_context(user) -> dict[str, object]:
    return {
        "has_provider_profile": _user_has_provider_profile(user),
        "capabilities": plan_capabilities_for_user(user),
        "user_tier": user_plan_tier(user, fallback=CanonicalPlanTier.BASIC),
        "has_extras_portal": _has_active_extras_portal_subscription(user),
    }


def notification_preference_availability(
    *,
    user,
    pref_key: str,
    audience_mode: str | None = None,
    context: dict[str, object] | None = None,
) -> dict[str, object]:
    cfg = NOTIFICATION_CATALOG.get(pref_key, {})
    if not cfg:
        return {"locked": False, "reason": ""}

    context = context or _notification_entitlement_context(user)
    normalized_mode = normalize_preference_mode(audience_mode)
    if normalized_mode == NotificationPreference.AudienceMode.PROVIDER and not bool(context.get("has_provider_profile")):
        return {
            "locked": True,
            "reason": "يتطلب حساب مزود خدمة نشطًا.",
        }

    capabilities = dict(context.get("capabilities") or {})
    if not bool(capabilities.get("notifications_enabled", True)):
        return {
            "locked": True,
            "reason": "الإشعارات معطلة في نوع الاشتراك الحالي.",
        }

    user_tier = str(context.get("user_tier") or CanonicalPlanTier.BASIC)
    required_tier = canonical_tier_from_value(cfg.get("required_tier"), fallback=CanonicalPlanTier.BASIC)
    if canonical_tier_order(user_tier) < canonical_tier_order(required_tier):
        return {
            "locked": True,
            "reason": f"يلزم الاشتراك في الباقة {CanonicalPlanTier(required_tier).label}.",
        }

    for capability_path in tuple(cfg.get("required_capabilities") or ()):
        value = _capability_value(capabilities, capability_path)
        if capability_path.endswith("schedule_hours_nonempty"):
            if isinstance(value, (list, tuple)) and len(value) > 0:
                continue
        if isinstance(value, (list, tuple, set, dict)):
            is_available = bool(value)
        else:
            is_available = bool(value)
        if not is_available:
            return {
                "locked": True,
                "reason": str(cfg.get("missing_capability_reason") or "غير متاح ضمن نوع الاشتراك الحالي."),
            }

    required_extra_prefixes = tuple(cfg.get("required_extra_prefixes") or ())
    if required_extra_prefixes and not any(user_has_active_extra(user, prefix) for prefix in required_extra_prefixes):
        return {
            "locked": True,
            "reason": str(cfg.get("missing_extra_reason") or "يتطلب خدمة إضافية فعالة."),
        }

    if bool(cfg.get("requires_extras_portal")) and not bool(context.get("has_extras_portal")):
        return {
            "locked": True,
            "reason": str(cfg.get("missing_portal_reason") or "يتطلب اشتراكًا فعالًا في بوابة الخدمات الإضافية."),
        }

    return {"locked": False, "reason": ""}


def _user_tier_level(user) -> int:
    """
    1=basic, 2=pioneer, 3=professional
    """
    tier = user_plan_tier(user, fallback=CanonicalPlanTier.BASIC)
    if tier == CanonicalPlanTier.PROFESSIONAL:
        return 3
    if tier == CanonicalPlanTier.PIONEER:
        return 2
    return 1


def _is_pref_locked(user, pref_key: str, audience_mode: str | None = None) -> bool:
    return bool(notification_preference_availability(user=user, pref_key=pref_key, audience_mode=audience_mode)["locked"])


def get_or_create_notification_preferences(user, *, mode: str | None = None, exposed_only: bool = False):
    normalized_mode = normalize_preference_mode(mode)
    existing = {
        (p.key, p.audience_mode): p
        for p in NotificationPreference.objects.filter(user=user)
    }
    creates = []
    for key, cfg in NOTIFICATION_CATALOG.items():
        supported_modes = _pref_supported_modes(key)
        if normalized_mode == NotificationPreference.AudienceMode.SHARED:
            target_modes = supported_modes
        else:
            target_modes = tuple(mode_key for mode_key in supported_modes if mode_key in {normalized_mode, NotificationPreference.AudienceMode.SHARED})

        for audience_mode in target_modes:
            if (key, audience_mode) in existing:
                continue
            creates.append(
                NotificationPreference(
                    user=user,
                    key=key,
                    audience_mode=audience_mode,
                    enabled=bool(cfg.get("default_enabled", True)),
                    tier=cfg["tier"],
                )
            )
    if creates:
        NotificationPreference.objects.bulk_create(creates)

    qs = NotificationPreference.objects.filter(user=user)
    if normalized_mode in {NotificationPreference.AudienceMode.CLIENT, NotificationPreference.AudienceMode.PROVIDER}:
        qs = qs.filter(audience_mode__in=[normalized_mode, NotificationPreference.AudienceMode.SHARED])
    if exposed_only:
        rows = list(qs.order_by("tier", "audience_mode", "id"))
        return [row for row in rows if _pref_is_exposed(row.key)]
    return list(qs.order_by("tier", "audience_mode", "id"))


def should_send_notification(*, user, pref_key: str | None, audience_mode: str | None = None) -> bool:
    if not pref_key:
        return True
    if pref_key not in NOTIFICATION_CATALOG:
        return True
    normalized_mode = normalize_preference_mode(audience_mode)
    entitlement_context = _notification_entitlement_context(user)
    if bool(
        notification_preference_availability(
            user=user,
            pref_key=pref_key,
            audience_mode=normalized_mode,
            context=entitlement_context,
        )["locked"]
    ):
        return False
    pref = NotificationPreference.objects.filter(
        user=user,
        key=pref_key,
        audience_mode=normalized_mode,
    ).first()
    if pref is None and normalized_mode != NotificationPreference.AudienceMode.SHARED:
        pref = NotificationPreference.objects.filter(
            user=user,
            key=pref_key,
            audience_mode=NotificationPreference.AudienceMode.SHARED,
        ).first()
    if pref is None:
        cfg = NOTIFICATION_CATALOG[pref_key]
        pref = NotificationPreference.objects.create(
            user=user,
            key=pref_key,
            audience_mode=normalized_mode,
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
    normalized_audience_mode = normalize_preference_mode(audience_mode)
    derived_pref_key = pref_key or EVENT_TO_PREF_KEY.get(event_type or "")
    if not should_send_notification(user=user, pref_key=derived_pref_key, audience_mode=normalized_audience_mode):
        return None

    with transaction.atomic():
        notif = Notification.objects.create(
            user=user,
            title=title,
            body=body,
            kind=kind,
            url=url,
            audience_mode=normalized_audience_mode,
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
