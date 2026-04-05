from __future__ import annotations

from decimal import Decimal
from urllib.parse import urlencode
from django.conf import settings
from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from apps.billing.models import Invoice, InvoiceStatus, PaymentAttempt, PaymentAttemptStatus, PaymentProvider
from apps.billing.models import InvoiceLineItem
from apps.subscriptions.configuration import (
    canonical_subscription_plan_for_tier,
    resolved_plan_decimal,
    template_subscription_plan_for_plan,
)
from apps.subscriptions.tiering import (
    CanonicalPlanTier,
    canonical_tier_from_value,
    canonical_tier_label,
    db_tier_for_canonical,
)

from .models import (
    VerificationRequest, VerificationDocument,
    VerificationStatus, VerifiedBadge, VerificationBadgeType,
    VerificationBlueProfile, VerificationBlueSubjectType,
    VerificationRequirement,
    VerificationRequirementAttachment,
)


REQUIREMENTS_CATALOG: dict[str, dict[str, dict[str, str]]] = {
    VerificationBadgeType.BLUE: {
        "B1": {
            "code": "B1",
            "title": "التوثيق اللحظي بهوية وطنية أو إقامة أو سجل تجاري صادر من المملكة العربية السعودية",
        },
    },
    VerificationBadgeType.GREEN: {
        "G1": {
            "code": "G1",
            "title": "توثيق الاعتماد المهني (الهندسي، الطبي، الصحي، القانوني، المحاسبي...الخ)",
        },
        "G2": {
            "code": "G2",
            "title": "توثيق الرخص التنظيمية (شهادة معروف، وثيقة ممارس حر موثق...الخ)",
        },
        "G3": {
            "code": "G3",
            "title": "توثيق الخبرات العملية (تعريف من جهة العمل، التأمينات الاجتماعية...الخ)",
        },
        "G4": {
            "code": "G4",
            "title": "توثيق الدرجة العلمية والأكاديمية (الشهادة العلمية، القرارات الأكاديمية...الخ)",
        },
        "G5": {
            "code": "G5",
            "title": "توثيق الشهادات الاحترافية (التقنية، الهندسية، الإدارية، القانونية، المالية، الاقتصادية، المحاسبية...الخ)",
        },
        "G6": {
            "code": "G6",
            "title": "توثيق كفو (عبر أبشر لمن يعمل في توصيل الطلبات أو النقل التشاركي ويستخدم مركبته الخاصة)",
        },
    },
}


BADGE_PUBLIC_DEFINITIONS: dict[str, dict[str, str]] = {
    VerificationBadgeType.BLUE: {
        "badge_type": VerificationBadgeType.BLUE,
        "title": "الشارة الزرقاء",
        "short_description": "توثيق الهوية الشخصية أو الصفة التجارية.",
        "explanation": "تعني أن مقدم الخدمة أكمل التحقق الأساسي لهويته الشخصية أو صفته التجارية عبر مستندات سعودية رسمية.",
    },
    VerificationBadgeType.GREEN: {
        "badge_type": VerificationBadgeType.GREEN,
        "title": "الشارة الخضراء",
        "short_description": "توثيق الاعتمادات المهنية والرخص والخبرة والشهادات المرتبطة بالمجال.",
        "explanation": "تعني أن مقدم الخدمة قدم واعتمد أدلة كفاءة مهنية أو ترخيص أو اعتماد أو خبرة مرتبطة بخدمته.",
    },
}


def _get_verification_currency():
    from apps.core.models import PlatformConfig
    return PlatformConfig.load().verification_currency


VERIFICATION_PRICING_CURRENCY = "SAR"  # kept as module-level fallback
VERIFICATION_BILLING_CYCLE = "yearly"
VERIFICATION_BILLING_CYCLE_LABEL = "سنوي"
VERIFICATION_CHARGE_MODEL = "per_verification"
VERIFICATION_CHARGE_MODEL_LABEL = "لكل طلب توثيق"
VERIFICATION_TAX_POLICY = "inclusive"
VERIFICATION_TAX_POLICY_LABEL = "شامل الضريبة"
VERIFICATION_ADDITIONAL_VAT_PERCENT = Decimal("0.00")
VERIFICATION_PRICE_NOTE = (
    "الرسوم السنوية المعروضة هي المبلغ النهائي لكل طلب توثيق، ولا تضاف عليها "
    "ضريبة أو رسوم إضافية عند إصدار الفاتورة."
)
VERIFICATION_BLOCKING_REQUEST_STATUSES = (
    VerificationStatus.NEW,
    VerificationStatus.IN_REVIEW,
    VerificationStatus.APPROVED,
    VerificationStatus.PENDING_PAYMENT,
    VerificationStatus.ACTIVE,
)


def get_public_badge_detail(badge_type: str):
    bt = (badge_type or "").strip().lower()
    definition = BADGE_PUBLIC_DEFINITIONS.get(bt)
    if not definition:
        return None

    requirements = list((REQUIREMENTS_CATALOG.get(bt) or {}).values())
    return {
        **definition,
        "requirements": requirements,
    }


def get_public_badges_catalog():
    items = []
    for bt in (VerificationBadgeType.BLUE, VerificationBadgeType.GREEN):
        detail = get_public_badge_detail(bt)
        if detail:
            items.append(detail)
    return {
        "count": len(items),
        "items": items,
    }


