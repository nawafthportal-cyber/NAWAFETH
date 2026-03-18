from __future__ import annotations

from collections import defaultdict
from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.db import transaction
from django.db.models import Count
from django.utils import timezone

from apps.billing.models import Invoice, InvoiceStatus
from apps.providers.eligibility import ensure_provider_access

from .bootstrap import ensure_basic_subscription_plan
from .models import Subscription, SubscriptionPlan, SubscriptionStatus
from .offers import subscription_offer_end_at, subscription_offer_for_plan
from .tiering import CanonicalPlanTier, canonical_tier_from_inputs, canonical_tier_order, db_tier_for_canonical

CURRENT_SUBSCRIPTION_STATUSES = (
    SubscriptionStatus.ACTIVE,
    SubscriptionStatus.GRACE,
)


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
    from apps.core.models import PlatformConfig
    return PlatformConfig.load().subscription_grace_days


def is_current_subscription_status(status: str) -> bool:
    return str(status or "").strip().lower() in CURRENT_SUBSCRIPTION_STATUSES


def _subscription_sort_timestamp(sub: Subscription) -> float:
    marker = getattr(sub, "start_at", None) or getattr(sub, "created_at", None)
    if not marker:
        return 0.0
    try:
        return float(marker.timestamp())
    except Exception:
        return 0.0


def _subscription_priority(sub: Subscription) -> tuple[int, int, float, int, int]:
    tier = plan_to_tier(getattr(sub, "plan", None))
    is_paid = tier != CanonicalPlanTier.BASIC
    status_priority = 2 if getattr(sub, "status", None) == SubscriptionStatus.ACTIVE else 1
    return (
        1 if is_paid else 0,
        status_priority,
        _subscription_sort_timestamp(sub),
        canonical_tier_order(tier),
        int(getattr(sub, "id", 0) or 0),
    )


def pick_effective_current_subscription(subscriptions) -> Subscription | None:
    effective = None
    for sub in subscriptions:
        if not is_current_subscription_status(getattr(sub, "status", None)):
            continue
        if effective is None or _subscription_priority(sub) > _subscription_priority(effective):
            effective = sub
    return effective


def pick_effective_active_subscription(subscriptions) -> Subscription | None:
    return pick_effective_current_subscription(subscriptions)


def get_effective_active_subscription(user) -> Subscription | None:
    subscriptions = (
        Subscription.objects.filter(user=user, status__in=CURRENT_SUBSCRIPTION_STATUSES)
        .select_related("plan")
        .order_by("id")
    )
    return pick_effective_current_subscription(subscriptions)


def get_effective_active_subscriptions_map(user_ids: list[int]) -> dict[int, Subscription]:
    if not user_ids:
        return {}

    grouped: dict[int, list[Subscription]] = defaultdict(list)
    subscriptions = (
        Subscription.objects.filter(user_id__in=user_ids, status__in=CURRENT_SUBSCRIPTION_STATUSES)
        .select_related("plan")
        .order_by("user_id", "id")
    )
    for sub in subscriptions:
        grouped[sub.user_id].append(sub)

    return {
        user_id: effective
        for user_id, items in grouped.items()
        if (effective := pick_effective_current_subscription(items)) is not None
    }


def _has_provider_profile(user) -> bool:
    try:
        return bool(getattr(user, "provider_profile", None))
    except Exception:
        return False


def normalize_user_current_subscriptions(*, user, preferred_subscription_id: int | None = None, changed_by=None, dry_run: bool = False) -> dict[str, object]:
    if not getattr(user, "pk", None):
        return {
            "effective": None,
            "current_ids": [],
            "cancelled_ids": [],
        }

    current_subscriptions = list(
        Subscription.objects.select_for_update()
        .filter(user=user, status__in=CURRENT_SUBSCRIPTION_STATUSES)
        .select_related("plan")
        .order_by("id")
    )
    current_ids = [sub.id for sub in current_subscriptions]
    if not current_subscriptions:
        return {
            "effective": None,
            "current_ids": current_ids,
            "cancelled_ids": [],
        }

    effective = next(
        (
            sub
            for sub in current_subscriptions
            if preferred_subscription_id and sub.id == preferred_subscription_id
        ),
        None,
    )
    if effective is None:
        effective = pick_effective_current_subscription(current_subscriptions)

    cancelled_ids: list[int] = []
    if effective is None:
        return {
            "effective": None,
            "current_ids": current_ids,
            "cancelled_ids": cancelled_ids,
        }

    for sub in current_subscriptions:
        if sub.id == effective.id:
            continue
        cancelled_ids.append(sub.id)
        if dry_run:
            continue
        sub.status = SubscriptionStatus.CANCELLED
        sub.save(update_fields=["status", "updated_at"])
        _sync_subscription_to_unified(sub=sub, changed_by=changed_by)
        try:
            from apps.audit.models import AuditAction
            from apps.audit.services import log_action

            log_action(
                actor=changed_by,
                action=AuditAction.SUBSCRIPTION_ACCOUNT_CANCELLED,
                reference_type="subscription",
                reference_id=str(sub.pk),
                extra={
                    "reason": "current_subscription_normalized",
                    "effective_subscription_id": effective.id,
                },
            )
        except Exception:
            pass

    return {
        "effective": effective,
        "current_ids": current_ids,
        "cancelled_ids": cancelled_ids,
    }


