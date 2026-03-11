from django.core.management.base import BaseCommand

from apps.promo.services import send_due_promo_messages


class Command(BaseCommand):
    help = "Send due promotional message items."

    def handle(self, *args, **options):
        count = send_due_promo_messages()
        self.stdout.write(f"Delivered {count} promotional message campaign(s).")
