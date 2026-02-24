from __future__ import annotations

from dataclasses import dataclass

from django.core.management.base import BaseCommand
from django.db import transaction
from django.db.models import Count, Min

from apps.providers.models import ProviderFollow, ProviderLike, ProviderPortfolioLike


@dataclass
class CleanupSpec:
    label: str
    model: type
    group_fields: tuple[str, str]


class Command(BaseCommand):
    help = (
        "Clean duplicate provider relation rows (follows, likes, portfolio likes) "
        "with a unified report. Dry-run by default."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--apply",
            action="store_true",
            help="Apply deletions. Without this flag, command runs in dry-run mode.",
        )

    def handle(self, *args, **options):
        apply_changes = bool(options.get("apply"))
        mode = "APPLY" if apply_changes else "DRY-RUN"

        specs = [
            CleanupSpec("ProviderFollow", ProviderFollow, ("user_id", "provider_id")),
            CleanupSpec("ProviderLike", ProviderLike, ("user_id", "provider_id")),
            CleanupSpec("ProviderPortfolioLike", ProviderPortfolioLike, ("user_id", "item_id")),
        ]

        total_groups = 0
        total_rows_to_delete = 0
        total_deleted = 0

        self.stdout.write(f"[{mode}] Starting unified duplicate cleanup report")

        for spec in specs:
            groups, rows_to_delete = self._scan_duplicates(spec)
            total_groups += len(groups)
            total_rows_to_delete += rows_to_delete

            self.stdout.write(
                f"\n[{spec.label}] groups={len(groups)} duplicate_rows={rows_to_delete}"
            )

            if groups:
                self._print_preview(spec, groups)

            if apply_changes and groups:
                deleted = self._apply_cleanup(spec, groups)
                total_deleted += deleted
                self.stdout.write(self.style.SUCCESS(f"[{spec.label}] deleted_rows={deleted}"))
            elif not apply_changes:
                self.stdout.write(f"[{spec.label}] dry-run only")

        self.stdout.write("\n=== Unified Summary ===")
        self.stdout.write(f"mode: {mode}")
        self.stdout.write(f"duplicate_groups: {total_groups}")
        self.stdout.write(f"duplicate_rows_to_delete: {total_rows_to_delete}")
        if apply_changes:
            self.stdout.write(self.style.SUCCESS(f"deleted_rows: {total_deleted}"))
        else:
            self.stdout.write(self.style.WARNING("No rows deleted (dry-run). Use --apply to execute."))

    def _scan_duplicates(self, spec: CleanupSpec):
        a, b = spec.group_fields
        groups = list(
            spec.model.objects.values(a, b)
            .annotate(row_count=Count("id"), keep_id=Min("id"))
            .filter(row_count__gt=1)
            .order_by(a, b)
        )
        rows_to_delete = sum(int(row["row_count"]) - 1 for row in groups)
        return groups, rows_to_delete

    def _print_preview(self, spec: CleanupSpec, groups: list[dict]):
        a, b = spec.group_fields
        preview_limit = 10
        for row in groups[:preview_limit]:
            self.stdout.write(
                f" - {a}={row[a]} {b}={row[b]} count={row['row_count']} keep_id={row['keep_id']}"
            )
        if len(groups) > preview_limit:
            self.stdout.write(f" ... and {len(groups) - preview_limit} more groups")

    def _apply_cleanup(self, spec: CleanupSpec, groups: list[dict]) -> int:
        a, b = spec.group_fields
        deleted_total = 0
        with transaction.atomic():
            for row in groups:
                deleted_count, _ = (
                    spec.model.objects.filter(**{a: row[a], b: row[b]})
                    .exclude(id=row["keep_id"])
                    .delete()
                )
                deleted_total += deleted_count
        return deleted_total

