from __future__ import annotations

from datetime import datetime

from django.contrib import messages
from django.core.exceptions import ValidationError
from django.core.paginator import Paginator
from django.shortcuts import get_object_or_404, redirect, render
from django.utils import timezone
from django.views.decorators.http import require_POST

from apps.audit.models import AuditAction
from apps.audit.services import log_action
from apps.backoffice.policies import ContentHideDeletePolicy, ContentManagePolicy
from apps.content.models import (
    ContentBlockKey,
    LegalDocumentType,
    SiteContentBlock,
    SiteLegalDocument,
    SiteLinks,
)
from apps.content.services import sanitize_multiline_text, sanitize_text
from apps.dashboard.access import has_action_permission, has_dashboard_access
from apps.dashboard.contracts import DashboardCode
from apps.dashboard.security import (
    ALLOWED_ALL_EXTENSIONS,
    ALLOWED_ALL_MIME_TYPES,
    ALLOWED_MEDIA_EXTENSIONS,
    ALLOWED_MEDIA_MIME_TYPES,
    FileValidationError,
    validate_uploaded_file,
)
from apps.moderation.integrations import record_content_action_case
from apps.providers.models import ProviderPortfolioItem, ProviderSpotlightItem

from ..view_utils import build_layout_context, dashboard_v2_access_required


CONTENT_BLOCK_GROUPS: tuple[dict[str, object], ...] = (
    {
        "slug": "onboarding",
        "title": "شاشات التعريف والانطلاق",
        "description": "النصوص والوسائط الخاصة ببداية رحلة المستخدم.",
        "prefixes": ("onboarding_",),
    },
    {
        "slug": "home",
        "title": "الصفحة الرئيسية",
        "description": "العناوين والنصوص المختصرة المعروضة على الواجهة الرئيسية.",
        "prefixes": ("home_",),
    },
    {
        "slug": "auth",
        "title": "الدخول والتسجيل",
        "description": "محتوى صفحات login/signup/twofa.",
        "prefixes": ("login_", "signup_", "twofa_"),
    },
    {
        "slug": "pages",
        "title": "الصفحات التعريفية",
        "description": "محتوى من نحن والشروط والمساعدة.",
        "prefixes": ("about_", "terms_", "settings_"),
    },
    {
        "slug": "support",
        "title": "التواصل والبلاغات",
        "description": "النصوص المعروضة داخل بوابة الدعم والتواصل.",
        "prefixes": ("contact_",),
    },
)


def _group_content_blocks(blocks_map: dict[str, SiteContentBlock]) -> list[dict[str, object]]:
    grouped: list[dict[str, object]] = []
    choices = list(ContentBlockKey.choices)
    remaining = list(choices)

    for group in CONTENT_BLOCK_GROUPS:
        rows = []
        for key, label in remaining:
            if any(str(key).startswith(prefix) for prefix in group["prefixes"]):
                rows.append({"key": key, "label": label, "block": blocks_map.get(key)})
        if rows:
            grouped.append(
                {
                    "slug": group["slug"],
                    "title": group["title"],
                    "description": group["description"],
                    "items": rows,
                }
            )
            remaining = [choice for choice in remaining if all(choice[0] != row["key"] for row in rows)]

    if remaining:
        grouped.append(
            {
                "slug": "other",
                "title": "عناصر إضافية",
                "description": "بلوكات غير مصنفة ضمن الأقسام الأساسية.",
                "items": [{"key": key, "label": label, "block": blocks_map.get(key)} for key, label in remaining],
            }
        )

    return grouped


def _latest_legal_docs() -> dict[str, SiteLegalDocument]:
    latest: dict[str, SiteLegalDocument] = {}
    for doc in SiteLegalDocument.objects.order_by("doc_type", "-published_at", "-id"):
        if doc.doc_type in latest:
            continue
        latest[doc.doc_type] = doc
    return latest


