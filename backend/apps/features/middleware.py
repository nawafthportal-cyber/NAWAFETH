from __future__ import annotations

from django.conf import settings
from django.core.cache import cache
from django.db import DatabaseError

from apps.subscriptions.models import Subscription
from apps.subscriptions.services import refresh_subscription_status


class SubscriptionRefreshMiddleware:
    """
    تحديث حالة الاشتراك بشكل خفيف عند كل Request
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        # This middleware is an auxiliary refresh hook and must never break
        # request handling when the DB/session backend is temporarily down.
        try:
            user = getattr(request, "user", None)
            if user is not None and user.is_authenticated:
                user_id = getattr(user, "id", None)
                if user_id is not None:
                    interval_seconds = max(
                        60,
                        int(getattr(settings, "SUBSCRIPTION_REFRESH_INTERVAL_SECONDS", 300) or 300),
                    )
                    throttle_key = f"subscriptions:refresh:user:{user_id}"
                    should_refresh = True
                    try:
                        should_refresh = bool(cache.add(throttle_key, "1", timeout=interval_seconds))
                    except Exception:
                        # If cache is unavailable, keep the previous behavior.
                        should_refresh = True
                    if not should_refresh:
                        return self.get_response(request)
                    sub = Subscription.objects.filter(user_id=user_id).order_by("-id").first()
                    if sub:
                        try:
                            refresh_subscription_status(sub=sub)
                        except Exception:
                            pass
        except DatabaseError:
            pass

        return self.get_response(request)
