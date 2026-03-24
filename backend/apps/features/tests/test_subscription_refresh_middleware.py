from __future__ import annotations

import pytest
from django.db import OperationalError
from django.http import HttpResponse

from apps.features.middleware import SubscriptionRefreshMiddleware


class _BrokenUser:
    @property
    def is_authenticated(self):
        raise OperationalError("db temporarily unavailable")


class _AuthenticatedUser:
    id = 101
    is_authenticated = True


def _ok_response(_request):
    return HttpResponse("ok")


def test_subscription_refresh_middleware_does_not_break_when_user_resolution_hits_db_error():
    middleware = SubscriptionRefreshMiddleware(_ok_response)
    request = type("Request", (), {})()
    request.user = _BrokenUser()

    response = middleware(request)

    assert response.status_code == 200
    assert response.content == b"ok"


def test_subscription_refresh_middleware_does_not_break_when_subscription_query_hits_db_error(monkeypatch):
    middleware = SubscriptionRefreshMiddleware(_ok_response)
    request = type("Request", (), {})()
    request.user = _AuthenticatedUser()

    def _raise_db_error(*args, **kwargs):
        raise OperationalError("db temporarily unavailable")

    monkeypatch.setattr("apps.features.middleware.Subscription.objects.filter", _raise_db_error)

    response = middleware(request)

    assert response.status_code == 200
    assert response.content == b"ok"
