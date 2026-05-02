from __future__ import annotations

import calendar
import logging
import os
from decimal import Decimal

from django.conf import settings
from django.db import connections
from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from apps.billing.models import Invoice, InvoiceLineItem, InvoiceStatus, money_round
from apps.notifications.models import EventType
from apps.notifications.services import create_notification

from .models import (
    PromoAdPrice,
    PromoAdType,
    PromoMessageChannel,
    PromoOpsStatus,
    PromoPosition,
    PromoPriceUnit,
    PromoPricingRule,
    PromoRequest,
    PromoRequestItem,
    PromoRequestStatus,
    PromoSearchScope,
    PromoServiceType,
)

logger = logging.getLogger("apps.promo")

DEFAULT_PROMO_PRICING_RULES: tuple[dict[str, str | int | Decimal], ...] = (
    {
        "code": "home_banner_daily",
        "service_type": PromoServiceType.HOME_BANNER,
        "title": "بنر الصفحة الرئيسية - لكل 24 ساعة",
        "unit": PromoPriceUnit.DAY,
        "amount": Decimal("1000.00"),
        "sort_order": 10,
    },
    {
        "code": "featured_daily",
        "service_type": PromoServiceType.FEATURED_SPECIALISTS,
        "title": "شريط أبرز المختصين - لكل 24 ساعة",
        "unit": PromoPriceUnit.DAY,
        "amount": Decimal("1000.00"),
        "sort_order": 20,
    },
    {
        "code": "portfolio_daily",
        "service_type": PromoServiceType.PORTFOLIO_SHOWCASE,
        "title": "البنرات والمشاريع - لكل 24 ساعة",
        "unit": PromoPriceUnit.DAY,
        "amount": Decimal("1000.00"),
        "sort_order": 30,
    },
    {
        "code": "snapshots_daily",
        "service_type": PromoServiceType.SNAPSHOTS,
        "title": "شريط اللمحات - لكل 24 ساعة",
        "unit": PromoPriceUnit.DAY,
        "amount": Decimal("1000.00"),
        "sort_order": 40,
    },
    {
        "code": "search_first",
        "service_type": PromoServiceType.SEARCH_RESULTS,
        "title": "الظهور في قوائم البحث - الأول في القائمة",
        "unit": PromoPriceUnit.DAY,
        "search_position": PromoPosition.FIRST,
        "amount": Decimal("10000.00"),
        "sort_order": 50,
    },
    {
        "code": "search_second",
        "service_type": PromoServiceType.SEARCH_RESULTS,
        "title": "الظهور في قوائم البحث - الثاني في القائمة",
        "unit": PromoPriceUnit.DAY,
        "search_position": PromoPosition.SECOND,
        "amount": Decimal("5000.00"),
        "sort_order": 51,
    },
    {
        "code": "search_top5",
        "service_type": PromoServiceType.SEARCH_RESULTS,
        "title": "الظهور في قوائم البحث - ضمن أول خمسة أسماء",
        "unit": PromoPriceUnit.DAY,
        "search_position": PromoPosition.TOP5,
        "amount": Decimal("2500.00"),
        "sort_order": 52,
    },
    {
        "code": "search_top10",
        "service_type": PromoServiceType.SEARCH_RESULTS,
        "title": "الظهور في قوائم البحث - ضمن أول عشرة أسماء",
        "unit": PromoPriceUnit.DAY,
        "search_position": PromoPosition.TOP10,
        "amount": Decimal("1200.00"),
        "sort_order": 53,
    },
    {
        "code": "messages_notification",
        "service_type": PromoServiceType.PROMO_MESSAGES,
        "title": "الرسائل الدعائية - رسائل التنبيه",
        "unit": PromoPriceUnit.CAMPAIGN,
        "message_channel": PromoMessageChannel.NOTIFICATION,
        "amount": Decimal("900.00"),
        "sort_order": 60,
    },
    {
        "code": "messages_chat",
        "service_type": PromoServiceType.PROMO_MESSAGES,
        "title": "الرسائل الدعائية - رسائل المحادثات",
        "unit": PromoPriceUnit.CAMPAIGN,
        "message_channel": PromoMessageChannel.CHAT,
        "amount": Decimal("700.00"),
        "sort_order": 61,
    },
    {
        "code": "sponsorship_monthly",
        "service_type": PromoServiceType.SPONSORSHIP,
        "title": "الرعاية - لكل شهر",
        "unit": PromoPriceUnit.MONTH,
        "amount": Decimal("12000.00"),
        "sort_order": 70,
    },
)


