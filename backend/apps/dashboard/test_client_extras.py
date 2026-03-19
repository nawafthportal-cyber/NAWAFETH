"""
اختبارات بوابة العميل للخدمات الإضافية — Phase 6.
"""
import pytest
from decimal import Decimal

from django.test import Client
from django.urls import reverse

from apps.accounts.models import User
from apps.backoffice.models import AccessLevel, UserAccessProfile
from apps.billing.models import Invoice, InvoiceStatus
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY
from apps.extras.models import ExtraPurchase, ExtraPurchaseStatus, ServiceCatalog


def _make_client_user(phone="0500090001"):
    """Create a CLIENT-level user with OTP-verified session."""
    user = User.objects.create_user(phone=phone, password="Pass12345!")
    UserAccessProfile.objects.create(user=user, level=AccessLevel.CLIENT)
    c = Client()
    assert c.login(phone=phone, password="Pass12345!")
    s = c.session
    s[SESSION_OTP_VERIFIED_KEY] = True
    s.save()
    return user, c


def _make_admin_user(phone="0500090099"):
    """Create an ADMIN-level user (no client_extras access)."""
    user = User.objects.create_user(phone=phone, password="Pass12345!")
    UserAccessProfile.objects.create(user=user, level=AccessLevel.ADMIN)
    c = Client()
    assert c.login(phone=phone, password="Pass12345!")
    s = c.session
    s[SESSION_OTP_VERIFIED_KEY] = True
    s.save()
    return user, c


def _seed_catalog():
    """Seed a ServiceCatalog item for tests."""
    ServiceCatalog.objects.all().delete()
    return ServiceCatalog.objects.create(
        sku="test_10gb", title="تخزين 10GB", price=Decimal("100.00"),
        currency="SAR", is_active=True, sort_order=1,
    )


# ─── Catalog ────────────────────────────────────────────────

@pytest.mark.django_db
def test_client_extras_catalog_accessible():
    _seed_catalog()
    _, c = _make_client_user()
    res = c.get(reverse("dashboard:client_extras_catalog"))
    assert res.status_code == 200
    assert "تخزين 10GB" in res.content.decode()


@pytest.mark.django_db
def test_client_extras_catalog_empty():
    ServiceCatalog.objects.all().delete()
    _, c = _make_client_user()
    res = c.get(reverse("dashboard:client_extras_catalog"))
    assert res.status_code == 200


@pytest.mark.django_db
def test_client_extras_catalog_blocked_for_admin():
    """ADMIN users should NOT access client-only dashboards."""
    _seed_catalog()
    _, c = _make_admin_user()
    res = c.get(reverse("dashboard:client_extras_catalog"))
    # Should redirect (access denied → first_allowed_dashboard_route)
    assert res.status_code == 302


@pytest.mark.django_db
def test_client_extras_catalog_requires_login():
    c = Client()
    res = c.get(reverse("dashboard:client_extras_catalog"))
    assert res.status_code == 302


# ─── Purchases ──────────────────────────────────────────────

@pytest.mark.django_db
def test_client_extras_purchases_empty():
    _, c = _make_client_user()
    res = c.get(reverse("dashboard:client_extras_purchases"))
    assert res.status_code == 200


@pytest.mark.django_db
def test_client_extras_purchases_shows_own():
    user, c = _make_client_user()
    inv = Invoice.objects.create(
        user=user, code="INV-T001", title="فاتورة تخزين",
        subtotal=Decimal("100"), vat_percent=Decimal("15"),
        vat_amount=Decimal("15"), total=Decimal("115"),
        status=InvoiceStatus.PAID,
    )
    ExtraPurchase.objects.create(
        user=user, sku="test_10gb", title="تخزين 10GB",
        subtotal=Decimal("100"), invoice=inv,
        status=ExtraPurchaseStatus.ACTIVE,
    )
    res = c.get(reverse("dashboard:client_extras_purchases"))
    assert res.status_code == 200
    assert "تخزين 10GB" in res.content.decode()
    assert "INV-T001" in res.content.decode()


