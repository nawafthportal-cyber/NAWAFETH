from __future__ import annotations

from datetime import timedelta

from django.core.paginator import Paginator
from django.db.models import Count
from django.urls import reverse
from django.utils import timezone
from django.shortcuts import render

from apps.analytics.filters import parse_dates
from apps.analytics.models import AnalyticsEvent
from apps.analytics.services import (
    extras_kpis,
    kpis_summary,
    promo_kpis,
    provider_kpis,
    requests_breakdown,
    revenue_daily,
    revenue_monthly,
    subscription_kpis,
)
from apps.core.feature_flags import analytics_kpi_surfaces_enabled
from apps.dashboard.access import has_action_permission, has_dashboard_access
from apps.dashboard.contracts import DashboardCode

from ..view_utils import build_layout_context, dashboard_v2_access_required


def _normalize_dates(request):
    start_date, end_date = parse_dates(request.GET)
    if end_date is None:
        end_date = timezone.localdate()
    if start_date is None:
        start_date = end_date - timedelta(days=29)
    if start_date > end_date:
        start_date, end_date = end_date, start_date
    return start_date, end_date


def _empty_kpi_payload(*, start_date, end_date) -> dict:
    date_range = {
        "start": start_date.isoformat(),
        "end": end_date.isoformat(),
        "days": (end_date - start_date).days + 1,
    }
    return {
        "date_range": date_range,
        "summary": {},
        "items": [],
    }


def _analytics_bundle(*, start_date, end_date, enabled: bool):
    if not enabled:
        provider_data = _empty_kpi_payload(start_date=start_date, end_date=end_date)
        promo_data = _empty_kpi_payload(start_date=start_date, end_date=end_date)
        subscription_data = _empty_kpi_payload(start_date=start_date, end_date=end_date)
        extras_data = _empty_kpi_payload(start_date=start_date, end_date=end_date)
        summary_cards = {
            "revenue_total": 0,
            "invoices_paid": 0,
            "subs_active": 0,
            "subs_expired": 0,
            "ad_requests": 0,
            "md_requests": 0,
        }
        revenue_daily_rows = []
        revenue_monthly_rows = []
        breakdown_rows = {"verification": [], "promo": []}
    else:
        provider_data = provider_kpis(start_date=start_date, end_date=end_date, limit=12)
        promo_data = promo_kpis(start_date=start_date, end_date=end_date, limit=12)
        subscription_data = subscription_kpis(start_date=start_date, end_date=end_date, limit=12)
        extras_data = extras_kpis(start_date=start_date, end_date=end_date, limit=12)
        summary_cards = kpis_summary(start_date=start_date, end_date=end_date)
        revenue_daily_rows = revenue_daily(start_date=start_date, end_date=end_date)
        revenue_monthly_rows = revenue_monthly(start_date=start_date, end_date=end_date)
        breakdown_rows = requests_breakdown()

    return {
        "enabled": enabled,
        "provider_data": provider_data,
        "promo_data": promo_data,
        "subscription_data": subscription_data,
        "extras_data": extras_data,
        "summary_cards": summary_cards,
        "revenue_daily_rows": revenue_daily_rows,
        "revenue_monthly_rows": revenue_monthly_rows,
        "breakdown_rows": breakdown_rows,
    }


@dashboard_v2_access_required(DashboardCode.ANALYTICS, write=False)
def analytics_overview_view(request):
    start_date, end_date = _normalize_dates(request)
    enabled = analytics_kpi_surfaces_enabled()
    payload = _analytics_bundle(start_date=start_date, end_date=end_date, enabled=enabled)

    context = build_layout_context(
        request,
        title="التحليلات",
        subtitle="Overview تشغيلي للمؤشرات الأساسية",
        active_code=DashboardCode.ANALYTICS,
        breadcrumbs=[{"label": "لوحة التحكم", "url": "dashboard_v2:home"}],
    )
    context.update(
        {
            **payload,
            "date_from_val": start_date.isoformat(),
            "date_to_val": end_date.isoformat(),
            "can_export": has_dashboard_access(request.user, DashboardCode.ANALYTICS, write=True)
            and has_action_permission(request.user, "analytics.export"),
            "events_count": AnalyticsEvent.objects.count(),
            "reports_sections": [
                {"key": "provider", "label": "المزوّدون"},
                {"key": "promo", "label": "الترويج"},
                {"key": "subscription", "label": "الاشتراكات"},
                {"key": "extras", "label": "الخدمات الإضافية"},
            ],
        }
    )
    return render(request, "dashboard_v2/analytics/overview.html", context)