@dashboard_v2_access_required(DashboardCode.CONTENT, write=False)
def content_home_view(request):
    blocks_map = {block.key: block for block in SiteContentBlock.objects.all()}
    grouped_blocks = _group_content_blocks(blocks_map)
    latest_docs = _latest_legal_docs()
    links = SiteLinks.objects.order_by("-updated_at", "-id").first()

    can_write_dashboard = has_dashboard_access(request.user, DashboardCode.CONTENT, write=True)
    can_manage_content = can_write_dashboard and has_action_permission(request.user, "content.manage")
    can_hide_delete_content = can_write_dashboard and has_action_permission(request.user, "content.hide_delete")

    context = build_layout_context(
        request,
        title="إدارة المحتوى",
        subtitle="تحديث بلوكات المنصة والمستندات والروابط الرسمية",
        active_code=DashboardCode.CONTENT,
        breadcrumbs=[{"label": "لوحة التحكم", "url": "dashboard_v2:home"}],
    )
    context.update(
        {
            "grouped_blocks": grouped_blocks,
            "doc_rows": [
                {"key": key, "label": label, "doc": latest_docs.get(key)}
                for key, label in LegalDocumentType.choices
            ],
            "links": links,
            "blocks_count": len(blocks_map),
            "active_blocks_count": sum(1 for block in blocks_map.values() if block.is_active),
            "portfolio_count": ProviderPortfolioItem.objects.count(),
            "spotlight_count": ProviderSpotlightItem.objects.count(),
            "can_manage_content": can_manage_content,
            "can_hide_delete_content": can_hide_delete_content,
        }
    )
    return render(request, "dashboard_v2/content/home.html", context)


