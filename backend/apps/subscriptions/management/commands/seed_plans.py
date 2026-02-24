from django.core.management.base import BaseCommand

from apps.subscriptions.bootstrap import seed_default_subscription_plans


class Command(BaseCommand):
    help = "Seed default subscription plans"

    def handle(self, *args, **options):
        count = seed_default_subscription_plans(force_update=True)
        self.stdout.write(self.style.SUCCESS(f"✅ Plans seeded successfully ({count})"))