def normalize_current_subscriptions(*, dry_run: bool = False) -> dict[str, int]:
    from apps.accounts.models import User

    duplicate_user_ids = list(
        Subscription.objects.filter(status__in=CURRENT_SUBSCRIPTION_STATUSES)
        .values("user_id")
        .annotate(current_count=Count("id"))
        .filter(current_count__gt=1)
        .values_list("user_id", flat=True)
    )

    summary = {
        "users": len(duplicate_user_ids),
        "normalized_users": 0,
        "cancelled_rows": 0,
        "errors": 0,
    }
    if not duplicate_user_ids:
        return summary

    for user in User.objects.filter(id__in=duplicate_user_ids).order_by("id"):
        try:
            with transaction.atomic():
                result = normalize_user_current_subscriptions(user=user, dry_run=dry_run)
        except Exception:
            summary["errors"] += 1
            continue
        cancelled = result.get("cancelled_ids") or []
        if cancelled:
            summary["normalized_users"] += 1
            summary["cancelled_rows"] += len(cancelled)

    return summary


@transaction.atomic
def ensure_basic_subscription_entitlement(*, user, at=None) -> tuple[Subscription | None, bool]:
    if not getattr(user, "pk", None) or not _has_provider_profile(user):
        return None, False

    basic_plan = ensure_basic_subscription_plan()
    normalized = normalize_user_current_subscriptions(user=user)
    current = normalized.get("effective")
    if current and plan_to_tier(getattr(current, "plan", None)) == CanonicalPlanTier.BASIC:
        return current, False
    if current and plan_to_tier(getattr(current, "plan", None)) != CanonicalPlanTier.BASIC:
        return None, False

    now = at or timezone.now()
    sub = Subscription.objects.create(
        user=user,
        plan=basic_plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=now,
        end_at=None,
        grace_end_at=None,
        auto_renew=False,
    )
    return sub, True


def backfill_provider_basic_entitlements(*, dry_run: bool = False) -> dict[str, int]:
    from apps.providers.models import ProviderProfile

    summary = {
        "providers": 0,
        "created": 0,
        "existing_basic": 0,
        "current_non_basic": 0,
        "errors": 0,
    }

    ensure_basic_subscription_plan()

    for profile in ProviderProfile.objects.select_related("user").order_by("id"):
        summary["providers"] += 1
        user = getattr(profile, "user", None)
        if not getattr(user, "pk", None):
            summary["errors"] += 1
            continue

        try:
            with transaction.atomic():
                normalized = normalize_user_current_subscriptions(user=user, dry_run=dry_run)
        except Exception:
            summary["errors"] += 1
            continue

        current = normalized.get("effective")
        if current and plan_to_tier(getattr(current, "plan", None)) == CanonicalPlanTier.BASIC:
            summary["existing_basic"] += 1
            continue
        if current and plan_to_tier(getattr(current, "plan", None)) != CanonicalPlanTier.BASIC:
            summary["current_non_basic"] += 1
            continue

        if dry_run:
            summary["created"] += 1
            continue

        try:
            _, created = ensure_basic_subscription_entitlement(user=user)
        except Exception:
            summary["errors"] += 1
            continue

        if created:
            summary["created"] += 1
        else:
            summary["existing_basic"] += 1

    return summary


