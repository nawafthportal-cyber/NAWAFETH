from __future__ import annotations

import csv
from django.http import HttpResponse

from apps.billing.models import Invoice


def _csv_safe_cell(value):
    if value is None:
        return ""
    text = str(value)
    if text and text[0] in {"=", "+", "-", "@"}:
        return f"'{text}"
    return text


def export_paid_invoices_csv():
    qs = Invoice.objects.filter(status="paid").order_by("-paid_at")[:5000]

    resp = HttpResponse(content_type="text/csv")
    resp["Content-Disposition"] = 'attachment; filename="paid_invoices.csv"'

    writer = csv.writer(resp)
    writer.writerow(["invoice_code", "user_phone", "total", "paid_at"])

    for inv in qs:
        writer.writerow(
            [
                _csv_safe_cell(inv.code),
                _csv_safe_cell(getattr(inv.user, "phone", "")),
                _csv_safe_cell(inv.total),
                _csv_safe_cell(inv.paid_at),
            ]
        )

    return resp
