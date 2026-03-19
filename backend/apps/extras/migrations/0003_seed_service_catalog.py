"""
Seed ServiceCatalog from existing EXTRA_SKUS hardcoded values.
"""
from django.db import migrations


SEED_DATA = [
    {"sku": "uploads_10gb_month", "title": "زيادة سعة مرفقات 10GB (شهري)", "price": "59.00", "sort_order": 1},
    {"sku": "uploads_50gb_month", "title": "زيادة سعة مرفقات 50GB (شهري)", "price": "199.00", "sort_order": 2},
    {"sku": "vip_support_month", "title": "دعم VIP (شهري)", "price": "149.00", "sort_order": 3},
    {"sku": "promo_boost_7d", "title": "Boost إعلان 7 أيام", "price": "99.00", "sort_order": 4},
    {"sku": "tickets_100", "title": "رصيد 100 تذكرة دعم", "price": "79.00", "sort_order": 5},
]


def seed_catalog(apps, schema_editor):
    ServiceCatalog = apps.get_model("extras", "ServiceCatalog")
    for item in SEED_DATA:
        ServiceCatalog.objects.update_or_create(
            sku=item["sku"],
            defaults={
                "title": item["title"],
                "price": item["price"],
                "sort_order": item["sort_order"],
                "is_active": True,
            },
        )


def unseed_catalog(apps, schema_editor):
    ServiceCatalog = apps.get_model("extras", "ServiceCatalog")
    ServiceCatalog.objects.filter(sku__in=[d["sku"] for d in SEED_DATA]).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("extras", "0002_add_service_catalog"),
    ]

    operations = [
        migrations.RunPython(seed_catalog, unseed_catalog),
    ]
