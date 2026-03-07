import pytest
from django.test import Client
from django.urls import reverse

from apps.accounts.models import User
from apps.audit.models import AuditAction, AuditLog
from apps.backoffice.models import AccessLevel, Dashboard, UserAccessProfile
from apps.billing.models import Invoice, InvoiceStatus
from apps.dashboard.auth import SESSION_OTP_VERIFIED_KEY


pytestmark = pytest.mark.django_db


@pytest.mark.parametrize(
    "reference_type,reference_id",
    [
        ("subscription", "1"),
        ("verify_request", "AD000001"),
    ],
)
def test_dashboard_blocks_manual_status_change_for_protected_billing_flows(reference_type, reference_id):
    admin_user = User.objects.create_user(phone=f"0509{reference_id[-4:]:0>6}", password="Pass12345!", is_staff=True)
    billing_dashboard = Dashboard.objects.create(code="billing", name_ar="الفوترة", sort_order=10)
    UserAccessProfile.objects.create(user=admin_user, level=AccessLevel.ADMIN).allowed_dashboards.set([billing_dashboard])

    invoice = Invoice.objects.create(
        user=admin_user,
        title="فاتورة محمية",
        subtotal="100.00",
        reference_type=reference_type,
        reference_id=reference_id,
        status=InvoiceStatus.DRAFT,
    )
    invoice.mark_pending()
    invoice.save(update_fields=["status", "subtotal", "vat_percent", "vat_amount", "total", "updated_at"])

    client = Client()
    assert client.login(phone=admin_user.phone, password="Pass12345!")
    session = client.session
    session[SESSION_OTP_VERIFIED_KEY] = True
    session.save()

    response = client.post(
        reverse("dashboard:billing_invoice_set_status_action", args=[invoice.id]),
        data={"action": "mark_paid"},
    )

    invoice.refresh_from_db()
    assert response.status_code == 302
    assert invoice.status == InvoiceStatus.PENDING
    assert invoice.payment_confirmed is False
    assert AuditLog.objects.filter(
        action=AuditAction.INVOICE_STATUS_CHANGE_BLOCKED,
        reference_type="invoice",
        reference_id=invoice.code,
    ).exists()
