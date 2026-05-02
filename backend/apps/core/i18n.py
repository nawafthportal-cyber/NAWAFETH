from __future__ import annotations

from django.utils.translation import get_language


def normalize_language_code(value: str | None) -> str:
    code = str(value or "").strip().lower()
    if code.startswith("en"):
        return "en"
    return "ar"


def get_request_language(request=None) -> str:
    if request is not None:
        direct_language = getattr(request, "LANGUAGE_CODE", None)
        if direct_language:
            return normalize_language_code(direct_language)
        wrapped_request = getattr(request, "_request", None)
        wrapped_language = getattr(wrapped_request, "LANGUAGE_CODE", None)
        if wrapped_language:
            return normalize_language_code(wrapped_language)
    return normalize_language_code(get_language())


def localized_model_field(obj, field_name: str, *, request=None, lang: str | None = None) -> str:
    active_lang = normalize_language_code(lang or get_request_language(request))
    primary_value = getattr(obj, f"{field_name}_{active_lang}", "") or ""
    if primary_value:
        return primary_value
    fallback_value = getattr(obj, f"{field_name}_ar", "") or ""
    if fallback_value:
        return fallback_value
    return getattr(obj, field_name, "") or ""