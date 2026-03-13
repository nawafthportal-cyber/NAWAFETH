from django.urls import path

from .views import (
    PromoRequestCreateView,
    PromoRequestPreviewView,
    MyPromoRequestsListView,
    PromoRequestDetailView,
    PromoAddAssetView,

    PublicHomeBannersView,
    PublicActivePromosView,
    PublicHomeCarouselView,

    BackofficePromoRequestsListView,
    BackofficeQuoteView,
    BackofficeRejectView,
    BackofficePromoAssignView,
)

urlpatterns = [
    # client
    path("requests/preview/", PromoRequestPreviewView.as_view(), name="preview"),
    path("requests/create/", PromoRequestCreateView.as_view(), name="create"),
    path("requests/my/", MyPromoRequestsListView.as_view(), name="my"),
    path("requests/<int:pk>/", PromoRequestDetailView.as_view(), name="detail"),
    path("requests/<int:pk>/assets/", PromoAddAssetView.as_view(), name="add_asset"),

    # public ads
    path("banners/home/", PublicHomeBannersView.as_view(), name="public_home_banners"),
    path("home-carousel/", PublicHomeCarouselView.as_view(), name="public_home_carousel"),
    path("active/", PublicActivePromosView.as_view(), name="public_active"),

    # backoffice
    path("backoffice/requests/", BackofficePromoRequestsListView.as_view(), name="bo_list"),
    path("backoffice/requests/<int:pk>/assign/", BackofficePromoAssignView.as_view(), name="bo_assign"),
    path("backoffice/requests/<int:pk>/quote/", BackofficeQuoteView.as_view(), name="bo_quote"),
    path("backoffice/requests/<int:pk>/reject/", BackofficeRejectView.as_view(), name="bo_reject"),
]
