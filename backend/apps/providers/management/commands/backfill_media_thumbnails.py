from __future__ import annotations

from django.core.management.base import BaseCommand

from apps.providers.media_thumbnails import ensure_media_thumbnail
from apps.providers.models import ProviderPortfolioItem, ProviderSpotlightItem


class Command(BaseCommand):
    help = (
        "Generate missing thumbnails for provider portfolio/spotlight items. "
        "Use --force to regenerate even when a thumbnail exists."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--force",
            action="store_true",
            help="Regenerate thumbnail even if thumbnail field already has a stored file.",
        )
        parser.add_argument(
            "--limit",
            type=int,
            default=0,
            help="Maximum items to process per model (0 means no limit).",
        )

    def _process_queryset(self, *, label: str, queryset, force: bool, limit: int) -> tuple[int, int, int]:
        total = 0
        generated = 0
        failed = 0
        qs = queryset
        if limit and limit > 0:
            qs = qs[:limit]
        for item in qs.iterator():
            total += 1
            ok = ensure_media_thumbnail(item, force=force)
            if ok:
                generated += 1
            else:
                failed += 1
        self.stdout.write(
            f"{label}: processed={total} generated={generated} skipped_or_failed={failed}"
        )
        return total, generated, failed

    def handle(self, *args, **options):
        force = bool(options.get("force"))
        limit = int(options.get("limit") or 0)

        portfolio_qs = ProviderPortfolioItem.objects.all().order_by("id")
        spotlight_qs = ProviderSpotlightItem.objects.all().order_by("id")

        if not force:
            portfolio_qs = portfolio_qs.filter(thumbnail__isnull=True)
            spotlight_qs = spotlight_qs.filter(thumbnail__isnull=True)

        t1, g1, f1 = self._process_queryset(
            label="portfolio",
            queryset=portfolio_qs,
            force=force,
            limit=limit,
        )
        t2, g2, f2 = self._process_queryset(
            label="spotlight",
            queryset=spotlight_qs,
            force=force,
            limit=limit,
        )

        total = t1 + t2
        generated = g1 + g2
        failed = f1 + f2
        self.stdout.write(
            self.style.SUCCESS(
                f"Done: processed={total} generated={generated} skipped_or_failed={failed}"
            )
        )
