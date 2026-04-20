from __future__ import annotations

from collections import defaultdict
from datetime import date, datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP

from django.db import transaction
from django.db.models import Count, Sum
from django.db.models.functions import TruncDate, TruncMonth
from django.utils import timezone

from apps.billing.models import Invoice
from apps.extras.models import ExtraPurchase, ExtraPurchaseStatus
from apps.marketplace.models import RequestStatusLog, ServiceRequest
from apps.promo.models import PromoRequest
from apps.providers.location_formatter import format_city_display
from apps.subscriptions.models import Subscription, SubscriptionStatus
from apps.verification.models import VerificationRequest

from .models import (
    AnalyticsEvent,
    CampaignDailyStats,
    ExtrasDailyStats,
    ProviderDailyStats,
    SubscriptionDailyStats,
)


PERCENT_QUANT = Decimal("0.01")
DEFAULT_KPI_DAYS = 30


def _coerce_day(value=None) -> date:
    if value is None:
        return timezone.localdate()
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    if isinstance(value, datetime):
        if timezone.is_naive(value):
            value = timezone.make_aware(value, timezone.get_current_timezone())
        return timezone.localtime(value).date()
    raise TypeError("day must be a date or datetime")


def _coerce_int(value, default: int | None = None) -> int | None:
    if value in (None, ""):
        return default
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return default


def _percent(numerator: int, denominator: int) -> Decimal:
    if not denominator:
        return Decimal("0.00")
    return (
        (Decimal(str(numerator)) * Decimal("100")) / Decimal(str(denominator))
    ).quantize(PERCENT_QUANT, rounding=ROUND_HALF_UP)


def _day_window(target_day: date) -> tuple[datetime, datetime]:
    start = timezone.make_aware(datetime.combine(target_day, datetime.min.time()), timezone.get_current_timezone())
    end = start + timedelta(days=1)
    return start, end


def _normalize_range(start_date=None, end_date=None, *, default_days: int = DEFAULT_KPI_DAYS) -> tuple[date, date]:
    if end_date is None:
        end_date = timezone.localdate()
    if start_date is None:
        start_date = end_date - timedelta(days=max(0, int(default_days) - 1))
    if start_date > end_date:
        start_date, end_date = end_date, start_date
    return start_date, end_date


def _delete_missing_day_rows(model, *, target_day: date, keep_keys: list):
    qs = model.objects.filter(day=target_day)
    if keep_keys:
        field_name = model._meta.unique_together[0][1]
        qs.exclude(**{f"{field_name}__in": keep_keys}).delete()
    else:
        qs.delete()


def _campaign_identity(event: AnalyticsEvent) -> tuple[str, str, str]:
    payload = event.payload or {}
    banner_id = str(payload.get("banner_id") or "").strip()
    title = str(payload.get("title") or payload.get("headline") or "").strip()
    if event.event_name.startswith("promo.banner_") and banner_id:
        return f"banner:{banner_id}", "banner", title or f"Banner #{banner_id}"
    if event.event_name.startswith("promo.popup_"):
        object_id = str(event.object_id or payload.get("provider_id") or "").strip()
        return f"popup:{object_id or 'unknown'}", "popup", title or f"Popup {object_id or 'unknown'}"
    if event.event_name == "promo.request_activated":
        object_id = str(event.object_id or "").strip()
        return f"promo_request:{object_id or 'unknown'}", "promo_request", title or f"Promo Request #{object_id or 'unknown'}"
    object_key = str(event.object_id or banner_id or "unknown").strip()
    object_type = str(event.object_type or "campaign").strip().lower() or "campaign"
    return f"{object_type}:{object_key}", object_type, title or f"{object_type} #{object_key}"


def _subscription_bucket(payload: dict, sub: Subscription | None = None) -> tuple[str, str, str]:
    if sub is not None and getattr(sub, "plan", None) is not None:
        plan = sub.plan
        return (
            str(getattr(plan, "code", "") or ""),
            str(getattr(plan, "title", "") or ""),
            str(getattr(plan, "tier", "") or ""),
        )
    return (
        str(payload.get("plan_code") or ""),
        str(payload.get("plan_title") or payload.get("plan_name") or ""),
        str(payload.get("tier") or ""),
    )


