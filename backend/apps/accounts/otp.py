import random
from datetime import timedelta

from django.conf import settings
from django.utils import timezone


def generate_otp_code() -> str:
    return f"{random.randint(0, 9999):04d}"


def otp_expiry(minutes: int = 5):
    return timezone.now() + timedelta(minutes=minutes)


def client_ip(request) -> str | None:
    """Extract client IP from request (X-Forwarded-For or REMOTE_ADDR)."""
    xff = (request.META.get("HTTP_X_FORWARDED_FOR") or "").strip()
    if xff:
        return xff.split(",")[0].strip() or None
    return (request.META.get("REMOTE_ADDR") or "").strip() or None


def create_otp(phone: str, request) -> str:
    """Create an OTP record and return the generated code."""
    from .models import OTP
    code = generate_otp_code()
    OTP.objects.create(
        phone=phone,
        ip_address=client_ip(request),
        code=code,
        expires_at=otp_expiry(5),
    )
    return code


def verify_otp(phone: str, code: str) -> bool:
    """Verify OTP code and mark it used. Returns True if valid.

    Accepts any 4-digit code when accept_any_otp_code() is True,
    or specific dev test code via matches_dev_test_code().
    """
    from .models import OTP
    otp = OTP.objects.filter(phone=phone, is_used=False).order_by("-id").first()
    if not otp or otp.expires_at < timezone.now():
        return False

    # Normalize input
    code_str = str(code or "").strip()

    # Check for exact match
    if otp.code == code_str:
        valid = True
    # Dev/test explicit code
    elif matches_dev_test_code(code_str):
        valid = True
    # Accept any 4-digit numeric code when bypass enabled
    elif accept_any_otp_code() and code_str.isdigit() and len(code_str) == 4:
        valid = True
    else:
        valid = False

    if not valid:
        return False

    otp.is_used = True
    otp.save(update_fields=["is_used"])
    return True


def otp_dev_bypass_enabled() -> bool:
    return bool(getattr(settings, "DEBUG", False)) and bool(
        getattr(settings, "OTP_DEV_BYPASS_ENABLED", False)
    )


def otp_dev_test_code() -> str:
    code = (getattr(settings, "OTP_DEV_TEST_CODE", "") or "").strip()
    if otp_dev_bypass_enabled() and len(code) == 4 and code.isdigit():
        return code
    return ""


def accept_any_otp_code() -> bool:
    """Accept any 4-digit OTP when explicit bypass is enabled.

    Supports:
    - Development bypass (DEBUG + OTP_DEV_BYPASS_ENABLED + OTP_DEV_ACCEPT_ANY_4_DIGITS)
    - App bypass flag (OTP_APP_BYPASS) used by QA/staging and dashboard OTP flows.
    """
    dev_any = otp_dev_bypass_enabled() and bool(
        getattr(settings, "OTP_DEV_ACCEPT_ANY_4_DIGITS", False)
    )
    app_any = bool(getattr(settings, "OTP_APP_BYPASS", False))
    return bool(dev_any or app_any)


def matches_dev_test_code(code: str) -> bool:
    return bool(otp_dev_test_code()) and str(code or "").strip() == otp_dev_test_code()
