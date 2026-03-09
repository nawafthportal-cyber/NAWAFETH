from __future__ import annotations

from functools import wraps

from django.http import HttpRequest, HttpResponse
from django.shortcuts import redirect

from .access import dashboard_portal_eligible, first_allowed_dashboard_route


SESSION_OTP_VERIFIED_KEY = "dashboard_otp_verified"
SESSION_LOGIN_PHONE_KEY = "dashboard_login_phone"
SESSION_NEXT_URL_KEY = "dashboard_next_url"


def is_dashboard_otp_verified(request: HttpRequest) -> bool:
    return bool(getattr(request, "session", {}).get(SESSION_OTP_VERIFIED_KEY))


def dashboard_login_required(view_func):
    """Require authenticated dashboard-access user + OTP-verified session."""

    @wraps(view_func)
    def wrapped(request: HttpRequest, *args, **kwargs):
        user = getattr(request, "user", None)

        if not getattr(user, "is_authenticated", False):
            try:
                request.session[SESSION_NEXT_URL_KEY] = request.get_full_path()
            except Exception:
                pass
            return redirect("dashboard:login")

        if not dashboard_portal_eligible(user):
            fallback = first_allowed_dashboard_route(user)
            if fallback:
                return redirect(fallback)
            return HttpResponse("غير مصرح", status=403)

        if not is_dashboard_otp_verified(request):
            try:
                request.session[SESSION_NEXT_URL_KEY] = request.get_full_path()
            except Exception:
                pass
            return redirect("dashboard:otp")

        return view_func(request, *args, **kwargs)

    return wrapped


def dashboard_staff_required(view_func):
    """Alias for legacy naming in dashboard views."""

    return dashboard_login_required(view_func)
