from django.urls import path

from .views import (
    BackofficeModerationAssignView,
    BackofficeModerationCaseDetailView,
    BackofficeModerationCasesListView,
    BackofficeModerationDecisionView,
    BackofficeModerationStatusView,
    ModerationCaseDetailView,
    ModerationReportCreateView,
    MyModerationCasesListView,
)


urlpatterns = [
    path("reports/", ModerationReportCreateView.as_view(), name="report_create"),
    path("cases/my/", MyModerationCasesListView.as_view(), name="my_cases"),
    path("cases/<int:pk>/", ModerationCaseDetailView.as_view(), name="case_detail"),
    path("backoffice/cases/", BackofficeModerationCasesListView.as_view(), name="backoffice_cases"),
    path("backoffice/cases/<int:pk>/", BackofficeModerationCaseDetailView.as_view(), name="backoffice_case_detail"),
    path("backoffice/cases/<int:pk>/assign/", BackofficeModerationAssignView.as_view(), name="backoffice_assign"),
    path("backoffice/cases/<int:pk>/status/", BackofficeModerationStatusView.as_view(), name="backoffice_status"),
    path("backoffice/cases/<int:pk>/decision/", BackofficeModerationDecisionView.as_view(), name="backoffice_decision"),
]
