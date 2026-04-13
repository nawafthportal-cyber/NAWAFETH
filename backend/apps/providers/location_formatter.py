from __future__ import annotations

from functools import lru_cache

from .models import SaudiCity


def _clean_text(value) -> str:
    return " ".join(str(value or "").split()).strip()


def _strip_region_prefix(region_name: str) -> str:
    normalized = _clean_text(region_name)
    if normalized.startswith("المنطقة "):
        return normalized.replace("المنطقة ", "", 1).strip()
    if normalized.startswith("منطقة "):
        return normalized.replace("منطقة ", "", 1).strip()
    return normalized


@lru_cache(maxsize=256)
def _lookup_region_for_city(city_name: str) -> str:
    normalized_city = _clean_text(city_name)
    if not normalized_city:
        return ""

    city_obj = (
        SaudiCity.objects.select_related("region")
        .filter(name_ar=normalized_city, is_active=True, region__is_active=True)
        .order_by("region__sort_order", "sort_order", "id")
        .first()
    )
    if not city_obj or not getattr(city_obj, "region", None):
        return ""
    return _strip_region_prefix(getattr(city_obj.region, "name_ar", ""))


def format_city_display(city: str, *, region: str = "") -> str:
    normalized_city = _clean_text(city)
    normalized_region = _strip_region_prefix(region)

    if not normalized_city:
        return ""
    if " - " in normalized_city:
        return normalized_city
    if normalized_region:
        if normalized_city == normalized_region:
            return normalized_city
        return f"{normalized_region} - {normalized_city}"

    inferred_region = _lookup_region_for_city(normalized_city)
    if inferred_region:
        return f"{inferred_region} - {normalized_city}"
    return normalized_city
