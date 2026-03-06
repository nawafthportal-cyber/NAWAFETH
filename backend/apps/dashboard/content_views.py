from __future__ import annotations

from datetime import datetime

from django.contrib import messages
from django.core.exceptions import ValidationError
from django.shortcuts import get_object_or_404, redirect, render
from django.utils import timezone
from django.views.decorators.http import require_POST

from apps.audit.models import AuditAction
from apps.audit.services import log_action
from apps.content.models import ContentBlockKey, LegalDocumentType, SiteContentBlock, SiteLegalDocument, SiteLinks
from apps.content.services import sanitize_multiline_text, sanitize_text

from .auth import dashboard_staff_required as staff_member_required
from .views import _dashboard_allowed, dashboard_access_required


@staff_member_required
@dashboard_access_required("content", write=False)
def content_management(request):
    blocks = {
        b.key: b
        for b in SiteContentBlock.objects.all()
    }

    latest_docs: dict[str, SiteLegalDocument] = {}
    for doc in SiteLegalDocument.objects.order_by("doc_type", "-published_at", "-id"):
        if doc.doc_type in latest_docs:
            continue
        latest_docs[doc.doc_type] = doc

    links = SiteLinks.objects.order_by("-updated_at", "-id").first()
    can_write = _dashboard_allowed(request.user, "content", write=True)

    return render(
        request,
        "dashboard/content_management.html",
        {
            "blocks": blocks,
            "block_choices": ContentBlockKey.choices,
            "doc_choices": LegalDocumentType.choices,
            "latest_docs": latest_docs,
            "links": links,
            "can_write": can_write,
        },
    )


@require_POST
@staff_member_required
@dashboard_access_required("content", write=True)
def content_block_update_action(request, key: str):
    valid_keys = {choice[0] for choice in ContentBlockKey.choices}
    if key not in valid_keys:
        return redirect("dashboard:content_management")

    title_ar = sanitize_multiline_text(request.POST.get("title_ar", ""))
    body_ar = sanitize_multiline_text(request.POST.get("body_ar", ""))
    uploaded_media = request.FILES.get("media_file")
    remove_media = (request.POST.get("remove_media") or "") in {"1", "on", "true"}
    is_active = (request.POST.get("is_active") or "") in {"1", "on", "true"}

    if not title_ar:
        messages.error(request, "عنوان البلوك مطلوب")
        return redirect("dashboard:content_management")

    obj, _created = SiteContentBlock.objects.get_or_create(key=key)
    old_media_name = obj.media_file.name if obj.media_file else ""
    old_media_storage = obj.media_file.storage if obj.media_file else None
    before = {
        "title_ar": obj.title_ar,
        "body_ar": obj.body_ar,
        "media_url": obj.media_file.url if obj.media_file else "",
        "media_type": obj.media_type,
        "is_active": obj.is_active,
    }
    obj.title_ar = title_ar
    obj.body_ar = body_ar
    if remove_media:
        obj.media_file = ""
    elif uploaded_media:
        obj.media_file = uploaded_media
    obj.is_active = is_active
    obj.updated_by = request.user

    try:
        obj.full_clean()
    except ValidationError as exc:
        messages.error(request, "بيانات المحتوى غير صالحة: %s" % ", ".join(exc.messages))
        return redirect("dashboard:content_management")

    obj.save()

    should_delete_old_media = old_media_name and (
        (remove_media and not obj.media_file)
        or (uploaded_media and old_media_name != getattr(obj.media_file, "name", ""))
    )
    if should_delete_old_media and old_media_storage is not None:
        try:
            old_media_storage.delete(old_media_name)
        except Exception:
            pass

    log_action(
        actor=request.user,
        request=request,
        action=AuditAction.CONTENT_BLOCK_UPDATED,
        reference_type="content.site_content_block",
        reference_id=str(obj.id),
        extra={
            "key": key,
            "before": before,
            "after": {
                "title_ar": obj.title_ar,
                "body_ar": obj.body_ar,
                "media_url": obj.media_file.url if obj.media_file else "",
                "media_type": obj.media_type,
                "is_active": obj.is_active,
            },
        },
    )
    messages.success(request, "تم تحديث المحتوى بنجاح")
    return redirect("dashboard:content_management")


