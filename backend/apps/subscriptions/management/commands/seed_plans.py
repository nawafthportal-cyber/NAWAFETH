from django.core.management.base import BaseCommand

from apps.subscriptions.bootstrap import seed_default_subscription_plans


class Command(BaseCommand):
    help = "Seed default subscription plans"

    def add_arguments(self, parser):
        parser.add_argument(
            "--force-update",
            action="store_true",
            help="Overwrite the current canonical plan values with the bootstrap snapshot.",
        )

    def handle(self, *args, **options):
        count = seed_default_subscription_plans(force_update=bool(options.get("force_update")))
        self.stdout.write(self.style.SUCCESS(f"✅ Plans seeded successfully ({count})"))
