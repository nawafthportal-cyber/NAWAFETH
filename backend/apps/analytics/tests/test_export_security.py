import pytest
from decimal import Decimal
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.audit.models import AuditAction, AuditLog
from apps.backoffice.models import AccessLevel, UserAccessProfile
from apps.billing.models import Invoice


pytestmark = pytest.mark.django_db


def test_paid_invoices_export_csv_sanitizes_formula_cells_and_is_audited():
    user = User.objects.create_user(phone="0513000001", password="Pass12345!")
    UserAccessProfile.objects.create(user=user, level=AccessLevel.ADMIN)

    inv = Invoice.objects.create(
        user=user,
        title="فاتورة",
        subtotal=Decimal("10.00"),
        total=Decimal("10.00"),
        status="paid",
    )
    inv.code = "=CMD"
    inv.save(update_fields=["code", "updated_at"])

    api = APIClient()
    api.force_authenticate(user=user)
    response = api.get("/api/analytics/export/paid-invoices.csv")

    assert response.status_code == 200
    body = response.content.decode("utf-8")
    assert "'=CMD" in body

    assert AuditLog.objects.filter(
        actor=user,
        action=AuditAction.DATA_EXPORTED,
        reference_type="export",
        reference_id="paid_invoices.csv",
    ).exists()