@require_POST
@dashboard_v2_access_required(DashboardCode.CONTENT, write=True)
def content_block_update_action(request, key: str):
    valid_keys = {choice[0] for choice in ContentBlockKey.choices}
    if key not in valid_keys:
        messages.error(request, "مفتاح البلوك غير صالح.")
        return redirect("dashboard_v2:content_home")

    policy = ContentManagePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="content.site_content_block",
        reference_id=key,
        extra={"surface": "dashboard_v2.content_block_update_action"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتعديل محتوى المنصة.")
        return redirect("dashboard_v2:content_home")

    title_ar = sanitize_multiline_text(request.POST.get("title_ar", ""))
    body_ar = sanitize_multiline_text(request.POST.get("body_ar", ""))
    uploaded_media = request.FILES.get("media_file")
    remove_media = (request.POST.get("remove_media") or "") in {"1", "on", "true"}
    is_active = (request.POST.get("is_active") or "") in {"1", "on", "true"}

    if uploaded_media:
        try:
            validate_uploaded_file(
                uploaded_media,
                allowed_extensions=ALLOWED_MEDIA_EXTENSIONS,
                allowed_mime_types=ALLOWED_MEDIA_MIME_TYPES,
            )
        except FileValidationError as exc:
            messages.error(request, str(exc))
            return redirect("dashboard_v2:content_home")

    if not title_ar:
        messages.error(request, "عنوان البلوك مطلوب.")
        return redirect("dashboard_v2:content_home")

    block, _ = SiteContentBlock.objects.get_or_create(key=key)
    old_media_name = block.media_file.name if block.media_file else ""
    old_media_storage = block.media_file.storage if block.media_file else None
    before_payload = {
        "title_ar": block.title_ar,
        "body_ar": block.body_ar,
        "media_type": block.media_type,
        "is_active": block.is_active,
    }

    block.title_ar = title_ar
    block.body_ar = body_ar
    block.is_active = is_active
    block.updated_by = request.user
    if remove_media:
        block.media_file = ""
    elif uploaded_media:
        block.media_file = uploaded_media

    try:
        block.full_clean()
    except ValidationError as exc:
        messages.error(request, "بيانات البلوك غير صالحة: %s" % ", ".join(exc.messages))
        return redirect("dashboard_v2:content_home")

    block.save()

    should_delete_old_media = old_media_name and (
        (remove_media and not block.media_file)
        or (uploaded_media and old_media_name != getattr(block.media_file, "name", ""))
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
        reference_id=str(block.id),
        extra={
            "key": key,
            "before": before_payload,
            "after": {
                "title_ar": block.title_ar,
                "body_ar": block.body_ar,
                "media_type": block.media_type,
                "is_active": block.is_active,
            },
        },
    )
    messages.success(request, "تم تحديث البلوك بنجاح.")
    return redirect("dashboard_v2:content_home")


@require_POST
@dashboard_v2_access_required(DashboardCode.CONTENT, write=True)
def content_doc_upload_action(request, doc_type: str):
    valid_types = {choice[0] for choice in LegalDocumentType.choices}
    if doc_type not in valid_types:
        messages.error(request, "نوع المستند غير صالح.")
        return redirect("dashboard_v2:content_home")

    policy = ContentManagePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="content.site_legal_document",
        reference_id=doc_type,
        extra={"surface": "dashboard_v2.content_doc_upload_action"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بإدارة المستندات.")
        return redirect("dashboard_v2:content_home")

    uploaded = request.FILES.get("file")
    body_ar = sanitize_multiline_text(request.POST.get("body_ar", ""))
    if not uploaded and not body_ar:
        messages.error(request, "أدخل نص المستند أو أرفق ملفًا.")
        return redirect("dashboard_v2:content_home")

    if uploaded:
        try:
            validate_uploaded_file(
                uploaded,
                allowed_extensions=ALLOWED_ALL_EXTENSIONS,
                allowed_mime_types=ALLOWED_ALL_MIME_TYPES,
            )
        except FileValidationError as exc:
            messages.error(request, str(exc))
            return redirect("dashboard_v2:content_home")

    version = sanitize_text(request.POST.get("version", "1.0")) or "1.0"
    is_active = (request.POST.get("is_active") or "") in {"1", "on", "true"}

    published_at_raw = (request.POST.get("published_at") or "").strip()
    published_at = timezone.now()
    if published_at_raw:
        try:
            parsed = datetime.strptime(published_at_raw, "%Y-%m-%dT%H:%M")
            published_at = timezone.make_aware(parsed, timezone.get_current_timezone())
        except Exception:
            messages.error(request, "صيغة تاريخ النشر غير صحيحة.")
            return redirect("dashboard_v2:content_home")

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
        messages.error(request, "فشل التحقق من المستند: %s" % ", ".join(exc.messages))
        return redirect("dashboard_v2:content_home")

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
    messages.success(request, "تم حفظ المستند بنجاح.")
    return redirect("dashboard_v2:content_home")


@require_POST
@dashboard_v2_access_required(DashboardCode.CONTENT, write=True)
def content_links_update_action(request):
    policy = ContentManagePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="content.site_links",
        reference_id="",
        extra={"surface": "dashboard_v2.content_links_update_action"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بتعديل روابط المنصة.")
        return redirect("dashboard_v2:content_home")

    links = SiteLinks.objects.order_by("-updated_at", "-id").first()
    if links is None:
        links = SiteLinks.objects.create()

    before_payload = {
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
        return redirect("dashboard_v2:content_home")

    links.save()

    log_action(
        actor=request.user,
        request=request,
        action=AuditAction.CONTENT_LINKS_UPDATED,
        reference_type="content.site_links",
        reference_id=str(links.id),
        extra={
            "before": before_payload,
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
    messages.success(request, "تم تحديث الروابط بنجاح.")
    return redirect("dashboard_v2:content_home")


@dashboard_v2_access_required(DashboardCode.CONTENT, write=False)
def content_portfolio_list_view(request):
    qs = (
        ProviderPortfolioItem.objects.select_related("provider", "provider__user")
        .order_by("-created_at", "-id")
    )
    provider_q = (request.GET.get("provider") or "").strip()
    file_type = (request.GET.get("file_type") or "").strip()
    if provider_q:
        qs = qs.filter(provider__display_name__icontains=provider_q)
    if file_type in {"image", "video"}:
        qs = qs.filter(file_type=file_type)

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    query = request.GET.copy()
    query.pop("page", None)

    can_delete_content = has_dashboard_access(request.user, DashboardCode.CONTENT, write=True) and has_action_permission(
        request.user, "content.hide_delete"
    )

    context = build_layout_context(
        request,
        title="محتوى معرض الأعمال",
        subtitle="مراجعة عناصر portfolio الخاصة بالمزودين",
        active_code=DashboardCode.CONTENT,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "إدارة المحتوى", "url": "dashboard_v2:content_home"},
        ],
    )
    context.update(
        {
            "page_obj": page_obj,
            "query_string": query.urlencode(),
            "provider_q": provider_q,
            "file_type": file_type,
            "can_delete_content": can_delete_content,
            "table_headers": ["العنصر", "المزود", "النوع", "تاريخ الإضافة", "إجراءات"],
        }
    )
    return render(request, "dashboard_v2/content/portfolio_list.html", context)


@require_POST
@dashboard_v2_access_required(DashboardCode.CONTENT, write=True)
def content_portfolio_delete_action(request, item_id: int):
    item = get_object_or_404(ProviderPortfolioItem, id=item_id)
    policy = ContentHideDeletePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="providers.provider_portfolio_item",
        reference_id=str(item.id),
        extra={"surface": "dashboard_v2.content_portfolio_delete_action"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بحذف هذا المحتوى.")
        return redirect("dashboard_v2:content_portfolio_list")

    provider_id = item.provider_id
    file_type = item.file_type
    caption = item.caption
    try:
        record_content_action_case(
            item=item,
            content_kind="portfolio_item",
            action_name="delete",
            by_user=request.user,
            request=request,
            note="dashboard_v2_portfolio_delete",
        )
    except Exception:
        pass
    item.delete()
    log_action(
        actor=request.user,
        request=request,
        action=AuditAction.CONTENT_BLOCK_UPDATED,
        reference_type="providers.provider_portfolio_item",
        reference_id=str(item_id),
        extra={
            "action": "delete",
            "provider_id": provider_id,
            "file_type": file_type,
            "caption": caption,
        },
    )
    messages.success(request, "تم حذف العنصر.")
    return redirect("dashboard_v2:content_portfolio_list")


@dashboard_v2_access_required(DashboardCode.CONTENT, write=False)
def content_spotlight_list_view(request):
    qs = (
        ProviderSpotlightItem.objects.select_related("provider", "provider__user")
        .order_by("-created_at", "-id")
    )
    provider_q = (request.GET.get("provider") or "").strip()
    file_type = (request.GET.get("file_type") or "").strip()
    if provider_q:
        qs = qs.filter(provider__display_name__icontains=provider_q)
    if file_type in {"image", "video"}:
        qs = qs.filter(file_type=file_type)

    paginator = Paginator(qs, 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    query = request.GET.copy()
    query.pop("page", None)

    can_delete_content = has_dashboard_access(request.user, DashboardCode.CONTENT, write=True) and has_action_permission(
        request.user, "content.hide_delete"
    )

    context = build_layout_context(
        request,
        title="محتوى الأضواء",
        subtitle="مراجعة عناصر spotlight الخاصة بالمزودين",
        active_code=DashboardCode.CONTENT,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "إدارة المحتوى", "url": "dashboard_v2:content_home"},
        ],
    )
    context.update(
        {
            "page_obj": page_obj,
            "query_string": query.urlencode(),
            "provider_q": provider_q,
            "file_type": file_type,
            "can_delete_content": can_delete_content,
            "table_headers": ["العنصر", "المزود", "النوع", "تاريخ الإضافة", "إجراءات"],
        }
    )
    return render(request, "dashboard_v2/content/spotlight_list.html", context)


@require_POST
@dashboard_v2_access_required(DashboardCode.CONTENT, write=True)
def content_spotlight_delete_action(request, item_id: int):
    item = get_object_or_404(ProviderSpotlightItem, id=item_id)
    policy = ContentHideDeletePolicy.evaluate_and_log(
        request.user,
        request=request,
        reference_type="providers.provider_spotlight_item",
        reference_id=str(item.id),
        extra={"surface": "dashboard_v2.content_spotlight_delete_action"},
    )
    if not policy.allowed:
        messages.error(request, "غير مصرح بحذف هذا المحتوى.")
        return redirect("dashboard_v2:content_spotlight_list")

    provider_id = item.provider_id
    file_type = item.file_type
    caption = item.caption
    try:
        record_content_action_case(
            item=item,
            content_kind="spotlight_item",
            action_name="delete",
            by_user=request.user,
            request=request,
            note="dashboard_v2_spotlight_delete",
        )
    except Exception:
        pass
    item.delete()
    log_action(
        actor=request.user,
        request=request,
        action=AuditAction.CONTENT_BLOCK_UPDATED,
        reference_type="providers.provider_spotlight_item",
        reference_id=str(item_id),
        extra={
            "action": "delete",
            "provider_id": provider_id,
            "file_type": file_type,
            "caption": caption,
        },
    )
    messages.success(request, "تم حذف العنصر.")
    return redirect("dashboard_v2:content_spotlight_list")

