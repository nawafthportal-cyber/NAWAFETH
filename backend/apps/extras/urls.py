from django.urls import path

from .views import (
    BuyExtraView,
    CreateExtrasBundleRequestView,
    ExtrasBundlePaymentLinkView,
    ExtrasCatalogView,
    MyExtrasBundleRequestsView,
    MyExtrasListView,
    MyLoyaltyWalletView,
)

urlpatterns = [
    path("catalog/", ExtrasCatalogView.as_view(), name="catalog"),
    path("my/", MyExtrasListView.as_view(), name="my_extras"),
    path("loyalty/my/", MyLoyaltyWalletView.as_view(), name="loyalty_my"),
    path("buy/<str:sku>/", BuyExtraView.as_view(), name="buy_extra"),
    path("bundle-payment-link/<uuid:attempt_id>/", ExtrasBundlePaymentLinkView.as_view(), name="bundle_payment_link"),
    path("bundle-requests/", CreateExtrasBundleRequestView.as_view(), name="bundle_request_create"),
    path("bundle-requests/my/", MyExtrasBundleRequestsView.as_view(), name="bundle_request_my"),
]
