from __future__ import annotations

import logging

from django.contrib import messages
from django.contrib.auth import login, logout
from django.core.cache import cache
from django.http import HttpRequest, HttpResponse
from django.shortcuts import redirect, render

from apps.accounts.models import User
from apps.accounts.otp import accept_any_otp_code, create_otp, verify_otp

from .access import dashboard_portal_eligible, first_allowed_dashboard_route, sync_dashboard_user_access
from .auth import (
    SESSION_LOGIN_PHONE_KEY,
    SESSION_NEXT_URL_KEY,
    SESSION_OTP_VERIFIED_KEY,
)
from .security import is_safe_redirect_url


logger = logging.getLogger(__name__)

# ── Rate Limiting ──────────────────────────────────────────────
OTP_MAX_ATTEMPTS = 5          # max failed attempts per phone
OTP_LOCKOUT_SECONDS = 300     # 5 minutes lockout
LOGIN_MAX_ATTEMPTS = 10       # max login attempts per IP
LOGIN_LOCKOUT_SECONDS = 600   # 10 minutes lockout


def _rate_limit_key(prefix: str, identifier: str) -> str:
    """Build a cache key for rate limiting."""
    safe_id = identifier.replace(" ", "_")
    return f"dashboard_rl:{prefix}:{safe_id}"


def _is_rate_limited(prefix: str, identifier: str, max_attempts: int, lockout_seconds: int) -> bool:
    """Check if identifier is rate-limited.  Increment counter on each call."""
    key = _rate_limit_key(prefix, identifier)
    attempts = cache.get(key, 0)
    if attempts >= max_attempts:
        return True
    cache.set(key, attempts + 1, lockout_seconds)
    return False


def _reset_rate_limit(prefix: str, identifier: str) -> None:
    """Clear rate limit counter on successful auth."""
    cache.delete(_rate_limit_key(prefix, identifier))


def _keep_digits(value: str) -> str:
    return "".join(ch for ch in (value or "") if ch.isdigit())


def _normalize_phone_local05(phone: str) -> str:
    raw = (phone or "").strip()
    digits = _keep_digits(raw)

    if len(digits) == 10 and digits.startswith("05"):
        return digits
    if len(digits) == 9 and digits.startswith("5"):
        return f"0{digits}"
    if len(digits) == 12 and digits.startswith("9665"):
        return f"0{digits[3:]}"
    if len(digits) == 14 and digits.startswith("009665"):
        return f"0{digits[5:]}"

    return raw


def _phone_candidates(phone: str) -> list[str]:
    raw = (phone or "").strip()
    local = _normalize_phone_local05(raw)
    digits = _keep_digits(raw)
    local_digits = _keep_digits(local)

    candidates = {
        raw,
        local,
        digits,
        local_digits,
    }

    if len(local_digits) == 10 and local_digits.startswith("05"):
        tail = local_digits[1:]
        candidates.update(
            {
                tail,
                f"+966{tail}",
                f"966{tail}",
                f"00966{tail}",
            }
        )

    return [c for c in candidates if c]


def dashboard_login(request: HttpRequest) -> HttpResponse:
    user = getattr(request, "user", None)
    if getattr(user, "is_authenticated", False) and bool(request.session.get(SESSION_OTP_VERIFIED_KEY)):
        fallback = first_allowed_dashboard_route(user)
        if fallback:
            return redirect(fallback)
        return redirect("dashboard:home")

    if request.method == "POST":
        phone_raw = (request.POST.get("phone") or "").strip()
        phone = _normalize_phone_local05(phone_raw)

        if not phone:
            messages.error(request, "رقم الجوال مطلوب")
            return render(request, "dashboard/login.html", {})

        # Rate limit by IP address
        client_ip = request.META.get("HTTP_X_FORWARDED_FOR", "").split(",")[0].strip() or request.META.get("REMOTE_ADDR", "unknown")
        if _is_rate_limited("login_ip", client_ip, LOGIN_MAX_ATTEMPTS, LOGIN_LOCKOUT_SECONDS):
            messages.error(request, "تم تجاوز عدد المحاولات. يرجى الانتظار 10 دقائق.")
            return render(request, "dashboard/login.html", {"phone": phone_raw})

        dashboard_user = User.objects.filter(phone__in=_phone_candidates(phone)).order_by("id").first()
        if dashboard_user:
            changed_fields = sync_dashboard_user_access(dashboard_user, force_staff_role_state=False)
            if changed_fields:
                dashboard_user.save(update_fields=changed_fields)

        if not dashboard_user or not dashboard_user.is_active or not dashboard_portal_eligible(dashboard_user):
            messages.error(request, "لا يوجد حساب تشغيل فعّال بهذا الرقم")
            return render(request, "dashboard/login.html", {"phone": phone_raw})

        request.session[SESSION_LOGIN_PHONE_KEY] = dashboard_user.phone

        # Dev mode: user can enter ANY 4 digits.
        # Production mode: generate/store OTP (delivery is external).
        if not accept_any_otp_code():
            create_otp(dashboard_user.phone, request)
            logger.info("Dashboard OTP generated phone=%s", dashboard_user.phone)

        return redirect("dashboard:otp")

    return render(request, "dashboard/login.html", {})


