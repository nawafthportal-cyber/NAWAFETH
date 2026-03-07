import pytest
from datetime import timedelta
from rest_framework.test import APIClient
from decimal import Decimal

from apps.accounts.models import User, UserRole
from apps.providers.models import ProviderProfile
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


def _make_provider(user, *, sync_role: bool = True):
    if sync_role:
        user.role_state = UserRole.PROVIDER
        user.save(update_fields=["role_state"])
    return ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name=f"Provider {user.phone}",
        bio="bio",
    )


def test_plans_list(api, user):
    SubscriptionPlan.objects.create(
        code="BASIC",
        tier="basic",
        title="Basic",
        period=PlanPeriod.MONTH,
        price=Decimal("10.00"),
        features=["verify_green"],
    )
    _make_provider(user)
    api.force_authenticate(user=user)
    r = api.get("/api/subscriptions/plans/")
    assert r.status_code == 200
    assert len(r.data) >= 1
    plan_payload = r.data[0]
    assert plan_payload["canonical_tier"] == "basic"
    assert plan_payload["tier"] == "basic"
    assert plan_payload["tier_label"] == "أساسية"
    assert plan_payload["capabilities"]["competitive_requests"]["visibility_delay_hours"] == 72
    assert plan_payload["capabilities"]["banner_images"]["limit"] == 1
    assert plan_payload["provider_offer"]["plan_name"] == "الأساسية"
    assert plan_payload["provider_offer"]["annual_price"] == "0.00"
    assert plan_payload["provider_offer"]["verification_blue_label"] == "100.00 ر.س سنويًا"
    assert plan_payload["provider_offer"]["cta"]["state"] == "current"
    assert plan_payload["provider_offer"]["cta"]["label"] == "الباقة الحالية"
    labels = plan_payload.get("feature_labels") or []
    assert any("رسوم التوثيق" in label for label in labels)
    assert not any("توثيق (شارة" in label for label in labels)


def test_plans_list_exposes_upgrade_cards_and_official_provider_offer(api, user):
    _make_provider(user)
    plan_pioneer, _ = SubscriptionPlan.objects.update_or_create(
        code="riyadi",
        defaults={
            "tier": "riyadi",
            "title": "ريادية خام",
            "period": PlanPeriod.MONTH,
            "price": Decimal("79.00"),
        },
    )
    plan_professional, _ = SubscriptionPlan.objects.update_or_create(
        code="pro",
        defaults={
            "tier": "pro",
            "title": "احترافية خام",
            "period": PlanPeriod.MONTH,
            "price": Decimal("99.00"),
        },
    )
    api.force_authenticate(user=user)

    response = api.get("/api/subscriptions/plans/")

    assert response.status_code == 200
    by_id = {item["id"]: item for item in response.data}
    pioneer_offer = by_id[plan_pioneer.id]["provider_offer"]
    professional_offer = by_id[plan_professional.id]["provider_offer"]

    assert pioneer_offer["plan_name"] == "الريادية"
    assert pioneer_offer["annual_price"] == "199.00"
    assert pioneer_offer["billing_cycle_label"] == "سنوي"
    assert pioneer_offer["verification_blue_label"] == "50.00 ر.س سنويًا"
    assert pioneer_offer["verification_green_label"] == "50.00 ر.س سنويًا"
    assert pioneer_offer["cta"]["state"] == "upgrade"
    assert pioneer_offer["cta"]["label"] == "ترقية"
    assert pioneer_offer["request_access_label"] == "بعد 24 ساعة"

    assert professional_offer["plan_name"] == "الاحترافية"
    assert professional_offer["annual_price"] == "999.00"
    assert professional_offer["promotional_permissions_label"] == "متاحة للمحادثات والإشعارات"
    assert professional_offer["support_sla_label"] == "خلال 5 ساعات"
    assert professional_offer["cta"]["state"] == "upgrade"


def test_subscribe(api, user):
    plan = SubscriptionPlan.objects.create(
        code="PRO",
        tier="pro",
        title="Pro",
        period=PlanPeriod.MONTH,
        price=Decimal("25.00"),
        features=["verify_blue"],
    )
    _make_provider(user)
    api.force_authenticate(user=user)
    r = api.post(f"/api/subscriptions/subscribe/{plan.pk}/")
    assert r.status_code == 201
    assert r.data["invoice"] is not None
    sub = Subscription.objects.get(pk=r.data["id"])
    ur = UnifiedRequest.objects.get(source_app="subscriptions", source_model="Subscription", source_object_id=str(sub.id))
    assert ur.code.startswith("SD")
    assert ur.status == "new"
    assert ur.metadata_record.payload.get("invoice_id") == sub.invoice_id


