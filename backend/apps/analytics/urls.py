from django.urls import path

from .views import (
    AnalyticsEventIngestView,
    DashboardKPIsView,
    ExtrasKPIsView,
    PromoKPIsView,
    ProviderKPIsView,
    RevenueDailyView,
    RevenueMonthlyView,
    RequestsBreakdownView,
    ExportPaidInvoicesCSVView,
    SubscriptionKPIsView,
)

urlpatterns = [
    path("events/", AnalyticsEventIngestView.as_view(), name="event_ingest"),
    path("kpis/", DashboardKPIsView.as_view(), name="kpis"),
    path("kpis/providers/", ProviderKPIsView.as_view(), name="provider_kpis"),
    path("kpis/promo/", PromoKPIsView.as_view(), name="promo_kpis"),
    path("kpis/subscriptions/", SubscriptionKPIsView.as_view(), name="subscription_kpis"),
    path("kpis/extras/", ExtrasKPIsView.as_view(), name="extras_kpis"),
    path("revenue/daily/", RevenueDailyView.as_view(), name="revenue_daily"),
    path("revenue/monthly/", RevenueMonthlyView.as_view(), name="revenue_monthly"),
    path("requests/breakdown/", RequestsBreakdownView.as_view(), name="requests_breakdown"),
    path("export/paid-invoices.csv", ExportPaidInvoicesCSVView.as_view(), name="export_paid_invoices_csv"),
]
