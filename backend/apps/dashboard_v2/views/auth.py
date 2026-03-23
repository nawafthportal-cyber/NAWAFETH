from __future__ import annotations

import logging

from django.contrib import messages
from django.contrib.auth import login, logout
from django.core.cache import cache
from django.http import HttpRequest, HttpResponse
from django.shortcuts import redirect, render

from apps.accounts.models import User
from apps.accounts.otp import accept_any_otp_code, create_otp, verify_otp
from apps.dashboard.access import dashboard_portal_eligible, sync_dashboard_user_access
from apps.dashboard.auth import (
    SESSION_LOGIN_PHONE_KEY,
    SESSION_NEXT_URL_KEY,
    SESSION_OTP_VERIFIED_KEY,
)

from ..view_utils import safe_post_login_redirect


logger = logging.getLogger(__name__)

OTP_MAX_ATTEMPTS = 5
OTP_LOCKOUT_SECONDS = 300
LOGIN_MAX_ATTEMPTS = 10
LOGIN_LOCKOUT_SECONDS = 600


def _rate_limit_key(prefix: str, identifier: str) -> str:
    return f"dashboard_v2_rl:{prefix}:{(identifier or '').strip().replace(' ', '_')}"


def _is_rate_limited(prefix: str, identifier: str, max_attempts: int, lockout_seconds: int) -> bool:
    key = _rate_limit_key(prefix, identifier)
    attempts = cache.get(key, 0)
    if attempts >= max_attempts:
        return True
    cache.set(key, attempts + 1, lockout_seconds)
    return False


def _reset_rate_limit(prefix: str, identifier: str) -> None:
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
    candidates = {raw, local, digits, local_digits}
    if len(local_digits) == 10 and local_digits.startswith("05"):
        tail = local_digits[1:]
        candidates.update({tail, f"+966{tail}", f"966{tail}", f"00966{tail}"})
    return [value for value in candidates if value]


def login_view(request: HttpRequest) -> HttpResponse:
    user = getattr(request, "user", None)
    if getattr(user, "is_authenticated", False) and bool(request.session.get(SESSION_OTP_VERIFIED_KEY)):
        return redirect(safe_post_login_redirect(request, user=user))

    if request.method == "POST":
        phone_raw = (request.POST.get("phone") or "").strip()
        phone = _normalize_phone_local05(phone_raw)
        if not phone:
            messages.error(request, "رقم الجوال مطلوب")
            return render(request, "dashboard_v2/auth/login.html", {})

        client_ip = request.META.get("HTTP_X_FORWARDED_FOR", "").split(",")[0].strip() or request.META.get("REMOTE_ADDR", "unknown")
        if _is_rate_limited("login_ip", client_ip, LOGIN_MAX_ATTEMPTS, LOGIN_LOCKOUT_SECONDS):
            messages.error(request, "تم تجاوز عدد المحاولات. يرجى الانتظار 10 دقائق.")
            return render(request, "dashboard_v2/auth/login.html", {"phone": phone_raw})

        dashboard_user = User.objects.filter(phone__in=_phone_candidates(phone)).order_by("id").first()
        if dashboard_user:
            changed_fields = sync_dashboard_user_access(dashboard_user, force_staff_role_state=False)
            if changed_fields:
                dashboard_user.save(update_fields=changed_fields)

        if not dashboard_user or not dashboard_user.is_active or not dashboard_portal_eligible(dashboard_user):
            messages.error(request, "لا يوجد حساب تشغيل فعّال بهذا الرقم")
            return render(request, "dashboard_v2/auth/login.html", {"phone": phone_raw})

        request.session[SESSION_LOGIN_PHONE_KEY] = dashboard_user.phone
        _reset_rate_limit("login_ip", client_ip)
        if not accept_any_otp_code():
            create_otp(dashboard_user.phone, request)
            logger.info("Dashboard V2 OTP generated phone=%s", dashboard_user.phone)
        return redirect("dashboard_v2:otp")

    return render(request, "dashboard_v2/auth/login.html", {})


def otp_view(request: HttpRequest) -> HttpResponse:
    if bool(request.session.get(SESSION_OTP_VERIFIED_KEY)) and getattr(getattr(request, "user", None), "is_authenticated", False):
        return redirect(safe_post_login_redirect(request, user=request.user))

    phone = (request.session.get(SESSION_LOGIN_PHONE_KEY) or "").strip()
    if not phone:
        return redirect("dashboard_v2:login")

    if request.method == "POST":
        code = (request.POST.get("code") or "").strip()
        if not (len(code) == 4 and code.isdigit()):
            messages.error(request, "الكود يجب أن يكون 4 أرقام")
            return render(request, "dashboard_v2/auth/otp.html", {"phone": phone})

        if _is_rate_limited("otp", phone, OTP_MAX_ATTEMPTS, OTP_LOCKOUT_SECONDS):
            messages.error(request, "تم تجاوز عدد المحاولات. يرجى الانتظار 5 دقائق.")
            return render(request, "dashboard_v2/auth/otp.html", {"phone": phone})

        if not accept_any_otp_code() and not verify_otp(phone, code):
            messages.error(request, "الكود غير صحيح أو منتهي")
            return render(request, "dashboard_v2/auth/otp.html", {"phone": phone})

        dashboard_user = User.objects.filter(phone__in=_phone_candidates(phone)).order_by("id").first()
        if dashboard_user:
            changed_fields = sync_dashboard_user_access(dashboard_user, force_staff_role_state=False)
            if changed_fields:
                dashboard_user.save(update_fields=changed_fields)

        if not dashboard_user or not dashboard_user.is_active or not dashboard_portal_eligible(dashboard_user):
            messages.error(request, "لا يوجد حساب تشغيل صالح لهذا الرقم")
            return redirect("dashboard_v2:login")

        login(request, dashboard_user, backend="django.contrib.auth.backends.ModelBackend")
        request.session[SESSION_OTP_VERIFIED_KEY] = True
        _reset_rate_limit("otp", phone)

        return redirect(safe_post_login_redirect(request, user=dashboard_user))

    return render(
        request,
        "dashboard_v2/auth/otp.html",
        {
            "phone": phone,
            "dev_accept_any": accept_any_otp_code(),
        },
    )


def logout_view(request: HttpRequest) -> HttpResponse:
    try:
        request.session.pop(SESSION_OTP_VERIFIED_KEY, None)
        request.session.pop(SESSION_LOGIN_PHONE_KEY, None)
        request.session.pop(SESSION_NEXT_URL_KEY, None)
    except Exception:
        pass
    logout(request)
    return redirect("dashboard_v2:login")
