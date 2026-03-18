from __future__ import annotations

from django.http import Http404, HttpRequest, HttpResponse
from django.shortcuts import render

from apps.analytics.filters import parse_dates
from apps.analytics.services import extras_kpis, promo_kpis, provider_kpis, subscription_kpis
from apps.core.feature_flags import analytics_kpi_surfaces_enabled

from .auth import dashboard_staff_required as staff_member_required
from .views import dashboard_access_required


def _ensure_enabled():
    if not analytics_kpi_surfaces_enabled():
        raise Http404


@staff_member_required
@dashboard_access_required("analytics", write=False)
def analytics_insights(request: HttpRequest) -> HttpResponse:
    _ensure_enabled()
    start_date, end_date = parse_dates(request.GET)
    provider_data = provider_kpis(start_date=start_date, end_date=end_date, limit=8)
    promo_data = promo_kpis(start_date=start_date, end_date=end_date, limit=8)
    subscription_data = subscription_kpis(start_date=start_date, end_date=end_date, limit=8)
    extras_data = extras_kpis(start_date=start_date, end_date=end_date, limit=8)

    return render(
        request,
        "dashboard/analytics_insights.html",
        {
            "provider_data": provider_data,
            "promo_data": promo_data,
            "subscription_data": subscription_data,
            "extras_data": extras_data,
            "date_range": provider_data["date_range"],
            "date_from_val": provider_data["date_range"]["start"],
            "date_to_val": provider_data["date_range"]["end"],
        },
    )
