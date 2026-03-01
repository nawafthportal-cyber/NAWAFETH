from django.urls import path
from .views import MobileWebHomeView

app_name = "mobile_web"

urlpatterns = [
    path("", MobileWebHomeView.as_view(), name="home"),
]
