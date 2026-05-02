from __future__ import annotations

import logging

from django.conf import settings
from django.core.cache import cache
from django.db import DatabaseError
from django.utils.html import strip_tags

from apps.core.db_outage import mark_database_outage

from .models import SiteContentBlock, SiteLegalDocument, SiteLinks


logger = logging.getLogger(__name__)
_CACHE_VERSION = "v2"
_TEMPLATE_CACHE_KEY = f"content:{_CACHE_VERSION}:template_site_payload"
_PUBLIC_CACHE_KEY = f"content:{_CACHE_VERSION}:public_content_payload"


def sanitize_text(value: str) -> str:
    cleaned = strip_tags((value or "").replace("\x00", ""))
    return " ".join(cleaned.split())


def sanitize_multiline_text(value: str) -> str:
    cleaned = strip_tags((value or "").replace("\x00", ""))
    normalized = cleaned.replace("\r\n", "\n").replace("\r", "\n")
    lines = [" ".join(line.split()) for line in normalized.split("\n")]
    return "\n".join(lines).strip()


DEFAULT_TOPBAR_BRAND_TITLE = "نوافــذ"
DEFAULT_TOPBAR_BRAND_SUBTITLE = "المنصة الرقمية للخدمات"
DEFAULT_FOOTER_BRAND_TITLE = "نوافــذ"
DEFAULT_FOOTER_BRAND_DESCRIPTION = "منصة تجمعك بالمختصين والعروض والخدمات في تجربة أوضح وأسرع على الويب."
DEFAULT_FOOTER_COPYRIGHT = "جميع الحقوق محفوظة لمنصة نوافــذ"
DEFAULT_TOPBAR_BRAND_TITLE_EN = "Nawafeth"
DEFAULT_TOPBAR_BRAND_SUBTITLE_EN = "Digital Services Platform"
DEFAULT_FOOTER_BRAND_TITLE_EN = "Nawafeth"
DEFAULT_FOOTER_BRAND_DESCRIPTION_EN = "A platform that brings you specialists, offers, and services in a clearer and faster web experience."
DEFAULT_FOOTER_COPYRIGHT_EN = "All rights reserved to Nawafeth Platform"


def default_site_links_payload() -> dict[str, str]:
    return {
        "x_url": "",
        "instagram_url": "",
        "snapchat_url": "",
        "tiktok_url": "",
        "youtube_url": "",
        "whatsapp_url": "",
        "email": "",
        "android_store": "",
        "ios_store": "",
        "website_url": "",
    }


def _social_links_payload(links: dict[str, str]) -> list[dict[str, str]]:
    social_links = [
        {"key": "x", "label": "X", "url": links["x_url"]},
        {"key": "instagram", "label": "Instagram", "url": links["instagram_url"]},
        {"key": "snapchat", "label": "Snapchat", "url": links["snapchat_url"]},
        {"key": "tiktok", "label": "TikTok", "url": links["tiktok_url"]},
        {"key": "youtube", "label": "YouTube", "url": links["youtube_url"]},
        {"key": "whatsapp", "label": "WhatsApp", "url": links["whatsapp_url"]},
        {"key": "email", "label": "Email", "url": f"mailto:{links['email']}" if links["email"] else ""},
    ]
    return [item for item in social_links if item["url"]]


def _store_links_payload(links: dict[str, str]) -> list[dict[str, str]]:
    store_links = [
        {"key": "android", "label": "Google Play", "url": links["android_store"]},
        {"key": "ios", "label": "App Store", "url": links["ios_store"]},
    ]
    return [item for item in store_links if item["url"]]


def _log_public_content_fallback(exc: Exception | None = None) -> None:
    mark_database_outage(reason="content.public_payload", exc=exc)
    logger.warning(
        "Site public content unavailable; using default payloads instead. error=%s",
        str(exc)[:220] if exc else "-",
    )


def _template_payload_cache_ttl() -> int:
    return max(30, int(getattr(settings, "SITE_TEMPLATE_PAYLOAD_CACHE_TTL", 300) or 300))


def _public_payload_cache_ttl() -> int:
    return max(30, int(getattr(settings, "SITE_PUBLIC_PAYLOAD_CACHE_TTL", 300) or 300))


def invalidate_public_content_cache() -> None:
    try:
        cache.delete_many([_TEMPLATE_CACHE_KEY, _PUBLIC_CACHE_KEY])
    except Exception:
        pass


def _block_payloads() -> dict[str, dict]:
    blocks_qs = SiteContentBlock.objects.filter(is_active=True).order_by("key")
    return {
        b.key: {
            "title_ar": b.title_ar,
            "body_ar": b.body_ar,
            "media_url": b.media_file.url if b.media_file else "",
            "media_type": b.media_type,
            "has_media": bool(b.media_file),
            "updated_at": b.updated_at.isoformat(),
        }
        for b in blocks_qs
    }


def _latest_legal_documents() -> dict[str, dict]:
    active_docs = SiteLegalDocument.objects.filter(is_active=True).order_by("doc_type", "-published_at", "-id")
    docs_by_type: dict[str, SiteLegalDocument] = {}
    for doc in active_docs:
        if doc.doc_type in docs_by_type:
            continue
        docs_by_type[doc.doc_type] = doc

    docs: dict[str, dict] = {}
    for doc_type, label in SiteLegalDocument._meta.get_field("doc_type").choices:
        doc = docs_by_type.get(doc_type)
        if doc is None:
            continue
        docs[doc_type] = {
            "doc_type": doc.doc_type,
            "label_ar": label,
            "version": doc.version,
            "published_at": doc.published_at.isoformat() if doc.published_at else None,
            "body_ar": doc.body_ar,
            "file_url": doc.file.url if doc.file else "",
            "has_body": bool((doc.body_ar or "").strip()),
            "has_file": bool(doc.file),
        }
    return docs


