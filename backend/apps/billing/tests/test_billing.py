from decimal import Decimal

import pytest
from django.test import override_settings
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole
from apps.billing.models import Invoice, InvoiceStatus, WebhookEvent
from apps.billing.services import handle_webhook, init_payment, sign_webhook_payload
from apps.providers.models import ProviderProfile
from apps.subscriptions.models import PlanPeriod, PlanTier, Subscription, SubscriptionPlan, SubscriptionStatus
from apps.subscriptions.services import start_subscription_checkout
from apps.verification.models import (
    VerificationBadgeType,
    VerificationRequest,
    VerificationRequirement,
    VerificationStatus,
    VerifiedBadge,
)


pytestmark = pytest.mark.django_db


@pytest.fixture
def api():
    return APIClient()


@pytest.fixture
def user():
    return User.objects.create_user(phone="0533333333", password="Pass12345!")


def _make_provider(user):
    user.role_state = UserRole.PROVIDER
    user.save(update_fields=["role_state"])
    return ProviderProfile.objects.create(
        user=user,
        provider_type="individual",
        display_name=f"Provider {user.phone}",
        bio="bio",
    )


def _webhook_payload(*, invoice: Invoice, provider_reference: str, status: str, amount: str | None = None, currency: str | None = None):
    return {
        "provider_reference": provider_reference,
        "invoice_code": invoice.code,
        "status": status,
        "amount": amount or str(invoice.total),
        "currency": currency or invoice.currency,
    }


def _signed_headers(*, provider: str, payload: dict, event_id: str):
    return {
        "HTTP_X_SIGNATURE": sign_webhook_payload(provider=provider, payload=payload, event_id=event_id),
        "HTTP_X_EVENT_ID": event_id,
    }


def test_create_invoice(api, user):
    api.force_authenticate(user=user)
    r = api.post("/api/billing/invoices/", data={
        "title": "Test",
        "subtotal": "100.00",
        "reference_type": "x",
        "reference_id": "1",
    }, format="json")
    assert r.status_code == 201
    assert r.data["code"].startswith("IV")


def test_init_payment(api, user):
    api.force_authenticate(user=user)
    inv = Invoice.objects.create(user=user, title="T", subtotal="50.00", reference_type="x", reference_id="1")
    r = api.post(f"/api/billing/invoices/{inv.pk}/init-payment/", data={"provider": "mock"}, format="json")
    assert r.status_code == 200
    assert "checkout_url" in r.data


@override_settings(BILLING_WEBHOOK_SECRETS={"mock": "phase1-secret"})
def test_webhook_rejects_invalid_signature(api, user):
    inv = Invoice.objects.create(user=user, title="T", subtotal="50.00", reference_type="x", reference_id="1")
    attempt = init_payment(invoice=inv, provider="mock", by_user=user, idempotency_key="billing-invalid-signature")
    payload = _webhook_payload(invoice=attempt.invoice, provider_reference=attempt.provider_reference, status="success")

    response = api.post(
        "/api/billing/webhooks/mock/",
        data=payload,
        format="json",
        HTTP_X_SIGNATURE="bad-signature",
        HTTP_X_EVENT_ID="evt-invalid-signature",
    )

    inv.refresh_from_db()
    assert response.status_code == 403
    assert response.data["code"] == "invalid_signature"
    assert inv.status == InvoiceStatus.PENDING
    assert inv.payment_confirmed is False
    assert WebhookEvent.objects.filter(provider="mock", event_id="evt-invalid-signature").count() == 0


@override_settings(BILLING_WEBHOOK_SECRETS={"mock": "phase1-secret"})
def test_webhook_rejects_duplicate_event_id(api, user):
    inv = Invoice.objects.create(user=user, title="T", subtotal="50.00", reference_type="x", reference_id="1")
    attempt = init_payment(invoice=inv, provider="mock", by_user=user, idempotency_key="billing-duplicate-event")
    payload = _webhook_payload(invoice=attempt.invoice, provider_reference=attempt.provider_reference, status="success")
    headers = _signed_headers(provider="mock", payload=payload, event_id="evt-duplicate")

    first = api.post("/api/billing/webhooks/mock/", data=payload, format="json", **headers)
    second = api.post("/api/billing/webhooks/mock/", data=payload, format="json", **headers)

    inv.refresh_from_db()
    assert first.status_code == 200
    assert second.status_code == 409
    assert second.data["code"] == "duplicate_event"
    assert WebhookEvent.objects.filter(provider="mock", event_id="evt-duplicate").count() == 1
    assert inv.status == InvoiceStatus.PAID
    assert inv.payment_confirmed is True


