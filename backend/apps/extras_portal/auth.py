from __future__ import annotations

from functools import wraps

from django.http import HttpRequest, HttpResponse

from django.shortcuts import redirect


SESSION_PORTAL_OTP_VERIFIED_KEY = "extras_portal_otp_verified"
SESSION_PORTAL_NEXT_URL_KEY = "extras_portal_next_url"
SESSION_PORTAL_LOGIN_USER_ID_KEY = "extras_portal_login_user_id"


def is_portal_otp_verified(request: HttpRequest) -> bool:
    return bool(getattr(request, "session", {}).get(SESSION_PORTAL_OTP_VERIFIED_KEY))


def extras_portal_login_required(view_func):
    """Require authenticated user + OTP-verified session for extras portal."""

    @wraps(view_func)
    def wrapped(request: HttpRequest, *args, **kwargs):
        user = getattr(request, "user", None)
        if not getattr(user, "is_authenticated", False):
            try:
                request.session[SESSION_PORTAL_NEXT_URL_KEY] = request.get_full_path()
            except Exception:
                pass
            return redirect("extras_portal:login")

        # Must be a provider user
        if not hasattr(user, "provider_profile"):
            return HttpResponse("غير مصرح", status=403)

        return view_func(request, *args, **kwargs)

    return wrapped
