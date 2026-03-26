from django.urls import path

from apps.excellence import dashboard_views as excellence_dashboard_views

from . import views


urlpatterns = [
    path("", views.dashboard_index, name="index"),
    path("login/", views.login_view, name="login"),
    path("otp/", views.otp_view, name="otp"),
    path("otp/resend/", views.resend_otp_view, name="otp_resend"),
    path("logout/", views.logout_view, name="logout"),
    path("admin-control/", views.admin_control_home, name="admin_control_home"),
    path("support/", views.support_dashboard, name="support_dashboard"),
    path("support/<int:ticket_id>/", views.support_dashboard, name="support_ticket_detail"),
    path("promo/", views.promo_dashboard, name="promo_dashboard"),
    path("promo/<int:request_id>/", views.promo_dashboard, name="promo_request_detail"),
    path("promo/modules/<slug:module_key>/", views.promo_module, name="promo_module"),
    path("promo/pricing/", views.promo_pricing, name="promo_pricing"),
    path("content/", views.content_dashboard_home, name="content_dashboard_home"),
    path("content/first-time/", views.content_first_time, name="content_first_time"),
    path("content/intro/", views.content_intro, name="content_intro"),
    path("content/settings/", views.content_settings, name="content_settings"),
    path("content/reviews/", views.content_reviews_dashboard, name="content_reviews_dashboard"),
    path("content/reviews/<int:ticket_id>/", views.content_reviews_dashboard, name="content_reviews_ticket_detail"),
    path("content/excellence/", views.content_excellence, name="content_excellence"),
    path("content/excellence/api/", views.content_excellence_api, name="content_excellence_api"),
    path("analytics/insights/", views.analytics_insights, name="analytics_insights"),
    path("excellence/", excellence_dashboard_views.excellence_dashboard, name="excellence_dashboard"),
    path(
        "excellence/candidate/<int:candidate_id>/",
        excellence_dashboard_views.excellence_candidate_detail,
        name="excellence_candidate_detail",
    ),
    path(
        "excellence/candidate/<int:candidate_id>/approve/",
        excellence_dashboard_views.excellence_candidate_approve_action,
        name="excellence_candidate_approve_action",
    ),
    path(
        "excellence/award/<int:award_id>/revoke/",
        excellence_dashboard_views.excellence_award_revoke_action,
        name="excellence_award_revoke_action",
    ),
]
