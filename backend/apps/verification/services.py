from __future__ import annotations

from decimal import Decimal
from django.conf import settings
from django.db import transaction
from django.utils import timezone

from apps.billing.models import Invoice, InvoiceStatus
from apps.billing.models import InvoiceLineItem

from .models import (
    VerificationRequest, VerificationDocument,
    VerificationStatus, VerifiedBadge, VerificationBadgeType,
    VerificationRequirement,
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

    expired_badges = list(
        VerifiedBadge.objects.filter(is_active=True, expires_at__lte=now)
        .order_by("id")[:limit]
    )
    if not expired_badges:
        return 0

    expired_ids = [badge.id for badge in expired_badges]
    user_ids = sorted({badge.user_id for badge in expired_badges if badge.user_id})
    VerifiedBadge.objects.filter(id__in=expired_ids).update(is_active=False)

    if user_ids:
        from apps.accounts.models import User

        for user in User.objects.filter(id__in=user_ids):
            sync_provider_badges(user)

    return len(expired_ids)


def _fee_for_badge(badge_type: str) -> Decimal:
    """
    رسوم افتراضية (قابلة للتخصيص من settings لاحقًا).
    - الأزرق: 100
    - الأخضر: 100
    """
    blue_fee = getattr(settings, "VERIFY_BLUE_FEE", Decimal("100.00"))
    green_fee = getattr(settings, "VERIFY_GREEN_FEE", Decimal("100.00"))
    if badge_type == VerificationBadgeType.GREEN:
        return Decimal(str(green_fee))
    return Decimal(str(blue_fee))


def _fee_for_user_and_badge(user, badge_type: str) -> Decimal:
    """
    رسوم التوثيق حسب الباقة (إن وُجدت) مع fallback للرسوم الثابتة.

    settings.VERIFY_FEES_BY_PLAN مثال:
    {
        "BASIC": {"blue": "120.00", "green": "60.00"},
        "PRO": {"blue": "80.00", "green": "40.00"},
    }
    """
    try:
        from apps.subscriptions.models import Subscription, SubscriptionStatus
    except Exception:
        return _fee_for_badge(badge_type)

    active_sub = (
        Subscription.objects.filter(user=user, status=SubscriptionStatus.ACTIVE)
        .select_related("plan")
        .order_by("-id")
        .first()
    )
    if not active_sub or not getattr(active_sub, "plan", None):
        return _fee_for_badge(badge_type)

    plan_code = ((active_sub.plan.code or "") if active_sub.plan else "").strip().upper()
    if not plan_code:
        return _fee_for_badge(badge_type)

    raw_matrix = getattr(settings, "VERIFY_FEES_BY_PLAN", {}) or {}
    # Normalize top-level keys to uppercase for safer matching.
    matrix = {str(k).strip().upper(): (v or {}) for k, v in raw_matrix.items()}
    plan_fees = matrix.get(plan_code, {}) or {}
    amount = plan_fees.get(badge_type)
    if amount is None:
        amount = plan_fees.get(str(badge_type).lower())
    if amount is None:
        return _fee_for_badge(badge_type)
    return Decimal(str(amount))


@transaction.atomic
def decide_document(*, doc: VerificationDocument, is_approved: bool, note: str, by_user):
    doc = VerificationDocument.objects.select_for_update().get(pk=doc.pk)
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
    - إنشاء فاتورة + تحويل الطلب إلى pending_payment
    """
    vr = VerificationRequest.objects.select_for_update().get(pk=vr.pk)

    reqs = list(vr.requirements.all())
    if not reqs:
        # Legacy fallback: treat as single item if documents exist.
        docs = list(vr.documents.all())
        if not docs:
            raise ValueError("لا توجد مستندات/بنود مرفوعة لهذا الطلب.")
        # Create a synthetic requirement to proceed.
        bt = vr.badge_type or VerificationBadgeType.BLUE
        definition = resolve_requirement_def(bt, "B1" if bt == VerificationBadgeType.BLUE else "G1")
        reqs = [
            VerificationRequirement.objects.create(
                request=vr,
                badge_type=bt,
                code=definition["code"],
                title=definition["title"],
                is_approved=True,
                decision_note="",
                decided_by=by_user,
                decided_at=timezone.now(),
            )
        ]

    undecided = [r for r in reqs if r.is_approved is None]
    if undecided:
        raise ValueError("يوجد بنود لم يتم اتخاذ قرار بشأنها بعد.")

    approved_items = [r for r in reqs if r.is_approved is True]
    rejected_items = [r for r in reqs if r.is_approved is False]

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

    # Create invoice with line items per approved requirement.
    if not vr.invoice_id:
        inv = Invoice.objects.create(
            user=vr.requester,
            title="رسوم التوثيق",
            description="رسوم بنود التوثيق لمدة سنة",
            subtotal=Decimal("0.00"),
            reference_type="verify_request",
            reference_id=vr.code,
            status=InvoiceStatus.DRAFT,
        )
        for idx, item in enumerate(approved_items):
            fee = _fee_for_user_and_badge(vr.requester, item.badge_type)
            InvoiceLineItem.objects.create(
                invoice=inv,
                item_code=item.code,
                title=item.title,
                amount=fee,
                sort_order=idx,
            )
        inv.mark_pending()
        inv.save(update_fields=["status", "subtotal", "vat_percent", "vat_amount", "total", "updated_at"])

        vr.invoice = inv
        vr.status = VerificationStatus.PENDING_PAYMENT
        vr.save(update_fields=["invoice", "status", "updated_at"])

    _sync_verification_to_unified(vr=vr, changed_by=by_user)
    return vr


@transaction.atomic
def activate_after_payment(*, vr: VerificationRequest):
    """
    تفعيل الشارة بعد الدفع:
    - إنشاء VerifiedBadge
    - تحديث flags على ProviderProfile إن وجد
    """
    vr = VerificationRequest.objects.select_for_update().get(pk=vr.pk)

    if not vr.invoice or vr.invoice.status != "paid":
        raise ValueError("الفاتورة غير مدفوعة بعد.")

    if vr.status == VerificationStatus.ACTIVE:
        return vr

    now = timezone.now()
    vr.activated_at = now
    vr.expires_at = now + vr.activation_window()
    vr.status = VerificationStatus.ACTIVE
    vr.save(update_fields=["activated_at", "expires_at", "status", "updated_at"])

    approved = list(vr.requirements.filter(is_approved=True))
    if not approved:
        # Fallback: single badge based on legacy field.
        bt = vr.badge_type or VerificationBadgeType.BLUE
        d = resolve_requirement_def(bt, "B1" if bt == VerificationBadgeType.BLUE else "G1")
        approved = [VerificationRequirement(request=vr, badge_type=bt, code=d["code"], title=d["title"], is_approved=True)]

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
