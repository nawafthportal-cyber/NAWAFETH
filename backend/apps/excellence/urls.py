from django.urls import path

from .api import ExcellenceBadgeCatalogView

app_name = "excellence"

urlpatterns = [
    path("catalog/", ExcellenceBadgeCatalogView.as_view(), name="catalog"),
]
