from django.core.management.base import BaseCommand

from apps.subscriptions.services import backfill_provider_basic_entitlements


class Command(BaseCommand):
    help = "Create missing free Basic entitlements for provider accounts."

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Report what would be created without writing rows.",
        )

    def handle(self, *args, **options):
        dry_run = bool(options.get("dry_run"))
        summary = backfill_provider_basic_entitlements(dry_run=dry_run)
        prefix = "DRY RUN " if dry_run else ""
        self.stdout.write(
            self.style.SUCCESS(
                f"{prefix}providers={summary['providers']} created={summary['created']} "
                f"existing_basic={summary['existing_basic']} current_non_basic={summary['current_non_basic']} "
                f"errors={summary['errors']}"
            )
        )