def verification_blue_preview_for_user(*, user, subject_type: str, official_number: str, official_date):
    provider_profile = getattr(user, "provider_profile", None)
    first_name = str(getattr(user, "first_name", "") or "").strip()
    last_name = str(getattr(user, "last_name", "") or "").strip()
    full_name = " ".join(part for part in [first_name, last_name] if part).strip()
    username = str(getattr(user, "username", "") or "").strip()
    phone = str(getattr(user, "phone", "") or "").strip()
    provider_display_name = str(getattr(provider_profile, "display_name", "") or "").strip()

    if subject_type == VerificationBlueSubjectType.BUSINESS:
        verified_name = provider_display_name or full_name or username or phone or "اسم المنشأة"
        verified_name_label = "اسم المنشأة"
        official_number_label = "رقم السجل التجاري"
        official_date_label = "تاريخه"
    else:
        verified_name = full_name or provider_display_name or username or phone or "اسم العميل"
        verified_name_label = "اسم العميل"
        official_number_label = "رقم الهوية / الإقامة"
        official_date_label = "تاريخ الميلاد"

    subject_labels = dict(VerificationBlueSubjectType.choices)
    return {
        "subject_type": subject_type,
        "subject_type_label": subject_labels.get(subject_type, subject_type),
        "official_number": str(official_number or "").strip(),
        "official_date": official_date.isoformat() if official_date else None,
        "official_number_label": official_number_label,
        "official_date_label": official_date_label,
        "verified_name": verified_name,
        "verified_name_label": verified_name_label,
        "verification_source": "elm",
        "verification_source_label": "من خدمات علم",
        "can_confirm": True,
    }


def resolve_requirement_def(badge_type: str, code: str) -> dict[str, str]:
    bt = (badge_type or "").strip()
    c = (code or "").strip().upper()
    d = (REQUIREMENTS_CATALOG.get(bt, {}) or {}).get(c)
    if d:
        return d
    # Fallback: accept unknown codes but keep a minimal title.
    return {"code": c or "UNKNOWN", "title": c or "بند توثيق"}


def _sync_verification_to_unified(*, vr: VerificationRequest, changed_by=None):
    """
    مزامنة طلب التوثيق مع محرك الطلبات الموحد (تكامل تدريجي غير معطّل).
    """
    try:
        from apps.unified_requests.services import upsert_unified_request
        from apps.unified_requests.models import UnifiedRequestType
    except Exception:
        return

    upsert_unified_request(
        request_type=UnifiedRequestType.VERIFICATION,
        requester=vr.requester,
        source_app="verification",
        source_model="VerificationRequest",
        source_object_id=vr.id,
        status=vr.status,
        priority="normal",
        summary=f"طلب توثيق {vr.get_badge_type_display()}",
        metadata={
            "badge_type": vr.badge_type,
            "verification_code": vr.code or "",
            "invoice_id": vr.invoice_id,
        },
        assigned_team_code="verify",
        assigned_team_name="التوثيق",
        assigned_user=vr.assigned_to,
        changed_by=changed_by,
    )


def _safe_set_profile_flags(user, badge_type: str, active: bool):
    """
    محاولة تحديث ProviderProfile flags إن كانت موجودة في مشروعك.
    بدون كسر النظام لو ما كانت موجودة.
    """
    profile = getattr(user, "provider_profile", None) or getattr(user, "providerprofile", None)
    if not profile:
        return

    if badge_type == VerificationBadgeType.BLUE and hasattr(profile, "is_verified_blue"):
        profile.is_verified_blue = active
    if badge_type == VerificationBadgeType.GREEN and hasattr(profile, "is_verified_green"):
        profile.is_verified_green = active

    # اختياري: حفظ تاريخ انتهاء إن وجد
    if hasattr(profile, "verified_expires_at"):
        # لو عندك هذا الحقل مستقبلًا
        profile.verified_expires_at = None

    try:
        profile.save()
    except Exception:
        # لا نفشل التشغيل
        pass


def sync_provider_badges(user) -> dict[str, bool]:
    """
    مزامنة flags الشارات داخل ProviderProfile من المصدر المرجعي VerifiedBadge.
    يعتمد فقط على الشارات الفعالة وغير المنتهية.
    """
    now = timezone.now()

    has_blue = VerifiedBadge.objects.filter(
        user=user,
        badge_type=VerificationBadgeType.BLUE,
        is_active=True,
        expires_at__gt=now,
    ).exists()
    has_green = VerifiedBadge.objects.filter(
        user=user,
        badge_type=VerificationBadgeType.GREEN,
        is_active=True,
        expires_at__gt=now,
    ).exists()

    profile = getattr(user, "provider_profile", None) or getattr(user, "providerprofile", None)
    if profile:
        changed = False
        if hasattr(profile, "is_verified_blue") and profile.is_verified_blue != has_blue:
            profile.is_verified_blue = has_blue
            changed = True
        if hasattr(profile, "is_verified_green") and profile.is_verified_green != has_green:
            profile.is_verified_green = has_green
            changed = True
        if changed:
            try:
                profile.save(update_fields=["is_verified_blue", "is_verified_green", "updated_at"])
            except Exception:
                try:
                    profile.save()
                except Exception:
                    pass

    return {
        "is_verified_blue": has_blue,
        "is_verified_green": has_green,
    }


def expire_verified_badges_and_sync(*, now=None, limit: int = 1000) -> int:
    now = now or timezone.now()

    expired_requests = list(
        VerificationRequest.objects.filter(
            status=VerificationStatus.ACTIVE,
            expires_at__isnull=False,
            expires_at__lte=now,
        )
        .select_related("requester")
        .order_by("id")[:limit]
    )
    if not expired_requests:
        return 0

    request_ids = [vr.id for vr in expired_requests]
    user_ids = sorted({vr.requester_id for vr in expired_requests if vr.requester_id})
    VerificationRequest.objects.filter(id__in=request_ids).update(status=VerificationStatus.EXPIRED)
    changed = VerifiedBadge.objects.filter(request_id__in=request_ids, is_active=True).update(is_active=False)

    if user_ids:
        from apps.accounts.models import User

        for user in User.objects.filter(id__in=user_ids):
            sync_provider_badges(user)

    return max(changed, len(request_ids))


