from django.urls import path
from . import views
from . import auth_views

app_name = "dashboard"

urlpatterns = [
    path("login/", auth_views.dashboard_login, name="login"),
    path("otp/", auth_views.dashboard_otp, name="otp"),
    path("logout/", auth_views.dashboard_logout, name="logout"),
    path("", views.dashboard_home, name="home"),
    path("requests/", views.requests_list, name="requests_list"),
    path("requests/<int:request_id>/", views.request_detail, name="request_detail"),

    path("providers/", views.providers_list, name="providers_list"),
    path("providers/<int:provider_id>/", views.provider_detail, name="provider_detail"),

    path("services/", views.services_list, name="services_list"),
    path("billing/", views.billing_invoices_list, name="billing_invoices_list"),
    path("unified-requests/", views.unified_requests_list, name="unified_requests_list"),
    path("unified-requests/<int:unified_request_id>/", views.unified_request_detail, name="unified_request_detail"),
    path(
        "billing/<int:invoice_id>/actions/set-status/",
        views.billing_invoice_set_status_action,
        name="billing_invoice_set_status_action",
    ),
    path("support/", views.support_tickets_list, name="support_tickets_list"),
    path("support/<int:ticket_id>/", views.support_ticket_detail, name="support_ticket_detail"),
    path("support/<int:ticket_id>/actions/assign/", views.support_ticket_assign_action, name="support_ticket_assign_action"),
    path("support/<int:ticket_id>/actions/status/", views.support_ticket_status_action, name="support_ticket_status_action"),
    path(
        "support/<int:ticket_id>/actions/delete-reported/",
        views.support_ticket_delete_reported_object_action,
        name="support_ticket_delete_reported_object_action",
    ),

    path("verification/", views.verification_requests_list, name="verification_requests_list"),
    path("verification/<int:verification_id>/", views.verification_request_detail, name="verification_request_detail"),
    path("verification/<int:verification_id>/actions/finalize/", views.verification_finalize_action, name="verification_finalize_action"),
    path("verification/<int:verification_id>/actions/activate/", views.verification_activate_action, name="verification_activate_action"),

    path("promo/", views.promo_requests_list, name="promo_requests_list"),
    path("promo/inquiries/", views.promo_inquiries_list, name="promo_inquiries_list"),
    path("promo/pricing/", views.promo_pricing, name="promo_pricing"),
    path("promo/pricing/actions/update/", views.promo_pricing_update_action, name="promo_pricing_update_action"),
    path("promo/<int:promo_id>/", views.promo_request_detail, name="promo_request_detail"),
    path("promo/<int:promo_id>/actions/quote/", views.promo_quote_action, name="promo_quote_action"),
    path("promo/<int:promo_id>/actions/reject/", views.promo_reject_action, name="promo_reject_action"),
    path("promo/<int:promo_id>/actions/activate/", views.promo_activate_action, name="promo_activate_action"),

    path("subscriptions/", views.subscriptions_list, name="subscriptions_list"),
    path("subscriptions/<int:subscription_id>/actions/refresh/", views.subscription_refresh_action, name="subscription_refresh_action"),
    path("subscriptions/<int:subscription_id>/actions/activate/", views.subscription_activate_action, name="subscription_activate_action"),

    path("extras/", views.extras_list, name="extras_list"),
    path("extras/<int:extra_id>/actions/activate/", views.extra_activate_action, name="extra_activate_action"),

    path("features/", views.features_overview, name="features_overview"),
    path("access-profiles/", views.access_profiles_list, name="access_profiles_list"),
    path(
        "access-profiles/actions/create/",
        views.access_profile_create_action,
        name="access_profile_create_action",
    ),
    path(
        "access-profiles/<int:profile_id>/actions/update/",
        views.access_profile_update_action,
        name="access_profile_update_action",
    ),
    path(
        "access-profiles/<int:profile_id>/actions/toggle-revoke/",
        views.access_profile_toggle_revoke_action,
        name="access_profile_toggle_revoke_action",
    ),

    # Categories & Subcategories
    path("categories/", views.categories_list, name="categories_list"),
    path("categories/create/", views.category_create, name="category_create"),
    path("categories/<int:category_id>/", views.category_detail, name="category_detail"),
    path("categories/<int:category_id>/edit/", views.category_edit, name="category_edit"),
    
    path("subcategories/create/", views.subcategory_create, name="subcategory_create"),
    path("subcategories/<int:subcategory_id>/edit/", views.subcategory_edit, name="subcategory_edit"),

    # Actions (POST)
    path(
        "categories/<int:category_id>/actions/toggle-active/",
        views.category_toggle_active,
        name="category_toggle_active",
    ),
    path(
        "categories/<int:category_id>/subcategories/<int:subcategory_id>/actions/toggle-active/",
        views.subcategory_toggle_active,
        name="subcategory_toggle_active",
    ),
    path(
        "providers/<int:provider_id>/services/<int:service_id>/actions/toggle-active/",
        views.provider_service_toggle_active,
        name="provider_service_toggle_active",
    ),

    # Actions (POST)
    path(
        "requests/<int:request_id>/actions/accept/",
        views.request_accept,
        name="request_accept",
    ),
    path(
        "requests/<int:request_id>/actions/send/",
        views.request_send,
        name="request_send",
    ),
    path(
        "requests/<int:request_id>/actions/start/",
        views.request_start,
        name="request_start",
    ),
    path(
        "requests/<int:request_id>/actions/complete/",
        views.request_complete,
        name="request_complete",
    ),
    path(
        "requests/<int:request_id>/actions/cancel/",
        views.request_cancel,
        name="request_cancel",
    ),
]