def _classify_subscription_activation(sub: Subscription) -> tuple[bool, bool]:
    previous = (
        Subscription.objects.filter(user=sub.user)
        .exclude(id=sub.id)
        .select_related("plan")
        .order_by("-start_at", "-created_at", "-id")
        .first()
    )
    if previous is None or previous.plan_id is None or sub.plan_id is None:
        return False, False
    if previous.plan_id == sub.plan_id:
        return True, False
    tier_rank = {"basic": 1, "pro": 2, "enterprise": 3}
    previous_tier = tier_rank.get(str(getattr(previous.plan, "tier", "")).lower(), 0)
    current_tier = tier_rank.get(str(getattr(sub.plan, "tier", "")).lower(), 0)
    return False, current_tier > previous_tier


@transaction.atomic
def rebuild_provider_daily_stats(target_day=None) -> int:
    day = _coerce_day(target_day)
    counters: dict[int, dict[str, int]] = defaultdict(
        lambda: {
            "profile_views": 0,
            "chat_starts": 0,
            "requests_received": 0,
            "requests_accepted": 0,
            "requests_completed": 0,
            "requests_cancelled": 0,
        }
    )

    for event in AnalyticsEvent.objects.filter(event_name="provider.profile_view", occurred_at__date=day):
        provider_id = _coerce_int(event.object_id)
        if provider_id:
            counters[provider_id]["profile_views"] += 1

    for event in AnalyticsEvent.objects.filter(event_name="messaging.direct_thread_created", occurred_at__date=day):
        provider_id = _coerce_int((event.payload or {}).get("provider_profile_id"))
        if provider_id:
            counters[provider_id]["chat_starts"] += 1

    for row in (
        ServiceRequest.objects.filter(created_at__date=day, provider_id__isnull=False)
        .values("provider_id")
        .annotate(count=Count("id"))
    ):
        provider_id = row["provider_id"]
        counters[provider_id]["requests_received"] += int(row["count"] or 0)

    for row in (
        RequestStatusLog.objects.filter(created_at__date=day, request__provider_id__isnull=False, to_status="in_progress")
        .values("request__provider_id")
        .annotate(count=Count("id"))
    ):
        provider_id = row["request__provider_id"]
        counters[provider_id]["requests_accepted"] += int(row["count"] or 0)

    for row in (
        RequestStatusLog.objects.filter(created_at__date=day, request__provider_id__isnull=False, to_status="completed")
        .values("request__provider_id")
        .annotate(count=Count("id"))
    ):
        provider_id = row["request__provider_id"]
        counters[provider_id]["requests_completed"] += int(row["count"] or 0)

    for row in (
        RequestStatusLog.objects.filter(created_at__date=day, request__provider_id__isnull=False, to_status="cancelled")
        .values("request__provider_id")
        .annotate(count=Count("id"))
    ):
        provider_id = row["request__provider_id"]
        counters[provider_id]["requests_cancelled"] += int(row["count"] or 0)

    for provider_id, values in counters.items():
        ProviderDailyStats.objects.update_or_create(
            day=day,
            provider_id=provider_id,
            defaults={
                **values,
                "accept_rate": _percent(values["requests_accepted"], values["requests_received"]),
                "completion_rate": _percent(values["requests_completed"], values["requests_accepted"]),
            },
        )

    _delete_missing_day_rows(ProviderDailyStats, target_day=day, keep_keys=list(counters.keys()))
    return len(counters)


@transaction.atomic
def rebuild_campaign_daily_stats(target_day=None) -> int:
    day = _coerce_day(target_day)
    counters: dict[str, dict[str, object]] = {}
    for event in AnalyticsEvent.objects.filter(
        event_name__in=(
            "promo.banner_impression",
            "promo.banner_click",
            "promo.popup_open",
            "promo.popup_click",
            "promo.request_activated",
        ),
        occurred_at__date=day,
    ).order_by("id"):
        campaign_key, campaign_kind, label = _campaign_identity(event)
        bucket = counters.setdefault(
            campaign_key,
            {
                "campaign_kind": campaign_kind,
                "label": label[:160],
                "object_type": str(event.object_type or "")[:80],
                "object_id": str(event.object_id or "")[:50],
                "source_app": str(event.source_app or "")[:50],
                "impressions": 0,
                "popup_opens": 0,
                "clicks": 0,
                "leads": 0,
                "conversions": 0,
            },
        )
        if event.event_name == "promo.banner_impression":
            bucket["impressions"] += 1
        elif event.event_name == "promo.banner_click":
            bucket["clicks"] += 1
            bucket["leads"] += 1
        elif event.event_name == "promo.popup_open":
            bucket["popup_opens"] += 1
        elif event.event_name == "promo.popup_click":
            bucket["clicks"] += 1
            bucket["leads"] += 1
        elif event.event_name == "promo.request_activated":
            bucket["conversions"] += 1

    for campaign_key, values in counters.items():
        CampaignDailyStats.objects.update_or_create(
            day=day,
            campaign_key=campaign_key,
            defaults={
                **values,
                "ctr": _percent(int(values["clicks"]), int(values["impressions"])),
            },
        )

    _delete_missing_day_rows(CampaignDailyStats, target_day=day, keep_keys=list(counters.keys()))
    return len(counters)


