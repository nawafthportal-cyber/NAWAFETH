"""
URL configuration for config project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/5.1/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.urls import include, path
from django.contrib import admin
from django.conf import settings
from django.conf.urls.static import static
from django.utils.translation import gettext_lazy as _

from apps.core.health import HealthCheckView, HealthLiveView, HealthReadyView, healthz
from apps.core.views import RootFaviconView, RootRobotsTxtView, RootServiceWorkerView, UnreadBadgesView
from apps.billing.views import MockCheckoutView
from apps.mobile_web.views import (
    MobileWebHomeView,
    MobileWebLoginView,
    MobileWebOnboardingView,
    MobileWebTwoFAView,
    MobileWebSignupView,
    MobileWebSearchView,
    MobileWebOrdersView,
    MobileWebOrderDetailView,
    MobileWebInteractiveView,
    MobileWebProfileView,
    MobileWebProviderDetailView,
    MobileWebNotificationsView,
    MobileWebChatsView,
    MobileWebChatDetailView,
    MobileWebLegacyPromoRequestRedirectView,
    MobileWebLegacyThreadChatRedirectView,
    MobileWebLegacyRequestChatRedirectView,
    MobileWebLegacyRequestRedirectView,
    MobileWebAddServiceView,
    MobileWebUrgentRequestView,
    MobileWebRequestQuoteView,
    MobileWebSettingsView,
    MobileWebTermsView,
    MobileWebAboutView,
    MobileWebContactView,
    MobileWebLanguageView,
    MobileWebMyQrView,
    MobileWebLoginSettingsView,
    MobileWebNotificationSettingsView,
    MobileWebProviderDashboardView,
    MobileWebProviderOrdersView,
    MobileWebProviderOrderDetailView,
    MobileWebPlansView,
    MobileWebPlanSummaryView,
    MobileWebSubscriptionPaymentView,
    MobileWebVerificationView,
    MobileWebVerificationPaymentView,
    MobileWebServiceDetailView,
    MobileWebServiceRequestFormView,
    MobileWebProviderRegisterView,
    MobileWebPromotionView,
    MobileWebPromotionPaymentView,
    MobileWebAdditionalServicesView,
    MobileWebAdditionalServicesPaymentView,
    MobileWebProviderServicesView,
    MobileWebProviderReviewsView,
    MobileWebProviderProfileEditView,
    MobileWebProviderPortfolioView,
    MobileWebProfileCompletionView,
    MobileWebProvidersMapView,
    MobileWebSearchProvidersView,
)

admin.site.site_header = _("إدارة منصة نوافذ")
admin.site.site_title = _("لوحة إدارة نوافذ")
admin.site.index_title = _("مرحبًا بك في لوحة التحكم")

urlpatterns = [
    path("favicon.ico", RootFaviconView.as_view(), name="favicon"),
    path("robots.txt", RootRobotsTxtView.as_view(), name="robots_txt"),
    path("sw.js", RootServiceWorkerView.as_view(), name="service_worker"),
    path("checkout/<str:provider>/<uuid:attempt_id>/", MockCheckoutView.as_view(), name="public_mock_checkout"),
    path("healthz/", healthz, name="healthz"),
    path("health/", HealthCheckView.as_view(), name="health"),
    path("health/live/", HealthLiveView.as_view(), name="health_live"),
    path("health/ready/", HealthReadyView.as_view(), name="health_ready"),
    path("admin-panel/", admin.site.urls),
    path("api/accounts/", include(("apps.accounts.urls", "accounts"), namespace="accounts")),
    path("api/providers/", include(("apps.providers.urls", "providers"), namespace="providers")),
    path("api/marketplace/", include(("apps.marketplace.urls", "marketplace"), namespace="marketplace")),
    path("api/messaging/", include(("apps.messaging.urls", "messaging"), namespace="messaging")),
    path(
        "api/notifications/",
        include(("apps.notifications.urls", "notifications"), namespace="notifications"),
    ),
    path("api/reviews/", include(("apps.reviews.urls", "reviews"), namespace="reviews")),
    path("api/content/", include(("apps.content.urls", "content"), namespace="content")),
    path("api/moderation/", include(("apps.moderation.urls", "moderation"), namespace="moderation")),
    path("api/core/unread-badges/", UnreadBadgesView.as_view(), name="unread_badges"),
    path("api/excellence/", include(("apps.excellence.urls", "excellence"), namespace="excellence")),
    path("api/public/", include(("apps.verification.public_urls", "public"), namespace="public")),

    path(
        "dashboard/",
        include(("apps.dashboard.urls", "dashboard"), namespace="dashboard"),
    ),

    path(
        "portal/extras/",
        include(("apps.extras_portal.urls", "extras_portal"), namespace="extras_portal"),
    ),
    path("api/backoffice/", include(("apps.backoffice.urls", "backoffice"), namespace="backoffice")),
    path("api/support/", include(("apps.support.urls", "support"), namespace="support")),
    path("api/billing/", include(("apps.billing.urls", "billing"), namespace="billing")),
    path("api/verification/", include(("apps.verification.urls", "verification"), namespace="verification")),
    path("api/promo/", include(("apps.promo.urls", "promo"), namespace="promo")),
    path("api/subscriptions/", include(("apps.subscriptions.urls", "subscriptions"), namespace="subscriptions")),
    path("api/extras/", include(("apps.extras.urls", "extras"), namespace="extras")),

    path("api/features/", include(("apps.features.urls", "features"), namespace="features")),

    path("api/analytics/", include(("apps.analytics.urls", "analytics"), namespace="analytics")),

    # Mobile Web View
    path("mobile-web/", include(("apps.mobile_web.urls", "mobile_web"), namespace="mobile_web")),

    # Root — serve responsive home page at /
    path("", MobileWebHomeView.as_view(), name="home"),
    path("login/", MobileWebLoginView.as_view(), name="login"),
    path("onboarding/", MobileWebOnboardingView.as_view(), name="onboarding"),
    path("twofa/", MobileWebTwoFAView.as_view(), name="twofa"),
    path("signup/", MobileWebSignupView.as_view(), name="signup"),
    path("search/", MobileWebSearchView.as_view(), name="search"),
    path("orders/", MobileWebOrdersView.as_view(), name="orders"),
    path("orders/<int:request_id>/", MobileWebOrderDetailView.as_view(), name="order_detail"),
    path("interactive/", MobileWebInteractiveView.as_view(), name="interactive"),
    path("profile/", MobileWebProfileView.as_view(), name="profile"),
    path("provider/<int:provider_id>/<str:provider_slug>/", MobileWebProviderDetailView.as_view(), name="provider_detail_slug"),
    path("provider/<int:provider_id>/", MobileWebProviderDetailView.as_view(), name="provider_detail"),
    path("notifications/", MobileWebNotificationsView.as_view(), name="notifications"),
    path(
        "notification-settings/",
        MobileWebNotificationSettingsView.as_view(),
        name="notification_settings",
    ),
    path("chats/", MobileWebChatsView.as_view(), name="chats"),
    path("chat/<int:thread_id>/", MobileWebChatDetailView.as_view(), name="chat_detail"),
    path("threads/<int:thread_id>/chat", MobileWebLegacyThreadChatRedirectView.as_view(), name="legacy_thread_chat"),
    path("threads/<int:thread_id>/chat/", MobileWebLegacyThreadChatRedirectView.as_view()),
    path("requests/<int:request_id>", MobileWebLegacyRequestRedirectView.as_view(), name="legacy_request_detail"),
    path("requests/<int:request_id>/", MobileWebLegacyRequestRedirectView.as_view()),
    path("requests/<int:request_id>/chat", MobileWebLegacyRequestChatRedirectView.as_view(), name="legacy_request_chat"),
    path("requests/<int:request_id>/chat/", MobileWebLegacyRequestChatRedirectView.as_view()),
    path("promo/requests/<int:request_id>/", MobileWebLegacyPromoRequestRedirectView.as_view(), name="legacy_promo_request"),
    path("add-service/", MobileWebAddServiceView.as_view(), name="add_service"),
    path("urgent-request/", MobileWebUrgentRequestView.as_view(), name="urgent_request"),
    path("request-quote/", MobileWebRequestQuoteView.as_view(), name="request_quote"),
    path("settings/", MobileWebSettingsView.as_view(), name="settings"),
    path("terms/", MobileWebTermsView.as_view(), name="terms"),
    path("about/", MobileWebAboutView.as_view(), name="about"),
    path("contact/", MobileWebContactView.as_view(), name="contact"),
    path("language/", MobileWebLanguageView.as_view(), name="language"),
    path("my-qr/", MobileWebMyQrView.as_view(), name="my_qr"),
    path("login-settings/", MobileWebLoginSettingsView.as_view(), name="login_settings"),
    # Provider/mobile parity routes mounted at root to match hard-coded web links.
    path("provider-dashboard/", MobileWebProviderDashboardView.as_view(), name="provider_dashboard"),
    path("provider-orders/", MobileWebProviderOrdersView.as_view(), name="provider_orders"),
    path(
        "provider-orders/<int:request_id>/",
        MobileWebProviderOrderDetailView.as_view(),
        name="provider_order_detail",
    ),
    path("plans/", MobileWebPlansView.as_view(), name="plans"),
    path("plans/summary/", MobileWebPlanSummaryView.as_view(), name="plan_summary"),
    path("plans/payment/", MobileWebSubscriptionPaymentView.as_view(), name="subscription_payment"),
    path("verification/", MobileWebVerificationView.as_view(), name="verification"),
    path("verification/payment/", MobileWebVerificationPaymentView.as_view(), name="verification_payment"),
    path("service/<int:service_id>/", MobileWebServiceDetailView.as_view(), name="service_detail"),
    path("service-request/", MobileWebServiceRequestFormView.as_view(), name="service_request_form"),
    path("provider-register/", MobileWebProviderRegisterView.as_view(), name="provider_register"),
    path("promotion/", MobileWebPromotionView.as_view(), name="promotion"),
    path("promotion/payment/", MobileWebPromotionPaymentView.as_view(), name="promotion_payment"),
    path("additional-services/", MobileWebAdditionalServicesView.as_view(), name="additional_services"),
    path("additional-services/payment/", MobileWebAdditionalServicesPaymentView.as_view(), name="additional_services_payment"),
    path("provider-services/", MobileWebProviderServicesView.as_view(), name="provider_services"),
    path("provider-reviews/", MobileWebProviderReviewsView.as_view(), name="provider_reviews"),
    path("provider-profile-edit/", MobileWebProviderProfileEditView.as_view(), name="provider_profile_edit"),
    path("provider-portfolio/", MobileWebProviderPortfolioView.as_view(), name="provider_portfolio"),
    path("profile-completion/", MobileWebProfileCompletionView.as_view(), name="profile_completion"),
    path("providers-map/", MobileWebProvidersMapView.as_view(), name="providers_map"),
    path("search-providers/", MobileWebSearchProvidersView.as_view(), name="search_providers"),
]

if settings.DEBUG or getattr(settings, "SERVE_MEDIA", False):
    # django.conf.urls.static.static() is a no-op when DEBUG=False (even on
    # Django 5.x).  When SERVE_MEDIA is explicitly True (e.g. R2/S3 fallback
    # to local storage on Render) we must register the pattern ourselves so
    # that uploaded media is reachable in production.
    if settings.DEBUG:
        urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
    else:
        import re as _re
        from django.urls import re_path as _re_path
        from django.views.static import serve as _serve_static

        _media_prefix = settings.MEDIA_URL.lstrip("/")
        urlpatterns += [
            _re_path(
                r"^%s(?P<path>.*)$" % _re.escape(_media_prefix),
                _serve_static,
                {"document_root": settings.MEDIA_ROOT},
            ),
        ]

if settings.DEBUG or getattr(settings, "SERVE_STATIC", False):
    # Resilient static fallback for production environments where STATIC_ROOT
    # artifacts may be missing unexpectedly. WhiteNoise will still serve first
    # when collectstatic output exists.
    if settings.DEBUG:
        urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)
    else:
        import re as _re
        from django.urls import re_path as _re_path
        from django.contrib.staticfiles.views import serve as _serve_staticfiles

        _static_prefix = settings.STATIC_URL.lstrip("/")
        urlpatterns += [
            _re_path(
                r"^%s(?P<path>.*)$" % _re.escape(_static_prefix),
                _serve_staticfiles,
                {"insecure": True},
            ),
        ]
