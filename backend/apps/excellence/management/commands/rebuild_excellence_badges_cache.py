from django.core.management.base import BaseCommand

from apps.excellence.services import rebuild_excellence_badges_cache


class Command(BaseCommand):
    help = "Rebuild excellence badges cache from the source-of-truth tables"

    def add_arguments(self, parser):
        parser.add_argument("--provider-id", type=int, dest="provider_id")
        parser.add_argument("--limit", type=int, dest="limit")
        parser.add_argument("--batch-size", type=int, dest="batch_size", default=500)

    def handle(self, *args, **options):
        provider_id = options.get("provider_id")
        limit = options.get("limit")
        batch_size = options.get("batch_size") or 500

        result = rebuild_excellence_badges_cache(
            provider_id=provider_id,
            limit=limit,
            batch_size=batch_size,
        )
        self.stdout.write(
            self.style.SUCCESS(
                "Excellence badges cache rebuilt: "
                f"processed={result['processed']} updated={result['updated']} errors={result['errors']}"
            )
        )