def _fee_for_badge(badge_type: str) -> Decimal:
    """
    الرسم المرجعي:
    1) VerificationPricingRule (DB first)
    2) canonical basic plan fallback
    """
    from .models import VerificationPricingRule

    try:
        rule = VerificationPricingRule.objects.get(badge_type=badge_type, is_active=True)
        return Decimal(str(rule.fee))
    except VerificationPricingRule.DoesNotExist:
        pass

    # fallback: canonical basic plan
    basic_plan = canonical_subscription_plan_for_tier(CanonicalPlanTier.BASIC)
    field_name = (
        "verification_green_fee"
        if badge_type == VerificationBadgeType.GREEN
        else "verification_blue_fee"
    )
    amount = getattr(basic_plan, field_name, None)
    return Decimal(str(amount if amount is not None else "0.00"))


def verification_billing_policy() -> dict[str, object]:
    return {
        "currency": _get_verification_currency() or VERIFICATION_PRICING_CURRENCY,
        "billing_cycle": VERIFICATION_BILLING_CYCLE,
        "billing_cycle_label": VERIFICATION_BILLING_CYCLE_LABEL,
        "charge_model": VERIFICATION_CHARGE_MODEL,
        "charge_model_label": VERIFICATION_CHARGE_MODEL_LABEL,
        "tax_policy": VERIFICATION_TAX_POLICY,
        "tax_policy_label": VERIFICATION_TAX_POLICY_LABEL,
        "tax_included": True,
        "additional_vat_percent": str(
            VERIFICATION_ADDITIONAL_VAT_PERCENT.quantize(Decimal("0.01"))
        ),
        "price_note": VERIFICATION_PRICE_NOTE,
    }


def _badge_billing_title(badge_type: str) -> str:
    if badge_type == VerificationBadgeType.GREEN:
        return "رسوم التوثيق للشارة الخضراء"
    return "رسوم التوثيق للشارة الزرقاء"


def _badge_billing_code(badge_type: str) -> str:
    if badge_type == VerificationBadgeType.GREEN:
        return "VERIFY_GREEN"
    return "VERIFY_BLUE"


def _ordered_unique_badge_types(badge_types) -> list[str]:
    normalized_badges = [
        str(badge_type or "").strip().lower()
        for badge_type in (badge_types or [])
    ]
    seen = set()
    ordered = []
    for badge_type in (VerificationBadgeType.BLUE, VerificationBadgeType.GREEN):
        if badge_type in normalized_badges and badge_type not in seen:
            seen.add(badge_type)
            ordered.append(badge_type)
    for badge_type in normalized_badges:
        if badge_type in VerificationBadgeType.values and badge_type not in seen:
            seen.add(badge_type)
            ordered.append(badge_type)
    return ordered


def verification_invoice_preview_for_request(*, vr: VerificationRequest) -> dict[str, object]:
    approved_items = list(vr.requirements.filter(is_approved=True).order_by("sort_order", "id"))
    pricing_snapshot = verification_pricing_for_user(vr.requester)
    pricing_policy = verification_billing_policy()
    currency = str(pricing_policy.get("currency") or _get_verification_currency() or VERIFICATION_PRICING_CURRENCY)
    vat_percent = Decimal(str(pricing_policy.get("additional_vat_percent") or "0.00"))

    lines: list[dict[str, object]] = []
    subtotal = Decimal("0.00")
    for idx, item in enumerate(approved_items):
        amount = _fee_for_user_and_badge(vr.requester, item.badge_type)
        subtotal += amount
        lines.append(
            {
                "sort_order": idx,
                "item_code": item.code,
                "title": item.title,
                "badge_type": item.badge_type,
                "amount": amount,
            }
        )

    vat_amount = Decimal("0.00")
    if vat_percent > Decimal("0.00"):
        vat_amount = (subtotal * vat_percent / Decimal("100.00")).quantize(Decimal("0.01"))
    total = (subtotal + vat_amount).quantize(Decimal("0.01"))

    return {
        "currency": currency,
        "pricing": pricing_snapshot,
        "tax_policy": pricing_policy.get("tax_policy"),
        "tax_policy_label": pricing_policy.get("tax_policy_label"),
        "billing_cycle": pricing_policy.get("billing_cycle"),
        "billing_cycle_label": pricing_policy.get("billing_cycle_label"),
        "additional_vat_percent": str(vat_percent.quantize(Decimal("0.01"))),
        "price_note": pricing_policy.get("price_note") or "",
        "subtotal": subtotal.quantize(Decimal("0.01")),
        "vat_percent": vat_percent.quantize(Decimal("0.01")),
        "vat_amount": vat_amount.quantize(Decimal("0.01")),
        "total": total,
        "lines": lines,
    }


def _requirement_attachment_count(req: VerificationRequirement) -> int:
    cached = getattr(req, "_prefetched_objects_cache", {}).get("attachments")
    if cached is not None:
        return len(cached)
    return req.attachments.count()


def verification_request_blocking_open_request_for_badge(
    user,
    badge_type: str,
    *,
    exclude_request_id: int | None = None,
) -> VerificationRequest | None:
    normalized_badge = str(badge_type or "").strip().lower()
    if normalized_badge not in VerificationBadgeType.values or not getattr(user, "pk", None):
        return None

    qs = VerificationRequest.objects.filter(
        requester=user,
        status__in=VERIFICATION_BLOCKING_REQUEST_STATUSES,
    )
    if exclude_request_id:
        qs = qs.exclude(pk=exclude_request_id)

    return (
        qs.filter(
            Q(badge_type=normalized_badge) | Q(requirements__badge_type=normalized_badge)
        )
        .distinct()
        .order_by("-requested_at", "-id")
        .first()
    )


def verification_request_has_blocking_open_request(user, badge_type: str, *, exclude_request_id: int | None = None) -> bool:
    return verification_request_blocking_open_request_for_badge(
        user,
        badge_type,
        exclude_request_id=exclude_request_id,
    ) is not None


def _verification_user_handle(user) -> str:
    label = (getattr(user, "username", "") or getattr(user, "phone", "") or f"user-{getattr(user, 'id', '')}").strip()
    if label and not label.startswith("@"):
        label = f"@{label}"
    return label or "غير محدد"


