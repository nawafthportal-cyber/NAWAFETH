from __future__ import annotations

from functools import lru_cache

from .models import SaudiCity

CITY_SCOPE_SEPARATOR = " - "


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


def split_city_scope(value: str) -> tuple[str, str]:
    normalized = _clean_text(value)
    if not normalized:
        return "", ""
    if CITY_SCOPE_SEPARATOR not in normalized:
        return "", normalized

    region_part, city_part = normalized.split(CITY_SCOPE_SEPARATOR, 1)
    return _strip_region_prefix(region_part), _clean_text(city_part)


def build_location_label(country: str, city: str = "") -> str:
        country_part = _clean_text(country)
        city_part = _clean_text(city)
        if country_part and city_part:
            return f"{country_part}{CITY_SCOPE_SEPARATOR}{city_part}"
        return country_part or city_part


def split_location_label(value: str) -> tuple[str, str]:
        country_part, city_part = split_city_scope(value)
        return _clean_text(country_part), _clean_text(city_part)


def resolve_country_city(country: str = "", city: str = "", location_label: str = "") -> tuple[str, str, str]:
    normalized_country = _clean_text(country)
    normalized_city = _clean_text(city)
    normalized_label = _clean_text(location_label)

    if normalized_label:
        label_country, label_city = split_location_label(normalized_label)
        if label_country and not normalized_country:
            normalized_country = label_country
        if label_city and not normalized_city:
            normalized_city = label_city

    if normalized_city and CITY_SCOPE_SEPARATOR in normalized_city:
        label_country, label_city = split_location_label(normalized_city)
        if label_country and not normalized_country:
            normalized_country = label_country
        if label_city:
            normalized_city = label_city

    resolved_label = build_location_label(normalized_country, normalized_city)
    return normalized_country, normalized_city, resolved_label


def normalize_city_scope(city: str, *, region: str = "") -> str:
    normalized_region = _strip_region_prefix(region)
    scope_region, scope_city = split_city_scope(city)
    city_part = scope_city or _clean_text(city)
    region_part = normalized_region or scope_region
    if not city_part:
        return ""
    return format_city_display(city_part, region=region_part)


def city_matches_scope(request_city: str, *, provider_city: str, provider_region: str = "") -> bool:
    request_region, request_city_name = split_city_scope(normalize_city_scope(request_city))
    provider_region_name, provider_city_name = split_city_scope(
        normalize_city_scope(provider_city, region=provider_region)
    )

    if not request_city_name:
        return True
    if not provider_city_name:
        return False
    if request_city_name != provider_city_name:
        return False
    if request_region and provider_region_name and request_region != provider_region_name:
        return False
    return True


def provider_city_query_values(provider_city: str, *, provider_region: str = "") -> list[str]:
    values: list[str] = []
    normalized_scope = normalize_city_scope(provider_city, region=provider_region)
    _, city_only = split_city_scope(normalized_scope)

    for value in (normalized_scope, city_only):
        cleaned = _clean_text(value)
        if cleaned and cleaned not in values:
            values.append(cleaned)
    return values


def format_city_display(city: str, *, region: str = "") -> str:
    normalized_city = _clean_text(city)
    normalized_region = _strip_region_prefix(region)

    if not normalized_city:
        return ""
    if CITY_SCOPE_SEPARATOR in normalized_city:
        scope_region, scope_city = split_city_scope(normalized_city)
        if not scope_city:
            return ""
        if scope_region:
            return f"{scope_region}{CITY_SCOPE_SEPARATOR}{scope_city}"
        return scope_city
    if normalized_region:
        if normalized_city == normalized_region:
            return normalized_city
        return f"{normalized_region}{CITY_SCOPE_SEPARATOR}{normalized_city}"

    inferred_region = _lookup_region_for_city(normalized_city)
    if inferred_region:
        return f"{inferred_region}{CITY_SCOPE_SEPARATOR}{normalized_city}"
    return normalized_city
