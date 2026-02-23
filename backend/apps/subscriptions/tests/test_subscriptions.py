import pytest
from datetime import timedelta
from rest_framework.test import APIClient
from decimal import Decimal

from apps.accounts.models import User
from apps.subscriptions.models import SubscriptionPlan, PlanPeriod, Subscription, SubscriptionStatus
from apps.subscriptions.services import activate_subscription_after_payment, refresh_subscription_status
from apps.unified_requests.models import UnifiedRequest


pytestmark = pytest.mark.django_db


@pytest.fixture
def api():
    return APIClient()


@pytest.fixture
def user():
    return User.objects.create_user(phone="0588888888", password="Pass12345!")


def test_plans_list(api, user):
    SubscriptionPlan.objects.create(code="BASIC", title="Basic", period=PlanPeriod.MONTH, price=Decimal("10.00"), features=["verify_green"])
    api.force_authenticate(user=user)
    r = api.get("/api/subscriptions/plans/")
    assert r.status_code == 200
    assert len(r.data) >= 1


def test_subscribe(api, user):
    plan = SubscriptionPlan.objects.create(code="PRO", title="Pro", period=PlanPeriod.MONTH, price=Decimal("25.00"), features=["verify_blue"])
    api.force_authenticate(user=user)
    r = api.post(f"/api/subscriptions/subscribe/{plan.pk}/")
    assert r.status_code == 201
    assert r.data["invoice"] is not None
    sub = Subscription.objects.get(pk=r.data["id"])
    ur = UnifiedRequest.objects.get(source_app="subscriptions", source_model="Subscription", source_object_id=str(sub.id))
    assert ur.code.startswith("SD")
    assert ur.status == "pending_payment"
    assert ur.metadata_record.payload.get("invoice_id") == sub.invoice_id


def test_subscriptions_endpoints_require_auth(api):
    r1 = api.get("/api/subscriptions/plans/")
    r2 = api.get("/api/subscriptions/my/")
    assert r1.status_code in (401, 403)
    assert r2.status_code in (401, 403)


def test_subscription_activation_and_refresh_syncs_unified(user):
    plan = SubscriptionPlan.objects.create(code="PROX", title="Pro X", period=PlanPeriod.MONTH, price=Decimal("25.00"))
    sub = Subscription.objects.create(user=user, plan=plan, status=SubscriptionStatus.PENDING_PAYMENT)
    # Simulate initial unified sync path used by checkout
    from apps.subscriptions.services import _sync_subscription_to_unified

    _sync_subscription_to_unified(sub=sub, changed_by=user)
    sub.invoice_id = None  # guard in case reused; not needed
    from apps.billing.models import Invoice
    inv = Invoice.objects.create(user=user, subtotal=Decimal("25.00"), reference_type="subscription", reference_id=str(sub.pk))
    inv.mark_pending()
    inv.save()
    inv.mark_paid()
    inv.save()
    sub.invoice = inv
    sub.save(update_fields=["invoice", "updated_at"])

    sub = activate_subscription_after_payment(sub=sub)
    ur = UnifiedRequest.objects.get(source_app="subscriptions", source_model="Subscription", source_object_id=str(sub.id))
    assert ur.status == "active"
    assert ur.metadata_record.payload.get("subscription_status") == "active"

    sub.end_at = sub.start_at - timedelta(seconds=1)
    sub.grace_end_at = sub.end_at + timedelta(days=1)
    sub.save(update_fields=["end_at", "grace_end_at", "updated_at"])
    sub = refresh_subscription_status(sub=sub)
    ur.refresh_from_db()
    # GRACE maps to active in unified generalized lifecycle.
    assert sub.status == "grace"
    assert ur.status == "active"
    assert ur.metadata_record.payload.get("subscription_status") == "grace"