@transaction.atomic
def deactivate_verified_badge(*, badge: VerifiedBadge, by_user=None) -> VerifiedBadge:
    badge = VerifiedBadge.objects.select_for_update().select_related("user", "request").get(pk=badge.pk)
    if not badge.is_active:
        return badge

    badge.is_active = False
    badge.save(update_fields=["is_active"])
    _sync_verification_to_unified(vr=badge.request, changed_by=by_user or badge.user)
    return badge


@transaction.atomic
def create_renewal_request_from_verified_badge(*, badge: VerifiedBadge, assigned_to=None, by_user=None) -> VerificationRequest:
    badge = VerifiedBadge.objects.select_for_update().select_related("user", "request", "request__blue_profile").get(pk=badge.pk)
    if not badge.is_active:
        raise ValueError("سجل التوثيق المحدد غير مفعل أو تم حذفه من القائمة.")

    if verification_request_has_blocking_open_request(
        badge.user,
        badge.badge_type,
        exclude_request_id=badge.request_id,
    ):
        raise ValueError("يوجد طلب توثيق قائم لنفس نوع الشارة، أكمل معالجته أولًا قبل إنشاء طلب تجديد جديد.")

    source_request = badge.request
    source_requirements = list(
        source_request.requirements.order_by("sort_order", "id").prefetch_related("attachments")
    )
    source_requirement = next((item for item in source_requirements if item.code == badge.verification_code), None)
    requirement_def = resolve_requirement_def(
        badge.badge_type,
        badge.verification_code or ("B1" if badge.badge_type == VerificationBadgeType.BLUE else "G1"),
    )
    requirement_title = (
        (source_requirement.title if source_requirement is not None else "")
        or (badge.verification_title or "")
        or requirement_def["title"]
    )[:220]

    renewal_request = VerificationRequest.objects.create(
        requester=badge.user,
        assigned_to=assigned_to,
        assigned_at=timezone.now() if assigned_to else None,
        badge_type=badge.badge_type,
        priority=int(getattr(source_request, "priority", 2) or 2),
        status=VerificationStatus.NEW,
        admin_note=f"طلب تجديد لسجل {badge.verification_code} للحساب {_verification_user_handle(badge.user)}"[:300],
    )

    renewal_requirement = VerificationRequirement.objects.create(
        request=renewal_request,
        badge_type=badge.badge_type,
        code=requirement_def["code"],
        title=requirement_title,
        evidence_expires_at=(source_requirement.evidence_expires_at if source_requirement is not None else None),
        sort_order=0,
    )

    if source_requirement is not None:
        source_attachments = list(getattr(source_requirement, "_prefetched_objects_cache", {}).get("attachments") or source_requirement.attachments.all())
        for attachment in source_attachments:
            VerificationRequirementAttachment.objects.create(
                requirement=renewal_requirement,
                file=attachment.file.name,
                uploaded_by=by_user or attachment.uploaded_by,
            )

    source_blue_profile = getattr(source_request, "blue_profile", None)
    if badge.badge_type == VerificationBadgeType.BLUE and source_blue_profile is not None:
        VerificationBlueProfile.objects.create(
            request=renewal_request,
            subject_type=source_blue_profile.subject_type,
            official_number=source_blue_profile.official_number,
            official_date=source_blue_profile.official_date,
            verified_name=source_blue_profile.verified_name,
            is_name_approved=source_blue_profile.is_name_approved,
            verification_source=source_blue_profile.verification_source or "elm",
            verified_at=source_blue_profile.verified_at,
        )

        for document in source_request.documents.order_by("id"):
            VerificationDocument.objects.create(
                request=renewal_request,
                doc_type=document.doc_type,
                title=document.title,
                file=document.file.name,
                uploaded_by=by_user or document.uploaded_by,
            )

    _sync_verification_to_unified(vr=renewal_request, changed_by=by_user or assigned_to or badge.user)
    return renewal_request


@transaction.atomic
def mark_request_in_review(*, vr: VerificationRequest, changed_by=None) -> VerificationRequest:
    vr = VerificationRequest.objects.select_for_update().get(pk=vr.pk)
    if vr.status not in (VerificationStatus.NEW, VerificationStatus.REJECTED):
        return vr

    vr.status = VerificationStatus.IN_REVIEW
    vr.save(update_fields=["status", "updated_at"])
    _sync_verification_to_unified(vr=vr, changed_by=changed_by)
    return vr


def _document_target_badge_types(vr: VerificationRequest, doc_type: str) -> set[str]:
    if vr.badge_type in VerificationBadgeType.values:
        return {vr.badge_type}

    normalized_doc_type = str(doc_type or "").strip().lower()
    if normalized_doc_type in {"id", "cr", "iban"}:
        return {VerificationBadgeType.BLUE}
    if normalized_doc_type in {"license"}:
        return {VerificationBadgeType.GREEN}

    req_badges = {
        str(req.badge_type or "").strip().lower()
        for req in vr.requirements.all()
        if str(req.badge_type or "").strip().lower() in VerificationBadgeType.values
    }
    return req_badges or set(VerificationBadgeType.values)


@transaction.atomic
def mirror_document_to_requirement_attachments(*, doc: VerificationDocument) -> list[VerificationRequirementAttachment]:
    doc = VerificationDocument.objects.select_for_update().select_related("request").get(pk=doc.pk)
    vr = doc.request
    reqs = list(vr.requirements.all().order_by("sort_order", "id"))
    if not reqs:
        return []

    target_badges = _document_target_badge_types(vr, doc.doc_type)
    target_requirements = [req for req in reqs if req.badge_type in target_badges] or reqs

    created: list[VerificationRequirementAttachment] = []
    for req in target_requirements:
        created.append(
            VerificationRequirementAttachment.objects.create(
                requirement=req,
                file=doc.file.name,
                uploaded_by=doc.uploaded_by,
            )
        )
    return created


