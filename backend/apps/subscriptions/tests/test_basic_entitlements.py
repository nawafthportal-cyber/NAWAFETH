from decimal import Decimal
from io import StringIO

import pytest
from django.core.management import call_command
from rest_framework.test import APIClient

from apps.accounts.models import OTP, User, UserRole
from apps.providers.models import ProviderProfile
from apps.subscriptions.bootstrap import ensure_basic_subscription_plan
from apps.subscriptions.models import PlanPeriod, Subscription, SubscriptionPlan, SubscriptionStatus
from apps.subscriptions.services import ensure_basic_subscription_entitlement, start_subscription_checkout, user_plan_tier
from apps.subscriptions.tiering import CanonicalPlanTier
from apps.verification.services import verification_pricing_for_user


pytestmark = pytest.mark.django_db


def _login_via_otp(client: APIClient, phone: str) -> str:
    send = client.post("/api/accounts/otp/send/", {"phone": phone}, format="json")
    assert send.status_code == 200
    payload = send.json()
    code = payload.get("dev_code") or OTP.objects.filter(phone=phone).order_by("-id").values_list("code", flat=True).first()
    assert code

    verify = client.post("/api/accounts/otp/verify/", {"phone": phone, "code": code}, format="json")
    assert verify.status_code == 200
    return verify.json()["access"]


def _complete_registration(client: APIClient, phone: str, username: str) -> None:
    response = client.post(
        "/api/accounts/complete/",
        {
            "first_name": "Basic",
            "last_name": "Provider",
            "username": username,
            "email": f"{phone}@example.com",
            "password": "StrongPass123!",
            "password_confirm": "StrongPass123!",
            "accept_terms": True,
        },
        format="json",
    )
    assert response.status_code == 200


def _active_basic_subscription(user: User):
    return Subscription.objects.filter(
        user=user,
        status=SubscriptionStatus.ACTIVE,
        plan__tier="basic",
    ).select_related("plan").first()


def test_provider_register_auto_assigns_free_basic_entitlement():
    client = APIClient()
    phone = "0500011001"
    access = _login_via_otp(client, phone)
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

    _complete_registration(client, phone, "basic_provider_1001")
    user = User.objects.get(phone=phone)
    assert Subscription.objects.filter(user=user).count() == 0

    response = client.post(
        "/api/providers/register/",
        {
            "provider_type": "individual",
            "display_name": "مزود أساسي",
            "bio": "bio",
            "years_experience": 2,
            "city": "الرياض",
            "accepts_urgent": True,
        },
        format="json",
    )

    assert response.status_code == 201
    basic_sub = _active_basic_subscription(user)
    assert basic_sub is not None
    assert basic_sub.invoice_id is None
    assert basic_sub.status == SubscriptionStatus.ACTIVE
    assert basic_sub.plan.code == "basic"
    assert basic_sub.plan.price == Decimal("0.00")
    assert Subscription.objects.filter(user=user, status=SubscriptionStatus.ACTIVE, plan__code="basic").count() == 1
    assert user_plan_tier(user) == CanonicalPlanTier.BASIC


def test_direct_provider_profile_creation_auto_assigns_basic_entitlement():
    user = User.objects.create_user(phone="0500011002", password="Pass12345!", role_state=UserRole.PROVIDER)

    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="Admin Provider",
        bio="bio",
    )

    basic_sub = _active_basic_subscription(user)
    assert basic_sub is not None
    assert basic_sub.plan.price == Decimal("0.00")
    assert basic_sub.invoice_id is None


def test_free_basic_checkout_reuses_existing_entitlement_without_duplicate_invoice():
    user = User.objects.create_user(phone="0500011003", password="Pass12345!", role_state=UserRole.PROVIDER)
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="Checkout Provider",
        bio="bio",
    )
    basic_plan = ensure_basic_subscription_plan()

    before_ids = list(Subscription.objects.filter(user=user).values_list("id", flat=True))
    subscription = start_subscription_checkout(user=user, plan=basic_plan)
    after_ids = list(Subscription.objects.filter(user=user).values_list("id", flat=True))

    assert subscription.status == SubscriptionStatus.ACTIVE
    assert subscription.invoice_id is None
    assert after_ids == before_ids


