from __future__ import annotations

from django.db import transaction as db_transaction

from apps.marketplace.models import RequestStatus, ServiceRequest

from .models import ClientRecord, LoyaltyMembership, LoyaltyProgram, LoyaltyTransaction, LoyaltyTransactionType


def award_loyalty_points_for_completed_request(service_request: ServiceRequest) -> LoyaltyTransaction | None:
    provider = getattr(service_request, "provider", None)
    client = getattr(service_request, "client", None)
    if (
        str(getattr(service_request, "status", "") or "") != RequestStatus.COMPLETED
        or provider is None
        or client is None
    ):
        return None

    program = LoyaltyProgram.objects.filter(provider=provider, is_active=True).first()
    if program is None:
        return None

    points = int(program.points_per_completed_request or 0)
    if points <= 0:
        return None

    with db_transaction.atomic():
        if LoyaltyTransaction.objects.filter(
            membership__program=program,
            request=service_request,
            transaction_type=LoyaltyTransactionType.EARN,
        ).exists():
            return None

        membership, _created = LoyaltyMembership.objects.select_for_update().get_or_create(
            program=program,
            user=client,
            defaults={"points_balance": 0, "total_earned": 0, "total_redeemed": 0},
        )
        membership.points_balance = int(membership.points_balance or 0) + points
        membership.total_earned = int(membership.total_earned or 0) + points
        membership.save(update_fields=["points_balance", "total_earned", "updated_at"])

        ClientRecord.objects.update_or_create(
            provider=provider,
            user=client,
            defaults={"loyalty_points_added": membership.points_balance},
        )

        return LoyaltyTransaction.objects.create(
            membership=membership,
            transaction_type=LoyaltyTransactionType.EARN,
            points=points,
            description="نقاط مكتسبة من طلب خدمة مكتمل",
            request=service_request,
        )
