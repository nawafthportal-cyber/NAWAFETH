from __future__ import annotations

import os
import sys

import django


PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
os.environ.setdefault("DJANGO_ENV", "dev")
django.setup()

from apps.billing.models import Invoice, PaymentAttempt  # noqa: E402
from apps.extras.services import EXTRAS_BUNDLE_INVOICE_REFERENCE_TYPE, extras_bundle_payment_access_url  # noqa: E402
from apps.messaging.models import Message  # noqa: E402
from apps.notifications.models import Notification  # noqa: E402
from apps.unified_requests.models import UnifiedRequest, UnifiedRequestType  # noqa: E402


def main() -> None:
    updated_invoices = 0
    updated_metadata = 0
    updated_notifications = 0
    updated_messages = 0

    invoices = Invoice.objects.filter(reference_type=EXTRAS_BUNDLE_INVOICE_REFERENCE_TYPE).select_related("user").order_by("id")
    for invoice in invoices:
        request_code = str(invoice.reference_id or "").strip()
        if not request_code:
            continue

        request_obj = (
            UnifiedRequest.objects.select_related("requester", "metadata_record")
            .filter(request_type=UnifiedRequestType.EXTRAS, code=request_code)
            .first()
        )
        if request_obj is None or request_obj.requester_id is None:
            continue

        if invoice.user_id != request_obj.requester_id:
            invoice.user_id = request_obj.requester_id
            invoice.save(update_fields=["user", "updated_at"])
            updated_invoices += 1

        attempts = list(PaymentAttempt.objects.filter(invoice=invoice).exclude(checkout_url="").order_by("-created_at"))
        latest_attempt = attempts[0] if attempts else None
        if latest_attempt is not None and hasattr(request_obj, "metadata_record"):
            payload = dict(request_obj.metadata_record.payload or {})
            safe_latest_url = extras_bundle_payment_access_url(
                request_obj=request_obj,
                invoice=invoice,
                checkout_url=latest_attempt.checkout_url,
            )
            if payload.get("checkout_url") != safe_latest_url or str(payload.get("payment_attempt_id") or "") != str(latest_attempt.id):
                payload["checkout_url"] = safe_latest_url
                payload["payment_attempt_id"] = str(latest_attempt.id)
                request_obj.metadata_record.payload = payload
                request_obj.metadata_record.save(update_fields=["payload", "updated_at"])
                updated_metadata += 1

        for attempt in attempts:
            safe_url = extras_bundle_payment_access_url(
                request_obj=request_obj,
                invoice=invoice,
                checkout_url=attempt.checkout_url,
            )

            for notification in Notification.objects.filter(url=attempt.checkout_url):
                notification.url = safe_url
                notification.save(update_fields=["url"])
                updated_notifications += 1

            for message in Message.objects.filter(body__icontains=attempt.checkout_url):
                new_body = message.body.replace(attempt.checkout_url, safe_url)
                if new_body == message.body:
                    continue
                message.body = new_body
                message.save(update_fields=["body"])
                updated_messages += 1

    print("UPDATED_INVOICES", updated_invoices)
    print("UPDATED_METADATA", updated_metadata)
    print("UPDATED_NOTIFICATIONS", updated_notifications)
    print("UPDATED_MESSAGES", updated_messages)


if __name__ == "__main__":
    main()