@override_settings(BILLING_WEBHOOK_SECRETS={"mock": "phase1-secret"})
def test_webhook_rejects_amount_mismatch(api, user):
    inv = Invoice.objects.create(user=user, title="T", subtotal="50.00", reference_type="x", reference_id="1")
    attempt = init_payment(invoice=inv, provider="mock", by_user=user, idempotency_key="billing-amount-mismatch")
    payload = _webhook_payload(
        invoice=attempt.invoice,
        provider_reference=attempt.provider_reference,
        status="success",
        amount="999.00",
    )
    headers = _signed_headers(provider="mock", payload=payload, event_id="evt-amount-mismatch")

    response = api.post("/api/billing/webhooks/mock/", data=payload, format="json", **headers)

    inv.refresh_from_db()
    assert response.status_code == 400
    assert response.data["code"] == "amount_mismatch"
    assert inv.status == InvoiceStatus.PENDING
    assert inv.payment_confirmed is False


@override_settings(BILLING_WEBHOOK_SECRETS={"mock": "phase1-secret"})
def test_paid_webhook_sets_trusted_payment_and_activates_subscription(user):
    _make_provider(user)
    plan = SubscriptionPlan.objects.create(
        code="PHASE1-RIYADI",
        tier=PlanTier.RIYADI,
        title="Phase 1 Riyadi",
        period=PlanPeriod.MONTH,
        price=Decimal("120.00"),
    )
    sub = start_subscription_checkout(user=user, plan=plan)
    attempt = init_payment(invoice=sub.invoice, provider="mock", by_user=user, idempotency_key="phase1-sub-paid")
    payload = _webhook_payload(invoice=sub.invoice, provider_reference=attempt.provider_reference, status="success")

    result = handle_webhook(
        provider="mock",
        payload=payload,
        signature=sign_webhook_payload(provider="mock", payload=payload, event_id="evt-sub-paid"),
        event_id="evt-sub-paid",
    )

    sub.refresh_from_db()
    sub.invoice.refresh_from_db()
    assert result["ok"] is True
    assert sub.invoice.status == InvoiceStatus.PAID
    assert sub.invoice.payment_confirmed is True
    assert sub.invoice.payment_amount == sub.invoice.total
    assert sub.invoice.payment_currency == sub.invoice.currency
    assert sub.status == SubscriptionStatus.ACTIVE
    assert sub.start_at is not None


@override_settings(BILLING_WEBHOOK_SECRETS={"mock": "phase1-secret"})
def test_reversal_webhook_revokes_subscription_activation(user):
    _make_provider(user)
    plan = SubscriptionPlan.objects.create(
        code="PHASE1-PRO",
        tier=PlanTier.PRO,
        title="Phase 1 Pro",
        period=PlanPeriod.MONTH,
        price=Decimal("240.00"),
    )
    sub = start_subscription_checkout(user=user, plan=plan)
    attempt = init_payment(invoice=sub.invoice, provider="mock", by_user=user, idempotency_key="phase1-sub-reversal")
    success_payload = _webhook_payload(invoice=sub.invoice, provider_reference=attempt.provider_reference, status="success")
    refund_payload = _webhook_payload(invoice=sub.invoice, provider_reference=attempt.provider_reference, status="refunded")

    handle_webhook(
        provider="mock",
        payload=success_payload,
        signature=sign_webhook_payload(provider="mock", payload=success_payload, event_id="evt-sub-success"),
        event_id="evt-sub-success",
    )
    handle_webhook(
        provider="mock",
        payload=refund_payload,
        signature=sign_webhook_payload(provider="mock", payload=refund_payload, event_id="evt-sub-refund"),
        event_id="evt-sub-refund",
    )

    sub.refresh_from_db()
    sub.invoice.refresh_from_db()
    assert sub.invoice.status == InvoiceStatus.REFUNDED
    assert sub.invoice.payment_confirmed is False
    assert sub.status == SubscriptionStatus.PENDING_PAYMENT
    assert sub.start_at is None
    assert sub.end_at is None