@transaction.atomic
def start_subscription_checkout(*, user, plan: SubscriptionPlan) -> Subscription:
    """
    إنشاء اشتراك + فاتورة تلقائيًا
    """
    ensure_provider_access(user)
    offer = subscription_offer_for_plan(plan, user=user)
    action = offer.get("cta") or {}
    action_state = str(action.get("state") or "").strip().lower()

    if action_state == "pending":
        existing = (
            Subscription.objects.filter(
                user=user,
                plan=plan,
                status=SubscriptionStatus.PENDING_PAYMENT,
            )
            .select_related("plan", "invoice")
            .order_by("-id")
            .first()
        )
        if existing is not None:
            return existing
        raise ValueError("يوجد طلب ترقية قيد التفعيل لهذه الباقة.")

    if action_state == "unavailable":
        raise ValueError("لا يمكن خفض الباقة من هذا المسار.")

    if (
        plan_to_tier(plan) == CanonicalPlanTier.BASIC
        and Decimal(str(offer.get("final_payable_amount", "0.00"))) <= Decimal("0.00")
    ):
        entitlement, _ = ensure_basic_subscription_entitlement(user=user)
        if entitlement is None:
            raise ValueError("تعذر إنشاء الاستحقاق الأساسي.")
        return entitlement

    if action_state == "current":
        raise ValueError("هذه هي باقتك الحالية بالفعل.")

    return _create_pending_subscription_checkout(user=user, plan=plan, offer=offer)


def _create_pending_subscription_checkout(*, user, plan: SubscriptionPlan, offer: dict | None = None) -> Subscription:
    offer = offer or subscription_offer_for_plan(plan, user=user)

    sub = Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.PENDING_PAYMENT,
    )

    inv = Invoice.objects.create(
        user=user,
        title="فاتورة اشتراك",
        description=f"اشتراك باقة {offer.get('plan_name', plan.title)} ({offer.get('billing_cycle_label', 'سنوي')})",
        subtotal=Decimal(str(offer.get("final_payable_amount", sub.plan.price))),
        vat_percent=Decimal(str(offer.get("additional_vat_percent", "0.00"))),
        reference_type="subscription",
        reference_id=str(sub.pk),
        status=InvoiceStatus.DRAFT,
    )
    inv.mark_pending()
    inv.save(update_fields=["status", "subtotal", "vat_percent", "vat_amount", "total", "updated_at"])

    sub.invoice = inv
    sub.save(update_fields=["invoice", "updated_at"])
    _sync_subscription_to_unified(sub=sub, changed_by=user)
    try:
        from apps.analytics.tracking import safe_track_event

        safe_track_event(
            event_name="subscriptions.checkout_created",
            channel="server",
            surface="subscriptions.pending_checkout",
            source_app="subscriptions",
            object_type="Subscription",
            object_id=str(sub.id),
            actor=user,
            dedupe_key=f"subscriptions.checkout_created:{sub.id}:{inv.id}",
            payload={
                "plan_id": plan.id,
                "plan_code": plan.code,
                "invoice_id": inv.id,
                "status": sub.status,
            },
        )
    except Exception:
        pass
    return sub


def start_subscription_renewal_checkout(*, user, plan: SubscriptionPlan) -> Subscription:
    """
    إنشاء طلب تجديد إداري لنفس الباقة الحالية حتى لو كانت الباقة الحالية نفسها.
    هذا المسار مخصص للداشبورد ويجب ألا يغير قيود الاشتراك العامة في الواجهات العامة.
    """
    ensure_provider_access(user)

    existing = (
        Subscription.objects.filter(
            user=user,
            plan=plan,
            status=SubscriptionStatus.PENDING_PAYMENT,
        )
        .select_related("plan", "invoice")
        .order_by("-id")
        .first()
    )
    if existing is not None:
        return existing

    offer = subscription_offer_for_plan(plan, user=user)
    return _create_pending_subscription_checkout(user=user, plan=plan, offer=offer)


