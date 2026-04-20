from __future__ import annotations

from django.core.management.base import BaseCommand
from django.utils import timezone

from ...services import process_due_client_reminders


class Command(BaseCommand):
    help = "Fire due client reminders for extras portal providers."

    def handle(self, *args, **options):
        result = process_due_client_reminders(now=timezone.now())
        if result["due"] == 0:
            self.stdout.write("No due reminders")
            return

        self.stdout.write(f"Processed {result['due']} due reminder(s)")
        self.stdout.write(f"Fired={result['fired']} Skipped={result['skipped']} Errored={result['errored']}")