@override_settings(BILLING_WEBHOOK_SECRETS={"mock": "phase1-secret"})
def test_reversal_webhook_revokes_verification_badge(user):
    vr = VerificationRequest.objects.create(
        requester=user,
        badge_type=VerificationBadgeType.BLUE,
        status=VerificationStatus.PENDING_PAYMENT,
    )
    req = VerificationRequirement.objects.create(
        request=vr,
        badge_type=VerificationBadgeType.BLUE,
        code="B1",
        title="هوية وطنية",
        is_approved=True,
    )
    req.attachments.create(
        file=SimpleUploadedFile("b1.png", b"evidence", content_type="image/png"),
        uploaded_by=user,
    )
    invoice = Invoice.objects.create(
        user=user,
        title="رسوم التوثيق",
        subtotal=Decimal("100.00"),
        reference_type="verify_request",
        reference_id=vr.code,
        status=InvoiceStatus.DRAFT,
    )
    invoice.mark_pending()
    invoice.save(update_fields=["status", "subtotal", "vat_percent", "vat_amount", "total", "updated_at"])
    vr.invoice = invoice
    vr.save(update_fields=["invoice", "updated_at"])

    attempt = init_payment(invoice=invoice, provider="mock", by_user=user, idempotency_key="phase1-vr-reversal")
    success_payload = _webhook_payload(invoice=invoice, provider_reference=attempt.provider_reference, status="success")
    refund_payload = _webhook_payload(invoice=invoice, provider_reference=attempt.provider_reference, status="refunded")

    handle_webhook(
        provider="mock",
        payload=success_payload,
        signature=sign_webhook_payload(provider="mock", payload=success_payload, event_id="evt-vr-success"),
        event_id="evt-vr-success",
    )

    vr.refresh_from_db()
    assert vr.status == VerificationStatus.ACTIVE
    assert VerifiedBadge.objects.filter(request=vr, is_active=True).count() == 1

    handle_webhook(
        provider="mock",
        payload=refund_payload,
        signature=sign_webhook_payload(provider="mock", payload=refund_payload, event_id="evt-vr-refund"),
        event_id="evt-vr-refund",
    )

    vr.refresh_from_db()
    invoice.refresh_from_db()
    assert invoice.status == InvoiceStatus.REFUNDED
    assert vr.status == VerificationStatus.PENDING_PAYMENT
    assert vr.activated_at is None
    assert vr.expires_at is None
    assert VerifiedBadge.objects.filter(request=vr, is_active=True).count() == 0


@override_settings(BILLING_WEBHOOK_SECRETS={"mock": "phase1-secret"})
def test_cancelled_invoice_revokes_verification_badge(user):
    vr = VerificationRequest.objects.create(
        requester=user,
        badge_type=VerificationBadgeType.BLUE,
        status=VerificationStatus.PENDING_PAYMENT,
    )
    req = VerificationRequirement.objects.create(
        request=vr,
        badge_type=VerificationBadgeType.BLUE,
        code="B1",
        title="هوية وطنية",
        is_approved=True,
    )
    req.attachments.create(
        file=SimpleUploadedFile("b1.png", b"evidence", content_type="image/png"),
        uploaded_by=user,
    )
    invoice = Invoice.objects.create(
        user=user,
        title="رسوم التوثيق",
        subtotal=Decimal("100.00"),
        vat_percent=Decimal("0.00"),
        reference_type="verify_request",
        reference_id=vr.code,
        status=InvoiceStatus.DRAFT,
    )
    invoice.mark_pending()
    invoice.save(update_fields=["status", "subtotal", "vat_percent", "vat_amount", "total", "updated_at"])
    vr.invoice = invoice
    vr.save(update_fields=["invoice", "updated_at"])

    attempt = init_payment(invoice=invoice, provider="mock", by_user=user, idempotency_key="phase7-vr-cancel")
    success_payload = _webhook_payload(invoice=invoice, provider_reference=attempt.provider_reference, status="success")
    handle_webhook(
        provider="mock",
        payload=success_payload,
        signature=sign_webhook_payload(provider="mock", payload=success_payload, event_id="evt-vr-success-cancel"),
        event_id="evt-vr-success-cancel",
    )

    vr.refresh_from_db()
    assert vr.status == VerificationStatus.ACTIVE
    assert VerifiedBadge.objects.filter(request=vr, is_active=True).count() == 1

    invoice.refresh_from_db()
    invoice.clear_payment_confirmation()
    invoice.mark_cancelled(force=True)
    invoice.save(
        update_fields=[
            "status",
            "cancelled_at",
            "payment_confirmed",
            "payment_confirmed_at",
            "payment_provider",
            "payment_reference",
            "payment_event_id",
            "payment_amount",
            "payment_currency",
            "updated_at",
        ]
    )

    vr.refresh_from_db()
    assert vr.status == VerificationStatus.PENDING_PAYMENT
    assert VerifiedBadge.objects.filter(request=vr, is_active=True).count() == 0
