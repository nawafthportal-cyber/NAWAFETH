from django.db import migrations


REGION_CITY_MAP = {
    "منطقة الرياض": [
        "الرياض",
        "الخرج",
        "الدوادمي",
        "المجمعة",
        "القويعية",
        "وادي الدواسر",
        "الأفلاج",
        "الحريق",
        "الحوطة",
        "الدرعية",
        "الدلم",
        "الزلفي",
        "السليل",
        "المزاحمية",
        "ثادق",
        "حوطة بني تميم",
        "ضرما",
        "شقراء",
        "عفيف",
    ],
    "منطقة مكة المكرمة": [
        "مكة المكرمة",
        "جدة",
        "الطائف",
        "العرضيات",
        "القنفذة",
        "الليث",
        "الجموم",
        "رابغ",
        "رنية",
        "تربة",
        "ظلم",
    ],
    "منطقة المدينة المنورة": [
        "المدينة المنورة",
        "العلا",
        "بدر",
        "خيبر",
        "ينبع",
    ],
    "المنطقة الشرقية": [
        "الدمام",
        "الخبر",
        "الظهران",
        "الجبيل",
        "حفر الباطن",
        "القطيف",
        "الأحساء",
        "الخفجي",
    ],
    "منطقة القصيم": [
        "بريدة",
        "عنيزة",
        "الرس",
        "المذنب",
        "البكيرية",
        "البدائع",
        "القصيم",
    ],
    "منطقة عسير": [
        "أبها",
        "خميس مشيط",
        "بيشة",
        "تنومة",
        "سراة عبيدة",
        "محايل عسير",
        "النماص",
    ],
    "منطقة تبوك": [
        "تبوك",
        "الوجه",
        "أملج",
        "حقل",
        "ضباء",
    ],
    "منطقة حائل": [
        "حائل",
    ],
    "منطقة الحدود الشمالية": [
        "عرعر",
        "رفحاء",
        "طريف",
    ],
    "منطقة جازان": [
        "جازان",
        "صامطة",
        "صبيا",
    ],
    "منطقة نجران": [
        "نجران",
        "شرورة",
    ],
    "منطقة الباحة": [
        "الباحة",
        "بلجرشي",
    ],
    "منطقة الجوف": [
        "سكاكا",
        "القريات",
        "طبرجل",
    ],
}


def seed_region_city_catalog(apps, schema_editor):
    SaudiRegion = apps.get_model("providers", "SaudiRegion")
    SaudiCity = apps.get_model("providers", "SaudiCity")
    ProviderProfile = apps.get_model("providers", "ProviderProfile")

    city_to_region = {}

    for region_order, (region_name, city_names) in enumerate(REGION_CITY_MAP.items(), start=1):
        region, _ = SaudiRegion.objects.update_or_create(
            name_ar=region_name,
            defaults={"is_active": True, "sort_order": region_order},
        )

        for city_order, city_name in enumerate(city_names, start=1):
            SaudiCity.objects.update_or_create(
                region=region,
                name_ar=city_name,
                defaults={"is_active": True, "sort_order": city_order},
            )
            city_to_region.setdefault(city_name, set()).add(region_name)

    for profile in ProviderProfile.objects.filter(region="", city__isnull=False).exclude(city=""):
        regions = city_to_region.get(profile.city, set())
        if len(regions) == 1:
            profile.region = list(regions)[0]
            profile.save(update_fields=["region", "updated_at"])


def unseed_region_city_catalog(apps, schema_editor):
    SaudiRegion = apps.get_model("providers", "SaudiRegion")
    SaudiCity = apps.get_model("providers", "SaudiCity")

    SaudiCity.objects.filter(name_ar__in=[city for cities in REGION_CITY_MAP.values() for city in cities]).delete()
    SaudiRegion.objects.filter(name_ar__in=list(REGION_CITY_MAP.keys())).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("providers", "0018_saudiregion_providerprofile_region_saudicity"),
    ]

    operations = [
        migrations.RunPython(seed_region_city_catalog, unseed_region_city_catalog),
    ]
