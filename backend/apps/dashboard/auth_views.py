from __future__ import annotations

import logging

from django.conf import settings
from django.contrib import messages
from django.contrib.auth import login, logout
from django.http import HttpRequest, HttpResponse
from django.shortcuts import redirect, render
from django.utils import timezone

from apps.accounts.models import OTP, User
from apps.accounts.otp import generate_otp_code, otp_expiry

from .access import first_allowed_dashboard_route, sync_dashboard_user_access
from .auth import (
    SESSION_LOGIN_PHONE_KEY,
    SESSION_NEXT_URL_KEY,
    SESSION_OTP_VERIFIED_KEY,
)


logger = logging.getLogger(__name__)
_dashboard_otp_bypass_warning_logged = False


def _dashboard_accept_any_otp_code() -> bool:
    # Requested temporary behavior: allow any 4-digit code for dashboard OTP.
    # This intentionally bypasses OTP persistence/validation for dashboard login.
    # TODO: Switch this to an explicit environment/settings flag before production hardening.
    global _dashboard_otp_bypass_warning_logged
    enabled = True
    if enabled and not getattr(settings, "DEBUG", False) and not _dashboard_otp_bypass_warning_logged:
        logger.warning("Dashboard OTP bypass (accept any 4-digit code) is active while DEBUG=False")
        _dashboard_otp_bypass_warning_logged = True
    return enabled


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


def _client_ip(request: HttpRequest) -> str | None:
    xff = (request.META.get("HTTP_X_FORWARDED_FOR") or "").strip()
    if xff:
        return xff.split(",")[0].strip() or None
    return (request.META.get("REMOTE_ADDR") or "").strip() or None


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

        staff_user = User.objects.filter(phone__in=_phone_candidates(phone)).order_by("id").first()
        if staff_user:
            changed_fields = sync_dashboard_user_access(staff_user, force_staff_role_state=False)
            if changed_fields:
                staff_user.save(update_fields=changed_fields)

        if not staff_user or not staff_user.is_active or not staff_user.is_staff:
            messages.error(request, "لا يوجد حساب تشغيل فعّال بهذا الرقم")
            return render(request, "dashboard/login.html", {"phone": phone_raw})

        request.session[SESSION_LOGIN_PHONE_KEY] = staff_user.phone

        # Dev mode: user can enter ANY 4 digits.
        # Production mode: generate/store OTP (delivery is external).
        if not _dashboard_accept_any_otp_code():
            code = generate_otp_code()
            OTP.objects.create(
                phone=staff_user.phone,
                ip_address=_client_ip(request),
                code=code,
                expires_at=otp_expiry(5),
            )
            logger.info("Dashboard OTP generated phone=%s", staff_user.phone)

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

        dev_accept_any = _dashboard_accept_any_otp_code()
        if not dev_accept_any:
            otp = OTP.objects.filter(phone=phone, is_used=False).order_by("-id").first()
            if not otp or otp.expires_at < timezone.now() or otp.code != code:
                messages.error(request, "الكود غير صحيح أو منتهي")
                return render(request, "dashboard/otp.html", {"phone": phone})
            otp.is_used = True
            otp.save(update_fields=["is_used"])

        staff_user = User.objects.filter(phone__in=_phone_candidates(phone)).order_by("id").first()
        if staff_user:
            changed_fields = sync_dashboard_user_access(staff_user, force_staff_role_state=False)
            if changed_fields:
                staff_user.save(update_fields=changed_fields)

        if not staff_user or not staff_user.is_active or not staff_user.is_staff:
            messages.error(request, "لا يوجد حساب تشغيل صالح لهذا الرقم")
            return redirect("dashboard:login")

        login(request, staff_user, backend="django.contrib.auth.backends.ModelBackend")
        request.session[SESSION_OTP_VERIFIED_KEY] = True

        next_url = (request.session.pop(SESSION_NEXT_URL_KEY, "") or "").strip()
        if next_url and next_url.startswith("/"):
            return redirect(next_url)
        fallback = first_allowed_dashboard_route(staff_user)
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
            "dev_accept_any": _dashboard_accept_any_otp_code(),
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