def test_backfill_basic_entitlement_preserves_paid_upgrade_as_effective_tier():
    user = User.objects.create_user(phone="0500011004", password="Pass12345!", role_state=UserRole.PROVIDER)
    ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name="Legacy Paid Provider",
        bio="bio",
    )
    Subscription.objects.filter(user=user, plan__tier="basic").delete()

    pro_plan = SubscriptionPlan.objects.create(
        code="PRO_PHASE4",
        tier="pro",
        title="Professional",
        period=PlanPeriod.MONTH,
        price=Decimal("99.00"),
    )
    Subscription.objects.create(
        user=user,
        plan=pro_plan,
        status=SubscriptionStatus.ACTIVE,
    )

    created_sub, created = ensure_basic_subscription_entitlement(user=user)

    assert created is False
    assert created_sub is None
    assert user_plan_tier(user) == CanonicalPlanTier.PROFESSIONAL
    pricing = verification_pricing_for_user(user)
    assert pricing["tier"] == CanonicalPlanTier.PROFESSIONAL


def test_backfill_provider_basic_entitlements_command_is_safe_and_idempotent():
    provider_existing = User.objects.create_user(phone="0500011005", password="Pass12345!", role_state=UserRole.PROVIDER)
    ProviderProfile.objects.create(
        user=provider_existing,
        provider_type="individual",
        display_name="Existing Basic",
        bio="bio",
    )

    provider_missing = User.objects.create_user(phone="0500011006", password="Pass12345!", role_state=UserRole.PROVIDER)
    ProviderProfile.objects.create(
        user=provider_missing,
        provider_type="individual",
        display_name="Missing Basic",
        bio="bio",
    )
    Subscription.objects.filter(user=provider_missing).delete()

    provider_paid = User.objects.create_user(phone="0500011007", password="Pass12345!", role_state=UserRole.PROVIDER)
    ProviderProfile.objects.create(
        user=provider_paid,
        provider_type="individual",
        display_name="Paid Upgrade",
        bio="bio",
    )
    Subscription.objects.filter(user=provider_paid).delete()
    pioneer_plan = SubscriptionPlan.objects.create(
        code="RIYADI_PHASE4",
        tier="riyadi",
        title="Pioneer",
        period=PlanPeriod.MONTH,
        price=Decimal("79.00"),
    )
    Subscription.objects.create(user=provider_paid, plan=pioneer_plan, status=SubscriptionStatus.ACTIVE)

    dry_out = StringIO()
    call_command("backfill_provider_basic_entitlements", "--dry-run", stdout=dry_out)
    dry_text = dry_out.getvalue()
    assert "providers=3" in dry_text
    assert "created=1" in dry_text
    assert "current_non_basic=1" in dry_text
    assert Subscription.objects.filter(user=provider_missing, plan__tier="basic", status=SubscriptionStatus.ACTIVE).count() == 0

    out = StringIO()
    call_command("backfill_provider_basic_entitlements", stdout=out)
    text = out.getvalue()
    assert "providers=3" in text
    assert "created=1" in text
    assert "existing_basic=1" in text
    assert "current_non_basic=1" in text

    assert _active_basic_subscription(provider_missing) is not None
    assert _active_basic_subscription(provider_paid) is None
    assert user_plan_tier(provider_paid) == CanonicalPlanTier.PIONEER

    rerun = StringIO()
    call_command("backfill_provider_basic_entitlements", stdout=rerun)
    rerun_text = rerun.getvalue()
    assert "created=0" in rerun_text
    assert "existing_basic=2" in rerun_text
    assert "current_non_basic=1" in rerun_text
