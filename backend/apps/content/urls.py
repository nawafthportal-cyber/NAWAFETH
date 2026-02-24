from django.urls import path

from .views import PublicSiteContentView

app_name = "content"

urlpatterns = [
    path("public/", PublicSiteContentView.as_view(), name="public_content"),
]
