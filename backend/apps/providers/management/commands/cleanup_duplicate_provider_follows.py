from __future__ import annotations

from django.core.management.base import BaseCommand
from django.db import transaction
from django.db.models import Count, Min

from apps.providers.models import ProviderFollow


class Command(BaseCommand):
    help = "Clean duplicate ProviderFollow rows, keeping the oldest row per (user, provider)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--apply",
            action="store_true",
            help="Apply deletions. Without this flag, command runs in dry-run mode.",
        )

    def handle(self, *args, **options):
        apply_changes = bool(options.get("apply"))

        duplicate_groups = list(
            ProviderFollow.objects.values("user_id", "provider_id")
            .annotate(row_count=Count("id"), keep_id=Min("id"))
            .filter(row_count__gt=1)
            .order_by("user_id", "provider_id")
        )

        duplicate_rows_total = 0
        for row in duplicate_groups:
            duplicate_rows_total += int(row["row_count"]) - 1

        mode = "APPLY" if apply_changes else "DRY-RUN"
        self.stdout.write(
            f"[{mode}] duplicate groups: {len(duplicate_groups)}, duplicate rows to delete: {duplicate_rows_total}"
        )

        if not duplicate_groups:
            self.stdout.write(self.style.SUCCESS("No duplicate ProviderFollow rows found."))
            return

        preview_limit = 10
        for row in duplicate_groups[:preview_limit]:
            self.stdout.write(
                f" - user={row['user_id']} provider={row['provider_id']} count={row['row_count']} keep_id={row['keep_id']}"
            )
        if len(duplicate_groups) > preview_limit:
            self.stdout.write(f" ... and {len(duplicate_groups) - preview_limit} more groups")

        if not apply_changes:
            self.stdout.write(
                self.style.WARNING("Dry-run only. Re-run with --apply to delete duplicates.")
            )
            return

        deleted_total = 0
        with transaction.atomic():
            for row in duplicate_groups:
                deleted_count, _ = (
                    ProviderFollow.objects.filter(
                        user_id=row["user_id"],
                        provider_id=row["provider_id"],
                    )
                    .exclude(id=row["keep_id"])
                    .delete()
                )
                deleted_total += deleted_count

        self.stdout.write(
            self.style.SUCCESS(
                f"Deleted {deleted_total} duplicate ProviderFollow row(s) across {len(duplicate_groups)} group(s)."
            )
        )

