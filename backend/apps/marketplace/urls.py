from django.urls import path

from .api import (
    AcceptOfferView,
    AvailableUrgentRequestsView,
    AvailableCompetitiveRequestsView,
    CreateOfferView,
    MyClientRequestsView,
    MyClientRequestDetailView,
    MyProviderRequestsView,
    ProviderRequestDetailView,
    ProviderAssignedRequestAcceptView,
    ProviderRequestCancelView,
    ProviderAssignedRequestRejectView,
    ProviderProgressUpdateView,
    ProviderInputsDecisionView,
    RequestCancelView,
    RequestCompleteView,
    RequestReopenView,
    RequestOffersListView,
    RequestStartView,
    ServiceRequestCreateView,
    UrgentRequestAcceptView,
)

from .views import (
    provider_requests,
    request_action,
    request_detail,
)

app_name = "marketplace"

urlpatterns = [
    path("requests/create/", ServiceRequestCreateView.as_view(), name="request_create"),
    path("requests/urgent/accept/", UrgentRequestAcceptView.as_view(), name="urgent_accept"),

    # ✅ Inbox endpoints
    path(
        "provider/urgent/available/",
        AvailableUrgentRequestsView.as_view(),
        name="provider_urgent_available",
    ),
    path(
        "provider/competitive/available/",
        AvailableCompetitiveRequestsView.as_view(),
        name="provider_competitive_available",
    ),
    path(
        "provider/requests/",
        MyProviderRequestsView.as_view(),
        name="provider_requests",
    ),
    path(
        "provider/requests/<int:request_id>/detail/",
        ProviderRequestDetailView.as_view(),
        name="provider_request_detail",
    ),
    path(
        "provider/requests/<int:request_id>/accept/",
        ProviderAssignedRequestAcceptView.as_view(),
        name="provider_request_accept",
    ),
    path(
        "provider/requests/<int:request_id>/reject/",
        ProviderAssignedRequestRejectView.as_view(),
        name="provider_request_reject",
    ),
    path(
        "provider/requests/<int:request_id>/cancel/",
        ProviderRequestCancelView.as_view(),
        name="provider_request_cancel",
    ),
    path(
        "provider/requests/<int:request_id>/progress-update/",
        ProviderProgressUpdateView.as_view(),
        name="provider_request_progress_update",
    ),
    # HTML view (keeps API route above intact)
    path(
        "provider/requests/page/",
        provider_requests,
        name="provider_requests_page",
    ),

    path(
        "client/requests/",
        MyClientRequestsView.as_view(),
        name="client_requests",
    ),
    path(
        "client/requests/<int:request_id>/",
        MyClientRequestDetailView.as_view(),
        name="client_request_detail",
    ),

    path(
        "requests/<int:request_id>/offers/create/",
        CreateOfferView.as_view(),
        name="offer_create",
    ),
    path(
        "requests/<int:request_id>/offers/",
        RequestOffersListView.as_view(),
        name="offers_list",
    ),
    path(
        "offers/<int:offer_id>/accept/",
        AcceptOfferView.as_view(),
        name="offer_accept",
    ),
]

urlpatterns += [
    path("requests/<int:request_id>/", request_detail, name="request_detail"),
    path("requests/<int:request_id>/action/", request_action, name="request_action"),
    path("requests/<int:request_id>/start/", RequestStartView.as_view(), name="request_start"),
    path(
        "requests/<int:request_id>/complete/",
        RequestCompleteView.as_view(),
        name="request_complete",
    ),
    path(
        "requests/<int:request_id>/cancel/",
        RequestCancelView.as_view(),
        name="request_cancel",
    ),
    path(
        "requests/<int:request_id>/reopen/",
        RequestReopenView.as_view(),
        name="request_reopen",
    ),
    path(
        "requests/<int:request_id>/provider-inputs/decision/",
        ProviderInputsDecisionView.as_view(),
        name="provider_inputs_decision",
    ),
]
