from django.urls import path

from .views import PublicVerificationBadgeDetailView, PublicVerificationBadgesView

urlpatterns = [
    path("badges/", PublicVerificationBadgesView.as_view(), name="badges_catalog"),
    path("badges/<str:badge_type>/", PublicVerificationBadgeDetailView.as_view(), name="badge_detail"),
]