def verification_request_has_authoritative_evidence(*, vr: VerificationRequest, reqs=None, docs=None) -> bool:
    requirements = list(reqs) if reqs is not None else list(vr.requirements.all())
    if requirements:
        return any(_requirement_attachment_count(req) > 0 for req in requirements)

    documents = list(docs) if docs is not None else list(vr.documents.all())
    return bool(documents)


def sync_verification_request_badge_state(*, vr: VerificationRequest, now=None) -> int:
    vr = VerificationRequest.objects.select_related("requester", "invoice").get(pk=vr.pk)
    current_time = now or timezone.now()

    should_keep_badges_active = (
        vr.status == VerificationStatus.ACTIVE
        and vr.activated_at is not None
        and vr.expires_at is not None
        and vr.expires_at > current_time
        and vr.invoice is not None
        and vr.invoice.is_payment_effective()
    )
    if should_keep_badges_active:
        sync_provider_badges(vr.requester)
        return 0

    changed = VerifiedBadge.objects.filter(request=vr, is_active=True).update(is_active=False)
    sync_provider_badges(vr.requester)
    return changed


def verification_pricing_for_plan(plan=None) -> dict[str, object]:
    try:
        from apps.subscriptions.services import plan_to_tier
    except Exception:
        plan_to_tier = None

    template_plan = template_subscription_plan_for_plan(plan, fallback_tier=CanonicalPlanTier.BASIC)
    pricing_plan = plan or template_plan
    plan_code = (getattr(pricing_plan, "code", "") or "").strip().upper()
    plan_tier = (
        plan_to_tier(pricing_plan) if plan_to_tier and pricing_plan is not None else CanonicalPlanTier.BASIC
    )
    normalized_tier = canonical_tier_from_value(plan_tier, fallback=CanonicalPlanTier.BASIC) or CanonicalPlanTier.BASIC
    pricing_policy = verification_billing_policy()

    prices = {}
    for badge_type, field_name in (
        (VerificationBadgeType.BLUE, "verification_blue_fee"),
        (VerificationBadgeType.GREEN, "verification_green_fee"),
    ):
        amount_decimal = resolved_plan_decimal(plan, template_plan, field_name, default="0.00")
        prices[badge_type] = {
            "badge_type": badge_type,
            "amount": str(amount_decimal.quantize(Decimal("0.01"))),
            "final_amount": str(amount_decimal.quantize(Decimal("0.01"))),
            "is_free": amount_decimal <= Decimal("0.00"),
            "requires_payment": amount_decimal > Decimal("0.00"),
            "billing_cycle": pricing_policy["billing_cycle"],
            "tax_included": pricing_policy["tax_included"],
            "additional_vat_percent": pricing_policy["additional_vat_percent"],
        }

    return {
        "plan_code": plan_code.lower(),
        "tier": normalized_tier,
        "tier_legacy": db_tier_for_canonical(normalized_tier),
        "tier_label": canonical_tier_label(normalized_tier),
        **pricing_policy,
        "prices": prices,
    }


def verification_price_amount(pricing: dict[str, object], badge_type: str, *, prefer_final: bool = False) -> str:
    price_entry = ((pricing.get("prices") or {}).get(badge_type) or {})
    primary_key = "final_amount" if prefer_final else "amount"
    fallback_key = "amount" if prefer_final else "final_amount"
    value = price_entry.get(primary_key)
    if value is None:
        value = price_entry.get(fallback_key)
    return str(value if value is not None else "0.00")


def verification_pricing_for_user(user) -> dict[str, object]:
    try:
        from apps.subscriptions.services import get_effective_active_subscription
    except Exception:
        return verification_pricing_for_plan(None)

    active_sub = get_effective_active_subscription(user)
    pricing = verification_pricing_for_plan(getattr(active_sub, "plan", None))
    pricing["has_active_subscription"] = active_sub is not None
    if active_sub is not None:
        pricing["subscription_id"] = active_sub.id
    return pricing


def _fee_for_user_and_badge(user, badge_type: str) -> Decimal:
    """
    رسوم التوثيق منفصلة عن الاشتراك، لكن الاشتراك يؤثر على سعرها.
    الرسم النهائي سنوي ويُحتسب لكل بند توثيق معتمد وفق فئة الباقة الحالية.
    """
    pricing = verification_pricing_for_user(user)
    entry = (pricing.get("prices") or {}).get(badge_type, {})
    amount = (entry or {}).get("amount")
    if amount is None:
        return _fee_for_badge(badge_type)
    return Decimal(str(amount))


def _verification_default_payment_provider() -> str:
    configured = str(getattr(settings, "BILLING_DEFAULT_PROVIDER", "") or "").strip().lower()
    if configured in PaymentProvider.values:
        return configured
    return PaymentProvider.MOCK


def _ensure_checkout_attempt(*, invoice: Invoice, by_user):
    latest_attempt = (
        PaymentAttempt.objects.filter(invoice=invoice)
        .exclude(checkout_url="")
        .order_by("-created_at")
        .first()
    )
    if latest_attempt is not None:
        legacy_checkout_url = str(getattr(latest_attempt, "checkout_url", "") or "").strip().lower()
        if "example-pay.local" in legacy_checkout_url:
            # Repair legacy mock links generated before introducing local checkout routes.
            from apps.billing.services import _make_checkout_url

            latest_attempt.checkout_url = _make_checkout_url(latest_attempt.provider, str(latest_attempt.id))
            latest_attempt.save(update_fields=["checkout_url"])
        return latest_attempt

    from apps.billing.services import init_payment

    return init_payment(
        invoice=invoice,
        provider=_verification_default_payment_provider(),
        by_user=by_user or invoice.user,
        idempotency_key=f"verify-request-{invoice.id}",
    )


