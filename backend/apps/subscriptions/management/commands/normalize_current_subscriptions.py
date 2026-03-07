from django.core.management.base import BaseCommand

from apps.subscriptions.services import normalize_current_subscriptions


class Command(BaseCommand):
    help = "Normalize overlapping current subscriptions so each user has one current row."

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Report overlaps without writing changes.",
        )

    def handle(self, *args, **options):
        dry_run = bool(options.get("dry_run"))
        summary = normalize_current_subscriptions(dry_run=dry_run)
        prefix = "DRY RUN " if dry_run else ""
        self.stdout.write(
            self.style.SUCCESS(
                f"{prefix}users={summary['users']} normalized_users={summary['normalized_users']} "
                f"cancelled_rows={summary['cancelled_rows']} errors={summary['errors']}"
            )
        )
