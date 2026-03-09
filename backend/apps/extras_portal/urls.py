from django.urls import path

from . import views


app_name = "extras_portal"


urlpatterns = [
    path("", views.portal_home, name="home"),
    path("login/", views.portal_login, name="login"),
    path("otp/", views.portal_otp, name="otp"),
    path("logout/", views.portal_logout, name="logout"),

    path("reports/", views.portal_reports, name="reports"),
    path("reports/export/pdf/", views.portal_reports_export_pdf, name="reports_export_pdf"),
    path("reports/export/xlsx/", views.portal_reports_export_xlsx, name="reports_export_xlsx"),

    path("clients/", views.portal_clients, name="clients"),

    path("finance/", views.portal_finance, name="finance"),
    path("finance/export/pdf/", views.portal_finance_export_pdf, name="finance_export_pdf"),
    path("finance/export/xlsx/", views.portal_finance_export_xlsx, name="finance_export_xlsx"),

    path("finance/invoice/<int:pk>/", views.portal_invoice_detail, name="invoice_detail"),
]