def verification_payment_page_url(*, vr: VerificationRequest) -> str:
    params: dict[str, str] = {}
    if getattr(vr, "id", None):
        params["request_id"] = str(vr.id)
    if getattr(vr, "invoice_id", None):
        params["invoice_id"] = str(vr.invoice_id)
    base_path = "/verification/payment/"
    if not params:
        return base_path
    return f"{base_path}?{urlencode(params)}"


def _get_or_create_provider_direct_thread(*, user_a, user_b):
    from apps.messaging.models import Thread

    if not user_a or not user_b or user_a.id == user_b.id:
        return None

    thread = (
        Thread.objects.filter(is_direct=True, context_mode=Thread.ContextMode.PROVIDER)
        .filter(
            Q(participant_1=user_a, participant_2=user_b)
            | Q(participant_1=user_b, participant_2=user_a)
        )
        .order_by("-id")
        .first()
    )
    if thread is not None:
        return thread

    return Thread.objects.create(
        is_direct=True,
        context_mode=Thread.ContextMode.PROVIDER,
        participant_1=user_a,
        participant_2=user_b,
    )


def _send_verification_system_message(*, vr: VerificationRequest, sender, body: str):
    from apps.messaging.models import Message
    from apps.messaging.views import _unarchive_for_participants

    thread = _get_or_create_provider_direct_thread(user_a=sender, user_b=vr.requester)
    if thread is None:
        return None

    Message.objects.create(
        thread=thread,
        sender=sender,
        body=(body or "")[:2000],
        created_at=timezone.now(),
    )
    _unarchive_for_participants(thread)
    return thread


def _verification_rejection_reason_lines(reqs) -> list[str]:
    lines: list[str] = []
    for requirement in reqs or []:
        if requirement.is_approved is not False:
            continue
        reason = (requirement.decision_note or "").strip() or "لم يتم استيفاء متطلبات هذا البند."
        lines.append(f"- {requirement.code}: {reason}")
    return lines


def _notify_requester_review_outcome(*, vr: VerificationRequest, by_user, reqs=None) -> None:
    try:
        from apps.notifications.models import EventType
        from apps.notifications.services import create_notification
    except Exception:
        return

    requirements = list(reqs) if reqs is not None else list(vr.requirements.all())
    approved_count = sum(1 for item in requirements if item.is_approved is True)
    rejected_count = sum(1 for item in requirements if item.is_approved is False)
    request_code = vr.code or f"AD{vr.id:06d}"
    actor = by_user or getattr(vr, "assigned_to", None) or vr.requester
    thread = None
    notification_url = "/verification/"
    notification_title = ""
    notification_body = ""
    notification_kind = "info"
    message_body = ""
    payment_page_url = verification_payment_page_url(vr=vr)
    payment_link = ""

    if vr.status == VerificationStatus.PENDING_PAYMENT and vr.invoice_id:
        # Checkout link generation is best-effort and must not block request finalization.
        try:
            attempt = _ensure_checkout_attempt(invoice=vr.invoice, by_user=actor)
            payment_link = str(getattr(attempt, "checkout_url", "") or "").strip()
        except Exception:
            payment_link = ""
        notification_title = "استكمال رسوم التوثيق"
        notification_body = (
            f"تهانينا، تم اعتماد طلب التوثيق ({request_code}) وإصدار فاتورة بانتظار الدفع. "
            "افتح صفحة الدفع لإكمال السداد."
        )
        notification_kind = "info"

        message_lines = [
            f"رسالة آلية من فريق التوثيق بخصوص الطلب {request_code}.",
            "تهانينا، تمت الموافقة على طلب التوثيق.",
            f"تم اعتماد {approved_count} بند/بنود من طلب التوثيق.",
        ]
        if rejected_count:
            message_lines.append(f"تم رفض {rejected_count} بند/بنود أخرى بعد المراجعة.")
            message_lines.append("البنود المرفوضة وأسبابها:")
            message_lines.extend(_verification_rejection_reason_lines(requirements)[:6])
        if vr.invoice_id:
            invoice_code = vr.invoice.code or f"IV{vr.invoice_id:06d}"
            message_lines.append(f"رقم الفاتورة: {invoice_code}")
        message_lines.append(f"صفحة الدفع: {payment_page_url}")
        message_body = "\n".join(message_lines)
    elif vr.status == VerificationStatus.REJECTED:
        notification_title = "رفض طلب التوثيق"
        notification_body = f"تم رفض طلب التوثيق ({request_code}). افتح الرسالة النظامية لمراجعة أسباب الرفض."
        notification_kind = "error"

        message_lines = [
            f"رسالة آلية من فريق التوثيق بخصوص الطلب {request_code}.",
            "تم رفض طلب التوثيق بعد مراجعة البنود والمرفقات.",
        ]
        if (vr.reject_reason or "").strip():
            message_lines.append(f"ملخص القرار: {(vr.reject_reason or '').strip()}")
        message_lines.extend(_verification_rejection_reason_lines(requirements)[:4])
        message_body = "\n".join(message_lines)
    elif vr.status == VerificationStatus.ACTIVE:
        notification_title = "اكتمل طلب التوثيق"
        notification_body = f"تم اعتماد طلب التوثيق ({request_code}) وتفعيل التوثيق على الحساب بنجاح."
        notification_kind = "success"
        message_lines = [
            f"رسالة آلية من فريق التوثيق بخصوص الطلب {request_code}.",
            "تهانينا، تم اعتماد طلب التوثيق وتفعيل الشارة على حسابك بنجاح.",
        ]
        if rejected_count:
            message_lines.append(f"تم رفض {rejected_count} بند/بنود ضمن نفس الطلب.")
            message_lines.append("البنود المرفوضة وأسبابها:")
            message_lines.extend(_verification_rejection_reason_lines(requirements)[:6])
        message_body = "\n".join(message_lines)
    else:
        return

    if actor is not None and getattr(actor, "id", None) != vr.requester_id and message_body:
        try:
            thread = _send_verification_system_message(vr=vr, sender=actor, body=message_body)
        except Exception:
            thread = None

    if vr.status == VerificationStatus.PENDING_PAYMENT:
        notification_url = payment_page_url
    elif thread is not None:
        notification_url = f"/chat/{thread.id}/"
    elif payment_link:
        notification_url = payment_link

    try:
        create_notification(
            user=vr.requester,
            title=notification_title,
            body=notification_body,
            kind=notification_kind,
            url=notification_url,
            actor=actor,
            event_type=EventType.STATUS_CHANGED,
            request_id=vr.id,
            meta={
                "verification_request_id": vr.id,
                "verification_request_code": request_code,
                "status": vr.status,
                "invoice_id": vr.invoice_id,
                "thread_id": getattr(thread, "id", None),
                "approved_count": approved_count,
                "rejected_count": rejected_count,
            },
            pref_key="verification_completed",
            audience_mode="provider",
        )
    except Exception:
        pass


