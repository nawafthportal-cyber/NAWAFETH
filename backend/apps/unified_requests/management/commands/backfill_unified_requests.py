from __future__ import annotations

from django.core.management.base import BaseCommand


class Command(BaseCommand):
    help = "Backfill unified request records from existing support/verification/promo/subscriptions/extras data."

    def handle(self, *args, **options):
        from apps.unified_requests.models import UnifiedRequest
        from apps.support.models import SupportTicket
        from apps.support.services import _sync_ticket_to_unified
        from apps.verification.models import VerificationRequest
        from apps.verification.services import _sync_verification_to_unified
        from apps.promo.models import PromoRequest
        from apps.promo.services import _sync_promo_to_unified
        from apps.subscriptions.models import Subscription
        from apps.subscriptions.services import _sync_subscription_to_unified
        from apps.extras.models import ExtraPurchase
        from apps.extras.services import _sync_extra_to_unified

        stats: dict[str, int] = {
            "support": 0,
            "verification": 0,
            "promo": 0,
            "subscriptions": 0,
            "extras": 0,
            "created": 0,
            "updated": 0,
        }

        def _count_before(source_app: str, source_model: str, obj_id) -> bool:
            return UnifiedRequest.objects.filter(
                source_app=source_app,
                source_model=source_model,
                source_object_id=str(obj_id),
            ).exists()

        for t in SupportTicket.objects.select_related("requester", "assigned_team", "assigned_to").all().iterator():
            existed = _count_before("support", "SupportTicket", t.id)
            _sync_ticket_to_unified(ticket=t, changed_by=t.last_action_by)
            stats["support"] += 1
            stats["updated" if existed else "created"] += 1

        for vr in VerificationRequest.objects.select_related("requester", "assigned_to", "invoice").all().iterator():
            existed = _count_before("verification", "VerificationRequest", vr.id)
            _sync_verification_to_unified(vr=vr, changed_by=vr.assigned_to or vr.requester)
            stats["verification"] += 1
            stats["updated" if existed else "created"] += 1

        for pr in PromoRequest.objects.select_related("requester", "assigned_to", "invoice").all().iterator():
            existed = _count_before("promo", "PromoRequest", pr.id)
            _sync_promo_to_unified(pr=pr, changed_by=pr.assigned_to or pr.requester)
            stats["promo"] += 1
            stats["updated" if existed else "created"] += 1

        for sub in Subscription.objects.select_related("user", "plan", "invoice").all().iterator():
            existed = _count_before("subscriptions", "Subscription", sub.id)
            _sync_subscription_to_unified(sub=sub, changed_by=sub.user)
            stats["subscriptions"] += 1
            stats["updated" if existed else "created"] += 1

        for p in ExtraPurchase.objects.select_related("user", "invoice").all().iterator():
            existed = _count_before("extras", "ExtraPurchase", p.id)
            _sync_extra_to_unified(purchase=p, changed_by=p.user)
            stats["extras"] += 1
            stats["updated" if existed else "created"] += 1

        total = stats["support"] + stats["verification"] + stats["promo"] + stats["subscriptions"] + stats["extras"]
        self.stdout.write(
            self.style.SUCCESS(
                f"Backfill unified requests done. processed={total} created={stats['created']} updated={stats['updated']}"
            )
        )
        self.stdout.write(
            f"support={stats['support']} verification={stats['verification']} promo={stats['promo']} "
            f"subscriptions={stats['subscriptions']} extras={stats['extras']}"
        )