@require_POST
@staff_member_required
@dashboard_access_required("content", write=True)
def content_doc_upload_action(request, doc_type: str):
    valid_types = {choice[0] for choice in LegalDocumentType.choices}
    if doc_type not in valid_types:
        return redirect("dashboard:content_management")

    uploaded = request.FILES.get("file")
    body_ar = sanitize_multiline_text(request.POST.get("body_ar", ""))
    if not uploaded and not body_ar:
        messages.error(request, "أدخل نص المستند أو أرفق ملفاً واحداً على الأقل")
        return redirect("dashboard:content_management")

    version = sanitize_text(request.POST.get("version", "1.0")) or "1.0"
    is_active = (request.POST.get("is_active") or "") in {"1", "on", "true"}

    published_at_raw = (request.POST.get("published_at") or "").strip()
    published_at = timezone.now()
    if published_at_raw:
        try:
            dt = datetime.strptime(published_at_raw, "%Y-%m-%dT%H:%M")
            published_at = timezone.make_aware(dt, timezone.get_current_timezone())
        except Exception:
            messages.error(request, "صيغة تاريخ النشر غير صحيحة")
            return redirect("dashboard:content_management")

    doc = SiteLegalDocument(
        doc_type=doc_type,
        body_ar=body_ar,
        file=uploaded,
        version=version,
        published_at=published_at,
        is_active=is_active,
        uploaded_by=request.user,
    )

    try:
        doc.full_clean()
    except ValidationError as exc:
        messages.error(request, "فشل التحقق من الملف: %s" % ", ".join(exc.messages))
        return redirect("dashboard:content_management")

    doc.save()

    if is_active:
        SiteLegalDocument.objects.filter(doc_type=doc_type, is_active=True).exclude(id=doc.id).update(is_active=False)

    log_action(
        actor=request.user,
        request=request,
        action=AuditAction.CONTENT_DOCUMENT_UPLOADED,
        reference_type="content.site_legal_document",
        reference_id=str(doc.id),
        extra={
            "doc_type": doc.doc_type,
            "version": doc.version,
            "is_active": doc.is_active,
            "published_at": doc.published_at.isoformat() if doc.published_at else None,
            "has_body": bool(doc.body_ar),
            "has_file": bool(doc.file),
        },
    )
    messages.success(request, "تم حفظ المستند القانوني بنجاح")
    return redirect("dashboard:content_management")


@require_POST
@staff_member_required
@dashboard_access_required("content", write=True)
def content_links_update_action(request):
    links = SiteLinks.objects.order_by("-updated_at", "-id").first()
    if links is None:
        links = SiteLinks.objects.create()

    before = {
        "x_url": links.x_url,
        "whatsapp_url": links.whatsapp_url,
        "email": links.email,
        "android_store": links.android_store,
        "ios_store": links.ios_store,
        "website_url": links.website_url,
    }

    links.x_url = (request.POST.get("x_url") or "").strip()
    links.whatsapp_url = (request.POST.get("whatsapp_url") or "").strip()
    links.email = (request.POST.get("email") or "").strip()
    links.android_store = (request.POST.get("android_store") or "").strip()
    links.ios_store = (request.POST.get("ios_store") or "").strip()
    links.website_url = (request.POST.get("website_url") or "").strip()
    links.updated_by = request.user

    try:
        links.full_clean()
    except ValidationError as exc:
        messages.error(request, "بيانات الروابط غير صالحة: %s" % ", ".join(exc.messages))
        return redirect("dashboard:content_management")

    links.save()

    log_action(
        actor=request.user,
        request=request,
        action=AuditAction.CONTENT_LINKS_UPDATED,
        reference_type="content.site_links",
        reference_id=str(links.id),
        extra={
            "before": before,
            "after": {
                "x_url": links.x_url,
                "whatsapp_url": links.whatsapp_url,
                "email": links.email,
                "android_store": links.android_store,
                "ios_store": links.ios_store,
                "website_url": links.website_url,
            },
        },
    )
    messages.success(request, "تم تحديث روابط المنصة")
    return redirect("dashboard:content_management")