@transaction.atomic
def rebuild_subscription_daily_stats(target_day=None) -> int:
    day = _coerce_day(target_day)
    counters: dict[str, dict[str, object]] = {}

    for event in AnalyticsEvent.objects.filter(event_name="subscriptions.checkout_created", occurred_at__date=day):
        payload = event.payload or {}
        plan_code, plan_title, tier = _subscription_bucket(payload)
        key = plan_code or "unknown"
        bucket = counters.setdefault(
            key,
            {
                "plan_code": key,
                "plan_title": plan_title[:120],
                "tier": tier[:20],
                "checkouts_started": 0,
                "activations": 0,
                "upgrades": 0,
                "renewals": 0,
                "churns": 0,
            },
        )
        bucket["checkouts_started"] += 1

    activation_events = list(AnalyticsEvent.objects.filter(event_name="subscriptions.activated", occurred_at__date=day))
    activation_ids = [_coerce_int(event.object_id) for event in activation_events]
    subscriptions = {
        sub.id: sub
        for sub in Subscription.objects.filter(id__in=[sub_id for sub_id in activation_ids if sub_id]).select_related("plan", "user")
    }
    for event in activation_events:
        sub = subscriptions.get(_coerce_int(event.object_id))
        plan_code, plan_title, tier = _subscription_bucket(event.payload or {}, sub=sub)
        key = plan_code or "unknown"
        bucket = counters.setdefault(
            key,
            {
                "plan_code": key,
                "plan_title": plan_title[:120],
                "tier": tier[:20],
                "checkouts_started": 0,
                "activations": 0,
                "upgrades": 0,
                "renewals": 0,
                "churns": 0,
            },
        )
        bucket["activations"] += 1
        if sub is not None:
            renewed, upgraded = _classify_subscription_activation(sub)
            if renewed:
                bucket["renewals"] += 1
            if upgraded:
                bucket["upgrades"] += 1

    for row in (
        Subscription.objects.filter(updated_at__date=day, status__in=(SubscriptionStatus.CANCELLED, SubscriptionStatus.EXPIRED))
        .select_related("plan")
        .values("plan__code", "plan__title", "plan__tier")
        .annotate(count=Count("id"))
    ):
        key = str(row["plan__code"] or "unknown")
        bucket = counters.setdefault(
            key,
            {
                "plan_code": key,
                "plan_title": str(row["plan__title"] or "")[:120],
                "tier": str(row["plan__tier"] or "")[:20],
                "checkouts_started": 0,
                "activations": 0,
                "upgrades": 0,
                "renewals": 0,
                "churns": 0,
            },
        )
        bucket["churns"] += int(row["count"] or 0)

    for plan_code, values in counters.items():
        SubscriptionDailyStats.objects.update_or_create(
            day=day,
            plan_code=plan_code,
            defaults=values,
        )

    _delete_missing_day_rows(SubscriptionDailyStats, target_day=day, keep_keys=list(counters.keys()))
    return len(counters)