def test_subscribe_allows_unverified_provider(api, user):
    plan = SubscriptionPlan.objects.create(
        code="PRO2",
        tier="pro",
        title="Pro2",
        period=PlanPeriod.MONTH,
        price=Decimal("25.00"),
    )
    _make_provider(user)
    api.force_authenticate(user=user)
    r = api.post(f"/api/subscriptions/subscribe/{plan.pk}/")
    assert r.status_code == 201
    assert r.data["invoice"] is not None
    assert Subscription.objects.filter(user=user, plan=plan).exists()


def test_subscribe_uses_official_annual_amount_and_year_duration_for_canonical_plan(api, user):
    plan, _ = SubscriptionPlan.objects.update_or_create(
        code="riyadi",
        defaults={
            "tier": "riyadi",
            "title": "ريادية خام",
            "period": PlanPeriod.MONTH,
            "price": Decimal("79.00"),
        },
    )
    _make_provider(user)
    api.force_authenticate(user=user)

    response = api.post(f"/api/subscriptions/subscribe/{plan.pk}/")

    assert response.status_code == 201
    sub = Subscription.objects.select_related("invoice", "plan").get(pk=response.data["id"])
    assert sub.invoice is not None
    assert sub.invoice.subtotal == Decimal("199.00")
    assert sub.invoice.vat_percent == Decimal("0.00")
    assert sub.invoice.total == Decimal("199.00")

    sub.invoice.mark_payment_confirmed(
        provider="mock",
        provider_reference="annual-offer",
        event_id="annual-offer-event",
        amount=sub.invoice.total,
        currency=sub.invoice.currency,
    )
    sub.invoice.save()
    sub = activate_subscription_after_payment(sub=sub)

    assert sub.start_at is not None
    assert sub.end_at is not None
    assert (sub.end_at - sub.start_at).days == 365


def test_subscribe_rejects_current_or_lower_plan_selection(api, user):
    _make_provider(user)
    professional_plan, _ = SubscriptionPlan.objects.update_or_create(
        code="pro",
        defaults={
            "tier": "pro",
            "title": "احترافية",
            "period": PlanPeriod.YEAR,
            "price": Decimal("999.00"),
        },
    )
    professional_sub = Subscription.objects.create(
        user=user,
        plan=professional_plan,
        status=SubscriptionStatus.PENDING_PAYMENT,
    )
    from apps.billing.models import Invoice

    invoice = Invoice.objects.create(
        user=user,
        subtotal=Decimal("999.00"),
        vat_percent=Decimal("0.00"),
        reference_type="subscription",
        reference_id=str(professional_sub.pk),
    )
    invoice.mark_pending()
    invoice.save()
    invoice.mark_payment_confirmed(
        provider="mock",
        provider_reference="sub-current",
        event_id="sub-current",
        amount=invoice.total,
        currency=invoice.currency,
    )
    invoice.save()
    professional_sub.invoice = invoice
    professional_sub.save(update_fields=["invoice", "updated_at"])
    activate_subscription_after_payment(sub=professional_sub)

    api.force_authenticate(user=user)

    current_response = api.post(f"/api/subscriptions/subscribe/{professional_plan.pk}/")
    assert current_response.status_code == 400
    assert "الحالية" in str(current_response.data.get("detail", ""))

    basic_plan = Subscription.objects.get(user=user, plan__code="basic").plan
    lower_response = api.post(f"/api/subscriptions/subscribe/{basic_plan.pk}/")
    assert lower_response.status_code == 400
    assert "خفض" in str(lower_response.data.get("detail", ""))


def test_subscriptions_endpoints_require_auth(api):
    r1 = api.get("/api/subscriptions/plans/")
    r2 = api.get("/api/subscriptions/my/")
    assert r1.status_code in (401, 403)
    assert r2.status_code in (401, 403)


