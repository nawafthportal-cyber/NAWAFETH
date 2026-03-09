from django.urls import path
from . import views
from . import auth_views
from . import content_views
from . import reviews_views
from . import admin_views
from apps.excellence import dashboard_views as excellence_views

app_name = "dashboard"

urlpatterns = [
    path("login/", auth_views.dashboard_login, name="login"),
    path("otp/", auth_views.dashboard_otp, name="otp"),
    path("logout/", auth_views.dashboard_logout, name="logout"),
    path("", views.dashboard_home, name="home"),
    path("requests/", views.requests_list, name="requests_list"),
    path("requests/<int:request_id>/", views.request_detail, name="request_detail"),
    path("content/", content_views.content_management, name="content_management"),
    path("content/blocks/<str:key>/update/", content_views.content_block_update_action, name="content_block_update_action"),
    path("content/docs/<str:doc_type>/upload/", content_views.content_doc_upload_action, name="content_doc_upload_action"),
    path("content/links/update/", content_views.content_links_update_action, name="content_links_update_action"),

    path("reviews/", reviews_views.reviews_dashboard_list, name="reviews_dashboard_list"),
    path("reviews/<int:review_id>/", reviews_views.reviews_dashboard_detail, name="reviews_dashboard_detail"),
    path("reviews/<int:review_id>/actions/moderate/", reviews_views.reviews_dashboard_moderate_action, name="reviews_dashboard_moderate_action"),
    path("reviews/<int:review_id>/actions/respond/", reviews_views.reviews_dashboard_respond_action, name="reviews_dashboard_respond_action"),

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
        "support/<int:ticket_id>/actions/quick-update/",
        views.support_ticket_quick_update_action,
        name="support_ticket_quick_update_action",
    ),
    path(
        "support/<int:ticket_id>/actions/delete-reported/",
        views.support_ticket_delete_reported_object_action,
        name="support_ticket_delete_reported_object_action",
    ),
    path(
        "support/<int:ticket_id>/actions/add-comment/",
        admin_views.support_ticket_add_comment,
        name="support_ticket_add_comment",
    ),
    path("support/create/", admin_views.support_ticket_create, name="support_ticket_create"),

    path("verification/ops/", views.verification_ops, name="verification_ops"),
    path("verification/inquiries/<int:ticket_id>/", views.verification_inquiry_detail, name="verification_inquiry_detail"),
    path(
        "verification/inquiries/<int:ticket_id>/actions/assign/",
        views.verification_inquiry_assign_action,
        name="verification_inquiry_assign_action",
    ),
    path(
        "verification/inquiries/<int:ticket_id>/actions/status/",
        views.verification_inquiry_status_action,
        name="verification_inquiry_status_action",
    ),

    path("verification/", views.verification_requests_list, name="verification_requests_list"),
    path("verification/<int:verification_id>/", views.verification_request_detail, name="verification_request_detail"),
    path("verification/<int:verification_id>/actions/finalize/", views.verification_finalize_action, name="verification_finalize_action"),
    path("verification/<int:verification_id>/actions/activate/", views.verification_activate_action, name="verification_activate_action"),
    path(
        "verification/requirements/<int:req_id>/actions/decision/",
        views.verification_requirement_decision_action,
        name="verification_requirement_decision_action",
    ),

    path("verification/badges/", views.verified_badges_list, name="verified_badges_list"),
    path(
        "verification/badges/<int:badge_id>/actions/deactivate/",
        views.verified_badge_deactivate_action,
        name="verified_badge_deactivate_action",
    ),
    path(
        "verification/badges/<int:badge_id>/actions/renew/",
        views.verified_badge_renew_action,
        name="verified_badge_renew_action",
    ),

    path("excellence/", excellence_views.excellence_dashboard, name="excellence_dashboard"),
    path(
        "excellence/candidates/<int:candidate_id>/",
        excellence_views.excellence_candidate_detail,
        name="excellence_candidate_detail",
    ),
    path(
        "excellence/candidates/<int:candidate_id>/actions/approve/",
        excellence_views.excellence_candidate_approve_action,
        name="excellence_candidate_approve_action",
    ),
    path(
        "excellence/awards/<int:award_id>/actions/revoke/",
        excellence_views.excellence_award_revoke_action,
        name="excellence_award_revoke_action",
    ),

    path("promo/", views.promo_requests_list, name="promo_requests_list"),
    path("promo/inquiries/", views.promo_inquiries_list, name="promo_inquiries_list"),
    path("promo/inquiries/<int:ticket_id>/", views.promo_inquiry_detail, name="promo_inquiry_detail"),
    path("promo/inquiries/<int:ticket_id>/actions/assign/", views.promo_assign_action, name="promo_assign_action"),
    path("promo/inquiries/<int:ticket_id>/actions/profile/", views.promo_inquiry_profile_action, name="promo_inquiry_profile_action"),
    path("promo/inquiries/<int:ticket_id>/actions/status/", views.promo_inquiry_status_action, name="promo_inquiry_status_action"),
    path("promo/pricing/", views.promo_pricing, name="promo_pricing"),
    path("promo/pricing/actions/update/", views.promo_pricing_update_action, name="promo_pricing_update_action"),
    path("promo/modules/<slug:service_key>/", views.promo_service_board, name="promo_service_board"),
    path("promo/<int:promo_id>/", views.promo_request_detail, name="promo_request_detail"),
    path("promo/<int:promo_id>/actions/assign/", views.promo_request_assign_action, name="promo_request_assign_action"),
    path("promo/<int:promo_id>/actions/ops-status/", views.promo_request_ops_status_action, name="promo_request_ops_status_action"),
    path("promo/<int:promo_id>/actions/quote/", views.promo_quote_action, name="promo_quote_action"),
    path("promo/<int:promo_id>/actions/reject/", views.promo_reject_action, name="promo_reject_action"),
    path("promo/<int:promo_id>/actions/activate/", views.promo_activate_action, name="promo_activate_action"),

    path("promo/banners/", views.promo_home_banners_list, name="promo_home_banners"),
    path("promo/banners/create/", views.promo_home_banner_create, name="promo_home_banner_create"),
    path("promo/banners/<int:banner_id>/update/", views.promo_home_banner_update, name="promo_home_banner_update"),
    path("promo/banners/<int:banner_id>/toggle/", views.promo_home_banner_toggle, name="promo_home_banner_toggle"),
    path("promo/banners/<int:banner_id>/delete/", views.promo_home_banner_delete, name="promo_home_banner_delete"),

    path("subscriptions/ops/", views.subscriptions_ops, name="subscriptions_ops"),
    path("subscriptions/inquiries/<int:ticket_id>/", views.subscription_inquiry_detail, name="subscription_inquiry_detail"),
    path(
        "subscriptions/inquiries/<int:ticket_id>/actions/assign/",
        views.subscription_inquiry_assign_action,
        name="subscription_inquiry_assign_action",
    ),
    path(
        "subscriptions/inquiries/<int:ticket_id>/actions/status/",
        views.subscription_inquiry_status_action,
        name="subscription_inquiry_status_action",
    ),
    path("subscriptions/requests/<int:subscription_id>/", views.subscription_request_detail, name="subscription_request_detail"),
    path("subscriptions/requests/<int:subscription_id>/actions/add-note/", views.subscription_request_add_note_action, name="subscription_request_add_note_action"),
    path("subscriptions/requests/<int:subscription_id>/actions/set-status/", views.subscription_request_set_status_action, name="subscription_request_set_status_action"),
    path("subscriptions/requests/<int:subscription_id>/actions/assign/", views.subscription_request_assign_action, name="subscription_request_assign_action"),
    path("subscriptions/", views.subscriptions_list, name="subscriptions_list"),
    path("subscriptions/plans/compare/", views.subscription_plans_compare, name="subscription_plans_compare"),
    path("subscriptions/accounts/<int:subscription_id>/upgrade-summary/", views.subscription_upgrade_summary, name="subscription_upgrade_summary"),
    path("subscriptions/accounts/<int:subscription_id>/", views.subscription_account_detail, name="subscription_account_detail"),
    path("subscriptions/accounts/<int:subscription_id>/actions/add-note/", views.subscription_account_add_note_action, name="subscription_account_add_note_action"),
    path("subscriptions/payments/<int:subscription_id>/checkout/", views.subscription_payment_checkout, name="subscription_payment_checkout"),
    path("subscriptions/payments/<int:subscription_id>/actions/complete/", views.subscription_payment_complete_action, name="subscription_payment_complete_action"),
    path("subscriptions/payments/<int:subscription_id>/success/", views.subscription_payment_success, name="subscription_payment_success"),
    path("subscriptions/accounts/<int:subscription_id>/actions/renew/", views.subscription_account_renew_action, name="subscription_account_renew_action"),
    path("subscriptions/accounts/<int:subscription_id>/actions/upgrade/", views.subscription_account_upgrade_action, name="subscription_account_upgrade_action"),
    path("subscriptions/accounts/<int:subscription_id>/actions/cancel/", views.subscription_account_cancel_action, name="subscription_account_cancel_action"),
    path("subscriptions/<int:subscription_id>/actions/refresh/", views.subscription_refresh_action, name="subscription_refresh_action"),
    path("subscriptions/<int:subscription_id>/actions/activate/", views.subscription_activate_action, name="subscription_activate_action"),

    path("extras/ops/", views.extras_ops, name="extras_ops"),
    path("extras/inquiries/<int:ticket_id>/", views.extras_inquiry_detail, name="extras_inquiry_detail"),
    path(
        "extras/inquiries/<int:ticket_id>/actions/assign/",
        views.extras_inquiry_assign_action,
        name="extras_inquiry_assign_action",
    ),
    path(
        "extras/inquiries/<int:ticket_id>/actions/status/",
        views.extras_inquiry_status_action,
        name="extras_inquiry_status_action",
    ),
    path("extras/requests/<int:unified_request_id>/", views.extras_request_detail, name="extras_request_detail"),
    path(
        "extras/requests/<int:unified_request_id>/actions/assign/",
        views.extras_request_assign_action,
        name="extras_request_assign_action",
    ),
    path(
        "extras/requests/<int:unified_request_id>/actions/status/",
        views.extras_request_status_action,
        name="extras_request_status_action",
    ),

    path("extras/", views.extras_list, name="extras_list"),
    path("extras/finance/", views.extras_finance_list, name="extras_finance_list"),
    path("extras/clients/", views.extras_clients_list, name="extras_clients_list"),
    path("extras/<int:extra_id>/actions/activate/", views.extra_activate_action, name="extra_activate_action"),

    path("features/", views.features_overview, name="features_overview"),

    # ── Admin views (gap features) ──
    path("audit-logs/", admin_views.audit_log_list, name="audit_log_list"),
    path("users/", admin_views.users_list, name="users_list"),
    path("users/<int:user_id>/", admin_views.user_detail, name="user_detail"),
    path("users/<int:user_id>/actions/toggle-active/", admin_views.user_toggle_active, name="user_toggle_active"),
    path("users/<int:user_id>/actions/update-role/", admin_views.user_update_role, name="user_update_role"),
    path("plans/", admin_views.plans_list, name="plans_list"),
    path("plans/create/", admin_views.plan_form, name="plan_create"),
    path("plans/<int:plan_id>/edit/", admin_views.plan_form, name="plan_edit"),
    path("plans/<int:plan_id>/actions/toggle-active/", admin_views.plan_toggle_active, name="plan_toggle_active"),

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
