"""
Celery tasks — تنبيهات الانتهاء والتجديد.
تعتمد على PlatformConfig للمواعيد و ReminderLog لمنع التكرار.
"""

from __future__ import annotations

import logging
from datetime import timedelta

from celery import shared_task
from django.conf import settings
from django.db.models import Q
from django.utils import timezone

logger = logging.getLogger(__name__)


# ────────────────────────────────────────────
# 1. تنبيه قبل انتهاء الاشتراك
# ────────────────────────────────────────────

@shared_task(name="core.send_subscription_renewal_reminders")
def send_subscription_renewal_reminders() -> int:
    """
    Check active subscriptions that expire within the configured reminder windows
    and send notifications. Skips if already sent for that (sub, days_before) pair.
    """
    from apps.core.models import PlatformConfig, ReminderLog
    from apps.notifications.services import create_notification
    from apps.subscriptions.models import Subscription, SubscriptionStatus

    config = PlatformConfig.load()
    reminder_days = config.get_subscription_reminder_days()
    if not reminder_days:
        return 0

    now = timezone.now()
    sent_count = 0

    for days in reminder_days:
        window_start = now + timedelta(days=days - 1)
        window_end = now + timedelta(days=days)

        subs = Subscription.objects.filter(
            status=SubscriptionStatus.ACTIVE,
            end_at__gt=window_start,
            end_at__lte=window_end,
        ).select_related("user", "plan")

        for sub in subs:
            already = ReminderLog.objects.filter(
                user=sub.user,
                reminder_type=ReminderLog.ReminderType.SUBSCRIPTION_EXPIRY,
                reference_id=sub.pk,
                days_before=days,
            ).exists()
            if already:
                continue

            create_notification(
                user=sub.user,
                title="اشتراكك على وشك الانتهاء",
                body=f"ينتهي اشتراكك «{sub.plan.title}» خلال {days} يوم. جدّد الآن.",
                kind="warn",
                pref_key="subscription_expiry",
                audience_mode="provider",
            )
            ReminderLog.objects.create(
                user=sub.user,
                reminder_type=ReminderLog.ReminderType.SUBSCRIPTION_EXPIRY,
                reference_id=sub.pk,
                days_before=days,
            )
            sent_count += 1

    logger.info("send_subscription_renewal_reminders sent %d", sent_count)
    return sent_count


# ────────────────────────────────────────────
# 2. تنبيه قبل انتهاء التوثيق
# ────────────────────────────────────────────

@shared_task(name="core.send_verification_expiry_reminders")
def send_verification_expiry_reminders() -> int:
    """
    Send reminder before verification badge expires.
    """
    from apps.core.models import PlatformConfig, ReminderLog
    from apps.notifications.services import create_notification
    from apps.verification.models import VerificationRequest, VerificationStatus

    config = PlatformConfig.load()
    reminder_days = config.get_verification_reminder_days()
    if not reminder_days:
        return 0

    now = timezone.now()
    sent_count = 0

    for days in reminder_days:
        window_start = now + timedelta(days=days - 1)
        window_end = now + timedelta(days=days)

        badges = VerificationRequest.objects.filter(
            status=VerificationStatus.ACTIVE,
            expires_at__gt=window_start,
            expires_at__lte=window_end,
        ).select_related("requester")

        for badge in badges:
            already = ReminderLog.objects.filter(
                user=badge.requester,
                reminder_type=ReminderLog.ReminderType.VERIFICATION_EXPIRY,
                reference_id=badge.pk,
                days_before=days,
            ).exists()
            if already:
                continue

            create_notification(
                user=badge.requester,
                title="توثيقك على وشك الانتهاء",
                body=f"سينتهي توثيقك خلال {days} يوم. يُرجى تجديده.",
                kind="warn",
                pref_key="verification_expiry",
                audience_mode="provider",
            )
            ReminderLog.objects.create(
                user=badge.requester,
                reminder_type=ReminderLog.ReminderType.VERIFICATION_EXPIRY,
                reference_id=badge.pk,
                days_before=days,
            )
            sent_count += 1

    logger.info("send_verification_expiry_reminders sent %d", sent_count)
    return sent_count


# ────────────────────────────────────────────
# 3. إرسال الرسائل الدعائية المجدولة
# ────────────────────────────────────────────

@shared_task(name="core.send_due_promo_messages")
def send_due_promo_messages() -> int:
    """
    Deliver due promotional message items once their scheduled send_at is reached.
    """
    from apps.promo.services import send_due_promo_messages as _send_due_promo_messages

    count = _send_due_promo_messages(now=timezone.now(), limit=100)
    logger.info("send_due_promo_messages delivered %d campaigns", count)
    return count


# ────────────────────────────────────────────
# 4. إتمام تلقائي للحملات الترويجية المنتهية
# ────────────────────────────────────────────

@shared_task(name="core.auto_complete_expired_promos")
def auto_complete_expired_promos() -> int:
    """
    Move ACTIVE promo requests past their end_at to EXPIRED status.
    """
    from apps.promo.services import expire_due_promos

    count = expire_due_promos(now=timezone.now())
    logger.info("auto_complete_expired_promos expired %d campaigns", count)
    return count


@shared_task(name="core.cleanup_incomplete_promo_requests")
def cleanup_incomplete_promo_requests() -> int:
    """
    Remove promo requests that stayed incomplete/unpaid beyond the configured grace period.
    """
    if not bool(getattr(settings, "PROMO_INCOMPLETE_REQUEST_CLEANUP_ENABLED", True)):
        return 0

    from apps.promo.services import cleanup_incomplete_unpaid_promo_requests

    count = cleanup_incomplete_unpaid_promo_requests(
        now=timezone.now(),
        max_age_minutes=int(getattr(settings, "PROMO_INCOMPLETE_REQUEST_MAX_AGE_MINUTES", 30) or 30),
        limit=int(getattr(settings, "PROMO_INCOMPLETE_REQUEST_CLEANUP_LIMIT", 200) or 200),
    )
    logger.info("cleanup_incomplete_promo_requests removed %d promo drafts", count)
    return count