def calculate_sponsorship_end_at(*, start_at, months: int):
    if start_at is None:
        return None
    month_count = int(months or 0)
    if month_count <= 0:
        return None

    target_month_index = (start_at.month - 1) + month_count
    target_year = start_at.year + (target_month_index // 12)
    target_month = (target_month_index % 12) + 1
    target_day = min(start_at.day, calendar.monthrange(target_year, target_month)[1])
    return start_at.replace(year=target_year, month=target_month, day=target_day)


def _locked_promo_request_queryset():
    return PromoRequest.objects.select_for_update()


def _get_locked_promo_request(*, pr: PromoRequest) -> PromoRequest:
    return _locked_promo_request_queryset().get(pk=pr.pk)

PROMO_LEGACY_AD_TYPE_TO_RULE_CODES: dict[str, tuple[str, ...]] = {
    # Direct semantic mapping between legacy ad types and dynamic pricing rules.
    PromoAdType.BANNER_HOME: ("home_banner_daily",),
    PromoAdType.FEATURED_TOP5: ("search_top5",),
    PromoAdType.FEATURED_TOP10: ("search_top10",),
    PromoAdType.PUSH_NOTIFICATION: ("messages_notification",),
}

PROMO_RULE_CODE_TO_LEGACY_AD_TYPE: dict[str, str] = {
    rule_code: ad_type
    for ad_type, rule_codes in PROMO_LEGACY_AD_TYPE_TO_RULE_CODES.items()
    for rule_code in rule_codes
}


_ASSET_REQUIRED_SERVICE_TYPES = {
    PromoServiceType.HOME_BANNER,
    PromoServiceType.SPONSORSHIP,
}

_PAYMENT_IMMUTABLE_REQUEST_STATUSES = {
    PromoRequestStatus.REJECTED,
    PromoRequestStatus.CANCELLED,
    PromoRequestStatus.COMPLETED,
    PromoRequestStatus.EXPIRED,
}

_INCOMPLETE_REQUEST_STATUSES = {
    PromoRequestStatus.NEW,
    PromoRequestStatus.IN_REVIEW,
    PromoRequestStatus.QUOTED,
    PromoRequestStatus.PENDING_PAYMENT,
}


def _ensure_required_assets_uploaded(pr: PromoRequest) -> None:
    required_service_types = {
        PromoServiceType.HOME_BANNER,
        PromoServiceType.SPONSORSHIP,
    }

    missing_labels: list[str] = []
    for item in pr.items.all():
        if item.service_type in required_service_types and not item.assets.exists():
            missing_labels.append(item.get_service_type_display())

    if missing_labels:
        unique_labels: list[str] = []
        seen: set[str] = set()
        for label in missing_labels:
            if label not in seen:
                seen.add(label)
                unique_labels.append(label)

        labels_text = "، ".join(unique_labels)
        raise ValueError(
            "لا يمكن اعتماد التسعير لأن المرفقات غير مكتملة. "
            f"يرجى رفع مرفق وربطه مباشرةً بكل بند من البنود التالية: {labels_text}."
        )


@transaction.atomic
def discard_incomplete_promo_request(*, pr: PromoRequest, by_user=None, reason: str = "") -> bool:
    # Keep the lock query free from nullable outer joins (e.g., nullable invoice FK),
    # otherwise PostgreSQL may reject SELECT ... FOR UPDATE.
    locked = _get_locked_promo_request(pr=pr)

    if locked.status not in _INCOMPLETE_REQUEST_STATUSES:
        return False

    invoice = locked.invoice
    if invoice is not None and invoice.is_payment_effective():
        return False

    promo_id = int(locked.id)
    invoice_id = int(invoice.id) if invoice is not None else None
    locked.delete()

    # Promo uses unified-request mirror rows; remove stale mirror after hard delete.
    try:
        from apps.unified_requests.models import UnifiedRequest

        UnifiedRequest.objects.filter(
            source_app="promo",
            source_model="PromoRequest",
            source_object_id=str(promo_id),
        ).delete()
    except Exception:
        pass

    if invoice_id is not None:
        orphan_invoice = Invoice.objects.filter(pk=invoice_id).first()
        if (
            orphan_invoice is not None
            and not orphan_invoice.is_payment_effective()
            and not orphan_invoice.promo_requests.exists()
        ):
            orphan_invoice.delete()

    logger.info(
        "promo_incomplete_request_discarded promo_id=%s invoice_id=%s by_user=%s reason=%s",
        promo_id,
        invoice_id,
        getattr(by_user, "id", None),
        (reason or "").strip()[:120],
    )
    return True


def cleanup_incomplete_unpaid_promo_requests(*, now=None, max_age_minutes: int = 30, limit: int = 200) -> int:
    now = now or timezone.now()
    max_age_minutes = max(1, int(max_age_minutes or 30))
    limit = max(1, int(limit or 200))
    cutoff = now - timezone.timedelta(minutes=max_age_minutes)
    request_ids = list(
        PromoRequest.objects.filter(
            status__in=_INCOMPLETE_REQUEST_STATUSES,
            created_at__lte=cutoff,
        )
        .order_by("id")
        .values_list("id", flat=True)[:limit]
    )

    deleted = 0
    for request_id in request_ids:
        try:
            pr = PromoRequest.objects.only("id").get(pk=request_id)
            if discard_incomplete_promo_request(pr=pr, by_user=None, reason="auto_cleanup"):
                deleted += 1
        except PromoRequest.DoesNotExist:
            continue
        except Exception as exc:
            logger.warning(
                "promo_incomplete_cleanup_failed promo_id=%s error=%s",
                request_id,
                str(exc),
            )
    return deleted

def _platform_config():
    from apps.core.models import PlatformConfig

    return PlatformConfig.load()


def promo_min_campaign_hours() -> int:
    return max(24, int(_platform_config().promo_min_campaign_hours or 24))


def promo_min_campaign_message(*, prefix: str = "الحد الأدنى لمدة الحملة هو") -> str:
    return f"{prefix} {promo_min_campaign_hours()} ساعة."


def _promo_base_prices_map() -> dict[str, Decimal]:
    config = _platform_config()
    raw = config.get_promo_base_prices() or getattr(settings, "PROMO_BASE_PRICES", {}) or {}
    return {str(key): Decimal(str(value)) for key, value in raw.items()}


def _promo_position_multipliers_map() -> dict[str, Decimal]:
    config = _platform_config()
    raw = (
        config.get_promo_position_multipliers()
        or getattr(settings, "PROMO_POSITION_MULTIPLIER", {})
        or {}
    )
    return {str(key): Decimal(str(value)) for key, value in raw.items()}


def _promo_status_label(status: str) -> str:
    return {
        PromoRequestStatus.NEW: "جديد",
        PromoRequestStatus.IN_REVIEW: "قيد المراجعة",
        PromoRequestStatus.QUOTED: "تم التسعير",
        PromoRequestStatus.PENDING_PAYMENT: "بانتظار الدفع",
        PromoRequestStatus.ACTIVE: "مفعل",
        PromoRequestStatus.COMPLETED: "مكتمل",
        PromoRequestStatus.REJECTED: "مرفوض",
        PromoRequestStatus.EXPIRED: "منتهي",
        PromoRequestStatus.CANCELLED: "ملغي",
    }.get(status, status)


def _promo_request_web_url(pr: PromoRequest) -> str:
    return f"/promotion/?request_id={pr.id}"


def _notify_promo_status_change(*, pr: PromoRequest, status: str, actor=None) -> None:
    try:
        code_or_id = (pr.code or str(pr.id)).strip()
        create_notification(
            user=pr.requester,
            title="تحديث حالة الترويج",
            body=f"تم تحديث حالة طلب الترويج ({code_or_id}) إلى {_promo_status_label(status)}.",
            kind="promo_status_change",
            url=_promo_request_web_url(pr),
            actor=actor,
            event_type=EventType.STATUS_CHANGED,
            request_id=pr.id,
            meta={
                "payload": {"status": status, "ops_status": pr.ops_status},
                "status": status,
                "promo_request_id": pr.id,
                "promo_code": code_or_id,
            },
            pref_key="promo_status_change",
            audience_mode="provider",
        )
    except Exception:
        logger.exception(
            "Failed to send promo status notification",
            extra={"promo_request_id": getattr(pr, "id", None), "status": status},
        )


def _notify_promo_ops_completed(*, pr: PromoRequest, actor=None) -> None:
    try:
        code_or_id = (pr.code or str(pr.id)).strip()
        create_notification(
            user=pr.requester,
            title="اكتمل طلب الترويج",
            body=f"تم اكتمال تنفيذ طلب الترويج ({code_or_id}) بنجاح.",
            kind="promo_status_change",
            url=_promo_request_web_url(pr),
            actor=actor,
            event_type=EventType.STATUS_CHANGED,
            request_id=pr.id,
            meta={
                "payload": {"status": pr.status, "ops_status": pr.ops_status},
                "status": pr.status,
                "ops_status": pr.ops_status,
                "promo_request_id": pr.id,
                "promo_code": code_or_id,
                "ops_completed": True,
            },
            pref_key="promo_status_change",
            audience_mode="provider",
        )
    except Exception:
        logger.exception(
            "Failed to send promo completion notification",
            extra={"promo_request_id": getattr(pr, "id", None), "status": getattr(pr, "status", "")},
        )


def _promo_unified_status(pr: PromoRequest) -> str:
    if pr.status in {
        PromoRequestStatus.PENDING_PAYMENT,
        PromoRequestStatus.ACTIVE,
        PromoRequestStatus.EXPIRED,
        PromoRequestStatus.CANCELLED,
        PromoRequestStatus.REJECTED,
    }:
        return pr.status
    if pr.status == PromoRequestStatus.COMPLETED:
        return PromoOpsStatus.COMPLETED
    if pr.status == PromoRequestStatus.QUOTED and pr.invoice_id:
        return PromoRequestStatus.PENDING_PAYMENT
    if pr.ops_status == PromoOpsStatus.IN_PROGRESS:
        return PromoOpsStatus.IN_PROGRESS
    if pr.ops_status == PromoOpsStatus.COMPLETED:
        return PromoOpsStatus.COMPLETED
    if pr.status == PromoRequestStatus.IN_REVIEW:
        return PromoOpsStatus.IN_PROGRESS
    return PromoOpsStatus.NEW


def _sync_promo_to_unified(*, pr: PromoRequest, changed_by=None):
    try:
        from apps.unified_requests.services import upsert_unified_request
        from apps.unified_requests.models import UnifiedRequestType
    except Exception:
        return

    service_types = []
    if hasattr(pr, "items"):
        service_types = list(
            pr.items.order_by("sort_order", "id").values_list("service_type", flat=True)
        )

    upsert_unified_request(
        request_type=UnifiedRequestType.PROMO,
        requester=pr.requester,
        source_app="promo",
        source_model="PromoRequest",
        source_object_id=pr.id,
        status=_promo_unified_status(pr),
        priority="normal",
        summary=(_promo_request_summary(pr) or pr.title or "")[:300],
        metadata={
            "promo_code": pr.code or "",
            "ad_type": pr.ad_type,
            "invoice_id": pr.invoice_id,
            "total_days": pr.total_days,
            "status": pr.status,
            "ops_status": pr.ops_status,
            "service_types": service_types,
        },
        assigned_team_code="promo",
        assigned_team_name="الترويج",
        assigned_user=pr.assigned_to,
        changed_by=changed_by,
    )


def ensure_default_pricing_rules() -> None:
    existing_codes = set(PromoPricingRule.objects.values_list("code", flat=True))
    to_create = []
    for row in DEFAULT_PROMO_PRICING_RULES:
        code = str(row["code"])
        if code in existing_codes:
            continue
        to_create.append(PromoPricingRule(**row))
    if to_create:
        PromoPricingRule.objects.bulk_create(to_create)
        # On first bootstrap, inherit mapped legacy admin prices when available.
        for legacy_ad_type in PROMO_LEGACY_AD_TYPE_TO_RULE_CODES:
            sync_pricing_rules_from_legacy_ad_type(ad_type=legacy_ad_type, ensure_defaults=False)


def sync_pricing_rules_from_legacy_ad_type(*, ad_type: str, ensure_defaults: bool = True) -> int:
    """
    Sync mapped PromoPricingRule amount(s) from legacy PromoAdPrice row.

    Returns number of rules updated.
    """
    if ensure_defaults:
        ensure_default_pricing_rules()

    mapped_codes = PROMO_LEGACY_AD_TYPE_TO_RULE_CODES.get(str(ad_type or "").strip(), ())
    if not mapped_codes:
        return 0

    legacy_row = PromoAdPrice.objects.filter(ad_type=ad_type, is_active=True).only("price_per_day").first()
    if not legacy_row or legacy_row.price_per_day is None:
        return 0

    try:
        normalized_amount = Decimal(str(legacy_row.price_per_day)).quantize(Decimal("0.01"))
    except Exception:
        return 0

    if normalized_amount < 0:
        return 0

    updated_count = 0
    for rule in PromoPricingRule.objects.filter(code__in=mapped_codes):
        if rule.amount == normalized_amount:
            continue
        rule.amount = normalized_amount
        rule.save(update_fields=["amount", "updated_at"])
        updated_count += 1
    return updated_count


def sync_legacy_ad_price_from_pricing_rule(*, rule: PromoPricingRule) -> bool:
    """
    Sync mapped legacy PromoAdPrice row from a PromoPricingRule.

    Returns True when a mapping exists and sync is applied, False otherwise.
    """
    if rule is None:
        return False

    ad_type = PROMO_RULE_CODE_TO_LEGACY_AD_TYPE.get(str(getattr(rule, "code", "") or "").strip())
    if not ad_type:
        return False

    try:
        normalized_amount = Decimal(str(rule.amount)).quantize(Decimal("0.01"))
    except Exception:
        return False

    PromoAdPrice.objects.update_or_create(
        ad_type=ad_type,
        defaults={
            "price_per_day": normalized_amount,
            "is_active": bool(rule.is_active),
        },
    )
    return True


def _promo_request_summary(pr: PromoRequest) -> str:
    items = list(pr.items.all().order_by("sort_order", "id")) if hasattr(pr, "items") else []
    if items:
        labels = []
        for item in items:
            label = item.get_service_type_display()
            if label not in labels:
                labels.append(label)
        return " + ".join(labels)
    return pr.title or pr.get_ad_type_display()


def _legacy_position_value(position: str) -> Decimal:
    return _promo_position_multipliers_map().get(position, Decimal("1.0"))


def _get_base_price(ad_type: str) -> Decimal:
    try:
        row = PromoAdPrice.objects.filter(ad_type=ad_type, is_active=True).only("price_per_day").first()
        if row and row.price_per_day is not None:
            value = Decimal(str(row.price_per_day))
            if value > 0:
                return value
    except Exception:
        pass

    return _promo_base_prices_map().get(ad_type, Decimal("300"))


def calc_promo_quote(*, pr: PromoRequest) -> dict:
    start = pr.start_at
    end = pr.end_at
    days = (end.date() - start.date()).days
    if days <= 0:
        days = 1
    subtotal = _get_base_price(pr.ad_type)
    subtotal *= _legacy_position_value(pr.position)
    subtotal *= Decimal(str(days))
    return {"subtotal": subtotal.quantize(Decimal("0.01")), "days": days}


def _item_assets_count(item: PromoRequestItem) -> int:
    preview_count = getattr(item, "_preview_asset_count", None)
    if preview_count is not None:
        return max(0, int(preview_count or 0))
    count = item.assets.count()
    if count:
        return count
    if item.request.items.count() == 1:
        return item.request.assets.filter(item__isnull=True).count()
    return 0


def _item_assets(item: PromoRequestItem):
    assets = list(item.assets.all())
    if assets:
        return assets
    if item.request.items.count() == 1:
        return list(item.request.assets.filter(item__isnull=True))
    return []


def _duration_days(start_at, end_at) -> int:
    if not start_at or not end_at:
        return 0
    days = (end_at.date() - start_at.date()).days
    return days if days > 0 else 1


def _require_campaign_dates(item: PromoRequestItem) -> None:
    if not item.start_at or not item.end_at:
        raise ValueError(f"{item.get_service_type_display()}: تاريخ البداية والنهاية مطلوبان.")
    if item.end_at <= item.start_at:
        raise ValueError(f"{item.get_service_type_display()}: تاريخ النهاية يجب أن يكون بعد البداية.")
    if (item.end_at - item.start_at).total_seconds() < promo_min_campaign_hours() * 60 * 60:
        raise ValueError(f"{item.get_service_type_display()}: {promo_min_campaign_message()}")


def _get_pricing_rule(*, service_type: str, search_position: str = "", message_channel: str = "") -> PromoPricingRule:
    ensure_default_pricing_rules()
    qs = PromoPricingRule.objects.filter(service_type=service_type, is_active=True)
    if search_position:
        qs = qs.filter(search_position=search_position)
    if message_channel:
        qs = qs.filter(message_channel=message_channel)
    rule = qs.order_by("sort_order", "id").first()
    if not rule:
        raise ValueError("لا توجد قاعدة تسعير مفعلة للخيار المطلوب.")
    return rule


def calc_promo_item_quote(*, item: PromoRequestItem) -> dict:
    service_type = item.service_type
    if service_type == PromoServiceType.HOME_BANNER:
        _require_campaign_dates(item)
        if _item_assets_count(item) == 0:
            raise ValueError("بنر الصفحة الرئيسية يحتاج ملف تصميم مرفوعًا قبل التسعير.")
        days = _duration_days(item.start_at, item.end_at)
        rule = _get_pricing_rule(service_type=service_type)
        subtotal = rule.amount * Decimal(str(days))
        return {"subtotal": money_round(subtotal), "days": days, "rule": rule}

    if service_type in {
        PromoServiceType.FEATURED_SPECIALISTS,
        PromoServiceType.PORTFOLIO_SHOWCASE,
        PromoServiceType.SNAPSHOTS,
    }:
        _require_campaign_dates(item)
        days = _duration_days(item.start_at, item.end_at)
        rule = _get_pricing_rule(service_type=service_type)
        subtotal = rule.amount * Decimal(str(days))
        return {"subtotal": money_round(subtotal), "days": days, "rule": rule}

    if service_type == PromoServiceType.SEARCH_RESULTS:
        _require_campaign_dates(item)
        if item.search_scope not in PromoSearchScope.values:
            raise ValueError("الظهور في قوائم البحث: نوع القائمة مطلوب.")
        if item.search_position not in {
            PromoPosition.FIRST,
            PromoPosition.SECOND,
            PromoPosition.TOP5,
            PromoPosition.TOP10,
        }:
            raise ValueError("الظهور في قوائم البحث: ترتيب الظهور غير صحيح.")
        days = _duration_days(item.start_at, item.end_at)
        rule = _get_pricing_rule(service_type=service_type, search_position=item.search_position)
        subtotal = rule.amount * Decimal(str(days))
        return {"subtotal": money_round(subtotal), "days": days, "rule": rule}

    if service_type == PromoServiceType.PROMO_MESSAGES:
        if not item.send_at:
            raise ValueError("الرسائل الدعائية: وقت الإرسال مطلوب.")
        if not item.use_notification_channel and not item.use_chat_channel:
            raise ValueError("الرسائل الدعائية: اختر قناة إرسال واحدة على الأقل.")
        subtotal = Decimal("0.00")
        used_codes: list[str] = []
        if item.use_notification_channel:
            rule = _get_pricing_rule(
                service_type=service_type,
                message_channel=PromoMessageChannel.NOTIFICATION,
            )
            subtotal += rule.amount
            used_codes.append(rule.code)
        if item.use_chat_channel:
            rule = _get_pricing_rule(
                service_type=service_type,
                message_channel=PromoMessageChannel.CHAT,
            )
            subtotal += rule.amount
            used_codes.append(rule.code)
        return {
            "subtotal": money_round(subtotal),
            "days": 1,
            "rule": used_codes[-1] if used_codes else None,
            "rule_code": "+".join(used_codes),
        }

    if service_type == PromoServiceType.SPONSORSHIP:
        if _item_assets_count(item) == 0:
            raise ValueError("الرعاية تحتاج شعار الراعي أو ملف الرعاية قبل التسعير.")
        months = int(item.sponsorship_months or 0)
        if months <= 0:
            if item.start_at and item.end_at and item.end_at > item.start_at:
                days = _duration_days(item.start_at, item.end_at)
                months = max(1, (days + 29) // 30)
            else:
                raise ValueError("الرعاية: مدة الرعاية بالأشهر مطلوبة.")
        rule = _get_pricing_rule(service_type=service_type)
        subtotal = rule.amount * Decimal(str(months))
        return {"subtotal": money_round(subtotal), "days": months * 30, "rule": rule, "months": months}

    raise ValueError("نوع الخدمة الترويجية غير مدعوم في التسعير.")


def calc_promo_request_quote(*, pr: PromoRequest) -> dict:
    items = list(pr.items.all().order_by("sort_order", "id"))
    if not items:
        return calc_promo_quote(pr=pr)

    total = Decimal("0.00")
    window_days = 0
    results = []
    for item in items:
        quote = calc_promo_item_quote(item=item)
        rule = quote.get("rule")
        rule_code = quote.get("rule_code") or getattr(rule, "code", "")
        item.subtotal = quote["subtotal"]
        item.duration_days = int(quote.get("days") or 0)
        item.pricing_rule_code = rule_code
        item.save(update_fields=["subtotal", "duration_days", "pricing_rule_code", "updated_at"])
        total += item.subtotal
        window_days = max(window_days, item.duration_days)
        results.append({"item": item, "rule": rule, "rule_code": rule_code})
    return {"subtotal": money_round(total), "days": window_days, "items": results}


def preview_promo_request(*, requester, validated_data: dict) -> dict:
    items_data = list(validated_data.get("items") or [])
    vat_percent = Decimal(str(_platform_config().promo_vat_percent))

    if not items_data:
        pr = PromoRequest(
            requester=requester,
            title=(validated_data.get("title") or "طلب ترويج")[:160],
            ad_type=validated_data.get("ad_type") or PromoAdType.BANNER_HOME,
            start_at=validated_data.get("start_at"),
            end_at=validated_data.get("end_at"),
            position=validated_data.get("position") or PromoPosition.NORMAL,
            target_category=validated_data.get("target_category") or "",
            target_city=validated_data.get("target_city") or "",
            redirect_url=validated_data.get("redirect_url") or "",
        )
        if pr.ad_type == PromoAdType.PUSH_NOTIFICATION:
            preview_item = PromoRequestItem(
                request=pr,
                service_type=PromoServiceType.PROMO_MESSAGES,
                title=pr.title,
                send_at=pr.start_at,
                target_category=pr.target_category or "",
                target_city=pr.target_city or "",
                target_provider=validated_data.get("target_provider"),
                target_portfolio_item=validated_data.get("target_portfolio_item"),
                target_spotlight_item=validated_data.get("target_spotlight_item"),
                redirect_url=pr.redirect_url or "",
                message_title=validated_data.get("message_title") or "",
                message_body=validated_data.get("message_body") or "",
                use_notification_channel=True,
                use_chat_channel=False,
            )
            quote = calc_promo_item_quote(item=preview_item)
            rule_code = quote.get("rule_code") or getattr(quote.get("rule"), "code", PromoServiceType.PROMO_MESSAGES)
            subtotal = money_round(quote["subtotal"])
            vat_amount = money_round((subtotal * vat_percent) / Decimal("100"))
            total = money_round(subtotal + vat_amount)
            return {
                "title": pr.title,
                "ad_type": pr.ad_type,
                "subtotal": subtotal,
                "vat_percent": vat_percent,
                "vat_amount": vat_amount,
                "total": total,
                "currency": "SAR",
                "total_days": int(quote.get("days") or 0),
                "items": [
                    {
                        "service_type": preview_item.service_type,
                        "service_type_label": preview_item.get_service_type_display(),
                        "title": preview_item.title or preview_item.get_service_type_display(),
                        "subtotal": subtotal,
                        "duration_days": int(quote.get("days") or 0),
                        "pricing_rule_code": rule_code,
                    }
                ],
            }

        quote = calc_promo_quote(pr=pr)
        subtotal = money_round(quote["subtotal"])
        vat_amount = money_round((subtotal * vat_percent) / Decimal("100"))
        total = money_round(subtotal + vat_amount)
        return {
            "title": pr.title,
            "ad_type": pr.ad_type,
            "subtotal": subtotal,
            "vat_percent": vat_percent,
            "vat_amount": vat_amount,
            "total": total,
            "currency": "SAR",
            "total_days": int(quote.get("days") or 0),
            "items": [
                {
                    "service_type": pr.ad_type,
                    "service_type_label": pr.get_ad_type_display(),
                    "title": pr.title,
                    "subtotal": subtotal,
                    "duration_days": int(quote.get("days") or 0),
                    "pricing_rule_code": pr.ad_type,
                }
            ],
        }

    provider_profile = getattr(requester, "provider_profile", None)
    auto_targeted_service_types = {
        PromoServiceType.FEATURED_SPECIALISTS,
        PromoServiceType.PORTFOLIO_SHOWCASE,
        PromoServiceType.SNAPSHOTS,
        PromoServiceType.SEARCH_RESULTS,
    }
    pr = PromoRequest(
        requester=requester,
        title="طلب ترويج متعدد الخدمات",
        ad_type=PromoAdType.BUNDLE,
        start_at=timezone.now(),
        end_at=timezone.now(),
        position=PromoPosition.NORMAL,
    )

    subtotal = Decimal("0.00")
    total_days = 0
    preview_items = []

    expanded_index = 0
    for index, row in enumerate(items_data):
        normalized = {
            key: value
            for key, value in row.items()
            if key not in {"asset_count", "search_scopes", "resolved_search_scopes"}
        }
        scopes = [
            str(scope).strip()
            for scope in (row.get("resolved_search_scopes") or row.get("search_scopes") or [])
            if str(scope).strip()
        ]
        if not scopes and normalized.get("search_scope"):
            scopes = [str(normalized.get("search_scope") or "").strip()]

        expanded_rows = []
        if normalized.get("service_type") == PromoServiceType.SEARCH_RESULTS and scopes:
            scope_labels = dict(PromoSearchScope.choices)
            for scope in scopes:
                expanded = dict(normalized)
                expanded["target_city"] = ""
                expanded["search_scope"] = scope
                base_title = str(expanded.get("title") or "").strip()
                if base_title and len(scopes) > 1:
                    expanded["title"] = f"{base_title} - {scope_labels.get(scope, scope)}"[:160]
                expanded_rows.append(expanded)
        else:
            if normalized.get("service_type") == PromoServiceType.SEARCH_RESULTS:
                normalized["target_city"] = ""
            expanded_rows.append(normalized)

        for expanded in expanded_rows:
            if (
                provider_profile is not None
                and expanded.get("service_type") in auto_targeted_service_types
                and not expanded.get("target_provider")
            ):
                expanded["target_provider"] = provider_profile

            item = PromoRequestItem(request=pr, **expanded)
            item.sort_order = int(expanded.get("sort_order") or (index * 10 + expanded_index))
            item._preview_asset_count = int(row.get("asset_count") or 0)
            quote = calc_promo_item_quote(item=item)
            rule = quote.get("rule")
            rule_code = quote.get("rule_code") or getattr(rule, "code", item.service_type)
            item_subtotal = money_round(quote["subtotal"])
            item_days = int(quote.get("days") or 0)
            subtotal += item_subtotal
            total_days = max(total_days, item_days)
            preview_items.append(
                {
                    "service_type": item.service_type,
                    "service_type_label": item.get_service_type_display(),
                    "title": item.title or item.get_service_type_display(),
                    "subtotal": item_subtotal,
                    "duration_days": item_days,
                    "pricing_rule_code": rule_code,
                }
            )
            expanded_index += 1

    subtotal = money_round(subtotal)
    vat_amount = money_round((subtotal * vat_percent) / Decimal("100"))
    total = money_round(subtotal + vat_amount)
    summary_labels: list[str] = []
    for row in preview_items:
        label = str(row.get("service_type_label") or "").strip()
        if label and label not in summary_labels:
            summary_labels.append(label)
    request_title = (" + ".join(summary_labels) or "طلب ترويج متعدد الخدمات")[:160]
    return {
        "title": request_title,
        "ad_type": pr.ad_type,
        "subtotal": subtotal,
        "vat_percent": vat_percent,
        "vat_amount": vat_amount,
        "total": total,
        "currency": "SAR",
        "total_days": total_days,
        "items": preview_items,
    }


def _invoice_title_for_request(pr: PromoRequest) -> str:
    return f"فاتورة طلب الترويج {pr.code or pr.id}"


def _invoice_line_item_code_db_max_length(*, using: str = "default") -> int:
    field = InvoiceLineItem._meta.get_field("item_code")
    model_max = int(getattr(field, "max_length", 50) or 50)
    try:
        connection = connections[using]
        with connection.cursor() as cursor:
            description = connection.introspection.get_table_description(cursor, InvoiceLineItem._meta.db_table)
        for column in description:
            if getattr(column, "name", "") != field.column:
                continue
            for attr in ("internal_size", "display_size"):
                size = getattr(column, attr, None)
                if isinstance(size, int) and size > 0:
                    return size
            break
    except Exception:
        pass
    # Conservative fallback: column may still be varchar(20) if billing
    # migration 0005 has not been applied yet.
    return min(model_max, 20)


def _invoice_line_item_code(*, item: PromoRequestItem, using: str = "default") -> str:
    max_length = _invoice_line_item_code_db_max_length(using=using)
    raw_code = str(item.pricing_rule_code or item.service_type or "").strip()
    if len(raw_code) <= max_length:
        return raw_code

    fallback_code = str(item.service_type or "").strip()
    if fallback_code and len(fallback_code) <= max_length:
        return fallback_code

    return raw_code[:max_length]


def _sync_invoice_from_items(*, pr: PromoRequest) -> Invoice:
    q = calc_promo_request_quote(pr=pr)
    subtotal = money_round(q["subtotal"])

    if not pr.invoice_id:
        inv = Invoice.objects.create(
            user=pr.requester,
            title=_invoice_title_for_request(pr),
            description=_promo_request_summary(pr)[:300],
            subtotal=subtotal,
            reference_type="promo_request",
            reference_id=pr.code,
            status=InvoiceStatus.DRAFT,
            vat_percent=Decimal(str(_platform_config().promo_vat_percent)),
        )
    else:
        inv = pr.invoice
        inv.title = _invoice_title_for_request(pr)
        inv.description = _promo_request_summary(pr)[:300]
        inv.reference_type = "promo_request"
        inv.reference_id = pr.code or inv.reference_id
        inv.vat_percent = Decimal(str(_platform_config().promo_vat_percent))
        inv.save(update_fields=["title", "description", "reference_type", "reference_id", "vat_percent", "updated_at"])
        inv.lines.all().delete()

    line_rows = []
    using = getattr(inv._state, "db", None) or "default"
    for idx, row in enumerate(q.get("items", []), start=1):
        item = row["item"]
        line_rows.append(
            InvoiceLineItem(
                invoice=inv,
                item_code=_invoice_line_item_code(item=item, using=using),
                title=item.title or item.get_service_type_display(),
                amount=item.subtotal,
                sort_order=idx * 10,
            )
        )
    if not line_rows:
        line_rows.append(
            InvoiceLineItem(
                invoice=inv,
                item_code=pr.ad_type,
                title=pr.title or pr.get_ad_type_display(),
                amount=subtotal,
                sort_order=10,
            )
        )
    InvoiceLineItem.objects.bulk_create(line_rows)
    inv.mark_pending()
    inv.save(update_fields=["status", "subtotal", "vat_percent", "vat_amount", "total", "updated_at"])

    pr.subtotal = subtotal
    pr.total_days = int(q.get("days") or 0)
    pr.invoice = inv
    return inv


def _promo_message_sender_label(*, pr: PromoRequest) -> str:
    provider = getattr(pr.requester, "provider_profile", None)
    if provider and getattr(provider, "display_name", None):
        return str(provider.display_name)
    requester = getattr(pr, "requester", None)
    if requester is None:
        return "مزود خدمة"
    return str(
        getattr(requester, "username", "")
        or getattr(requester, "first_name", "")
        or getattr(requester, "phone", "")
        or "مزود خدمة"
    )


def _promo_message_default_url(*, item: PromoRequestItem) -> str:
    raw = str(item.redirect_url or item.request.redirect_url or "").strip()
    if raw:
        return raw
    provider = getattr(item.request.requester, "provider_profile", None)
    if provider and getattr(provider, "id", None):
        return f"/provider/{provider.id}/"
    return ""


def _promo_message_attachment_type(asset_type: str) -> str:
    return "image" if str(asset_type or "").strip().lower() == "image" else "file"


def _promo_message_recipient_users(*, item: PromoRequestItem):
    from apps.accounts.models import User, UserRole

    city = str(item.target_city or item.request.target_city or "").strip()
    category = str(item.target_category or item.request.target_category or "").strip()
    sender_id = item.request.requester_id

    # Providers can be filtered by city and category.
    provider_qs = User.objects.filter(
        is_active=True,
        role_state=UserRole.PROVIDER,
        provider_profile__isnull=False,
    ).exclude(id=sender_id)
    if city:
        provider_qs = provider_qs.filter(
            Q(provider_profile__city__iexact=city)
            | Q(city__iexact=city)
        )
    if category:
        provider_qs = provider_qs.filter(
            Q(provider_profile__providercategory__subcategory__name__iexact=category)
            | Q(provider_profile__providercategory__subcategory__category__name__iexact=category)
        )
    provider_ids = list(provider_qs.values_list("id", flat=True).distinct())

    # Clients do not carry service-category taxonomy, so category targeting
    # does not exclude them. City targeting still applies when provided.
    client_qs = User.objects.filter(
        is_active=True,
        role_state__in=[UserRole.CLIENT, UserRole.PHONE_ONLY],
    ).exclude(id=sender_id)
    if city:
        client_qs = client_qs.filter(city__iexact=city)
    client_ids = list(client_qs.values_list("id", flat=True).distinct())

    recipient_ids = list(set(provider_ids + client_ids))
    if not recipient_ids:
        return User.objects.none()
    return User.objects.filter(id__in=recipient_ids).select_related("provider_profile").order_by("id")


def _promo_recipient_audience_mode(*, recipient) -> str:
    role_state = str(getattr(recipient, "role_state", "") or "").strip().lower()
    return "provider" if role_state == "provider" else "client"


def _get_or_create_direct_thread(*, user_a, user_b, context_mode: str):
    from apps.messaging.models import Thread

    if not getattr(user_a, "id", None) or not getattr(user_b, "id", None):
        raise ValueError("missing direct-thread participants")
    if user_a.id == user_b.id:
        raise ValueError("cannot chat self")
    thread = (
        Thread.objects.filter(
            is_direct=True,
            is_system_thread=True,
            system_thread_key="promo_messages",
            context_mode=context_mode,
        )
        .filter(
            Q(participant_1=user_a, participant_2=user_b)
            | Q(participant_1=user_b, participant_2=user_a)
        )
        .first()
    )
    if thread:
        thread.set_participant_modes(
            participant_1_mode=context_mode,
            participant_2_mode=context_mode,
            save=True,
        )
        return thread
    return Thread.objects.create(
        is_direct=True,
        is_system_thread=True,
        system_thread_key="promo_messages",
        context_mode=context_mode,
        participant_1=user_a,
        participant_2=user_b,
        participant_1_mode=context_mode,
        participant_2_mode=context_mode,
    )


@transaction.atomic
def dispatch_promo_message_item(*, item: PromoRequestItem, now=None, allow_expired_window: bool = False) -> int:
    from apps.messaging.models import Thread, create_system_message
    from apps.messaging.views import _is_blocked_by_other, _unarchive_for_participants
    from apps.notifications.services import create_notification

    now = now or timezone.now()
    item = (
        PromoRequestItem.objects.select_for_update()
        .select_related(
            "request",
            "request__requester",
            "request__requester__provider_profile",
        )
        .prefetch_related("assets", "request__assets")
        .get(pk=item.pk)
    )

    if item.service_type != PromoServiceType.PROMO_MESSAGES:
        raise ValueError("promo item is not a promotional message")
    if item.request.status != PromoRequestStatus.ACTIVE:
        raise ValueError("promo request is not active")
    if item.message_sent_at:
        return int(item.message_recipients_count or 0)
    if not item.send_at or item.send_at > now:
        return 0
    if not allow_expired_window and item.request.end_at and item.request.end_at < now:
        return 0

    sender_user = item.request.requester
    body = str(item.message_body or item.request.message_body or "").strip()
    if not body and not _item_assets(item):
        raise ValueError("promo message has no body or attachments to deliver")

    title = str(item.message_title or item.request.message_title or "").strip()
    if not title:
        title = f"رسالة دعائية من {_promo_message_sender_label(pr=item.request)}"
    sender_label = _promo_message_sender_label(pr=item.request)
    assets = _item_assets(item)
    delivered_count = 0

    for recipient in _promo_message_recipient_users(item=item):
        delivered = False

        if item.use_notification_channel:
            notification_audience_mode = _promo_recipient_audience_mode(recipient=recipient)
            notification_pref_key = (
                "ads_and_offers" if notification_audience_mode == "provider" else "platform_recommendations"
            )
            notification = create_notification(
                user=recipient,
                title=title,
                body=body or "لديك رسالة دعائية جديدة.",
                kind="promo_offer",
                url=f"/notifications/?promo_item_id={item.id}",
                actor=sender_user,
                pref_key=notification_pref_key,
                audience_mode=notification_audience_mode,
                meta={
                    "promo_request_id": item.request_id,
                    "promo_request_item_id": item.id,
                    "channel": "notification",
                },
            )
            delivered = delivered or notification is not None

        if item.use_chat_channel:
            chat_context_mode = (
                Thread.ContextMode.PROVIDER
                if _promo_recipient_audience_mode(recipient=recipient) == "provider"
                else Thread.ContextMode.CLIENT
            )
            thread = _get_or_create_direct_thread(
                user_a=sender_user,
                user_b=recipient,
                context_mode=chat_context_mode,
            )
            if not _is_blocked_by_other(thread, sender_user.id):
                if body:
                    create_system_message(
                        thread=thread,
                        sender=sender_user,
                        body=body,
                        sender_team_name=sender_label,
                        system_thread_key="promo_messages",
                        reply_restricted_to=recipient,
                        reply_restriction_reason="الردود مغلقة على الرسائل الدعائية الآلية.",
                        created_at=now,
                    )
                    delivered = True
                for asset in assets:
                    create_system_message(
                        thread=thread,
                        sender=sender_user,
                        body="",
                        sender_team_name=sender_label,
                        system_thread_key="promo_messages",
                        reply_restricted_to=recipient,
                        reply_restriction_reason="الردود مغلقة على الرسائل الدعائية الآلية.",
                        attachment=asset.file,
                        attachment_type=_promo_message_attachment_type(asset.asset_type),
                        attachment_name=os.path.basename(getattr(asset.file, "name", "") or "").strip(),
                        created_at=now,
                    )
                    delivered = True
                _unarchive_for_participants(thread)

        if delivered:
            delivered_count += 1

    item.message_sent_at = now
    item.message_recipients_count = delivered_count
    item.message_dispatch_error = ""
    item.save(
        update_fields=[
            "message_sent_at",
            "message_recipients_count",
            "message_dispatch_error",
            "updated_at",
        ]
    )
    return delivered_count


def send_due_promo_messages(*, now=None, limit: int = 100) -> int:
    now = now or timezone.now()
    item_ids = list(
        PromoRequestItem.objects.filter(
            request__status=PromoRequestStatus.ACTIVE,
            request__end_at__gte=now,
            service_type=PromoServiceType.PROMO_MESSAGES,
            send_at__isnull=False,
            send_at__lte=now,
            message_sent_at__isnull=True,
        )
        .order_by("send_at", "id")
        .values_list("id", flat=True)[: max(1, int(limit or 100))]
    )

    processed = 0
    for item_id in item_ids:
        try:
            dispatch_promo_message_item(item=PromoRequestItem(pk=item_id), now=now)
            processed += 1
        except Exception as exc:
            PromoRequestItem.objects.filter(pk=item_id).update(
                message_dispatch_error=str(exc)[:255]
            )
    return processed


def _dispatch_due_messages_for_request(pr: PromoRequest, *, now=None) -> int:
    """Dispatch all due promo-message items for a single request, inline."""
    now = now or timezone.now()
    due_items = list(
        PromoRequestItem.objects.filter(
            request=pr,
            service_type=PromoServiceType.PROMO_MESSAGES,
            send_at__isnull=False,
            send_at__lte=now,
            message_sent_at__isnull=True,
        ).order_by("send_at", "id")
    )
    dispatched = 0
    for item in due_items:
        try:
            dispatch_promo_message_item(item=item, now=now, allow_expired_window=True)
            dispatched += 1
        except Exception as exc:
            PromoRequestItem.objects.filter(pk=item.pk).update(
                message_dispatch_error=str(exc)[:255]
            )
    return dispatched


@transaction.atomic
def expire_due_promos(*, now=None) -> int:
    now = now or timezone.now()
    qs = PromoRequest.objects.select_for_update().filter(
        status=PromoRequestStatus.ACTIVE,
        end_at__lte=now,
    ).order_by("id")
    rows = list(qs)
    count = len(rows)
    for pr in rows:
        # Dispatch any unsent promo messages while request is still ACTIVE
        _dispatch_due_messages_for_request(pr, now=now)
        pr.status = PromoRequestStatus.EXPIRED
        if pr.ops_status != PromoOpsStatus.COMPLETED:
            pr.ops_status = PromoOpsStatus.COMPLETED
            pr.ops_completed_at = pr.ops_completed_at or now
            pr.save(update_fields=["status", "ops_status", "ops_completed_at", "updated_at"])
        else:
            pr.save(update_fields=["status", "updated_at"])
        _sync_promo_to_unified(pr=pr, changed_by=None)
        _notify_promo_status_change(pr=pr, status=PromoRequestStatus.EXPIRED, actor=None)
    return count


@transaction.atomic
def quote_and_create_invoice(*, pr: PromoRequest, by_user, quote_note: str = "") -> PromoRequest:
    pr = PromoRequest.objects.select_for_update().prefetch_related("items", "assets", "items__assets").get(pk=pr.pk)

    if pr.status in (PromoRequestStatus.ACTIVE, PromoRequestStatus.EXPIRED, PromoRequestStatus.COMPLETED):
        raise ValueError("لا يمكن تسعير حملة مفعلة أو مكتملة أو منتهية.")

    if not pr.items.exists() and not pr.assets.exists():
        raise ValueError("لا يمكن التسعير قبل إضافة بنود الترويج أو مواد الإعلان.")

    _ensure_required_assets_uploaded(pr)

    _sync_invoice_from_items(pr=pr)
    pr.quote_note = (quote_note or "")[:300]
    pr.reviewed_at = timezone.now()
    pr.status = PromoRequestStatus.PENDING_PAYMENT
    pr.save(
        update_fields=[
            "subtotal",
            "total_days",
            "quote_note",
            "reviewed_at",
            "invoice",
            "status",
            "updated_at",
        ]
    )
    _sync_promo_to_unified(pr=pr, changed_by=by_user)
    _notify_promo_status_change(pr=pr, status=PromoRequestStatus.PENDING_PAYMENT, actor=by_user)
    try:
        from apps.analytics.tracking import safe_track_event

        safe_track_event(
            event_name="promo.request_quoted",
            channel="server",
            surface="promo.quote_and_create_invoice",
            source_app="promo",
            object_type="PromoRequest",
            object_id=str(pr.id),
            actor=by_user,
            dedupe_key=f"promo.request_quoted:{pr.id}:{pr.invoice_id}",
            payload={
                "invoice_id": pr.invoice_id,
                "subtotal": str(pr.subtotal or "0.00"),
                "total_days": pr.total_days,
                "status": pr.status,
            },
        )
    except Exception:
        pass

    if pr.invoice and money_round(Decimal(pr.invoice.total or 0)) <= Decimal("0.00"):
        pr.invoice.mark_paid()
        pr.invoice.clear_payment_confirmation()
        pr.invoice.save(
            update_fields=[
                "status",
                "paid_at",
                "payment_confirmed",
                "payment_confirmed_at",
                "payment_provider",
                "payment_reference",
                "payment_event_id",
                "payment_amount",
                "payment_currency",
                "updated_at",
            ]
        )
        apply_effective_payment(pr=pr)
        pr.refresh_from_db()
    return pr


@transaction.atomic
def reject_request(*, pr: PromoRequest, reason: str, by_user) -> PromoRequest:
    pr = PromoRequest.objects.select_for_update().get(pk=pr.pk)
    pr.status = PromoRequestStatus.REJECTED
    pr.reject_reason = (reason or "")[:300]
    pr.reviewed_at = timezone.now()
    pr.save(update_fields=["status", "reject_reason", "reviewed_at", "updated_at"])
    _sync_promo_to_unified(pr=pr, changed_by=by_user)
    _notify_promo_status_change(pr=pr, status=PromoRequestStatus.REJECTED, actor=by_user)
    return pr


@transaction.atomic
def apply_effective_payment(*, pr: PromoRequest) -> PromoRequest:
    pr = _get_locked_promo_request(pr=pr)
    if not pr.invoice:
        raise ValueError("لا توجد فاتورة مرتبطة بالطلب.")
    if not pr.invoice.is_payment_effective():
        raise ValueError("الفاتورة غير مدفوعة بعد.")

    if pr.status in _PAYMENT_IMMUTABLE_REQUEST_STATUSES:
        return pr

    now = timezone.now()
    if pr.end_at and pr.end_at <= now:
        # Temporarily activate so due promo messages can still be dispatched
        pr.status = PromoRequestStatus.ACTIVE
        pr.activated_at = pr.activated_at or now
        pr.save(update_fields=["status", "activated_at", "updated_at"])
        _dispatch_due_messages_for_request(pr, now=now)

        pr.status = PromoRequestStatus.EXPIRED
        pr.ops_status = PromoOpsStatus.COMPLETED
        pr.ops_completed_at = pr.ops_completed_at or now
        pr.save(update_fields=["status", "ops_status", "ops_completed_at", "updated_at"])
        _sync_promo_to_unified(pr=pr, changed_by=pr.requester)
        _notify_promo_status_change(pr=pr, status=PromoRequestStatus.EXPIRED, actor=pr.requester)
        return pr

    if pr.ops_status == PromoOpsStatus.COMPLETED:
        return activate_after_payment(pr=pr)

    update_fields = ["updated_at"]
    status_changed = pr.status != PromoRequestStatus.NEW
    if status_changed:
        pr.status = PromoRequestStatus.NEW
        update_fields.append("status")
    if pr.activated_at is not None:
        pr.activated_at = None
        update_fields.append("activated_at")

    if len(update_fields) > 1:
        pr.save(update_fields=update_fields)
        _sync_promo_to_unified(pr=pr, changed_by=pr.requester)
        if status_changed:
            _notify_promo_status_change(pr=pr, status=PromoRequestStatus.NEW, actor=pr.requester)

    return pr


@transaction.atomic
def activate_after_payment(*, pr: PromoRequest) -> PromoRequest:
    pr = _get_locked_promo_request(pr=pr)
    if not pr.invoice:
        raise ValueError("لا توجد فاتورة مرتبطة بالطلب.")
    if not pr.invoice.is_payment_effective():
        raise ValueError("الفاتورة غير مدفوعة بعد.")

    if pr.status in _PAYMENT_IMMUTABLE_REQUEST_STATUSES:
        return pr

    now = timezone.now()
    if pr.end_at and pr.end_at <= now:
        # Temporarily activate so due promo messages can still be dispatched
        pr.status = PromoRequestStatus.ACTIVE
        pr.activated_at = pr.activated_at or now
        pr.save(update_fields=["status", "activated_at", "updated_at"])
        _dispatch_due_messages_for_request(pr, now=now)

        pr.status = PromoRequestStatus.EXPIRED
        pr.ops_status = PromoOpsStatus.COMPLETED
        pr.ops_completed_at = pr.ops_completed_at or now
        pr.save(update_fields=["status", "ops_status", "ops_completed_at", "updated_at"])
        _sync_promo_to_unified(pr=pr, changed_by=pr.requester)
        _notify_promo_status_change(pr=pr, status=PromoRequestStatus.EXPIRED, actor=pr.requester)
        return pr

    if pr.status == PromoRequestStatus.ACTIVE and pr.activated_at is not None:
        return pr

    pr.status = PromoRequestStatus.ACTIVE
    pr.activated_at = now
    pr.save(update_fields=["status", "activated_at", "updated_at"])
    _sync_promo_to_unified(pr=pr, changed_by=pr.requester)
    _notify_promo_status_change(pr=pr, status=PromoRequestStatus.ACTIVE, actor=pr.requester)
    try:
        from apps.analytics.tracking import safe_track_event

        safe_track_event(
            event_name="promo.request_activated",
            channel="server",
            surface="promo.activate_after_payment",
            source_app="promo",
            object_type="PromoRequest",
            object_id=str(pr.id),
            actor=pr.requester,
            dedupe_key=f"promo.request_activated:{pr.id}:{pr.activated_at.isoformat() if pr.activated_at else ''}",
            payload={
                "invoice_id": pr.invoice_id,
                "activated_at": pr.activated_at.isoformat() if pr.activated_at else None,
                "status": pr.status,
            },
        )
    except Exception:
        pass

    try:
        from apps.audit.models import AuditAction
        from apps.audit.services import log_action

        log_action(
            actor=pr.requester,
            action=AuditAction.PROMO_REQUEST_ACTIVE,
            reference_type="promo_request",
            reference_id=pr.code,
        )
    except Exception:
        pass

    # Dispatch any promo messages that are already due at activation time
    _dispatch_due_messages_for_request(pr, now=now)

    return pr


@transaction.atomic
def revoke_after_payment_reversal(*, pr: PromoRequest) -> PromoRequest:
    pr = _get_locked_promo_request(pr=pr)
    if not pr.invoice or pr.invoice.is_payment_effective():
        return pr

    if pr.status in _PAYMENT_IMMUTABLE_REQUEST_STATUSES:
        return pr

    pr.status = PromoRequestStatus.PENDING_PAYMENT
    pr.activated_at = None
    pr.save(update_fields=["status", "activated_at", "updated_at"])
    _sync_promo_to_unified(pr=pr, changed_by=pr.requester)
    _notify_promo_status_change(pr=pr, status=PromoRequestStatus.PENDING_PAYMENT, actor=pr.requester)
    return pr


@transaction.atomic
def set_promo_ops_status(*, pr: PromoRequest, new_status: str, by_user, note: str | None = None) -> PromoRequest:
    if new_status not in PromoOpsStatus.values:
        raise ValueError("حالة التنفيذ غير صحيحة.")
    pr = _get_locked_promo_request(pr=pr)
    current_status = pr.ops_status or PromoOpsStatus.NEW
    if new_status == current_status:
        return pr

    allowed_transitions = {
        PromoOpsStatus.NEW: {PromoOpsStatus.IN_PROGRESS},
        PromoOpsStatus.IN_PROGRESS: {PromoOpsStatus.COMPLETED},
        PromoOpsStatus.COMPLETED: set(),
    }
    allowed_next = allowed_transitions.get(current_status)
    if allowed_next is not None and new_status not in allowed_next:
        raise ValueError("تسلسل حالة التنفيذ غير صحيح. الانتقال المسموح: جديد ← تحت المعالجة ← مكتمل.")

    if new_status in {PromoOpsStatus.IN_PROGRESS, PromoOpsStatus.COMPLETED}:
        if not pr.invoice or not pr.invoice.is_payment_effective():
            raise ValueError("لا يمكن بدء أو إكمال تنفيذ طلب الترويج قبل اعتماد الدفع.")

    pr.ops_status = new_status
    now = timezone.now()
    update_fields = ["ops_status", "updated_at"]
    if new_status == PromoOpsStatus.IN_PROGRESS and pr.ops_started_at is None:
        pr.ops_started_at = now
        update_fields.append("ops_started_at")
    if new_status == PromoOpsStatus.COMPLETED:
        pr.ops_completed_at = now
        update_fields.append("ops_completed_at")
    if note is not None:
        normalized_note = (note or "").strip()[:300]
        if normalized_note != (pr.quote_note or ""):
            pr.quote_note = normalized_note
            update_fields.append("quote_note")
    pr.save(update_fields=update_fields)

    if new_status == PromoOpsStatus.COMPLETED:
        pr = activate_after_payment(pr=pr)

    _sync_promo_to_unified(pr=pr, changed_by=by_user)
    if new_status == PromoOpsStatus.COMPLETED:
        _notify_promo_ops_completed(pr=pr, actor=by_user)
    return pr


def auto_expire_promo_requests() -> int:
    """Backward-compatible alias to the unified expiry workflow."""
    return expire_due_promos(now=timezone.now())
