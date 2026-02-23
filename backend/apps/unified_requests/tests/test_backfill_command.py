from datetime import timedelta
from decimal import Decimal
from io import StringIO

import pytest
from django.core.management import call_command
from django.utils import timezone

from apps.accounts.models import User
from apps.extras.models import ExtraPurchase
from apps.promo.models import PromoRequest
from apps.subscriptions.models import Subscription, SubscriptionPlan, SubscriptionStatus
from apps.support.models import SupportTicket
from apps.unified_requests.models import UnifiedRequest
from apps.verification.models import VerificationRequest


pytestmark = pytest.mark.django_db


def test_backfill_unified_requests_command_populates_all_sources():
    user = User.objects.create_user(phone="0501111222", password="Pass12345!")
    now = timezone.now()

    support = SupportTicket.objects.create(requester=user, ticket_type="tech", description="legacy support")
    verify = VerificationRequest.objects.create(requester=user, badge_type="blue")
    promo = PromoRequest.objects.create(
        requester=user,
        title="legacy promo",
        ad_type="banner_home",
        start_at=now + timedelta(days=1),
        end_at=now + timedelta(days=2),
        frequency="60s",
        position="normal",
    )
    plan = SubscriptionPlan.objects.create(code="LEGACY", title="Legacy", price=Decimal("10.00"))
    sub = Subscription.objects.create(user=user, plan=plan, status=SubscriptionStatus.PENDING_PAYMENT)
    extra = ExtraPurchase.objects.create(
        user=user,
        sku="uploads_10gb_month",
        title="Legacy Extra",
        extra_type="time_based",
        subtotal=Decimal("59.00"),
        status="pending_payment",
    )

    assert UnifiedRequest.objects.count() == 0

    out = StringIO()
    call_command("backfill_unified_requests", stdout=out)
    text = out.getvalue()
    assert "processed=5" in text

    assert UnifiedRequest.objects.count() == 5

    ur_support = UnifiedRequest.objects.get(source_app="support", source_model="SupportTicket", source_object_id=str(support.id))
    ur_verify = UnifiedRequest.objects.get(source_app="verification", source_model="VerificationRequest", source_object_id=str(verify.id))
    ur_promo = UnifiedRequest.objects.get(source_app="promo", source_model="PromoRequest", source_object_id=str(promo.id))
    ur_sub = UnifiedRequest.objects.get(source_app="subscriptions", source_model="Subscription", source_object_id=str(sub.id))
    ur_extra = UnifiedRequest.objects.get(source_app="extras", source_model="ExtraPurchase", source_object_id=str(extra.id))

    assert ur_support.code.startswith("HD")
    assert ur_verify.code.startswith("AD")
    assert ur_promo.code.startswith("MD")
    assert ur_sub.code.startswith("SD")
    assert ur_extra.code.startswith("P")
