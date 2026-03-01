from django.conf import settings
from django.utils import timezone
from django.utils.timezone import timedelta
import logging
import re
import secrets
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from .models import OTP, User, UserRole, Wallet
from .serializers import (
    CompleteRegistrationSerializer,
    MeUpdateSerializer,
    OTPSendSerializer,
    OTPVerifySerializer,
    WalletSerializer,
)

from .permissions import IsAtLeastPhoneOnly
from .otp import generate_otp_code, otp_expiry

logger = logging.getLogger(__name__)


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
                tail,  # 5XXXXXXXX
                f"+966{tail}",
                f"966{tail}",
                f"00966{tail}",
            }
        )

    return [c for c in candidates if c]


def _is_valid_username(username: str) -> bool:
    return bool(re.match(r"^[A-Za-z0-9_.]+$", username))


def _safe_media_url(field_file):
    if not field_file:
        return None
    try:
        name = (field_file.name or "").strip()
        if not name:
            return None
        if not field_file.storage.exists(name):
            return None
        return field_file.url
    except Exception:
        return None


def _me_payload(user: User) -> dict:
    has_provider_profile = False
    try:
        # related_name on ProviderProfile.user is "provider_profile"
        has_provider_profile = bool(getattr(user, "provider_profile", None))
    except Exception:
        has_provider_profile = False

    # Counts for client-side profile (best-effort)
    following_count = 0
    likes_count = 0
    favorites_media_count = 0
    try:
        following_count = user.provider_follows.count()
    except Exception:
        following_count = 0
    try:
        likes_count = user.provider_likes.count()
    except Exception:
        likes_count = 0
    try:
        # Source of truth for "مفضلتي" media in Interactive tab.
        favorites_media_count = user.portfolio_likes.count()
    except Exception:
        favorites_media_count = 0

    provider_profile_id = None
    provider_display_name = None
    provider_city = None
    provider_followers_count = 0
    provider_likes_received_count = 0
    provider_rating_avg = None
    provider_rating_count = 0
    if has_provider_profile:
        try:
            pp = user.provider_profile
            provider_profile_id = pp.id
            provider_display_name = pp.display_name
            provider_city = pp.city
            provider_followers_count = pp.followers.count()
            provider_likes_received_count = pp.likes.count()
            provider_rating_avg = pp.rating_avg
            provider_rating_count = pp.rating_count
        except Exception:
            pass

    role_state = getattr(user, "role_state", None)
    is_provider = bool(role_state == UserRole.PROVIDER) or has_provider_profile

    return {
        "id": user.id,
        "phone": user.phone,
        "email": user.email,
        "username": user.username,
        "first_name": getattr(user, "first_name", None),
        "last_name": getattr(user, "last_name", None),
        "city": getattr(user, "city", None),
        "profile_image": _safe_media_url(getattr(user, "profile_image", None)),
        "cover_image": _safe_media_url(getattr(user, "cover_image", None)),
        "role_state": role_state,
        "has_provider_profile": has_provider_profile,
        "is_provider": is_provider,
        "following_count": following_count,
        "likes_count": likes_count,
        "favorites_media_count": favorites_media_count,
        "provider_profile_id": provider_profile_id,
        "provider_display_name": provider_display_name,
        "provider_city": provider_city,
        "provider_followers_count": provider_followers_count,
        "provider_likes_received_count": provider_likes_received_count,
        "provider_rating_avg": provider_rating_avg,
        "provider_rating_count": provider_rating_count,
    }


def _client_ip(request) -> str | None:
    xff = (request.META.get("HTTP_X_FORWARDED_FOR") or "").strip()
    if xff:
        # First IP is the original client
        return xff.split(",")[0].strip() or None
    return (request.META.get("REMOTE_ADDR") or "").strip() or None


def _otp_test_authorized(request) -> bool:
    test_mode = bool(getattr(settings, "OTP_TEST_MODE", False))
    if not test_mode:
        return False

    test_key = (getattr(settings, "OTP_TEST_KEY", "") or "").strip()
    if not test_key:
        return False

    test_header = (
        getattr(settings, "OTP_TEST_HEADER", "X-OTP-TEST-KEY")
        or "X-OTP-TEST-KEY"
    ).strip()
    provided = (request.headers.get(test_header) or "").strip()
    return bool(provided) and secrets.compare_digest(provided, test_key)


