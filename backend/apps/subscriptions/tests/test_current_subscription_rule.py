from datetime import timedelta
from decimal import Decimal
from io import StringIO

import pytest
from django.core.management import call_command
from django.utils import timezone

from apps.accounts.models import User, UserRole
from apps.billing.models import Invoice
from apps.providers.models import ProviderProfile
from apps.subscriptions.models import PlanPeriod, Subscription, SubscriptionPlan, SubscriptionStatus
from apps.subscriptions.services import (
    activate_subscription_after_payment,
    get_effective_active_subscription,
    normalize_user_current_subscriptions,
    refresh_subscription_status,
    user_plan_tier,
)
from apps.subscriptions.tiering import CanonicalPlanTier
from apps.verification.services import verification_pricing_for_user


pytestmark = pytest.mark.django_db


def _make_provider(phone: str) -> User:
    user = User.objects.create_user(phone=phone, password="Pass12345!", role_state=UserRole.PROVIDER)
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name=f"Provider {phone}",
        bio="bio",
    )
    return user


def _create_paid_subscription(*, user: User, plan_code: str, tier: str, title: str, price: str = "99.00") -> Subscription:
    plan = SubscriptionPlan.objects.create(
        code=plan_code,
        tier=tier,
        title=title,
        period=PlanPeriod.YEAR,
        price=Decimal(price),
    )
    return Subscription.objects.create(
        user=user,
        plan=plan,
        status=SubscriptionStatus.PENDING_PAYMENT,
    )


def _mark_paid(subscription: Subscription, *, event_id: str) -> Subscription:
    invoice = Invoice.objects.create(
        user=subscription.user,
        subtotal=Decimal(subscription.plan.price),
        reference_type="subscription",
        reference_id=str(subscription.pk),
    )
    invoice.mark_pending()
    invoice.save()
    invoice.mark_payment_confirmed(
        provider="mock",
        provider_reference=f"ref-{event_id}",
        event_id=event_id,
        amount=invoice.total,
        currency=invoice.currency,
    )
    invoice.save()
    subscription.invoice = invoice
    subscription.save(update_fields=["invoice", "updated_at"])
    return activate_subscription_after_payment(sub=subscription)


def test_normalize_user_current_subscriptions_resolves_overlapping_current_rows_by_recency():
    user = _make_provider("0500012001")
    professional_plan = SubscriptionPlan.objects.create(
        code="PRO_OLD",
        tier="pro",
        title="Professional Old",
        period=PlanPeriod.YEAR,
        price=Decimal("999.00"),
    )
    pioneer_plan = SubscriptionPlan.objects.create(
        code="RIYADI_NEW",
        tier="riyadi",
        title="Pioneer New",
        period=PlanPeriod.YEAR,
        price=Decimal("199.00"),
    )
    now = timezone.now()
    professional = Subscription.objects.create(
        user=user,
        plan=professional_plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=now - timedelta(days=20),
    )
    pioneer = Subscription.objects.create(
        user=user,
        plan=pioneer_plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=now - timedelta(days=5),
    )

    result = normalize_user_current_subscriptions(user=user)

    professional.refresh_from_db()
    pioneer.refresh_from_db()
    current_rows = Subscription.objects.filter(user=user, status__in=[SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE])
    assert result["effective"].id == pioneer.id
    assert professional.status == SubscriptionStatus.CANCELLED
    assert pioneer.status == SubscriptionStatus.ACTIVE
    assert current_rows.count() == 1
    assert get_effective_active_subscription(user).id == pioneer.id
    assert user_plan_tier(user) == CanonicalPlanTier.PIONEER


def test_activate_paid_upgrade_cancels_basic_current_but_preserves_history():
    user = _make_provider("0500012002")
    basic = Subscription.objects.get(user=user, status=SubscriptionStatus.ACTIVE, plan__code="basic")

    paid = _create_paid_subscription(
        user=user,
        plan_code="PRO_PHASE5",
        tier="pro",
        title="Professional",
        price="999.00",
    )
    paid = _mark_paid(paid, event_id="phase5-upgrade")

    basic.refresh_from_db()
    current_rows = Subscription.objects.filter(user=user, status__in=[SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE])
    assert basic.status == SubscriptionStatus.CANCELLED
    assert paid.status == SubscriptionStatus.ACTIVE
    assert current_rows.count() == 1
    assert current_rows.first().id == paid.id
    assert Subscription.objects.filter(user=user).count() == 2
    assert user_plan_tier(user) == CanonicalPlanTier.PROFESSIONAL