@transaction.atomic
def rebuild_extras_daily_stats(target_day=None) -> int:
    day = _coerce_day(target_day)
    counters: dict[str, dict[str, object]] = {}

    relevant_events = list(
        AnalyticsEvent.objects.filter(
            event_name__in=("extras.checkout_created", "extras.activated", "extras.credit_consumed"),
            occurred_at__date=day,
        )
    )
    purchase_ids = [_coerce_int(event.object_id) for event in relevant_events]
    purchases = {
        purchase.id: purchase
        for purchase in ExtraPurchase.objects.filter(id__in=[purchase_id for purchase_id in purchase_ids if purchase_id])
    }

    for event in relevant_events:
        payload = event.payload or {}
        purchase = purchases.get(_coerce_int(event.object_id))
        sku = str(payload.get("sku") or getattr(purchase, "sku", "") or "unknown")[:80]
        if not sku:
            sku = "unknown"
        bucket = counters.setdefault(
            sku,
            {
                "sku": sku,
                "title": str(payload.get("title") or getattr(purchase, "title", "") or sku)[:160],
                "extra_type": str(payload.get("extra_type") or getattr(purchase, "extra_type", "") or "")[:20],
                "purchases": 0,
                "activations": 0,
                "consumptions": 0,
                "credits_consumed": 0,
            },
        )
        if event.event_name == "extras.checkout_created":
            bucket["purchases"] += 1
        elif event.event_name == "extras.activated":
            bucket["activations"] += 1
        elif event.event_name == "extras.credit_consumed":
            bucket["consumptions"] += 1
            bucket["credits_consumed"] += max(0, _coerce_int(payload.get("amount"), 0) or 0)

    for sku, values in counters.items():
        ExtrasDailyStats.objects.update_or_create(
            day=day,
            sku=sku,
            defaults=values,
        )

    _delete_missing_day_rows(ExtrasDailyStats, target_day=day, keep_keys=list(counters.keys()))
    return len(counters)


def rebuild_daily_analytics(target_day=None) -> dict[str, int | str]:
    day = _coerce_day(target_day)
    return {
        "day": day.isoformat(),
        "provider_rows": rebuild_provider_daily_stats(day),
        "campaign_rows": rebuild_campaign_daily_stats(day),
        "subscription_rows": rebuild_subscription_daily_stats(day),
        "extras_rows": rebuild_extras_daily_stats(day),
    }


def rebuild_daily_analytics_range(*, start_day=None, end_day=None) -> list[dict[str, int | str]]:
    start_date, end_date = _normalize_range(start_day, end_day, default_days=1)
    current = start_date
    rows = []
    while current <= end_date:
        rows.append(rebuild_daily_analytics(current))
        current += timedelta(days=1)
    return rows


def _build_date_range_payload(start_date: date, end_date: date) -> dict[str, str | int]:
    return {
        "start": start_date.isoformat(),
        "end": end_date.isoformat(),
        "days": (end_date - start_date).days + 1,
    }


def provider_kpis(*, start_date=None, end_date=None, provider_id=None, limit: int = 10) -> dict:
    start_date, end_date = _normalize_range(start_date, end_date)
    qs = ProviderDailyStats.objects.select_related("provider", "provider__user").filter(day__gte=start_date, day__lte=end_date)
    if provider_id:
        qs = qs.filter(provider_id=provider_id)
    rows = list(
        qs.values(
            "provider_id",
            "provider__display_name",
            "provider__city",
            "provider__region",
            "provider__user__phone",
        )
        .annotate(
            profile_views=Sum("profile_views"),
            chat_starts=Sum("chat_starts"),
            requests_received=Sum("requests_received"),
            requests_accepted=Sum("requests_accepted"),
            requests_completed=Sum("requests_completed"),
            requests_cancelled=Sum("requests_cancelled"),
        )
        .order_by("-requests_received", "-profile_views", "provider_id")[: max(1, int(limit or 10))]
    )
    items = []
    summary = {
        "profile_views": 0,
        "chat_starts": 0,
        "requests_received": 0,
        "requests_accepted": 0,
        "requests_completed": 0,
        "requests_cancelled": 0,
    }
    for row in rows:
        received = int(row["requests_received"] or 0)
        accepted = int(row["requests_accepted"] or 0)
        completed = int(row["requests_completed"] or 0)
        item = {
            "provider_id": row["provider_id"],
            "display_name": row["provider__display_name"] or "",
            "phone": row["provider__user__phone"] or "",
            "city": row["provider__city"] or "",
            "city_display": format_city_display(
                row["provider__city"] or "",
                region=row["provider__region"] or "",
            ),
            "profile_views": int(row["profile_views"] or 0),
            "chat_starts": int(row["chat_starts"] or 0),
            "requests_received": received,
            "requests_accepted": accepted,
            "requests_completed": completed,
            "requests_cancelled": int(row["requests_cancelled"] or 0),
            "accept_rate": float(_percent(accepted, received)),
            "completion_rate": float(_percent(completed, accepted)),
        }
        items.append(item)
        for key in summary:
            summary[key] += int(item[key])
    summary["accept_rate"] = float(_percent(summary["requests_accepted"], summary["requests_received"]))
    summary["completion_rate"] = float(_percent(summary["requests_completed"], summary["requests_accepted"]))
    return {
        "date_range": _build_date_range_payload(start_date, end_date),
        "summary": summary,
        "items": items,
    }


