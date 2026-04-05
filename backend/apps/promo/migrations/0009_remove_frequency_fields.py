from decimal import Decimal

from django.db import migrations


def collapse_frequency_pricing_rules(apps, schema_editor):
    PromoPricingRule = apps.get_model("promo", "PromoPricingRule")

    service_configs = {
        "featured_specialists": {
            "code": "featured_daily",
            "preferred_legacy_code": "featured_60s",
            "title": "شريط أبرز المختصين - لكل 24 ساعة",
            "sort_order": 20,
            "default_amount": Decimal("1000.00"),
        },
        "portfolio_showcase": {
            "code": "portfolio_daily",
            "preferred_legacy_code": "portfolio_60s",
            "title": "شريط البنرات والمشاريع - لكل 24 ساعة",
            "sort_order": 30,
            "default_amount": Decimal("1000.00"),
        },
        "snapshots": {
            "code": "snapshots_daily",
            "preferred_legacy_code": "snapshots_60s",
            "title": "شريط اللمحات - لكل 24 ساعة",
            "sort_order": 40,
            "default_amount": Decimal("1000.00"),
        },
    }

    for service_type, config in service_configs.items():
        service_rules = PromoPricingRule.objects.filter(service_type=service_type).order_by("sort_order", "id")

        source_rule = (
            service_rules.filter(code=config["code"]).first()
            or service_rules.filter(code=config["preferred_legacy_code"]).first()
            or service_rules.first()
        )
        amount = source_rule.amount if source_rule is not None else config["default_amount"]

        canonical_rule = service_rules.filter(code=config["code"]).first()
        if canonical_rule is None:
            canonical_rule = PromoPricingRule.objects.create(
                code=config["code"],
                service_type=service_type,
                title=config["title"],
                unit="day",
                frequency="",
                search_position="",
                message_channel="",
                amount=amount,
                is_active=True,
                sort_order=config["sort_order"],
            )
        else:
            canonical_rule.title = config["title"]
            canonical_rule.unit = "day"
            canonical_rule.frequency = ""
            canonical_rule.search_position = ""
            canonical_rule.message_channel = ""
            canonical_rule.amount = amount
            canonical_rule.sort_order = config["sort_order"]
            canonical_rule.save(
                update_fields=[
                    "title",
                    "unit",
                    "frequency",
                    "search_position",
                    "message_channel",
                    "amount",
                    "sort_order",
                    "updated_at",
                ]
            )

        PromoPricingRule.objects.filter(service_type=service_type).exclude(id=canonical_rule.id).delete()


def noop_reverse(apps, schema_editor):
    pass


class Migration(migrations.Migration):

    dependencies = [
        ("promo", "0008_promorequest_home_banner_scales"),
    ]

    operations = [
        migrations.RunPython(collapse_frequency_pricing_rules, noop_reverse),
        migrations.RemoveField(
            model_name="promorequest",
            name="frequency",
        ),
        migrations.RemoveField(
            model_name="promorequestitem",
            name="frequency",
        ),
        migrations.RemoveField(
            model_name="promopricingrule",
            name="frequency",
        ),
    ]
