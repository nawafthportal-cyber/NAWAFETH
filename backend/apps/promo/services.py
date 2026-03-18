from __future__ import annotations

import os
from decimal import Decimal

from django.conf import settings
from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from apps.billing.models import Invoice, InvoiceLineItem, InvoiceStatus, money_round
from apps.notifications.models import EventType
from apps.notifications.services import create_notification

from .models import (
    PromoAdPrice,
    PromoAdType,
    PromoFrequency,
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
        "code": "featured_10s",
        "service_type": PromoServiceType.FEATURED_SPECIALISTS,
        "title": "شريط أبرز المختصين - كل 10 ثواني",
        "unit": PromoPriceUnit.DAY,
        "frequency": PromoFrequency.S10,
        "amount": Decimal("2000.00"),
        "sort_order": 20,
    },
    {
        "code": "featured_30s",
        "service_type": PromoServiceType.FEATURED_SPECIALISTS,
        "title": "شريط أبرز المختصين - كل 30 ثانية",
        "unit": PromoPriceUnit.DAY,
        "frequency": PromoFrequency.S30,
        "amount": Decimal("1500.00"),
        "sort_order": 21,
    },
    {
        "code": "featured_60s",
        "service_type": PromoServiceType.FEATURED_SPECIALISTS,
        "title": "شريط أبرز المختصين - كل دقيقة",
        "unit": PromoPriceUnit.DAY,
        "frequency": PromoFrequency.S60,
        "amount": Decimal("1000.00"),
        "sort_order": 22,
    },
    {
        "code": "featured_300s",
        "service_type": PromoServiceType.FEATURED_SPECIALISTS,
        "title": "شريط أبرز المختصين - كل 5 دقائق",
        "unit": PromoPriceUnit.DAY,
        "frequency": PromoFrequency.S300,
        "amount": Decimal("500.00"),
        "sort_order": 23,
    },
    {
        "code": "featured_900s",
        "service_type": PromoServiceType.FEATURED_SPECIALISTS,
        "title": "شريط أبرز المختصين - كل 15 دقيقة",
        "unit": PromoPriceUnit.DAY,
        "frequency": PromoFrequency.S900,
        "amount": Decimal("250.00"),
        "sort_order": 24,
    },
    {
        "code": "featured_1800s",
        "service_type": PromoServiceType.FEATURED_SPECIALISTS,
        "title": "شريط أبرز المختصين - كل 30 دقيقة",
        "unit": PromoPriceUnit.DAY,
        "frequency": PromoFrequency.S1800,
        "amount": Decimal("200.00"),
        "sort_order": 25,
    },
    {
        "code": "featured_3600s",
        "service_type": PromoServiceType.FEATURED_SPECIALISTS,
        "title": "شريط أبرز المختصين - كل ساعة",
        "unit": PromoPriceUnit.DAY,
        "frequency": PromoFrequency.S3600,
        "amount": Decimal("100.00"),
        "sort_order": 26,
    },
    {
        "code": "portfolio_10s",
        "service_type": PromoServiceType.PORTFOLIO_SHOWCASE,
        "title": "شريط البنرات والمشاريع - كل 10 ثواني",
        "unit": PromoPriceUnit.DAY,
        "frequency": PromoFrequency.S10,
        "amount": Decimal("2000.00"),
        "sort_order": 30,
    },
    {
        "code": "portfolio_30s",
        "service_type": PromoServiceType.PORTFOLIO_SHOWCASE,
        "title": "شريط البنرات والمشاريع - كل 30 ثانية",
        "unit": PromoPriceUnit.DAY,
        "frequency": PromoFrequency.S30,
        "amount": Decimal("1500.00"),
        "sort_order": 31,
    },
    {
        "code": "portfolio_60s",
        "service_type": PromoServiceType.PORTFOLIO_SHOWCASE,
        "title": "شريط البنرات والمشاريع - كل دقيقة",
        "unit": PromoPriceUnit.DAY,
        "frequency": PromoFrequency.S60,
        "amount": Decimal("1000.00"),
        "sort_order": 32,
    },
    {
        "code": "portfolio_300s",
        "service_type": PromoServiceType.PORTFOLIO_SHOWCASE,
        "title": "شريط البنرات والمشاريع - كل 5 دقائق",
        "unit": PromoPriceUnit.DAY,
        "frequency": PromoFrequency.S300,
        "amount": Decimal("500.00"),
        "sort_order": 33,
    },
    {
        "code": "portfolio_900s",
        "service_type": PromoServiceType.PORTFOLIO_SHOWCASE,
        "title": "شريط البنرات والمشاريع - كل 15 دقيقة",
        "unit": PromoPriceUnit.DAY,
        "frequency": PromoFrequency.S900,
        "amount": Decimal("250.00"),
        "sort_order": 34,
    },
    {
        "code": "portfolio_1800s",
        "service_type": PromoServiceType.PORTFOLIO_SHOWCASE,
        "title": "شريط البنرات والمشاريع - كل 30 دقيقة",
        "unit": PromoPriceUnit.DAY,
        "frequency": PromoFrequency.S1800,
        "amount": Decimal("200.00"),
        "sort_order": 35,
    },
    {
        "code": "portfolio_3600s",
        "service_type": PromoServiceType.PORTFOLIO_SHOWCASE,
        "title": "شريط البنرات والمشاريع - كل ساعة",
        "unit": PromoPriceUnit.DAY,
        "frequency": PromoFrequency.S3600,
        "amount": Decimal("100.00"),
        "sort_order": 36,
    },
    {
        "code": "snapshots_10s",
        "service_type": PromoServiceType.SNAPSHOTS,
        "title": "شريط اللمحات - كل 10 ثواني",
        "unit": PromoPriceUnit.DAY,
        "frequency": PromoFrequency.S10,
        "amount": Decimal("2000.00"),
        "sort_order": 40,
    },
    {
        "code": "snapshots_30s",
        "service_type": PromoServiceType.SNAPSHOTS,
        "title": "شريط اللمحات - كل 30 ثانية",
        "unit": PromoPriceUnit.DAY,
        "frequency": PromoFrequency.S30,
        "amount": Decimal("1500.00"),
        "sort_order": 41,
    },
    {
        "code": "snapshots_60s",
        "service_type": PromoServiceType.SNAPSHOTS,
        "title": "شريط اللمحات - كل دقيقة",
        "unit": PromoPriceUnit.DAY,
        "frequency": PromoFrequency.S60,
        "amount": Decimal("1000.00"),
        "sort_order": 42,
    },
    {
        "code": "snapshots_300s",
        "service_type": PromoServiceType.SNAPSHOTS,
        "title": "شريط اللمحات - كل 5 دقائق",
        "unit": PromoPriceUnit.DAY,
        "frequency": PromoFrequency.S300,
        "amount": Decimal("500.00"),
        "sort_order": 43,
    },
    {
        "code": "snapshots_900s",
        "service_type": PromoServiceType.SNAPSHOTS,
        "title": "شريط اللمحات - كل 15 دقيقة",
        "unit": PromoPriceUnit.DAY,
        "frequency": PromoFrequency.S900,
        "amount": Decimal("250.00"),
        "sort_order": 44,
    },
    {
        "code": "snapshots_1800s",
        "service_type": PromoServiceType.SNAPSHOTS,
        "title": "شريط اللمحات - كل 30 دقيقة",
        "unit": PromoPriceUnit.DAY,
        "frequency": PromoFrequency.S1800,
        "amount": Decimal("200.00"),
        "sort_order": 45,
    },
    {
        "code": "snapshots_3600s",
        "service_type": PromoServiceType.SNAPSHOTS,
        "title": "شريط اللمحات - كل ساعة",
        "unit": PromoPriceUnit.DAY,
        "frequency": PromoFrequency.S3600,
        "amount": Decimal("100.00"),
        "sort_order": 46,
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


def _platform_config():
    from apps.core.models import PlatformConfig

    return PlatformConfig.load()


def promo_min_campaign_hours() -> int:
    return max(1, int(_platform_config().promo_min_campaign_hours or 24))


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


def _promo_frequency_multipliers_map() -> dict[str, Decimal]:
    config = _platform_config()
    raw = (
        config.get_promo_frequency_multipliers()
        or getattr(settings, "PROMO_FREQUENCY_MULTIPLIER", {})
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


def _notify_promo_status_change(*, pr: PromoRequest, status: str, actor=None) -> None:
    try:
        code_or_id = (pr.code or str(pr.id)).strip()
        create_notification(
            user=pr.requester,
            title="تحديث حالة الترويج",
            body=f"تم تحديث حالة طلب الترويج ({code_or_id}) إلى {_promo_status_label(status)}.",
            kind="promo_status_change",
            url=f"/promo/requests/{pr.id}/",
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
        pass


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


def _legacy_frequency_value(freq: str) -> Decimal:
    return _promo_frequency_multipliers_map().get(freq, Decimal("1.0"))


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
    subtotal *= _legacy_frequency_value(pr.frequency)
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


def _get_pricing_rule(*, service_type: str, frequency: str = "", search_position: str = "", message_channel: str = "") -> PromoPricingRule:
    ensure_default_pricing_rules()
    qs = PromoPricingRule.objects.filter(service_type=service_type, is_active=True)
    if frequency:
        qs = qs.filter(frequency=frequency)
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
        if item.frequency not in PromoFrequency.values:
            raise ValueError(f"{item.get_service_type_display()}: معدل الظهور غير صحيح.")
        days = _duration_days(item.start_at, item.end_at)
        rule = _get_pricing_rule(service_type=service_type, frequency=item.frequency)
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
            frequency=validated_data.get("frequency") or PromoFrequency.S60,
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
        title=(validated_data.get("title") or "طلب ترويج متعدد الخدمات")[:160],
        ad_type=PromoAdType.BUNDLE,
        start_at=timezone.now(),
        end_at=timezone.now(),
        frequency=PromoFrequency.S60,
        position=PromoPosition.NORMAL,
    )

    subtotal = Decimal("0.00")
    total_days = 0
    preview_items = []

    for index, row in enumerate(items_data):
        normalized = {key: value for key, value in row.items() if key != "asset_count"}
        if (
            provider_profile is not None
            and normalized.get("service_type") in auto_targeted_service_types
            and not normalized.get("target_provider")
        ):
            normalized["target_provider"] = provider_profile

        item = PromoRequestItem(request=pr, **normalized)
        item.sort_order = int(normalized.get("sort_order") or index)
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

    subtotal = money_round(subtotal)
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
        "total_days": total_days,
        "items": preview_items,
    }


def _invoice_title_for_request(pr: PromoRequest) -> str:
    return f"فاتورة طلب الترويج {pr.code or pr.id}"


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
    for idx, row in enumerate(q.get("items", []), start=1):
        item = row["item"]
        line_rows.append(
            InvoiceLineItem(
                invoice=inv,
                item_code=item.pricing_rule_code or item.service_type,
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

    qs = (
        User.objects.filter(
            is_active=True,
            role_state=UserRole.PROVIDER,
            provider_profile__isnull=False,
        )
        .select_related("provider_profile")
        .exclude(id=item.request.requester_id)
    )
    if city:
        qs = qs.filter(
            Q(provider_profile__city__iexact=city)
            | Q(city__iexact=city)
        )
    if category:
        qs = qs.filter(
            Q(provider_profile__providercategory__subcategory__name__iexact=category)
            | Q(provider_profile__providercategory__subcategory__category__name__iexact=category)
        )
    return qs.distinct().order_by("id")


def _get_or_create_direct_thread(*, user_a, user_b, context_mode: str):
    from apps.messaging.models import Thread

    if not getattr(user_a, "id", None) or not getattr(user_b, "id", None):
        raise ValueError("missing direct-thread participants")
    if user_a.id == user_b.id:
        raise ValueError("cannot chat self")
    thread = (
        Thread.objects.filter(is_direct=True, context_mode=context_mode)
        .filter(
            Q(participant_1=user_a, participant_2=user_b)
            | Q(participant_1=user_b, participant_2=user_a)
        )
        .first()
    )
    if thread:
        return thread
    return Thread.objects.create(
        is_direct=True,
        context_mode=context_mode,
        participant_1=user_a,
        participant_2=user_b,
    )


@transaction.atomic
def dispatch_promo_message_item(*, item: PromoRequestItem, now=None) -> int:
    from apps.messaging.models import Message, Thread
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
    if item.request.end_at and item.request.end_at < now:
        return 0

    sender_user = item.request.requester
    body = str(item.message_body or item.request.message_body or "").strip()
    if not body and not _item_assets(item):
        raise ValueError("promo message has no body or attachments to deliver")

    title = str(item.message_title or item.request.message_title or "").strip()
    if not title:
        title = f"رسالة دعائية من {_promo_message_sender_label(pr=item.request)}"
    landing_url = _promo_message_default_url(item=item)
    assets = _item_assets(item)
    delivered_count = 0

    for recipient in _promo_message_recipient_users(item=item):
        delivered = False

        if item.use_notification_channel:
            notification = create_notification(
                user=recipient,
                title=title,
                body=body or "لديك رسالة دعائية جديدة.",
                kind="promo_offer",
                url=landing_url,
                actor=sender_user,
                pref_key="ads_and_offers",
                audience_mode="provider",
                meta={
                    "promo_request_id": item.request_id,
                    "promo_request_item_id": item.id,
                    "channel": "notification",
                },
            )
            delivered = delivered or notification is not None

        if item.use_chat_channel:
            thread = _get_or_create_direct_thread(
                user_a=sender_user,
                user_b=recipient,
                context_mode=Thread.ContextMode.PROVIDER,
            )
            if not _is_blocked_by_other(thread, sender_user.id):
                if body:
                    Message.objects.create(
                        thread=thread,
                        sender=sender_user,
                        body=body,
                        created_at=now,
                    )
                    delivered = True
                for asset in assets:
                    Message.objects.create(
                        thread=thread,
                        sender=sender_user,
                        body="",
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
        activate_after_payment(pr=pr)
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
def activate_after_payment(*, pr: PromoRequest) -> PromoRequest:
    pr = PromoRequest.objects.select_for_update().get(pk=pr.pk)
    if not pr.invoice:
        raise ValueError("لا توجد فاتورة مرتبطة بالطلب.")
    if not pr.invoice.is_payment_effective():
        raise ValueError("الفاتورة غير مدفوعة بعد.")

    now = timezone.now()
    if pr.end_at and pr.end_at <= now:
        pr.status = PromoRequestStatus.EXPIRED
        pr.ops_status = PromoOpsStatus.COMPLETED
        pr.ops_completed_at = pr.ops_completed_at or now
        pr.save(update_fields=["status", "ops_status", "ops_completed_at", "updated_at"])
        _sync_promo_to_unified(pr=pr, changed_by=pr.requester)
        _notify_promo_status_change(pr=pr, status=PromoRequestStatus.EXPIRED, actor=pr.requester)
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
    return pr


@transaction.atomic
def revoke_after_payment_reversal(*, pr: PromoRequest) -> PromoRequest:
    pr = PromoRequest.objects.select_for_update().select_related("invoice").get(pk=pr.pk)
    if not pr.invoice or pr.invoice.is_payment_effective():
        return pr

    pr.status = PromoRequestStatus.PENDING_PAYMENT
    pr.activated_at = None
    pr.save(update_fields=["status", "activated_at", "updated_at"])
    _sync_promo_to_unified(pr=pr, changed_by=pr.requester)
    _notify_promo_status_change(pr=pr, status=PromoRequestStatus.PENDING_PAYMENT, actor=pr.requester)
    return pr


@transaction.atomic
def set_promo_ops_status(*, pr: PromoRequest, new_status: str, by_user, note: str = "") -> PromoRequest:
    if new_status not in PromoOpsStatus.values:
        raise ValueError("حالة التنفيذ غير صحيحة.")
    pr = PromoRequest.objects.select_for_update().get(pk=pr.pk)
    pr.ops_status = new_status
    now = timezone.now()
    update_fields = ["ops_status", "updated_at"]
    if new_status == PromoOpsStatus.IN_PROGRESS and pr.ops_started_at is None:
        pr.ops_started_at = now
        update_fields.append("ops_started_at")
    if new_status == PromoOpsStatus.COMPLETED:
        pr.ops_completed_at = now
        update_fields.append("ops_completed_at")
    pr.save(update_fields=update_fields)
    _sync_promo_to_unified(pr=pr, changed_by=by_user)
    return pr