def dashboard_otp(request: HttpRequest) -> HttpResponse:
    if bool(request.session.get(SESSION_OTP_VERIFIED_KEY)) and getattr(getattr(request, "user", None), "is_authenticated", False):
        fallback = first_allowed_dashboard_route(request.user)
        if fallback:
            return redirect(fallback)
        return redirect("dashboard:home")

    phone = (request.session.get(SESSION_LOGIN_PHONE_KEY) or "").strip()
    if not phone:
        return redirect("dashboard:login")

    if request.method == "POST":
        code = (request.POST.get("code") or "").strip()
        if not (len(code) == 4 and code.isdigit()):
            messages.error(request, "الكود يجب أن يكون 4 أرقام")
            return render(request, "dashboard/otp.html", {"phone": phone})

        # Rate limit OTP attempts per phone number
        if _is_rate_limited("otp", phone, OTP_MAX_ATTEMPTS, OTP_LOCKOUT_SECONDS):
            messages.error(request, "تم تجاوز عدد محاولات إدخال الكود. يرجى الانتظار 5 دقائق.")
            return render(request, "dashboard/otp.html", {"phone": phone})

        dev_accept_any = accept_any_otp_code()
        if not dev_accept_any:
            if not verify_otp(phone, code):
                messages.error(request, "الكود غير صحيح أو منتهي")
                return render(request, "dashboard/otp.html", {"phone": phone})

        dashboard_user = User.objects.filter(phone__in=_phone_candidates(phone)).order_by("id").first()
        if dashboard_user:
            changed_fields = sync_dashboard_user_access(dashboard_user, force_staff_role_state=False)
            if changed_fields:
                dashboard_user.save(update_fields=changed_fields)

        if not dashboard_user or not dashboard_user.is_active or not dashboard_portal_eligible(dashboard_user):
            messages.error(request, "لا يوجد حساب تشغيل صالح لهذا الرقم")
            return redirect("dashboard:login")

        login(request, dashboard_user, backend="django.contrib.auth.backends.ModelBackend")
        request.session[SESSION_OTP_VERIFIED_KEY] = True

        # Clear rate limit counters on successful login
        _reset_rate_limit("otp", phone)

        next_url = (request.session.pop(SESSION_NEXT_URL_KEY, "") or "").strip()
        if is_safe_redirect_url(next_url):
            return redirect(next_url)
        fallback = first_allowed_dashboard_route(dashboard_user)
        if fallback:
            return redirect(fallback)
        request.session.pop(SESSION_OTP_VERIFIED_KEY, None)
        logout(request)
        messages.error(request, "لا توجد لوحات تشغيل مفعلة لهذا الحساب")
        return redirect("dashboard:login")

    return render(
        request,
        "dashboard/otp.html",
        {
            "phone": phone,
            "dev_accept_any": accept_any_otp_code(),
        },
    )


def dashboard_logout(request: HttpRequest) -> HttpResponse:
    try:
        request.session.pop(SESSION_OTP_VERIFIED_KEY, None)
        request.session.pop(SESSION_LOGIN_PHONE_KEY, None)
        request.session.pop(SESSION_NEXT_URL_KEY, None)
    except Exception:
        pass
    logout(request)
    return redirect("dashboard:login")