def _site_links_payload() -> dict[str, str]:
    links = SiteLinks.load()
    return {
        "x_url": links.x_url,
        "instagram_url": links.instagram_url,
        "snapchat_url": links.snapchat_url,
        "tiktok_url": links.tiktok_url,
        "youtube_url": links.youtube_url,
        "whatsapp_url": links.whatsapp_url,
        "email": links.email,
        "android_store": links.android_store,
        "ios_store": links.ios_store,
        "website_url": links.website_url,
    }


def _resolve_bilingual_text(raw_value: str, *, default_ar: str, default_en: str) -> tuple[str, str]:
    cleaned = sanitize_text(raw_value)
    if cleaned:
      return cleaned, cleaned
    return default_ar, default_en


def public_branding_payload(blocks: dict[str, dict] | None = None) -> dict[str, object]:
    blocks = blocks if isinstance(blocks, dict) else _block_payloads()
    logo = blocks.get("topbar_brand_logo") or {}
    topbar_title, topbar_title_en = _resolve_bilingual_text(
        (blocks.get("topbar_brand_title") or {}).get("title_ar") or "",
        default_ar=DEFAULT_TOPBAR_BRAND_TITLE,
        default_en=DEFAULT_TOPBAR_BRAND_TITLE_EN,
    )
    topbar_subtitle, topbar_subtitle_en = _resolve_bilingual_text(
        (blocks.get("topbar_brand_subtitle") or {}).get("title_ar") or "",
        default_ar=DEFAULT_TOPBAR_BRAND_SUBTITLE,
        default_en=DEFAULT_TOPBAR_BRAND_SUBTITLE_EN,
    )
    footer_title, footer_title_en = _resolve_bilingual_text(
        (blocks.get("footer_brand_title") or {}).get("title_ar") or "",
        default_ar=DEFAULT_FOOTER_BRAND_TITLE,
        default_en=DEFAULT_FOOTER_BRAND_TITLE_EN,
    )
    footer_description, footer_description_en = _resolve_bilingual_text(
        (blocks.get("footer_brand_description") or {}).get("body_ar")
        or (blocks.get("footer_brand_description") or {}).get("title_ar")
        or "",
        default_ar=DEFAULT_FOOTER_BRAND_DESCRIPTION,
        default_en=DEFAULT_FOOTER_BRAND_DESCRIPTION_EN,
    )
    footer_copyright, footer_copyright_en = _resolve_bilingual_text(
        (blocks.get("footer_copyright") or {}).get("title_ar")
        or (blocks.get("footer_copyright") or {}).get("body_ar")
        or "",
        default_ar=DEFAULT_FOOTER_COPYRIGHT,
        default_en=DEFAULT_FOOTER_COPYRIGHT_EN,
    )
    logo_alt, logo_alt_en = _resolve_bilingual_text(
        logo.get("title_ar") or "",
        default_ar=DEFAULT_TOPBAR_BRAND_TITLE,
        default_en=DEFAULT_TOPBAR_BRAND_TITLE_EN,
    )
    return {
        "topbar_title": topbar_title,
        "topbar_title_en": topbar_title_en,
        "topbar_subtitle": topbar_subtitle,
        "topbar_subtitle_en": topbar_subtitle_en,
        "footer_title": footer_title,
        "footer_title_en": footer_title_en,
        "footer_description": footer_description,
        "footer_description_en": footer_description_en,
        "footer_copyright": footer_copyright,
        "footer_copyright_en": footer_copyright_en,
        "logo_url": logo.get("media_url") or "",
        "logo_alt": logo_alt,
        "logo_alt_en": logo_alt_en,
    }


def template_site_payload() -> dict[str, object]:
    cached = cache.get(_TEMPLATE_CACHE_KEY)
    if cached is not None:
        return dict(cached)

    try:
        blocks = _block_payloads()
        links = _site_links_payload()
    except DatabaseError as exc:
        _log_public_content_fallback(exc)
        blocks = {}
        links = default_site_links_payload()

    branding = public_branding_payload(blocks)
    payload = {
        "brand": branding,
        "links": links,
        "social_links": _social_links_payload(links),
        "store_links": _store_links_payload(links),
    }
    cache.set(_TEMPLATE_CACHE_KEY, payload, _template_payload_cache_ttl())
    return payload


def public_content_payload() -> dict:
    cached = cache.get(_PUBLIC_CACHE_KEY)
    if cached is not None:
        return dict(cached)

    try:
        blocks = _block_payloads()
        documents = _latest_legal_documents()
        links_payload = _site_links_payload()
    except DatabaseError as exc:
        _log_public_content_fallback(exc)
        blocks = {}
        documents = {}
        links_payload = default_site_links_payload()

    payload = {
        "blocks": blocks,
        "documents": documents,
        "links": links_payload,
        "branding": public_branding_payload(blocks),
    }
    cache.set(_PUBLIC_CACHE_KEY, payload, _public_payload_cache_ttl())
    return payload