def promo_kpis(*, start_date=None, end_date=None, campaign_kind: str = "", limit: int = 10) -> dict:
    start_date, end_date = _normalize_range(start_date, end_date)
    qs = CampaignDailyStats.objects.filter(day__gte=start_date, day__lte=end_date)
    if campaign_kind:
        qs = qs.filter(campaign_kind=campaign_kind)
    rows = list(
        qs.values("campaign_key", "campaign_kind", "label", "object_type", "object_id", "source_app")
        .annotate(
            impressions=Sum("impressions"),
            popup_opens=Sum("popup_opens"),
            clicks=Sum("clicks"),
            leads=Sum("leads"),
            conversions=Sum("conversions"),
        )
        .order_by("-impressions", "-clicks", "campaign_key")[: max(1, int(limit or 10))]
    )
    items = []
    summary = {"impressions": 0, "popup_opens": 0, "clicks": 0, "leads": 0, "conversions": 0}
    for row in rows:
        impressions = int(row["impressions"] or 0)
        clicks = int(row["clicks"] or 0)
        item = {
            "campaign_key": row["campaign_key"],
            "campaign_kind": row["campaign_kind"] or "",
            "label": row["label"] or row["campaign_key"],
            "object_type": row["object_type"] or "",
            "object_id": row["object_id"] or "",
            "source_app": row["source_app"] or "",
            "impressions": impressions,
            "popup_opens": int(row["popup_opens"] or 0),
            "clicks": clicks,
            "leads": int(row["leads"] or 0),
            "conversions": int(row["conversions"] or 0),
            "ctr": float(_percent(clicks, impressions)),
        }
        items.append(item)
        for key in summary:
            summary[key] += int(item[key])
    summary["ctr"] = float(_percent(summary["clicks"], summary["impressions"]))
    return {
        "date_range": _build_date_range_payload(start_date, end_date),
        "summary": summary,
        "items": items,
    }


def subscription_kpis(*, start_date=None, end_date=None, limit: int = 10) -> dict:
    start_date, end_date = _normalize_range(start_date, end_date)
    rows = list(
        SubscriptionDailyStats.objects.filter(day__gte=start_date, day__lte=end_date)
        .values("plan_code", "plan_title", "tier")
        .annotate(
            checkouts_started=Sum("checkouts_started"),
            activations=Sum("activations"),
            upgrades=Sum("upgrades"),
            renewals=Sum("renewals"),
            churns=Sum("churns"),
        )
        .order_by("-activations", "-checkouts_started", "plan_code")[: max(1, int(limit or 10))]
    )
    items = []
    summary = {"checkouts_started": 0, "activations": 0, "upgrades": 0, "renewals": 0, "churns": 0}
    for row in rows:
        item = {
            "plan_code": row["plan_code"] or "",
            "plan_title": row["plan_title"] or "",
            "tier": row["tier"] or "",
            "checkouts_started": int(row["checkouts_started"] or 0),
            "activations": int(row["activations"] or 0),
            "upgrades": int(row["upgrades"] or 0),
            "renewals": int(row["renewals"] or 0),
            "churns": int(row["churns"] or 0),
        }
        items.append(item)
        for key in summary:
            summary[key] += int(item[key])
    return {
        "date_range": _build_date_range_payload(start_date, end_date),
        "summary": summary,
        "items": items,
    }