@transaction.atomic
def decide_document(*, doc: VerificationDocument, is_approved: bool, note: str, by_user):
    doc = VerificationDocument.objects.select_for_update().select_related("request").get(pk=doc.pk)
    if doc.request.requirements.exists():
        raise ValueError("اعتماد التوثيق يتم عبر بنود التوثيق ومرفقاتها، وليس عبر المستندات legacy.")
    doc.is_approved = bool(is_approved)
    doc.decision_note = (note or "")[:300]
    doc.decided_by = by_user
    doc.decided_at = timezone.now()
    doc.save(update_fields=["is_approved", "decision_note", "decided_by", "decided_at"])
    mark_request_in_review(vr=doc.request, changed_by=by_user)
    return doc


@transaction.atomic
def decide_requirement(
    *,
    req: VerificationRequirement,
    is_approved: bool,
    note: str,
    by_user,
    evidence_expires_at=None,
):
    req = VerificationRequirement.objects.select_for_update().get(pk=req.pk)
    req.is_approved = bool(is_approved)
    req.decision_note = (note or "")[:300]
    req.evidence_expires_at = evidence_expires_at
    req.decided_by = by_user
    req.decided_at = timezone.now()
    req.save(update_fields=["is_approved", "decision_note", "evidence_expires_at", "decided_by", "decided_at"])
    mark_request_in_review(vr=req.request, changed_by=by_user)
    return req


@transaction.atomic
def finalize_request_and_create_invoice(*, vr: VerificationRequest, by_user):
    """
    اعتماد الطلب إذا:
    - كل المستندات تم اتخاذ قرار عليها
    - ولا يوجد أي مستند مرفوض
    ثم:
    - إنشاء فاتورة
    - تحويل الطلب إلى pending_payment إذا كانت الرسوم أكبر من صفر
    - أو تفعيل الشارة مباشرة إذا كانت الرسوم مجانية حسب الباقة
    """
    vr = VerificationRequest.objects.select_for_update().get(pk=vr.pk)

    reqs = list(vr.requirements.prefetch_related("attachments").all())

    if not reqs:
        docs = list(vr.documents.all())
        if not docs:
            raise ValueError("لا توجد مستندات/بنود مرفوعة لهذا الطلب.")

        undecided_docs = [d for d in docs if d.is_approved is None]
        if undecided_docs:
            raise ValueError("يوجد مستندات legacy لم يتم اتخاذ قرار بشأنها بعد.")

        approved_docs = [d for d in docs if d.is_approved is True]
        if not approved_docs:
            vr.reviewed_at = timezone.now()
            vr.status = VerificationStatus.REJECTED
            vr.reject_reason = "تم رفض جميع مستندات التوثيق."
            vr.save(update_fields=["status", "reject_reason", "reviewed_at", "updated_at"])
            _sync_verification_to_unified(vr=vr, changed_by=by_user)
            _notify_requester_review_outcome(vr=vr, by_user=by_user, reqs=[])
            return vr

        bt = vr.badge_type or VerificationBadgeType.BLUE
        definition = resolve_requirement_def(bt, "B1" if bt == VerificationBadgeType.BLUE else "G1")
        legacy_req = VerificationRequirement.objects.create(
            request=vr,
            badge_type=bt,
            code=definition["code"],
            title=definition["title"],
            is_approved=True,
            decision_note="اعتماد مسار legacy بعد مراجعة المستندات.",
            decided_by=by_user,
            decided_at=timezone.now(),
        )
        for doc in approved_docs:
            VerificationRequirementAttachment.objects.create(
                requirement=legacy_req,
                file=doc.file.name,
                uploaded_by=doc.uploaded_by,
            )
        reqs = list(
            VerificationRequirement.objects.filter(pk=legacy_req.pk).prefetch_related("attachments")
        )

    undecided = [r for r in reqs if r.is_approved is None]
    if undecided:
        raise ValueError("يوجد بنود لم يتم اتخاذ قرار بشأنها بعد.")

    approved_items = [r for r in reqs if r.is_approved is True]
    rejected_items = [r for r in reqs if r.is_approved is False]
    approved_without_evidence = [r for r in approved_items if _requirement_attachment_count(r) <= 0]
    if approved_without_evidence:
        raise ValueError("يوجد بنود معتمدة بدون مرفقات إثبات.")

    includes_blue = (
        vr.badge_type == VerificationBadgeType.BLUE
        or any(req.badge_type == VerificationBadgeType.BLUE for req in reqs)
    )
    if includes_blue and not hasattr(vr, "blue_profile"):
        raise ValueError("لا يمكن اعتماد طلب يتضمن الشارة الزرقاء بدون بيانات الشارة الزرقاء المعتمدة.")

    vr.reviewed_at = timezone.now()

    if not approved_items:
        vr.status = VerificationStatus.REJECTED
        vr.reject_reason = "تم رفض جميع بنود التوثيق."
        vr.save(update_fields=["status", "reject_reason", "reviewed_at", "updated_at"])
        _sync_verification_to_unified(vr=vr, changed_by=by_user)
        _notify_requester_review_outcome(vr=vr, by_user=by_user, reqs=reqs)
        return vr

    vr.status = VerificationStatus.APPROVED
    vr.approved_at = timezone.now()
    if rejected_items and not vr.reject_reason:
        vr.reject_reason = "تم رفض بعض البنود."
    vr.save(update_fields=["status", "approved_at", "reviewed_at", "reject_reason", "updated_at"])

    # Create invoice rows per approved verification item so the ops summary
    # matches the exact codes approved by the review team.
    if not vr.invoice_id:
        invoice_preview = verification_invoice_preview_for_request(vr=vr)
        inv = Invoice.objects.create(
            user=vr.requester,
            title="رسوم التوثيق",
            description="رسوم التوثيق السنوية",
            subtotal=Decimal("0.00"),
            vat_percent=VERIFICATION_ADDITIONAL_VAT_PERCENT,
            reference_type="verify_request",
            reference_id=vr.code,
            status=InvoiceStatus.DRAFT,
        )
        for line in invoice_preview["lines"]:
            InvoiceLineItem.objects.create(
                invoice=inv,
                item_code=str(line["item_code"]),
                title=str(line["title"]),
                amount=Decimal(str(line["amount"])),
                sort_order=int(line["sort_order"]),
            )
        inv.recalc()

        vr.invoice = inv
        vr.save(update_fields=["invoice", "updated_at"])

        if inv.total > Decimal("0.00"):
            inv.mark_pending()
            inv.save(update_fields=["status", "subtotal", "vat_percent", "vat_amount", "total", "updated_at"])

            vr.status = VerificationStatus.PENDING_PAYMENT
            vr.save(update_fields=["status", "updated_at"])
        else:
            inv.mark_paid(when=timezone.now())
            inv.save(update_fields=["status", "paid_at", "subtotal", "vat_percent", "vat_amount", "total", "updated_at"])
            vr = activate_after_payment(vr=vr)

        _sync_verification_to_unified(vr=vr, changed_by=by_user)
        _notify_requester_review_outcome(vr=vr, by_user=by_user, reqs=reqs)
    return vr