@transaction.atomic
def activate_subscription_after_payment(*, sub: Subscription) -> Subscription:
    """
    تفعيل الاشتراك بعد الدفع
    """
    sub = Subscription.objects.select_for_update().select_related("plan").get(pk=sub.pk)

    if not sub.invoice or not sub.invoice.is_payment_effective():
        raise ValueError("الفاتورة غير مدفوعة بعد.")

    now = timezone.now()
    if sub.status != SubscriptionStatus.ACTIVE:
        sub.start_at = now
        sub.end_at = subscription_offer_end_at(plan=sub.plan, start_at=now)
        sub.grace_end_at = sub.end_at + timedelta(days=_grace_days())
        sub.status = SubscriptionStatus.ACTIVE
        sub.save(update_fields=["start_at", "end_at", "grace_end_at", "status", "updated_at"])
    normalize_user_current_subscriptions(
        user=sub.user,
        preferred_subscription_id=sub.id,
        changed_by=sub.user,
    )

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
    try:
        from apps.analytics.tracking import safe_track_event

        safe_track_event(
            event_name="subscriptions.activated",
            channel="server",
            surface="subscriptions.activate_after_payment",
            source_app="subscriptions",
            object_type="Subscription",
            object_id=str(sub.id),
            actor=sub.user,
            dedupe_key=f"subscriptions.activated:{sub.id}:{sub.start_at.isoformat() if sub.start_at else ''}",
            payload={
                "plan_id": sub.plan_id,
                "plan_code": getattr(sub.plan, "code", ""),
                "status": sub.status,
                "end_at": sub.end_at.isoformat() if sub.end_at else None,
            },
        )
    except Exception:
        pass
    return sub


@transaction.atomic
def revoke_subscription_after_payment_reversal(*, sub: Subscription) -> Subscription:
    sub = Subscription.objects.select_for_update().select_related("plan", "invoice").get(pk=sub.pk)

    if not sub.invoice or sub.invoice.is_payment_effective():
        return sub

    if sub.status not in (SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE):
        return sub

    sub.start_at = None
    sub.end_at = None
    sub.grace_end_at = None
    sub.status = SubscriptionStatus.PENDING_PAYMENT
    sub.save(update_fields=["start_at", "end_at", "grace_end_at", "status", "updated_at"])

    try:
        from apps.audit.services import log_action
        from apps.audit.models import AuditAction

        log_action(
            actor=sub.user,
            action=AuditAction.SUBSCRIPTION_PAYMENT_REVOKED,
            reference_type="subscription",
            reference_id=str(sub.pk),
            extra={
                "plan": getattr(sub.plan, "code", ""),
                "invoice_id": sub.invoice_id,
                "invoice_status": getattr(sub.invoice, "status", ""),
            },
        )
    except Exception:
        pass

    if plan_to_tier(getattr(sub, "plan", None)) != CanonicalPlanTier.BASIC:
        ensure_basic_subscription_entitlement(user=sub.user)
    normalize_user_current_subscriptions(user=sub.user, changed_by=sub.user)

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
        normalize_user_current_subscriptions(user=sub.user, preferred_subscription_id=sub.id)
        _sync_subscription_to_unified(sub=sub, changed_by=None)
        return sub

    if sub.grace_end_at and now > sub.grace_end_at and sub.status in (SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE):
        sub.status = SubscriptionStatus.EXPIRED
        sub.save(update_fields=["status", "updated_at"])
        if plan_to_tier(getattr(sub, "plan", None)) != CanonicalPlanTier.BASIC:
            ensure_basic_subscription_entitlement(user=sub.user)
        normalize_user_current_subscriptions(user=sub.user)
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

    active = get_effective_active_subscription(user)
    if not active:
        return False
    features = {str(item or "").strip().lower() for item in getattr(active.plan, "feature_keys", lambda: [])()}
    return normalized_key in features


def plan_to_tier(plan: SubscriptionPlan | None) -> str:
    if not plan:
        return CanonicalPlanTier.BASIC
    return canonical_tier_from_inputs(
        tier=getattr(plan, "tier", ""),
        code=getattr(plan, "code", ""),
        title=getattr(plan, "title", ""),
        features=getattr(plan, "feature_keys", lambda: [])(),
    )


def plan_to_db_tier(plan: SubscriptionPlan | None) -> str:
    return db_tier_for_canonical(plan_to_tier(plan))


def user_plan_tier(user, *, fallback: str = CanonicalPlanTier.BASIC) -> str:
    active = get_effective_active_subscription(user)
    if not active:
        return canonical_tier_from_inputs(tier=fallback, fallback=CanonicalPlanTier.BASIC)
    return plan_to_tier(getattr(active, "plan", None))


def user_plan_db_tier(user, *, fallback: str = CanonicalPlanTier.BASIC) -> str:
    return db_tier_for_canonical(user_plan_tier(user, fallback=fallback))