def _issue_tokens_for_phone(phone: str):
    normalized_phone = _normalize_phone_local05(phone)
    phone_username = normalized_phone.lstrip("@")
    user = User.objects.filter(phone__in=_phone_candidates(normalized_phone)).order_by("id").first()
    created = False

    # Backward-compatibility: old account deletion flow used soft-delete
    # (is_active=False). Allow fresh registration with the same phone by
    # removing that legacy inactive user record first.
    if user is not None and not user.is_active:
        if user.is_staff or user.is_superuser:
            return None, created
        try:
            user.delete()
            user = None
        except Exception:
            return None, created

    if user is None:
        user = User.objects.create(
            phone=normalized_phone,
            role_state=UserRole.PHONE_ONLY,
            username=phone_username,
        )
        created = True

    # Ensure baseline "phone-only" identity for accounts that are still at
    # pre-completion level, and backfill username for legacy rows.
    update_fields: list[str] = []
    if user.role_state in (UserRole.VISITOR, UserRole.PHONE_ONLY) and user.role_state != UserRole.PHONE_ONLY:
        user.role_state = UserRole.PHONE_ONLY
        update_fields.append("role_state")

    current_username = (user.username or "").strip()
    if not current_username:
        user.username = phone_username
        update_fields.append("username")
    elif current_username == f"@{phone_username}":
        # Auto-fix accounts created with legacy phone username format.
        user.username = phone_username
        update_fields.append("username")

    if update_fields:
        user.save(update_fields=update_fields)

    refresh = RefreshToken.for_user(user)
    payload = {
        "ok": True,
        "user_id": user.id,
        "role_state": user.role_state,
        "is_new_user": bool(created),
        "needs_completion": user.role_state in (UserRole.VISITOR, UserRole.PHONE_ONLY),
        "refresh": str(refresh),
        "access": str(refresh.access_token),
    }
    return payload, created


class ThrottledTokenObtainPairView(TokenObtainPairView):
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "auth"


class ThrottledTokenRefreshView(TokenRefreshView):
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "refresh"