@dashboard_v2_access_required(DashboardCode.ANALYTICS, write=False)
def analytics_reports_index_view(request):
    start_date, end_date = _normalize_dates(request)
    enabled = analytics_kpi_surfaces_enabled()
    payload = _analytics_bundle(start_date=start_date, end_date=end_date, enabled=enabled)

    section = (request.GET.get("section") or "provider").strip().lower()
    section_map = {
        "provider": {
            "title": "تقرير أداء المزوّدين",
            "headers": ["المزوّد", "المدينة", "المشاهدات", "المحادثات", "الطلبات", "القبول %", "الإنجاز %"],
            "items": payload["provider_data"].get("items", []),
        },
        "promo": {
            "title": "تقرير أداء الترويج",
            "headers": ["الحملة", "النوع", "الانطباعات", "النقرات", "CTR %", "Leads", "Conversions"],
            "items": payload["promo_data"].get("items", []),
        },
        "subscription": {
            "title": "تقرير الاشتراكات",
            "headers": ["الخطة", "Tier", "Starts", "Activations", "Upgrades", "Renewals", "Churns"],
            "items": payload["subscription_data"].get("items", []),
        },
        "extras": {
            "title": "تقرير الخدمات الإضافية",
            "headers": ["الخدمة", "SKU", "النوع", "المشتريات", "التفعيلات", "الاستهلاك", "Credits"],
            "items": payload["extras_data"].get("items", []),
        },
    }
    if section not in section_map:
        section = "provider"

    selected = section_map[section]
    paginator = Paginator(selected["items"], 25)
    page_obj = paginator.get_page(request.GET.get("page") or "1")
    query = request.GET.copy()
    query.pop("page", None)

    context = build_layout_context(
        request,
        title="تقارير التحليلات",
        subtitle="Index موحّد لتقارير KPI بحسب الوحدة",
        active_code=DashboardCode.ANALYTICS,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "التحليلات", "url": "dashboard_v2:analytics_overview"},
        ],
    )
    context.update(
        {
            "enabled": enabled,
            "section": section,
            "sections": [
                {"key": "provider", "label": "المزوّدون"},
                {"key": "promo", "label": "الترويج"},
                {"key": "subscription", "label": "الاشتراكات"},
                {"key": "extras", "label": "الخدمات الإضافية"},
            ],
            "selected_title": selected["title"],
            "table_headers": selected["headers"],
            "page_obj": page_obj,
            "query_string": query.urlencode(),
            "date_from_val": start_date.isoformat(),
            "date_to_val": end_date.isoformat(),
            "date_range": payload["provider_data"].get("date_range"),
        }
    )
    return render(request, "dashboard_v2/analytics/reports_index.html", context)


@dashboard_v2_access_required(DashboardCode.ANALYTICS, write=False)
def analytics_exports_view(request):
    can_export = has_dashboard_access(request.user, DashboardCode.ANALYTICS, write=True) and has_action_permission(
        request.user,
        "analytics.export",
    )

    export_links = [
        {
            "label": "Provider KPI Report",
            "description": "تقرير مجمّع لأداء المزوّدين ضمن التحليلات.",
            "url": reverse("dashboard_v2:analytics_reports_index") + "?section=provider",
        },
        {
            "label": "Promo KPI Report",
            "description": "تقرير حملات الترويج (impressions/clicks/conversions).",
            "url": reverse("dashboard_v2:analytics_reports_index") + "?section=promo",
        },
        {
            "label": "Legacy Insights",
            "description": "صفحة legacy التحليلية للحالات المتقدمة أو التوافق الخلفي.",
            "url": reverse("dashboard:analytics_insights"),
        },
        {
            "label": "Features Overview CSV",
            "description": "تصدير حالة الميزات للمستخدمين (legacy).",
            "url": reverse("dashboard:features_overview") + "?export=csv",
        },
    ]

    context = build_layout_context(
        request,
        title="مركز التصدير التحليلي",
        subtitle="روابط التصدير والتقارير الجاهزة حسب الصلاحية",
        active_code=DashboardCode.ANALYTICS,
        breadcrumbs=[
            {"label": "لوحة التحكم", "url": "dashboard_v2:home"},
            {"label": "التحليلات", "url": "dashboard_v2:analytics_overview"},
        ],
    )
    context.update(
        {
            "can_export": can_export,
            "export_links": export_links,
            "event_rows": list(
                AnalyticsEvent.objects.values("event_name")
                .annotate(count=Count("id"))
                .order_by("-count", "event_name")[:20]
            ),
        }
    )
    return render(request, "dashboard_v2/analytics/exports.html", context)
