from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from apps.billing.models import Invoice, InvoiceStatus

from .models import PlanTier, Subscription, SubscriptionPlan, SubscriptionStatus


def _subscription_status_to_unified(status: str) -> str:
    if status in {SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE}:
        return "in_progress"
    if status in {SubscriptionStatus.EXPIRED, SubscriptionStatus.CANCELLED}:
        return "completed"
    return "new"


def _sync_subscription_to_unified(*, sub: Subscription, changed_by=None):
    try:
        from apps.unified_requests.services import upsert_unified_request
        from apps.unified_requests.models import UnifiedRequestType
    except Exception:
        return

    upsert_unified_request(
        request_type=UnifiedRequestType.SUBSCRIPTION,
        requester=sub.user,
        source_app="subscriptions",
        source_model="Subscription",
        source_object_id=sub.id,
        status=_subscription_status_to_unified(sub.status),
        priority="normal",
        summary=f"اشتراك {getattr(sub.plan, 'title', getattr(sub.plan, 'code', ''))}".strip(),
        metadata={
            "subscription_id": sub.id,
            "plan_id": sub.plan_id,
            "plan_code": getattr(getattr(sub, "plan", None), "code", "") or "",
            "subscription_status": sub.status,
            "invoice_id": sub.invoice_id,
            "start_at": sub.start_at.isoformat() if sub.start_at else None,
            "end_at": sub.end_at.isoformat() if sub.end_at else None,
            "grace_end_at": sub.grace_end_at.isoformat() if sub.grace_end_at else None,
        },
        assigned_team_code="subs",
        assigned_team_name="الاشتراكات",
        assigned_user=None,
        changed_by=changed_by,
    )


def _grace_days() -> int:
    return int(getattr(settings, "SUBS_GRACE_DAYS", 7))


@transaction.atomic
def start_subscription_checkout(*, user, plan: SubscriptionPlan) -> Subscription:
    """
    إنشاء اشتراك + فاتورة تلقائيًا
    """
    sub = Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.PENDING_PAYMENT,
    )

    inv = Invoice.objects.create(
        user=user,
        title="فاتورة اشتراك",
        description=f"اشتراك باقة {plan.title} ({plan.get_period_display()})",
        subtotal=Decimal(sub.plan.price),
        reference_type="subscription",
        reference_id=str(sub.pk),
        status=InvoiceStatus.DRAFT,
    )
    inv.mark_pending()
    inv.save(update_fields=["status", "subtotal", "vat_percent", "vat_amount", "total", "updated_at"])

    sub.invoice = inv
    sub.save(update_fields=["invoice", "updated_at"])
    _sync_subscription_to_unified(sub=sub, changed_by=user)
    return sub


@transaction.atomic
def activate_subscription_after_payment(*, sub: Subscription) -> Subscription:
    """
    تفعيل الاشتراك بعد الدفع
    """
    sub = Subscription.objects.select_for_update().select_related("plan").get(pk=sub.pk)

    if not sub.invoice or sub.invoice.status != "paid":
        raise ValueError("الفاتورة غير مدفوعة بعد.")

    if sub.status == SubscriptionStatus.ACTIVE:
        return sub

    now = timezone.now()
    sub.start_at = now
    sub.end_at = sub.calc_end_date(now)
    sub.grace_end_at = sub.end_at + timedelta(days=_grace_days())
    sub.status = SubscriptionStatus.ACTIVE
    sub.save(update_fields=["start_at", "end_at", "grace_end_at", "status", "updated_at"])

    # Audit
    try:
        from apps.audit.services import log_action
        from apps.audit.models import AuditAction

        log_action(
            actor=sub.user,
            action=AuditAction.SUBSCRIPTION_ACTIVE,
            reference_type="subscription",
            reference_id=str(sub.pk),
            extra={"plan": sub.plan.code},
        )
    except Exception:
        pass

    _sync_subscription_to_unified(sub=sub, changed_by=sub.user)
    return sub


@transaction.atomic
def refresh_subscription_status(*, sub: Subscription) -> Subscription:
    """
    تحديث حالة الاشتراك حسب الوقت:
    ACTIVE -> GRACE -> EXPIRED
    """
    sub = Subscription.objects.select_for_update().get(pk=sub.pk)
    now = timezone.now()

    if sub.status in (SubscriptionStatus.CANCELLED, SubscriptionStatus.PENDING_PAYMENT):
        return sub

    if sub.end_at and now > sub.end_at and sub.status == SubscriptionStatus.ACTIVE:
        sub.status = SubscriptionStatus.GRACE
        sub.save(update_fields=["status", "updated_at"])
        _sync_subscription_to_unified(sub=sub, changed_by=None)
        return sub

    if sub.grace_end_at and now > sub.grace_end_at and sub.status in (SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE):
        sub.status = SubscriptionStatus.EXPIRED
        sub.save(update_fields=["status", "updated_at"])
        _sync_subscription_to_unified(sub=sub, changed_by=None)
        return sub

    return sub


def user_has_feature(user, key: str) -> bool:
    """
    هل المستخدم لديه ميزة ضمن اشتراكه النشط؟
    """
    normalized_key = (key or "").strip().lower()
    # التوثيق مستقل عن الاشتراك؛ الباقة تؤثر على الرسوم فقط.
    if normalized_key in {"verify_blue", "verify_green"}:
        return False

    active = Subscription.objects.filter(user=user, status=SubscriptionStatus.ACTIVE).select_related("plan").order_by("-id").first()
    if not active:
        return False
    features = {str(item or "").strip().lower() for item in (active.plan.features or [])}
    return normalized_key in features


def plan_to_tier(plan: SubscriptionPlan | None) -> str:
    if not plan:
        return PlanTier.BASIC

    tier = (getattr(plan, "tier", "") or "").strip().lower()
    if tier in {PlanTier.BASIC, PlanTier.RIYADI, PlanTier.PRO}:
        return tier

    code = (getattr(plan, "code", "") or "").strip().lower()
    if "riyadi" in code or "entrepreneur" in code or "leading" in code:
        return PlanTier.RIYADI
    if "pro" in code or "professional" in code:
        return PlanTier.PRO
    return PlanTier.BASIC


def user_plan_tier(user, *, fallback: str = PlanTier.BASIC) -> str:
    active = (
        Subscription.objects.filter(user=user, status=SubscriptionStatus.ACTIVE)
        .select_related("plan")
        .order_by("-id")
        .first()
    )
    if not active:
        return fallback
    return plan_to_tier(getattr(active, "plan", None))