def test_grace_subscription_remains_effective_current_tier_until_full_expiry():
    user = _make_provider("0500012003")
    paid = _create_paid_subscription(
        user=user,
        plan_code="RIYADI_PHASE5",
        tier="riyadi",
        title="Pioneer",
        price="199.00",
    )
    paid = _mark_paid(paid, event_id="phase5-grace")

    paid.end_at = timezone.now() - timedelta(hours=1)
    paid.grace_end_at = timezone.now() + timedelta(days=2)
    paid.save(update_fields=["end_at", "grace_end_at", "updated_at"])

    paid = refresh_subscription_status(sub=paid)

    assert paid.status == SubscriptionStatus.GRACE
    assert user_plan_tier(user) == CanonicalPlanTier.PIONEER
    assert verification_pricing_for_user(user)["tier"] == CanonicalPlanTier.PIONEER
    assert Subscription.objects.filter(user=user, status=SubscriptionStatus.ACTIVE, plan__code="basic").count() == 0
    assert Subscription.objects.filter(user=user, status__in=[SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE]).count() == 1


def test_full_expiry_restores_basic_as_only_current_subscription():
    user = _make_provider("0500012004")
    paid = _create_paid_subscription(
        user=user,
        plan_code="PRO_EXPIRE",
        tier="pro",
        title="Professional",
        price="999.00",
    )
    paid = _mark_paid(paid, event_id="phase5-expire")

    past = timezone.now() - timedelta(days=10)
    paid.end_at = past
    paid.grace_end_at = past
    paid.save(update_fields=["end_at", "grace_end_at", "updated_at"])

    paid = refresh_subscription_status(sub=paid)
    paid = refresh_subscription_status(sub=paid)
    paid.refresh_from_db()

    current_rows = Subscription.objects.filter(user=user, status__in=[SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE])
    basic_current = current_rows.get(plan__code="basic")
    assert paid.status == SubscriptionStatus.EXPIRED
    assert basic_current.status == SubscriptionStatus.ACTIVE
    assert current_rows.count() == 1
    assert user_plan_tier(user) == CanonicalPlanTier.BASIC


def test_normalize_current_subscriptions_command_is_idempotent():
    user = _make_provider("0500012005")
    basic = Subscription.objects.get(user=user, status=SubscriptionStatus.ACTIVE, plan__code="basic")
    pioneer_plan = SubscriptionPlan.objects.create(
        code="RIYADI_CMD",
        tier="riyadi",
        title="Pioneer Command",
        period=PlanPeriod.YEAR,
        price=Decimal("199.00"),
    )
    pioneer = Subscription.objects.create(
        user=user,
        plan=pioneer_plan,
        status=SubscriptionStatus.ACTIVE,
        start_at=timezone.now(),
    )

    dry_out = StringIO()
    call_command("normalize_current_subscriptions", "--dry-run", stdout=dry_out)
    dry_text = dry_out.getvalue()
    assert "users=1" in dry_text
    assert "normalized_users=1" in dry_text
    assert "cancelled_rows=1" in dry_text

    out = StringIO()
    call_command("normalize_current_subscriptions", stdout=out)
    text = out.getvalue()
    assert "users=1" in text
    assert "normalized_users=1" in text
    assert "cancelled_rows=1" in text

    basic.refresh_from_db()
    pioneer.refresh_from_db()
    assert basic.status == SubscriptionStatus.CANCELLED
    assert pioneer.status == SubscriptionStatus.ACTIVE
    assert Subscription.objects.filter(user=user, status__in=[SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE]).count() == 1

    rerun = StringIO()
    call_command("normalize_current_subscriptions", stdout=rerun)
    rerun_text = rerun.getvalue()
    assert "users=0" in rerun_text
    assert "normalized_users=0" in rerun_text
    assert "cancelled_rows=0" in rerun_text
