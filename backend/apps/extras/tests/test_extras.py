import pytest
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.billing.models import Invoice
from apps.extras.models import ExtraPurchase
from apps.extras.services import activate_extra_after_payment, consume_credit
from apps.unified_requests.models import UnifiedRequest


pytestmark = pytest.mark.django_db


@pytest.fixture
def api():
    return APIClient()


@pytest.fixture
def user():
    return User.objects.create_user(phone="0599999999", password="Pass12345!")


def test_catalog(api, user, settings):
    settings.EXTRA_SKUS = {"uploads_10gb_month": {"title": "10GB", "price": 59}}
    api.force_authenticate(user=user)
    r = api.get("/api/extras/catalog/")
    assert r.status_code == 200
    assert len(r.data) == 1


def test_buy_extra(api, user, settings):
    settings.EXTRA_SKUS = {"uploads_10gb_month": {"title": "10GB", "price": 59}}
    api.force_authenticate(user=user)
    r = api.post("/api/extras/buy/uploads_10gb_month/")
    assert r.status_code == 201
    assert r.data["invoice"] is not None
    p = ExtraPurchase.objects.get(pk=r.data["id"])
    ur = UnifiedRequest.objects.get(source_app="extras", source_model="ExtraPurchase", source_object_id=str(p.id))
    assert ur.code.startswith("P")
    assert ur.status == "pending_payment"
    assert ur.metadata_record.payload.get("invoice_id") == p.invoice_id


def test_extras_endpoints_require_auth(api):
    r1 = api.get("/api/extras/catalog/")
    r2 = api.get("/api/extras/my/")
    assert r1.status_code in (401, 403)
    assert r2.status_code in (401, 403)


def test_extra_activation_and_credit_consumption_syncs_unified(user, settings):
    settings.EXTRA_SKUS = {"tickets_2": {"title": "تذاكر", "price": 10}}
    from apps.extras.services import create_extra_purchase_checkout

    p = create_extra_purchase_checkout(user=user, sku="tickets_2")
    inv: Invoice = p.invoice
    inv.mark_paid()
    inv.save()
    p = activate_extra_after_payment(purchase=p)

    ur = UnifiedRequest.objects.get(source_app="extras", source_model="ExtraPurchase", source_object_id=str(p.id))
    assert p.status == "active"
    assert ur.status == "active"
    assert ur.metadata_record.payload.get("credits_total") == 2

    assert consume_credit(user=user, sku="tickets_2", amount=1) is True
    ur.refresh_from_db()
    assert ur.metadata_record.payload.get("credits_used") == 1
    assert ur.status == "active"

    assert consume_credit(user=user, sku="tickets_2", amount=1) is True
    p.refresh_from_db()
    ur.refresh_from_db()
    assert p.status == "consumed"
    assert ur.status == "completed"
    assert ur.metadata_record.payload.get("purchase_status") == "consumed"
