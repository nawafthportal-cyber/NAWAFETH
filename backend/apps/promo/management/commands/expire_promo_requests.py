from __future__ import annotations

from django.core.management.base import BaseCommand

from apps.promo.services import expire_due_promos


class Command(BaseCommand):
    help = "Expire active promo requests whose end_at has passed."

    def handle(self, *args, **options):
        count = expire_due_promos()
        self.stdout.write(self.style.SUCCESS(f"Expired promo requests: {count}"))