@transaction.atomic
def activate_after_payment(*, vr: VerificationRequest, notify_requester: bool = False, changed_by=None):
    """
    تفعيل الشارة بعد الدفع:
    - إنشاء VerifiedBadge
    - تحديث flags على ProviderProfile إن وجد
    """
    vr = VerificationRequest.objects.select_for_update().select_related("invoice", "requester").get(pk=vr.pk)

    if not vr.invoice or not vr.invoice.is_payment_effective():
        raise ValueError("الفاتورة غير مدفوعة بعد.")

    if vr.status not in (
        VerificationStatus.APPROVED,
        VerificationStatus.PENDING_PAYMENT,
        VerificationStatus.ACTIVE,
    ):
        raise ValueError("لا يمكن التفعيل قبل اعتماد الطلب.")

    approved = list(vr.requirements.prefetch_related("attachments").filter(is_approved=True))
    if not approved:
        raise ValueError("لا توجد بنود معتمدة قابلة للتفعيل.")

    approved_without_evidence = [item for item in approved if _requirement_attachment_count(item) <= 0]
    if approved_without_evidence:
        raise ValueError("لا يمكن التفعيل بدون مرفقات إثبات للبنود المعتمدة.")

    if vr.status == VerificationStatus.ACTIVE:
        return vr

    now = timezone.now()
    vr.activated_at = now
    vr.expires_at = now + vr.activation_window()
    vr.status = VerificationStatus.ACTIVE
    vr.save(update_fields=["activated_at", "expires_at", "status", "updated_at"])

    # Deactivate previous active items by code.
    for item in approved:
        VerifiedBadge.objects.filter(
            user=vr.requester,
            verification_code=item.code,
            is_active=True,
        ).update(is_active=False)

    for item in approved:
        VerifiedBadge.objects.create(
            user=vr.requester,
            badge_type=item.badge_type,
            verification_code=item.code,
            verification_title=item.title,
            request=vr,
            activated_at=now,
            expires_at=vr.expires_at,
            is_active=True,
        )

    # Update ProviderProfile flags from source-of-truth badge records.
    sync_provider_badges(vr.requester)

    if notify_requester:
        try:
            _notify_requester_review_outcome(
                vr=vr,
                by_user=changed_by,
                reqs=list(vr.requirements.all()),
            )
        except Exception:
            pass

    _sync_verification_to_unified(vr=vr, changed_by=vr.requester)
    return vr


@transaction.atomic
def revoke_after_payment_reversal(*, vr: VerificationRequest):
    vr = VerificationRequest.objects.select_for_update().select_related("invoice").get(pk=vr.pk)

    if not vr.invoice or vr.invoice.is_payment_effective():
        return vr

    if vr.invoice.requires_payment_confirmation():
        vr.status = VerificationStatus.PENDING_PAYMENT
    elif vr.status == VerificationStatus.ACTIVE:
        vr.status = VerificationStatus.APPROVED
    vr.activated_at = None
    vr.expires_at = None
    vr.save(update_fields=["status", "activated_at", "expires_at", "updated_at"])

    sync_verification_request_badge_state(vr=vr)

    try:
        from apps.audit.services import log_action
        from apps.audit.models import AuditAction

        log_action(
            actor=vr.requester,
            action=AuditAction.VERIFY_REQUEST_PAYMENT_REVOKED,
            reference_type="verification",
            reference_id=str(vr.pk),
            extra={
                "verification_code": vr.code,
                "invoice_id": vr.invoice_id,
                "invoice_status": getattr(vr.invoice, "status", ""),
            },
        )
    except Exception:
        pass

    _sync_verification_to_unified(vr=vr, changed_by=vr.requester)
    return vr
