from django.urls import path

from .views import (
    CreateReviewView,
    ProviderReviewReplyView,
    ProviderReviewsListView,
    ProviderRatingSummaryView,
)

app_name = "reviews"

urlpatterns = [
    path("requests/<int:request_id>/review/", CreateReviewView.as_view(), name="create_review"),
    path("reviews/<int:review_id>/provider-reply/", ProviderReviewReplyView.as_view(), name="provider_reply"),
    path("providers/<int:provider_id>/reviews/", ProviderReviewsListView.as_view(), name="provider_reviews"),
    path("providers/<int:provider_id>/rating/", ProviderRatingSummaryView.as_view(), name="provider_rating"),
]