def extras_kpis(*, start_date=None, end_date=None, limit: int = 10) -> dict:
    start_date, end_date = _normalize_range(start_date, end_date)
    rows = list(
        ExtrasDailyStats.objects.filter(day__gte=start_date, day__lte=end_date)
        .values("sku", "title", "extra_type")
        .annotate(
            purchases=Sum("purchases"),
            activations=Sum("activations"),
            consumptions=Sum("consumptions"),
            credits_consumed=Sum("credits_consumed"),
        )
        .order_by("-purchases", "-activations", "sku")[: max(1, int(limit or 10))]
    )
    items = []
    summary = {"purchases": 0, "activations": 0, "consumptions": 0, "credits_consumed": 0}
    for row in rows:
        item = {
            "sku": row["sku"] or "",
            "title": row["title"] or row["sku"] or "",
            "extra_type": row["extra_type"] or "",
            "purchases": int(row["purchases"] or 0),
            "activations": int(row["activations"] or 0),
            "consumptions": int(row["consumptions"] or 0),
            "credits_consumed": int(row["credits_consumed"] or 0),
        }
        items.append(item)
        for key in summary:
            summary[key] += int(item[key])
    return {
        "date_range": _build_date_range_payload(start_date, end_date),
        "summary": summary,
        "items": items,
    }


def kpis_summary(start_date=None, end_date=None):
    start_date, end_date = _normalize_range(start_date, end_date)

    inv_qs = Invoice.objects.all()
    if start_date:
        inv_qs = inv_qs.filter(paid_at__date__gte=start_date)
    if end_date:
        inv_qs = inv_qs.filter(paid_at__date__lte=end_date)

    paid = inv_qs.filter(status="paid")

    revenue_total = paid.aggregate(total=Sum("total"))["total"] or 0
    invoices_paid = paid.count()

    subs_active = Subscription.objects.filter(
        status=SubscriptionStatus.ACTIVE,
        created_at__date__gte=start_date,
        created_at__date__lte=end_date,
    ).count()
    subs_expired = Subscription.objects.filter(
        status=SubscriptionStatus.EXPIRED,
        created_at__date__gte=start_date,
        created_at__date__lte=end_date,
    ).count()

    ad_total = VerificationRequest.objects.filter(
        requested_at__date__gte=start_date,
        requested_at__date__lte=end_date,
    ).count()
    md_total = PromoRequest.objects.filter(
        created_at__date__gte=start_date,
        created_at__date__lte=end_date,
    ).count()

    return {
        "revenue_total": float(revenue_total),
        "invoices_paid": invoices_paid,
        "subs_active": subs_active,
        "subs_expired": subs_expired,
        "ad_requests": ad_total,
        "md_requests": md_total,
    }


def revenue_daily(start_date=None, end_date=None):
    qs = Invoice.objects.filter(status="paid").exclude(paid_at__isnull=True)

    if start_date:
        qs = qs.filter(paid_at__date__gte=start_date)
    if end_date:
        qs = qs.filter(paid_at__date__lte=end_date)

    data = (
        qs.annotate(d=TruncDate("paid_at"))
        .values("d")
        .annotate(total=Sum("total"), count=Count("id"))
        .order_by("d")
    )
    return [{"date": str(x["d"]), "total": float(x["total"] or 0), "count": x["count"]} for x in data]


def revenue_monthly(start_date=None, end_date=None):
    qs = Invoice.objects.filter(status="paid").exclude(paid_at__isnull=True)

    if start_date:
        qs = qs.filter(paid_at__date__gte=start_date)
    if end_date:
        qs = qs.filter(paid_at__date__lte=end_date)

    data = (
        qs.annotate(m=TruncMonth("paid_at"))
        .values("m")
        .annotate(total=Sum("total"), count=Count("id"))
        .order_by("m")
    )

    out = []
    for x in data:
        month_value = x.get("m")
        if hasattr(month_value, "strftime"):
            month = month_value.strftime("%Y-%m")
        else:
            month = str(month_value)[:7]
        out.append({"month": month, "total": float(x["total"] or 0), "count": x["count"]})
    return out


def requests_breakdown(start_date=None, end_date=None):
    start_date, end_date = _normalize_range(start_date, end_date)

    ad_qs = VerificationRequest.objects.all()
    md_qs = PromoRequest.objects.all()

    if start_date:
        ad_qs = ad_qs.filter(requested_at__date__gte=start_date)
        md_qs = md_qs.filter(created_at__date__gte=start_date)
    if end_date:
        ad_qs = ad_qs.filter(requested_at__date__lte=end_date)
        md_qs = md_qs.filter(created_at__date__lte=end_date)

    ad = ad_qs.values("status").annotate(count=Count("id")).order_by("-count")
    md = md_qs.values("status").annotate(count=Count("id")).order_by("-count")

    return {
        "verification": list(ad),
        "promo": list(md),
    }
