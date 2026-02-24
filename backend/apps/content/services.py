from __future__ import annotations

from django.utils.html import strip_tags

from .models import SiteContentBlock, SiteLegalDocument, SiteLinks


def sanitize_text(value: str) -> str:
    cleaned = strip_tags((value or "").replace("\x00", ""))
    return " ".join(cleaned.split())


def public_content_payload() -> dict:
    blocks_qs = SiteContentBlock.objects.filter(is_active=True).order_by("key")
    blocks = {
        b.key: {
            "title_ar": b.title_ar,
            "body_ar": b.body_ar,
            "updated_at": b.updated_at.isoformat(),
        }
        for b in blocks_qs
    }

    active_docs = (
        SiteLegalDocument.objects.filter(is_active=True)
        .order_by("doc_type", "-published_at", "-id")
    )
    docs: dict[str, dict] = {}
    for doc in active_docs:
        if doc.doc_type in docs:
            continue
        docs[doc.doc_type] = {
            "doc_type": doc.doc_type,
            "version": doc.version,
            "published_at": doc.published_at.isoformat() if doc.published_at else None,
            "file_url": doc.file.url if doc.file else "",
        }

    links = SiteLinks.objects.order_by("-updated_at", "-id").first()
    links_payload = {
        "x_url": links.x_url if links else "",
        "whatsapp_url": links.whatsapp_url if links else "",
        "email": links.email if links else "",
        "android_store": links.android_store if links else "",
        "ios_store": links.ios_store if links else "",
        "website_url": links.website_url if links else "",
    }

    return {
        "blocks": blocks,
        "documents": docs,
        "links": links_payload,
    }
