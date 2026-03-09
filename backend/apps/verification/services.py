from __future__ import annotations

from decimal import Decimal
from django.conf import settings
from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from apps.billing.models import Invoice, InvoiceStatus
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
            "title": "توثيق كفؤ (عبر أبشر لمن يعمل في توصيل الطلبات أو النقل التشاركي ويستخدم مركبته الخاصة)",
        },
    },
}


BADGE_PUBLIC_DEFINITIONS: dict[str, dict[str, str]] = {
    VerificationBadgeType.BLUE: {
        "badge_type": VerificationBadgeType.BLUE,
        "title": "الشارة الزرقاء",
        "short_description": "توثيق الهوية أو السجل التجاري من مصادر سعودية رسمية.",
        "explanation": "تعني أن مقدم الخدمة أكمل التحقق الأساسي لهويته أو سجله التجاري داخل المملكة.",
    },
    VerificationBadgeType.GREEN: {
        "badge_type": VerificationBadgeType.GREEN,
        "title": "الشارة الخضراء",
        "short_description": "توثيق الكفاءة المهنية أو الاعتماد التنظيمي وفق متطلبات المجال.",
        "explanation": "تعني أن مقدم الخدمة قدم واعتمد أدلة كفاءة مهنية أو ترخيص/اعتماد مرتبط بخدمته.",
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
    الرسم المرجعي يأتي من canonical basic plan داخل قاعدة البيانات.
    """
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
        "currency": VERIFICATION_PRICING_CURRENCY,
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


def _requirement_attachment_count(req: VerificationRequirement) -> int:
    cached = getattr(req, "_prefetched_objects_cache", {}).get("attachments")
    if cached is not None:
        return len(cached)
    return req.attachments.count()


def verification_request_has_blocking_open_request(user, badge_type: str, *, exclude_request_id: int | None = None) -> bool:
    normalized_badge = str(badge_type or "").strip().lower()
    if normalized_badge not in VerificationBadgeType.values or not getattr(user, "pk", None):
        return False

    qs = VerificationRequest.objects.filter(
        requester=user,
        status__in=VERIFICATION_BLOCKING_REQUEST_STATUSES,
    )
    if exclude_request_id:
        qs = qs.exclude(pk=exclude_request_id)

    return qs.filter(
        Q(badge_type=normalized_badge) | Q(requirements__badge_type=normalized_badge)
    ).distinct().exists()


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
    doc = VerificationDocument.objects.select_for_update().select_related("request", "uploaded_by").get(pk=doc.pk)
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
    الرسم النهائي سنوي ويُحتسب مرة واحدة لكل طلب/شارة وفق فئة الباقة الحالية.
    """
    pricing = verification_pricing_for_user(user)
    entry = (pricing.get("prices") or {}).get(badge_type, {})
    amount = (entry or {}).get("amount")
    if amount is None:
        return _fee_for_badge(badge_type)
    return Decimal(str(amount))


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
    return doc


@transaction.atomic
def decide_requirement(*, req: VerificationRequirement, is_approved: bool, note: str, by_user):
    req = VerificationRequirement.objects.select_for_update().get(pk=req.pk)
    req.is_approved = bool(is_approved)
    req.decision_note = (note or "")[:300]
    req.decided_by = by_user
    req.decided_at = timezone.now()
    req.save(update_fields=["is_approved", "decision_note", "decided_by", "decided_at"])
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

    vr.reviewed_at = timezone.now()

    if not approved_items:
        vr.status = VerificationStatus.REJECTED
        vr.reject_reason = "تم رفض جميع بنود التوثيق."
        vr.save(update_fields=["status", "reject_reason", "reviewed_at", "updated_at"])
        _sync_verification_to_unified(vr=vr, changed_by=by_user)
        return vr

    vr.status = VerificationStatus.APPROVED
    vr.approved_at = timezone.now()
    if rejected_items and not vr.reject_reason:
        vr.reject_reason = "تم رفض بعض البنود."
    vr.save(update_fields=["status", "approved_at", "reviewed_at", "reject_reason", "updated_at"])

    # Create invoice once per approved badge flow, not per approved requirement.
    if not vr.invoice_id:
        pricing_snapshot = verification_pricing_for_user(vr.requester)
        pricing_by_badge = pricing_snapshot.get("prices") or {}
        approved_badge_types = _ordered_unique_badge_types(
            item.badge_type for item in approved_items
        )
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
        for idx, badge_type in enumerate(approved_badge_types):
            fee_payload = pricing_by_badge.get(badge_type) or {}
            fee = Decimal(str(fee_payload.get("amount", _fee_for_badge(badge_type))))
            InvoiceLineItem.objects.create(
                invoice=inv,
                item_code=_badge_billing_code(badge_type),
                title=_badge_billing_title(badge_type),
                amount=fee,
                sort_order=idx,
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
    return vr


@transaction.atomic
def activate_after_payment(*, vr: VerificationRequest):
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