def test_subscribe_rejects_non_provider(api, user):
    plan = SubscriptionPlan.objects.create(
        code="PRO3",
        tier="pro",
        title="Pro3",
        period=PlanPeriod.MONTH,
        price=Decimal("25.00"),
    )
    user.role_state = UserRole.CLIENT
    user.save(update_fields=["role_state"])
    api.force_authenticate(user=user)

    response = api.post(f"/api/subscriptions/subscribe/{plan.pk}/")

    assert response.status_code == 403
    assert "مقدمي الخدمات" in str(response.data.get("detail", ""))


def test_subscription_read_endpoints_reject_non_provider(api, user):
    user.role_state = UserRole.CLIENT
    user.save(update_fields=["role_state"])
    api.force_authenticate(user=user)

    plans_response = api.get("/api/subscriptions/plans/")
    my_response = api.get("/api/subscriptions/my/")

    assert plans_response.status_code == 403
    assert my_response.status_code == 403


def test_subscribe_rejects_provider_role_without_profile(api, user):
    plan = SubscriptionPlan.objects.create(
        code="PRO4",
        tier="pro",
        title="Pro4",
        period=PlanPeriod.MONTH,
        price=Decimal("25.00"),
    )
    user.role_state = UserRole.PROVIDER
    user.save(update_fields=["role_state"])
    api.force_authenticate(user=user)

    response = api.post(f"/api/subscriptions/subscribe/{plan.pk}/")

    assert response.status_code == 403
    assert "ملف مقدم الخدمة" in str(response.data.get("detail", ""))


def test_provider_profile_only_legacy_user_can_subscribe(api, user):
    plan = SubscriptionPlan.objects.create(
        code="PRO5",
        tier="pro",
        title="Pro5",
        period=PlanPeriod.MONTH,
        price=Decimal("25.00"),
    )
    _make_provider(user, sync_role=False)
    api.force_authenticate(user=user)

    response = api.post(f"/api/subscriptions/subscribe/{plan.pk}/")

    assert response.status_code == 201


def test_subscription_activation_and_refresh_syncs_unified(user):
    plan = SubscriptionPlan.objects.create(
        code="PROX",
        tier="pro",
        title="Pro X",
        period=PlanPeriod.MONTH,
        price=Decimal("25.00"),
    )
    _make_provider(user)
    sub = Subscription.objects.create(user=user, plan=plan, status=SubscriptionStatus.PENDING_PAYMENT)
    # Simulate initial unified sync path used by checkout
    from apps.subscriptions.services import _sync_subscription_to_unified

    _sync_subscription_to_unified(sub=sub, changed_by=user)
    sub.invoice_id = None  # guard in case reused; not needed
    from apps.billing.models import Invoice
    inv = Invoice.objects.create(user=user, subtotal=Decimal("25.00"), reference_type="subscription", reference_id=str(sub.pk))
    inv.mark_pending()
    inv.save()
    inv.mark_payment_confirmed(
        provider="mock",
        provider_reference="test-ref",
        event_id="test-event",
        amount=inv.total,
        currency=inv.currency,
    )
    inv.save()
    sub.invoice = inv
    sub.save(update_fields=["invoice", "updated_at"])

    sub = activate_subscription_after_payment(sub=sub)
    ur = UnifiedRequest.objects.get(source_app="subscriptions", source_model="Subscription", source_object_id=str(sub.id))
    assert ur.status == "in_progress"
    assert ur.metadata_record.payload.get("subscription_status") == "active"

    sub.end_at = sub.start_at - timedelta(seconds=1)
    sub.grace_end_at = sub.end_at + timedelta(days=1)
    sub.save(update_fields=["end_at", "grace_end_at", "updated_at"])
    sub = refresh_subscription_status(sub=sub)
    ur.refresh_from_db()
    # GRACE maps to in_progress in the unified operational lifecycle.
    assert sub.status == "grace"
    assert ur.status == "in_progress"
    assert ur.metadata_record.payload.get("subscription_status") == "grace"


def test_provider_subscription_pages_render_arabic_titles(client):
    plans_page = client.get("/plans/")
    summary_page = client.get("/plans/summary/?plan_id=1")

    assert plans_page.status_code == 200
    assert "باقات اشتراك مقدم الخدمة" in plans_page.content.decode("utf-8")

    assert summary_page.status_code == 200
    assert "ملخص الاشتراك والترقية" in summary_page.content.decode("utf-8")
