from django.db import migrations, models
import django.db.models.deletion


SEPARATORS = (" - ", " — ", " – ", " | ", "|")


def _clean(value):
    return " ".join(str(value or "").split()).strip()


def _lower(value):
    return _clean(value).lower()


def _legacy_section(caption):
    text = _clean(caption)
    for separator in SEPARATORS:
        index = text.find(separator)
        if index > 0:
            return _clean(text[:index])
    return ""


def backfill_portfolio_categories(apps, schema_editor):
    ProviderPortfolioItem = apps.get_model("providers", "ProviderPortfolioItem")
    ProviderCategory = apps.get_model("providers", "ProviderCategory")

    for item in ProviderPortfolioItem.objects.filter(category__isnull=True).iterator():
        relations = list(
            ProviderCategory.objects.filter(provider_id=item.provider_id)
            .select_related("subcategory", "subcategory__category")
        )
        if not relations:
            continue

        category_by_text = {}
        for relation in relations:
            subcategory = getattr(relation, "subcategory", None)
            category = getattr(subcategory, "category", None) if subcategory else None
            if not category:
                continue
            category_by_text[_lower(category.name)] = category.id
            category_by_text[_lower(subcategory.name)] = category.id

        caption = _clean(item.caption)
        candidates = [_legacy_section(caption), caption]
        category_id = None
        for candidate in candidates:
            key = _lower(candidate)
            if key and key in category_by_text:
                category_id = category_by_text[key]
                break

        unique_category_ids = {relation.subcategory.category_id for relation in relations if getattr(relation, "subcategory", None)}
        if category_id is None and len(unique_category_ids) == 1:
            category_id = next(iter(unique_category_ids))

        if category_id:
            ProviderPortfolioItem.objects.filter(pk=item.pk, category__isnull=True).update(category_id=category_id)


class Migration(migrations.Migration):

    dependencies = [
        ("providers", "0032_visibility_blocks_role_context"),
    ]

    operations = [
        migrations.AddField(
            model_name="providerportfolioitem",
            name="category",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="portfolio_items",
                to="providers.category",
            ),
        ),
        migrations.RunPython(backfill_portfolio_categories, migrations.RunPython.noop),
    ]
