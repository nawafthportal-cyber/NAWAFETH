import random
from datetime import timedelta
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
    """Verify OTP code and mark it used. Returns True if valid."""
    from .models import OTP
    otp = OTP.objects.filter(phone=phone, is_used=False).order_by("-id").first()
    if not otp or otp.expires_at < timezone.now() or otp.code != code:
        return False
    otp.is_used = True
    otp.save(update_fields=["is_used"])
    return True


def accept_any_otp_code() -> bool:
    """Dev bypass — accept any 4-digit code when DEBUG=True."""
    from django.conf import settings
    return getattr(settings, "DEBUG", False)