@api_view(["GET", "DELETE", "PATCH", "PUT"])
@permission_classes([IsAuthenticated])
def me_view(request):
    user = request.user

    if request.method == "DELETE":
        user.delete()
        return Response({"ok": True}, status=status.HTTP_200_OK)

    if request.method in ("PATCH", "PUT"):
        serializer = MeUpdateSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        # Username is immutable after registration/completion for all users.
        if "username" in data:
            return Response(
                {"username": ["لا يمكن تعديل اسم المستخدم بعد التسجيل"]},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Uniqueness safeguard for phone.
        if "phone" in data:
            new_phone = data.get("phone")
            if new_phone and new_phone != user.phone:
                if User.objects.filter(phone=new_phone).exclude(pk=user.pk).exists():
                    return Response(
                        {"phone": ["رقم الجوال مستخدم مسبقاً"]},
                        status=status.HTTP_400_BAD_REQUEST,
                    )
                user.phone = new_phone

        # Optional fields (allow clearing by sending empty string)
        for field in ("email", "first_name", "last_name", "city"):
            if field in data:
                val = data.get(field)
                setattr(user, field, val)

        for field in ("profile_image", "cover_image"):
            if field in data:
                setattr(user, field, data.get(field))

        user.save()

    return Response(_me_payload(user))


@api_view(["POST"])
@permission_classes([AllowAny])
@throttle_classes([ScopedRateThrottle])
def otp_send(request):
    s = OTPSendSerializer(data=request.data)
    s.is_valid(raise_exception=True)

    phone = _normalize_phone_local05(s.validated_data["phone"])
    client_ip = _client_ip(request)

    # Basic cooldown to prevent spam (professional default)
    cooldown_seconds = int(getattr(settings, "OTP_COOLDOWN_SECONDS", 60))
    last = OTP.objects.filter(phone=phone).order_by("-id").first()
    if last and (timezone.now() - last.created_at).total_seconds() < cooldown_seconds:
        return Response(
            {"detail": "يرجى الانتظار قبل إعادة إرسال الرمز"},
            status=status.HTTP_429_TOO_MANY_REQUESTS,
        )

    # Per-phone hourly limit
    phone_hourly_limit = int(getattr(settings, "OTP_PHONE_HOURLY_LIMIT", 0) or 0)
    if phone_hourly_limit > 0:
        since = timezone.now() - timedelta(hours=1)
        cnt = OTP.objects.filter(phone=phone, created_at__gte=since).count()
        if cnt >= phone_hourly_limit:
            return Response(
                {"detail": "تم تجاوز حد إرسال الرموز لهذا الرقم مؤقتًا"},
                status=status.HTTP_429_TOO_MANY_REQUESTS,
            )

    # Per-phone daily limit
    phone_daily_limit = int(getattr(settings, "OTP_PHONE_DAILY_LIMIT", 0) or 0)
    if phone_daily_limit > 0:
        today_start = timezone.localtime().replace(hour=0, minute=0, second=0, microsecond=0)
        cnt = OTP.objects.filter(phone=phone, created_at__gte=today_start).count()
        if cnt >= phone_daily_limit:
            return Response(
                {"detail": "تم تجاوز الحد اليومي لإرسال الرموز لهذا الرقم"},
                status=status.HTTP_429_TOO_MANY_REQUESTS,
            )

    # Per-IP hourly limit (best-effort)
    ip_hourly_limit = int(getattr(settings, "OTP_IP_HOURLY_LIMIT", 0) or 0)
    if ip_hourly_limit > 0 and client_ip:
        since = timezone.now() - timedelta(hours=1)
        cnt = OTP.objects.filter(ip_address=client_ip, created_at__gte=since).count()
        if cnt >= ip_hourly_limit:
            return Response(
                {"detail": "تم تجاوز حد إرسال الرموز من هذا الجهاز/الشبكة مؤقتًا"},
                status=status.HTTP_429_TOO_MANY_REQUESTS,
            )

    # Generate a new code.
    # For staging QA only, you can force a fixed OTP via OTP_TEST_CODE (e.g. 0000)
    # but only when OTP_TEST_MODE is enabled and the secret header matches.
    test_code = (getattr(settings, "OTP_TEST_CODE", "") or "").strip()
    if test_code and _otp_test_authorized(request):
        code = test_code
    else:
        code = generate_otp_code()
    OTP.objects.create(
        phone=phone,
        ip_address=client_ip,
        code=code,
        expires_at=otp_expiry(5),
    )

    # Audit (اختياري)
    try:
        from apps.audit.services import log_action
        from apps.audit.models import AuditAction

        actor = User.objects.filter(phone=phone).first()
        log_action(
            actor=actor,
            action=AuditAction.LOGIN_OTP_SENT,
            reference_type="phone",
            reference_id=phone,
            request=request,
        )
    except Exception:
        pass

    # ✅ Dev/Test helpers
    # - DEBUG: return dev_code for local development only.
    # - OTP_TEST_MODE: staging-only helper guarded by a secret header.
    payload = {"ok": True}
    if bool(getattr(settings, "DEBUG", False)):
        payload["dev_code"] = code
    elif _otp_test_authorized(request):
        payload["dev_code"] = code
    return Response(payload, status=status.HTTP_200_OK)


@api_view(["POST"])
@permission_classes([AllowAny])
@throttle_classes([ScopedRateThrottle])
def otp_verify(request):
    s = OTPVerifySerializer(data=request.data)
    s.is_valid(raise_exception=True)

    phone = _normalize_phone_local05(s.validated_data["phone"])
    code = s.validated_data["code"].strip()
    client_ip = _client_ip(request)

    # Staging-only fixed code bypass (QA): accept OTP_TEST_CODE when authorized.
    test_code = (getattr(settings, "OTP_TEST_CODE", "") or "").strip()
    if test_code and code == test_code and _otp_test_authorized(request):
        # Validate format only
        if not (len(code) == 4 and code.isdigit()):
            return Response({"detail": "الكود يجب أن يكون 4 أرقام"}, status=status.HTTP_400_BAD_REQUEST)

        payload, created = _issue_tokens_for_phone(phone)
        if payload is None:
            return Response({"detail": "الحساب غير نشط"}, status=status.HTTP_400_BAD_REQUEST)

        # Best-effort cleanup: mark last OTP as used.
        otp = OTP.objects.filter(phone=phone, is_used=False).order_by("-id").first()
        if otp:
            otp.is_used = True
            otp.save(update_fields=["is_used"])

        return Response(payload, status=status.HTTP_200_OK)

    # Staging-only app QA bypass (no headers): accept ANY 4-digit code.
    # - Must be explicitly enabled via OTP_APP_BYPASS=1
    # - If allowlist is provided, only allow those phone numbers
    # - Requires an existing OTP record to keep send limits/cooldowns meaningful
    app_bypass = bool(getattr(settings, "OTP_APP_BYPASS", False))
    bypass_allowlist = list(getattr(settings, "OTP_APP_BYPASS_ALLOWLIST", []) or [])
    bypass_allowed_for_phone = (not bypass_allowlist) or (phone in bypass_allowlist)

    if app_bypass and bypass_allowed_for_phone:
        if not (len(code) == 4 and code.isdigit()):
            return Response({"detail": "الكود يجب أن يكون 4 أرقام"}, status=status.HTTP_400_BAD_REQUEST)

        otp = OTP.objects.filter(phone=phone, is_used=False).order_by("-id").first()
        if not otp or otp.expires_at < timezone.now():
            return Response(
                {"detail": "أعد طلب رمز جديد"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        otp.is_used = True
        otp.save(update_fields=["is_used"])

        logger.warning("OTP_APP_BYPASS used phone=%s ip=%s", phone, client_ip)

        payload, created = _issue_tokens_for_phone(phone)
        if payload is None:
            return Response({"detail": "الحساب غير نشط"}, status=status.HTTP_400_BAD_REQUEST)

        return Response(payload, status=status.HTTP_200_OK)

    # FORCE BYPASS if configured (Resolves user frustration with Development/Testing)
    # Check settings directly, default to True (temporary/testing mode).
    # Temporary/testing-friendly behavior (user requested):
    # accept any 4-digit code unless explicitly disabled in settings.
    dev_accept_any = getattr(settings, "OTP_DEV_ACCEPT_ANY_CODE", True)
    
    # Also considering DEBUG just to be consistent, but prioritized dev_accept_any
    # User request: Accept ANY random numbers without verification (bypassing strict check)
    if dev_accept_any or settings.DEBUG:
        # Validate format only
        if not (len(code) == 4 and code.isdigit()):
             return Response({"detail": "الكود يجب أن يكون 4 أرقام"}, status=status.HTTP_400_BAD_REQUEST)

        # Skip DB check, mark LAST OTP as used if exists (for cleanup)
        otp = OTP.objects.filter(phone=phone, is_used=False).order_by("-id").first()
        if otp:
            otp.is_used = True
            otp.save(update_fields=["is_used"])

        payload, created = _issue_tokens_for_phone(phone)
        if payload is None:
            return Response({"detail": "الحساب غير نشط"}, status=status.HTTP_400_BAD_REQUEST)

        return Response(payload, status=status.HTTP_200_OK)

    # Normal Production Logic

    otp = OTP.objects.filter(phone=phone, is_used=False).order_by("-id").first()
    if not otp:
        return Response({"detail": "الكود غير صحيح"}, status=status.HTTP_400_BAD_REQUEST)

    if otp.expires_at < timezone.now():
        return Response({"detail": "انتهت صلاحية الكود"}, status=status.HTTP_400_BAD_REQUEST)

    # Limit brute-force attempts
    max_attempts = int(getattr(settings, "OTP_MAX_ATTEMPTS", 5))
    if otp.attempts >= max_attempts:
        otp.is_used = True
        otp.save(update_fields=["is_used"])
        return Response(
            {"detail": "تم تجاوز عدد المحاولات، أعد طلب رمز جديد"},
            status=status.HTTP_429_TOO_MANY_REQUESTS,
        )

    if otp.code != code:
        otp.attempts += 1
        if otp.attempts >= max_attempts:
            otp.is_used = True
            otp.save(update_fields=["attempts", "is_used"])
            return Response(
                {"detail": "تم تجاوز عدد المحاولات، أعد طلب رمز جديد"},
                status=status.HTTP_429_TOO_MANY_REQUESTS,
            )

        otp.save(update_fields=["attempts"])
        return Response({"detail": "الكود غير صحيح"}, status=status.HTTP_400_BAD_REQUEST)

    otp.is_used = True
    otp.save(update_fields=["is_used"])

    payload, created = _issue_tokens_for_phone(phone)
    if payload is None:
        return Response({"detail": "الحساب غير نشط"}, status=status.HTTP_400_BAD_REQUEST)

    # Audit (اختياري)
    try:
        from apps.audit.services import log_action
        from apps.audit.models import AuditAction

        log_action(
            actor=User.objects.filter(phone=phone).first(),
            action=AuditAction.LOGIN_OTP_VERIFIED,
            reference_type="user",
            reference_id=str(payload.get("user_id")),
            request=request,
        )
    except Exception:
        pass

    payload["is_new_user"] = bool(created)
    return Response(payload, status=status.HTTP_200_OK)


# Needed for ScopedRateThrottle on function-based views
otp_send.throttle_scope = "otp"
otp_verify.throttle_scope = "otp"


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def complete_registration(request):
    """Upgrade PHONE_ONLY user to CLIENT (level 3) after collecting required data."""
    s = CompleteRegistrationSerializer(data=request.data, context={"request": request})
    s.is_valid(raise_exception=True)

    user: User = request.user

    # Staff is already privileged; allow update but don't downgrade.
    if not getattr(user, "is_staff", False):
        # Only phone-only/visitor can be completed; already completed is idempotent.
        if user.role_state not in (UserRole.PHONE_ONLY, UserRole.VISITOR, UserRole.CLIENT, UserRole.PROVIDER):
            return Response({"detail": "حالة الحساب غير معروفة"}, status=status.HTTP_400_BAD_REQUEST)

    user.username = s.validated_data["username"]
    user.first_name = s.validated_data["first_name"]
    user.last_name = s.validated_data["last_name"]
    user.email = s.validated_data["email"]
    user.city = s.validated_data.get("city")
    user.set_password(s.validated_data["password"])
    user.terms_accepted_at = timezone.now()

    # Upgrade to CLIENT if not already CLIENT/PROVIDER
    if user.role_state in (UserRole.VISITOR, UserRole.PHONE_ONLY):
        user.role_state = UserRole.CLIENT

    user.save(
        update_fields=[
            "username",
            "first_name",
            "last_name",
            "email",
            "city",
            "password",
            "terms_accepted_at",
            "role_state",
        ]
    )
    return Response({"ok": True, "role_state": user.role_state}, status=status.HTTP_200_OK)


@api_view(["GET"])
@permission_classes([AllowAny])
def username_availability(request):
    """Check whether a username is available for registration."""
    username = (request.query_params.get("username") or "").strip()
    if not username:
        return Response(
            {"ok": True, "available": False, "detail": "اسم المستخدم مطلوب"},
            status=status.HTTP_200_OK,
        )

    if len(username) < 3:
        return Response(
            {
                "ok": True,
                "available": False,
                "detail": "اسم المستخدم يجب أن يكون 3 أحرف على الأقل",
            },
            status=status.HTTP_200_OK,
        )

    if not _is_valid_username(username):
        return Response(
            {
                "ok": True,
                "available": False,
                "detail": "اسم المستخدم يقبل الحروف الإنجليزية والأرقام و (_) و (.) فقط",
            },
            status=status.HTTP_200_OK,
        )

    exists = User.objects.filter(username__iexact=username).exists()
    if exists:
        return Response(
            {"ok": True, "available": False, "detail": "اسم المستخدم محجوز"},
            status=status.HTTP_200_OK,
        )

    return Response(
        {"ok": True, "available": True, "detail": "اسم المستخدم متاح"},
        status=status.HTTP_200_OK,
    )


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def logout_view(request):
    """Blacklist the refresh token so it can't be reused."""
    refresh = request.data.get("refresh")
    if refresh:
        try:
            token = RefreshToken(refresh)
            token.blacklist()
        except Exception:
            pass  # token may already be blacklisted or invalid
    return Response({"ok": True}, status=status.HTTP_200_OK)


@api_view(["DELETE"])
@permission_classes([IsAuthenticated])
def delete_account_view(request):
    """Permanently delete the authenticated user account."""
    user: User = request.user
    user.delete()
    return Response({"ok": True, "detail": "تم حذف الحساب بنجاح"}, status=status.HTTP_200_OK)


@api_view(["GET", "POST"])
@permission_classes([IsAtLeastPhoneOnly])
def wallet_view(request):
    """Open wallet (level 2+) and retrieve wallet info."""
    user: User = request.user
    wallet, _ = Wallet.objects.get_or_create(user=user)
    data = WalletSerializer(wallet).data
    return Response(data, status=status.HTTP_200_OK)
