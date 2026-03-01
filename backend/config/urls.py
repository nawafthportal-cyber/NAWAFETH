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
from apps.mobile_web.views import MobileWebHomeView

admin.site.site_header = _("إدارة منصة نوافذ")
admin.site.site_title = _("لوحة إدارة نوافذ")
admin.site.index_title = _("مرحبًا بك في لوحة التحكم")

urlpatterns = [
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
]

if settings.DEBUG or getattr(settings, "SERVE_MEDIA", False):
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
