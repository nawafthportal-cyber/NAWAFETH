from __future__ import annotations

from functools import wraps

from django.contrib.auth import logout
from django.http import HttpResponseForbidden
from django.shortcuts import redirect


SESSION_OTP_VERIFIED_KEY = "dashboard_otp_verified"
SESSION_LOGIN_USER_ID_KEY = "dashboard_login_user_id"
SESSION_NEXT_URL_KEY = "dashboard_next_url"


def clear_dashboard_auth_session(request) -> None:
    request.session.pop(SESSION_OTP_VERIFIED_KEY, None)
    request.session.pop(SESSION_LOGIN_USER_ID_KEY, None)
    request.session.pop(SESSION_NEXT_URL_KEY, None)


def _save_next_url(request) -> None:
    if request.method != "GET":
        return
    try:
        request.session[SESSION_NEXT_URL_KEY] = request.get_full_path()
    except Exception:
        return


def dashboard_staff_required(view_func):
    @wraps(view_func)
    def _wrapped(request, *args, **kwargs):
        user = getattr(request, "user", None)
        if not user or not user.is_authenticated:
            _save_next_url(request)
            return redirect("dashboard:login")

        if not getattr(user, "is_active", False):
            clear_dashboard_auth_session(request)
            logout(request)
            return redirect("dashboard:login")

        if not (getattr(user, "is_staff", False) or getattr(user, "is_superuser", False)):
            return HttpResponseForbidden("غير مصرح.")

        if not bool(request.session.get(SESSION_OTP_VERIFIED_KEY)):
            _save_next_url(request)
            return redirect("dashboard:otp")

        return view_func(request, *args, **kwargs)

    return _wrapped


# Backward-compatible alias used in legacy modules.
dashboard_login_required = dashboard_staff_required

