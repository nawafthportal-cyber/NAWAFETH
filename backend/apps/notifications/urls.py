from django.urls import path

from .views import (
    MyNotificationsView,
    UnreadCountView,
    MarkReadView,
    MarkAllReadView,
    NotificationActionView,
    NotificationPreferencesView,
    PromoNotificationPreviewView,
    RegisterDeviceTokenView,
    DeleteOldNotificationsView,
)

app_name = "notifications"

urlpatterns = [
    path("", MyNotificationsView.as_view(), name="list"),
    path("unread-count/", UnreadCountView.as_view(), name="unread_count"),
    path("promo-preview/<int:notif_id>/", PromoNotificationPreviewView.as_view(), name="promo_preview"),
    path("mark-read/<int:notif_id>/", MarkReadView.as_view(), name="mark_read"),
    path("mark-all-read/", MarkAllReadView.as_view(), name="mark_all_read"),
    path("actions/<int:notif_id>/", NotificationActionView.as_view(), name="actions"),
    path("preferences/", NotificationPreferencesView.as_view(), name="preferences"),
    path("delete-old/", DeleteOldNotificationsView.as_view(), name="delete_old"),
    path("device-token/", RegisterDeviceTokenView.as_view(), name="device_token"),
]
