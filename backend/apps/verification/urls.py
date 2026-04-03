from django.urls import path

from .views import (
    VerificationBluePreviewView,
    MyVerificationPricingView,
    VerificationRequestCreateView,
    MyVerificationRequestsListView,
    VerificationRequestDetailView,
    VerificationAddDocumentView,
    VerificationAddRequirementAttachmentView,

    BackofficeVerificationInquiriesListView,
    BackofficeVerificationRequestsListView,
    BackofficeVerificationAssignView,
    BackofficeDecideDocumentView,
    BackofficeDecideRequirementView,
    BackofficeFinalizeRequestView,
    BackofficeVerifiedAccountsListView,
)

urlpatterns = [
    # client
    path("pricing/my/", MyVerificationPricingView.as_view(), name="pricing_my"),
    path("blue-preview/", VerificationBluePreviewView.as_view(), name="blue_preview"),
    path("requests/create/", VerificationRequestCreateView.as_view(), name="create"),
    path("requests/my/", MyVerificationRequestsListView.as_view(), name="my"),
    path("requests/<int:pk>/", VerificationRequestDetailView.as_view(), name="detail"),
    path("requests/<int:pk>/documents/", VerificationAddDocumentView.as_view(), name="add_document"),
    path(
        "requests/<int:pk>/requirements/<int:req_id>/attachments/",
        VerificationAddRequirementAttachmentView.as_view(),
        name="add_requirement_attachment",
    ),

    # backoffice
    path("backoffice/inquiries/", BackofficeVerificationInquiriesListView.as_view(), name="bo_inquiries"),
    path("backoffice/requests/", BackofficeVerificationRequestsListView.as_view(), name="bo_list"),
    path("backoffice/verified-accounts/", BackofficeVerifiedAccountsListView.as_view(), name="bo_verified_accounts"),
    path("backoffice/requests/<int:pk>/assign/", BackofficeVerificationAssignView.as_view(), name="bo_assign"),
    path("backoffice/documents/<int:doc_id>/decision/", BackofficeDecideDocumentView.as_view(), name="bo_decide_doc"),
    path(
        "backoffice/requirements/<int:req_id>/decision/",
        BackofficeDecideRequirementView.as_view(),
        name="bo_decide_requirement",
    ),
    path("backoffice/requests/<int:pk>/finalize/", BackofficeFinalizeRequestView.as_view(), name="bo_finalize"),
]