@pytest.mark.django_db
def test_client_extras_purchases_hides_others():
    """A client should NOT see another user's purchases."""
    user, c = _make_client_user("0500090002")
    other = User.objects.create_user(phone="0500090003", password="Pass12345!")
    inv = Invoice.objects.create(
        user=other, code="INV-T002", title="فاتورة أخرى",
        subtotal=Decimal("200"), vat_percent=Decimal("15"),
        vat_amount=Decimal("30"), total=Decimal("230"),
        status=InvoiceStatus.PAID,
    )
    ExtraPurchase.objects.create(
        user=other, sku="test_50gb", title="تخزين 50GB",
        subtotal=Decimal("200"), invoice=inv,
        status=ExtraPurchaseStatus.ACTIVE,
    )
    res = c.get(reverse("dashboard:client_extras_purchases"))
    assert res.status_code == 200
    assert "تخزين 50GB" not in res.content.decode()
    assert "INV-T002" not in res.content.decode()


# ─── Buy ────────────────────────────────────────────────────

@pytest.mark.django_db
def test_client_extras_buy_requires_post():
    _seed_catalog()
    _, c = _make_client_user()
    res = c.get(reverse("dashboard:client_extras_buy", args=["test_10gb"]))
    # GET should redirect to catalog
    assert res.status_code == 302
    assert "client/extras" in res.url


@pytest.mark.django_db
def test_client_extras_buy_success():
    _seed_catalog()
    user, c = _make_client_user()
    res = c.post(reverse("dashboard:client_extras_buy", args=["test_10gb"]))
    assert res.status_code == 302
    assert ExtraPurchase.objects.filter(user=user, sku="test_10gb").exists()


@pytest.mark.django_db
def test_client_extras_buy_invalid_sku():
    _seed_catalog()
    _, c = _make_client_user()
    res = c.post(reverse("dashboard:client_extras_buy", args=["nonexistent_sku"]))
    assert res.status_code == 302  # redirects with error message


# ─── Invoice ────────────────────────────────────────────────

@pytest.mark.django_db
def test_client_extras_invoice_own():
    user, c = _make_client_user()
    inv = Invoice.objects.create(
        user=user, code="INV-T003", title="فاتورة اختبار",
        subtotal=Decimal("100"), vat_percent=Decimal("15"),
        vat_amount=Decimal("15"), total=Decimal("115"),
        status=InvoiceStatus.PENDING,
    )
    ExtraPurchase.objects.create(
        user=user, sku="test_10gb", title="تخزين 10GB",
        subtotal=Decimal("100"), invoice=inv,
        status=ExtraPurchaseStatus.PENDING_PAYMENT,
    )
    res = c.get(reverse("dashboard:client_extras_invoice", args=[inv.id]))
    assert res.status_code == 200
    assert "INV-T003" in res.content.decode()


@pytest.mark.django_db
def test_client_extras_invoice_other_user_404():
    """Client should NOT see another user's invoice."""
    _, c = _make_client_user("0500090004")
    other = User.objects.create_user(phone="0500090005", password="Pass12345!")
    inv = Invoice.objects.create(
        user=other, code="INV-T004", title="فاتورة غريب",
        subtotal=Decimal("50"), vat_percent=Decimal("15"),
        vat_amount=Decimal("7.50"), total=Decimal("57.50"),
        status=InvoiceStatus.PAID,
    )
    ExtraPurchase.objects.create(
        user=other, sku="test_10gb", title="تخزين 10GB",
        subtotal=Decimal("50"), invoice=inv,
        status=ExtraPurchaseStatus.ACTIVE,
    )
    res = c.get(reverse("dashboard:client_extras_invoice", args=[inv.id]))
    assert res.status_code == 404
