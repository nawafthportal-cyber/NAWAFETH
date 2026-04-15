from __future__ import annotations

from django.core.management.base import BaseCommand
from django.utils import timezone

from ...services import process_due_scheduled_messages


class Command(BaseCommand):
    help = "Send due scheduled extras portal messages (bulk messaging)."

    def handle(self, *args, **options):
        result = process_due_scheduled_messages(now=timezone.now())
        if result["due"] == 0:
            self.stdout.write("No due messages")
            return

        self.stdout.write(f"Processed {result['due']} due message(s)")
        self.stdout.write(f"Sent={result['sent']} Failed={result['failed']} Cancelled={result['cancelled']}")
