from django.conf import settings
from django.contrib.auth import login as auth_login, logout as auth_logout, update_session_auth_hash
from django.core.exceptions import ObjectDoesNotExist
from django.db import IntegrityError
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
from rest_framework_simplejwt.exceptions import InvalidToken
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from .models import OTP, BiometricToken, User, UserRole, Wallet
from .serializers import (
    BiometricEnrollSerializer,
    BiometricLoginSerializer,
    ChangePasswordSerializer,
    ChangeUsernameSerializer,
    CompleteRegistrationSerializer,
    MeUpdateSerializer,
    OTPSendSerializer,
    OTPVerifySerializer,
    WalletSerializer,
)
from .phone_validation import keep_digits as _keep_digits, normalize_phone_local05 as _normalize_phone_local05

from .permissions import IsAtLeastPhoneOnly
from .role_context import get_active_role, get_validated_role
from .otp import (
    accept_any_otp_code,
    generate_otp_code,
    matches_dev_test_code,
    otp_dev_bypass_enabled,
    otp_dev_test_code,
    otp_expiry,
)
from apps.core.throttling import build_cooldown_payload, throttled_response
from apps.providers.location_formatter import format_city_display
from apps.uploads.media_optimizer import optimize_upload_for_storage
from apps.uploads.validators import IMAGE_EXTENSIONS, IMAGE_MIME_TYPES, validate_secure_upload

logger = logging.getLogger(__name__)


def _safe_format_city_display(city: str | None, *, region: str = "") -> str:
    """Format city labels without letting optional region lookup break /me/.

    ``format_city_display`` may consult the SaudiCity table to infer the region.
    During brief local SQLite locks or transient DB hiccups, that secondary
    lookup should not cause the authenticated profile endpoint to fail.
    """
    raw_city = str(city or "").strip()
    if not raw_city:
        return ""
    try:
        return format_city_display(raw_city, region=region)
    except Exception:
        return raw_city

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


def _otp_app_bypass_allowed(phone: str) -> bool:
    if not bool(getattr(settings, "OTP_APP_BYPASS", False)):
        return False
    allowlist = getattr(settings, "OTP_APP_BYPASS_ALLOWLIST", None) or []
    # When an allowlist is configured, only those phones may bypass.
    if allowlist:
        normalized = _normalize_phone_local05(phone)
        return any(_normalize_phone_local05(p) == normalized for p in allowlist if p)
    return True


def _is_valid_username(username: str) -> bool:
    return bool(re.match(r"^[A-Za-z0-9_.]+$", username))


def _safe_media_url(field_file):
    """Return the URL for a media file field, or None.

    NOTE: We intentionally skip ``storage.exists()`` — it causes
    a remote HEAD request per file for R2/S3 and returns None for
    files on ephemeral disks after a Render redeploy.
    """
    if not field_file:
        return None
    try:
        name = (field_file.name or "").strip()
        if not name:
            return None
        return field_file.url
    except Exception:
        return None


def _has_completed_client_registration(user: User) -> bool:
    required_values = (
        getattr(user, "username", ""),
        getattr(user, "first_name", ""),
        getattr(user, "last_name", ""),
        getattr(user, "email", ""),
    )
    return bool(getattr(user, "terms_accepted_at", None)) and all(
        str(value or "").strip() for value in required_values
    )


def _resolve_profile_status(user: User) -> str:
    role_state = getattr(user, "role_state", None)
    if role_state == UserRole.PROVIDER:
        return "provider"
    if role_state == UserRole.STAFF:
        return "staff"
    if role_state == UserRole.VISITOR:
        return "visitor"
    if role_state == UserRole.PHONE_ONLY:
        return "phone_only"
    if role_state == UserRole.CLIENT:
        return "complete" if _has_completed_client_registration(user) else "phone_only"
    return "unknown"


def _resolve_role_label(user: User) -> str:
    role_state = getattr(user, "role_state", None)
    profile_status = _resolve_profile_status(user)
    if role_state == UserRole.PROVIDER:
        return "مقدم خدمة"
    if role_state == UserRole.STAFF:
        return "موظف"
    if role_state == UserRole.VISITOR:
        return "زائر"
    if profile_status == "phone_only":
        return "عميل برقم الجوال"
    if role_state == UserRole.CLIENT:
        return "عميل"
    return "حساب مستخدم"


def _me_payload(user: User, *, request=None) -> dict:
    active_role = get_active_role(request) if request is not None else UserRole.CLIENT
    validated_role = get_validated_role(request) if request is not None else UserRole.CLIENT
    profile_status = _resolve_profile_status(user)
    role_label = _resolve_role_label(user)

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
        following_count = (
            user.provider_follows.filter(role_context=active_role)
            .values("provider_id")
            .distinct()
            .count()
        )
    except Exception:
        following_count = 0
    try:
        likes_count = (
            user.provider_likes.filter(role_context=active_role)
            .values("provider_id")
            .distinct()
            .count()
        )
    except Exception:
        likes_count = 0
    try:
        portfolio_saved_ids = set(
            user.portfolio_saves.filter(role_context=active_role).values_list(
                "item_id", flat=True
            )
        )
        portfolio_liked_ids = set(
            user.portfolio_likes.filter(role_context=active_role).values_list(
                "item_id", flat=True
            )
        )
        spotlight_saved_ids = set(
            user.spotlight_saves.filter(role_context=active_role).values_list(
                "item_id", flat=True
            )
        )
        spotlight_liked_ids = set(
            user.spotlight_likes.filter(role_context=active_role).values_list(
                "item_id", flat=True
            )
        )
        favorites_media_count = len(portfolio_saved_ids | portfolio_liked_ids) + len(
            spotlight_saved_ids | spotlight_liked_ids
        )
    except Exception:
        favorites_media_count = 0

    provider_profile_id = None
    provider_display_name = None
    provider_city = None
    provider_followers_count = 0
    provider_likes_received_count = 0
    provider_rating_avg = None
    provider_rating_count = 0
    if has_provider_profile and validated_role == UserRole.PROVIDER:
        try:
            pp = user.provider_profile
            provider_profile_id = pp.id
            provider_display_name = pp.display_name
            provider_city = pp.city
            from django.core.cache import cache as _cache
            _fk = f"provider:{pp.id}:followers"
            _lk = f"provider:{pp.id}:likes"
            provider_followers_count = _cache.get(_fk)
            if provider_followers_count is None:
                provider_followers_count = pp.followers.count()
                _cache.set(_fk, provider_followers_count, 300)
            provider_likes_received_count = _cache.get(_lk)
            if provider_likes_received_count is None:
                provider_likes_received_count = pp.likes.count()
                _cache.set(_lk, provider_likes_received_count, 300)
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
        "city_display": _safe_format_city_display(getattr(user, "city", None)),
        "profile_image": _safe_media_url(getattr(user, "profile_image", None)),
        "cover_image": _safe_media_url(getattr(user, "cover_image", None)),
        "role_state": role_state,
        "profile_status": profile_status,
        "role_label": role_label,
        "has_provider_profile": has_provider_profile,
        "is_provider": is_provider,
        "following_count": following_count,
        "likes_count": likes_count,
        "favorites_media_count": favorites_media_count,
        "provider_profile_id": provider_profile_id,
        "provider_display_name": provider_display_name,
        "provider_city": provider_city,
        "provider_city_display": _safe_format_city_display(provider_city),
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


def _auth_backend_path() -> str:
    backends = getattr(settings, "AUTHENTICATION_BACKENDS", None) or ["django.contrib.auth.backends.ModelBackend"]
    return str(backends[0])


def _start_web_session(request, user: User | None) -> None:
    if request is None or user is None or not getattr(user, "is_active", False):
        return
    auth_login(request, user, backend=_auth_backend_path())


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
            return None, created, None
        try:
            user.delete()
            user = None
        except Exception:
            return None, created, None

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
        "profile_status": _resolve_profile_status(user),
        "role_label": _resolve_role_label(user),
        "is_new_user": bool(created),
        "needs_completion": user.role_state in (UserRole.VISITOR, UserRole.PHONE_ONLY),
        "refresh": str(refresh),
        "access": str(refresh.access_token),
    }
    return payload, created, user


class ThrottledTokenObtainPairView(TokenObtainPairView):
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "auth"


class ThrottledTokenRefreshView(TokenRefreshView):
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "refresh"

    def post(self, request, *args, **kwargs):
        try:
            response = super().post(request, *args, **kwargs)
        except (User.DoesNotExist, ObjectDoesNotExist):
            # The refresh token subject points to a user that no longer exists.
            # Return the expected auth failure instead of a server error.
            logging.getLogger("nawafeth.auth").warning(
                "token_refresh_failed status=%s reason=%s",
                status.HTTP_401_UNAUTHORIZED,
                "user_not_found",
                extra={"log_category": "auth_failure"},
            )
            raise InvalidToken("User not found")
        if response.status_code >= status.HTTP_400_BAD_REQUEST:
            logging.getLogger("nawafeth.auth").warning(
                "token_refresh_failed status=%s",
                response.status_code,
                extra={"log_category": "auth_failure"},
            )
        return response

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

        # Phone changes require OTP verification via the dedicated endpoints:
        #   POST /api/accounts/me/request-phone-change/
        #   POST /api/accounts/me/confirm-phone-change/
        # Direct mutation here is blocked to prevent silent credential replacement.
        if "phone" in data:
            return Response(
                {"phone": ["لتغيير رقم الجوال يجب التحقق عبر رمز OTP. استخدم /api/accounts/me/request-phone-change/"]},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Optional fields (allow clearing by sending empty string)
        for field in ("email", "first_name", "last_name", "city"):
            if field in data:
                val = data.get(field)
                setattr(user, field, val)

        from django.core.exceptions import ValidationError as DjangoValidationError

        try:
            for field in ("profile_image", "cover_image"):
                if field not in data:
                    continue
                upload = data.get(field)
                if upload is None:
                    setattr(user, field, None)
                    continue
                validate_secure_upload(
                    upload,
                    allowed_extensions=IMAGE_EXTENSIONS,
                    allowed_mime_types=IMAGE_MIME_TYPES,
                    max_size_mb=20,
                    rename=True,
                    rename_prefix=f"user_{field}",
                )
                optimized = optimize_upload_for_storage(upload, declared_type="image")
                setattr(user, field, optimized)
        except DjangoValidationError as exc:
            return Response(
                {"detail": str(exc)},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            user.save()
        except IntegrityError:
            return Response(
                {"phone": ["رقم الجوال مستخدم مسبقاً"]},
                status=status.HTTP_400_BAD_REQUEST,
            )
        except Exception as exc:
            # Catch storage backend errors (e.g. R2/S3 403 Forbidden)
            msg = str(exc)
            if any(kw in msg for kw in ("403", "Forbidden", "S3", "boto", "bucket", "storage", "ImproperlyConfigured")):
                import logging
                logging.getLogger(__name__).error("Storage error saving user profile: %s", msg)
                return Response(
                    {"detail": "فشل رفع الملف: مشكلة في التخزين السحابي. يرجى التواصل مع الدعم الفني."},
                    status=status.HTTP_502_BAD_GATEWAY,
                )
            raise

    return Response(_me_payload(user, request=request))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def change_username_view(request):
    serializer = ChangeUsernameSerializer(data=request.data, context={"request": request})
    serializer.is_valid(raise_exception=True)

    user = request.user
    user.username = serializer.validated_data["username"]
    user.save(update_fields=["username"])
    return Response({"ok": True, "username": user.username}, status=status.HTTP_200_OK)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def change_password_view(request):
    serializer = ChangePasswordSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    user = request.user
    current_password = serializer.validated_data["current_password"]
    new_password = serializer.validated_data["new_password"]

    if not user.check_password(current_password):
        return Response({"current_password": ["كلمة المرور الحالية غير صحيحة"]}, status=status.HTTP_400_BAD_REQUEST)

    user.set_password(new_password)
    user.save(update_fields=["password"])
    return Response({"ok": True}, status=status.HTTP_200_OK)


@api_view(["POST"])
@permission_classes([AllowAny])
@throttle_classes([ScopedRateThrottle])
def otp_send(request):
    s = OTPSendSerializer(data=request.data)
    s.is_valid(raise_exception=True)

    phone = _normalize_phone_local05(s.validated_data["phone"])
    client_ip = _client_ip(request)
    now = timezone.now()

    # Basic cooldown to prevent spam (professional default)
    cooldown_seconds = int(getattr(settings, "OTP_COOLDOWN_SECONDS", 60))
    last = OTP.objects.filter(phone=phone).order_by("-id").first()
    if last:
        remaining_cooldown = cooldown_seconds - (now - last.created_at).total_seconds()
        if remaining_cooldown > 0:
            return throttled_response(
                "يرجى الانتظار قبل إعادة إرسال الرمز",
                remaining_cooldown,
                code="otp_cooldown",
            )

    # Per-phone hourly limit
    phone_hourly_limit = int(getattr(settings, "OTP_PHONE_HOURLY_LIMIT", 0) or 0)
    if phone_hourly_limit > 0:
        since = now - timedelta(hours=1)
        phone_hourly_qs = OTP.objects.filter(phone=phone, created_at__gte=since).order_by("created_at")
        cnt = phone_hourly_qs.count()
        if cnt >= phone_hourly_limit:
            oldest = phone_hourly_qs.first()
            retry_after = (
                (oldest.created_at + timedelta(hours=1) - now).total_seconds() if oldest else 3600
            )
            return throttled_response(
                "تم تجاوز حد إرسال الرموز لهذا الرقم مؤقتًا",
                retry_after,
                code="otp_phone_hourly_limit",
            )

    # Per-phone daily limit
    phone_daily_limit = int(getattr(settings, "OTP_PHONE_DAILY_LIMIT", 0) or 0)
    if phone_daily_limit > 0:
        local_now = timezone.localtime(now)
        today_start = local_now.replace(hour=0, minute=0, second=0, microsecond=0)
        cnt = OTP.objects.filter(phone=phone, created_at__gte=today_start).count()
        if cnt >= phone_daily_limit:
            next_reset = today_start + timedelta(days=1)
            return throttled_response(
                "تم تجاوز الحد اليومي لإرسال الرموز لهذا الرقم",
                (next_reset - local_now).total_seconds(),
                code="otp_phone_daily_limit",
            )

    # Per-IP hourly limit (best-effort)
    ip_hourly_limit = int(getattr(settings, "OTP_IP_HOURLY_LIMIT", 0) or 0)
    if ip_hourly_limit > 0 and client_ip:
        since = now - timedelta(hours=1)
        ip_hourly_qs = OTP.objects.filter(ip_address=client_ip, created_at__gte=since).order_by("created_at")
        cnt = ip_hourly_qs.count()
        if cnt >= ip_hourly_limit:
            oldest = ip_hourly_qs.first()
            retry_after = (
                (oldest.created_at + timedelta(hours=1) - now).total_seconds() if oldest else 3600
            )
            return throttled_response(
                "تم تجاوز حد إرسال الرموز من هذا الجهاز/الشبكة مؤقتًا",
                retry_after,
                code="otp_ip_hourly_limit",
            )

    # Generate a new code.
    test_code = (getattr(settings, "OTP_TEST_CODE", "") or "").strip()
    dev_code = otp_dev_test_code()
    if dev_code:
        code = dev_code
    elif test_code and _otp_test_authorized(request):
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

    payload = {"ok": True}
    payload.update(build_cooldown_payload(cooldown_seconds))
    if otp_dev_bypass_enabled():
        payload["dev_mode"] = True
        payload["dev_accept_any_4_digits"] = accept_any_otp_code()
        if dev_code:
            payload["dev_code"] = dev_code
    elif bool(getattr(settings, "DEBUG", False)):
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

        payload, created, user = _issue_tokens_for_phone(phone)
        if payload is None:
            return Response({"detail": "الحساب غير نشط"}, status=status.HTTP_400_BAD_REQUEST)
        _start_web_session(request, user)

        # Best-effort cleanup: mark last OTP as used.
        otp = OTP.objects.filter(phone=phone, is_used=False).order_by("-id").first()
        if otp:
            otp.is_used = True
            otp.save(update_fields=["is_used"])

        return Response(payload, status=status.HTTP_200_OK)

    # App QA bypass (no headers): accept ANY 4-digit code.
    # - Must be explicitly enabled via OTP_APP_BYPASS=1
    # - Applies to any phone number while enabled
    # - Requires an existing OTP record to keep send limits/cooldowns meaningful
    app_bypass = _otp_app_bypass_allowed(phone)

    if app_bypass:
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

        payload, created, user = _issue_tokens_for_phone(phone)
        if payload is None:
            return Response({"detail": "الحساب غير نشط"}, status=status.HTTP_400_BAD_REQUEST)
        _start_web_session(request, user)

        return Response(payload, status=status.HTTP_200_OK)

    if matches_dev_test_code(code):
        if not (len(code) == 4 and code.isdigit()):
            return Response({"detail": "الكود يجب أن يكون 4 أرقام"}, status=status.HTTP_400_BAD_REQUEST)

        otp = OTP.objects.filter(phone=phone, is_used=False).order_by("-id").first()
        if otp:
            otp.is_used = True
            otp.save(update_fields=["is_used"])

        payload, created, user = _issue_tokens_for_phone(phone)
        if payload is None:
            return Response({"detail": "الحساب غير نشط"}, status=status.HTTP_400_BAD_REQUEST)
        _start_web_session(request, user)

        return Response(payload, status=status.HTTP_200_OK)

    if accept_any_otp_code():
        # Validate format only
        if not (len(code) == 4 and code.isdigit()):
            return Response({"detail": "الكود يجب أن يكون 4 أرقام"}, status=status.HTTP_400_BAD_REQUEST)

        # Skip DB check, mark LAST OTP as used if exists (for cleanup)
        otp = OTP.objects.filter(phone=phone, is_used=False).order_by("-id").first()
        if otp:
            otp.is_used = True
            otp.save(update_fields=["is_used"])

        payload, created, user = _issue_tokens_for_phone(phone)
        if payload is None:
            return Response({"detail": "الحساب غير نشط"}, status=status.HTTP_400_BAD_REQUEST)
        _start_web_session(request, user)

        return Response(payload, status=status.HTTP_200_OK)

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

    payload, created, user = _issue_tokens_for_phone(phone)
    if payload is None:
        return Response({"detail": "الحساب غير نشط"}, status=status.HTTP_400_BAD_REQUEST)
    _start_web_session(request, user)

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


# ────────────────────────────────────────
# 🔐 Biometric (Face ID / Fingerprint) endpoints
# ────────────────────────────────────────

@api_view(["POST"])
@permission_classes([IsAuthenticated])
def biometric_enroll(request):
    """Authenticated user enrolls biometric → receives a device_token."""
    user = request.user
    phone = _normalize_phone_local05(user.phone or "")
    if not phone:
        return Response(
            {"detail": "لا يوجد رقم جوال مرتبط بالحساب"},
            status=status.HTTP_400_BAD_REQUEST,
        )

    # Deactivate any old tokens for this user
    BiometricToken.objects.filter(user=user).update(is_active=False)

    # Generate a secure random token
    device_token = secrets.token_urlsafe(64)
    BiometricToken.objects.create(
        user=user,
        phone=phone,
        token=device_token,
    )

    return Response({"ok": True, "device_token": device_token})


@api_view(["POST"])
@permission_classes([AllowAny])
@throttle_classes([ScopedRateThrottle])
def biometric_login(request):
    """Login via biometric: phone + device_token → JWT tokens (no OTP needed)."""
    s = BiometricLoginSerializer(data=request.data)
    s.is_valid(raise_exception=True)

    phone = _normalize_phone_local05(s.validated_data["phone"])
    device_token = s.validated_data["device_token"]

    bt = BiometricToken.objects.filter(
        phone=phone, token=device_token, is_active=True
    ).select_related("user").first()

    if not bt or not bt.user.is_active:
        return Response(
            {"detail": "رمز المصادقة البيومترية غير صالح أو منتهي"},
            status=status.HTTP_401_UNAUTHORIZED,
        )

    user = bt.user
    _start_web_session(request, user)
    refresh = RefreshToken.for_user(user)
    payload = {
        "ok": True,
        "user_id": user.id,
        "role_state": user.role_state,
        "profile_status": _resolve_profile_status(user),
        "role_label": _resolve_role_label(user),
        "is_new_user": False,
        "needs_completion": user.role_state in (UserRole.VISITOR, UserRole.PHONE_ONLY),
        "refresh": str(refresh),
        "access": str(refresh.access_token),
    }

    try:
        from apps.audit.services import log_action
        from apps.audit.models import AuditAction
        log_action(
            actor=user,
            action=AuditAction.LOGIN_OTP_VERIFIED,
            reference_type="user",
            reference_id=str(user.id),
            request=request,
        )
    except Exception:
        pass

    return Response(payload, status=status.HTTP_200_OK)


biometric_login.throttle_scope = "otp"


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def biometric_revoke(request):
    """Revoke all biometric tokens for the current user."""
    count = BiometricToken.objects.filter(user=request.user, is_active=True).update(is_active=False)
    return Response({"ok": True, "revoked": count})


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
    update_session_auth_hash(request, user)
    return Response(
        {
            "ok": True,
            "role_state": user.role_state,
            "profile_status": _resolve_profile_status(user),
            "role_label": _resolve_role_label(user),
        },
        status=status.HTTP_200_OK,
    )

@api_view(["POST"])
@permission_classes([IsAuthenticated])
def skip_completion(request):
    """Allow a phone-only/visitor account to continue as a partial client."""
    user: User = request.user

    if user.role_state not in (
        UserRole.VISITOR,
        UserRole.PHONE_ONLY,
        UserRole.CLIENT,
        UserRole.PROVIDER,
        UserRole.STAFF,
    ):
        return Response({"detail": "حالة الحساب غير معروفة"}, status=status.HTTP_400_BAD_REQUEST)

    update_fields: list[str] = []
    if user.role_state in (UserRole.VISITOR, UserRole.PHONE_ONLY):
        user.role_state = UserRole.CLIENT
        update_fields.append("role_state")

    current_username = (user.username or "").strip()
    normalized_phone = _normalize_phone_local05(user.phone or "")
    phone_username = normalized_phone.lstrip("@")
    if not current_username and phone_username:
        user.username = phone_username
        update_fields.append("username")

    if update_fields:
        user.save(update_fields=update_fields)

    return Response(
        {
            "ok": True,
            "role_state": user.role_state,
            "needs_completion": False,
            "profile_status": _resolve_profile_status(user),
            "role_label": _resolve_role_label(user),
        },
        status=status.HTTP_200_OK,
    )


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
    auth_logout(request)
    return Response({"ok": True}, status=status.HTTP_200_OK)


@api_view(["DELETE"])
@permission_classes([IsAuthenticated])
def delete_account_view(request):
    """Permanently delete the authenticated user account."""
    user: User = request.user
    auth_logout(request)
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


# ─── Phone change (OTP-verified) ────────────────────────────────────────────
# Changing the auth phone (User.phone) requires proving ownership of the NEW
# number via OTP before any database write occurs.  Direct mutation via
# PATCH /api/accounts/me/ is intentionally blocked.

@api_view(["POST"])
@permission_classes([IsAuthenticated])
@throttle_classes([ScopedRateThrottle])
def request_phone_change_view(request):
    """Step 1 – send an OTP to the new phone number the user wants to adopt."""
    new_phone_raw = (request.data.get("phone") or "").strip()
    if not new_phone_raw:
        return Response({"phone": ["رقم الجوال مطلوب"]}, status=status.HTTP_400_BAD_REQUEST)

    new_phone = _normalize_phone_local05(new_phone_raw)
    if not new_phone or len(_keep_digits(new_phone)) < 9:
        return Response({"phone": ["صيغة رقم الجوال غير صحيحة، يجب أن تكون 05XXXXXXXX"]}, status=status.HTTP_400_BAD_REQUEST)

    if new_phone == _normalize_phone_local05(request.user.phone or ""):
        return Response({"phone": ["هذا هو رقم جوالك الحالي"]}, status=status.HTTP_400_BAD_REQUEST)

    if User.objects.filter(phone__in=_phone_candidates(new_phone)).exclude(pk=request.user.pk).exists():
        return Response({"phone": ["رقم الجوال مستخدم مسبقاً"]}, status=status.HTTP_400_BAD_REQUEST)

    now = timezone.now()
    cooldown_seconds = int(getattr(settings, "OTP_COOLDOWN_SECONDS", 60))
    last = OTP.objects.filter(phone=new_phone).order_by("-id").first()
    if last:
        remaining = cooldown_seconds - (now - last.created_at).total_seconds()
        if remaining > 0:
            return throttled_response("يرجى الانتظار قبل إعادة إرسال الرمز", remaining, code="otp_cooldown")

    dev_code = otp_dev_test_code()
    test_code = (getattr(settings, "OTP_TEST_CODE", "") or "").strip()
    if dev_code:
        code = dev_code
    elif test_code and _otp_test_authorized(request):
        code = test_code
    else:
        code = generate_otp_code()

    OTP.objects.create(
        phone=new_phone,
        ip_address=_client_ip(request),
        code=code,
        expires_at=otp_expiry(5),
    )

    payload = {"ok": True}
    payload.update(build_cooldown_payload(cooldown_seconds))
    if otp_dev_bypass_enabled():
        payload["dev_mode"] = True
        payload["dev_accept_any_4_digits"] = accept_any_otp_code()
        if dev_code:
            payload["dev_code"] = dev_code
    elif bool(getattr(settings, "DEBUG", False)):
        payload["dev_code"] = code
    elif _otp_test_authorized(request):
        payload["dev_code"] = code
    return Response(payload, status=status.HTTP_200_OK)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def confirm_phone_change_view(request):
    """Step 2 – verify OTP for new phone then update User.phone."""
    new_phone_raw = (request.data.get("phone") or "").strip()
    code = (request.data.get("code") or "").strip()

    if not new_phone_raw:
        return Response({"phone": ["رقم الجوال مطلوب"]}, status=status.HTTP_400_BAD_REQUEST)
    if not code:
        return Response({"code": ["رمز التحقق مطلوب"]}, status=status.HTTP_400_BAD_REQUEST)

    new_phone = _normalize_phone_local05(new_phone_raw)

    if User.objects.filter(phone__in=_phone_candidates(new_phone)).exclude(pk=request.user.pk).exists():
        return Response({"phone": ["رقم الجوال مستخدم مسبقاً"]}, status=status.HTTP_400_BAD_REQUEST)

    # Dev/test bypass: accept any 4-digit code when OTP_APP_BYPASS is enabled.
    if _otp_app_bypass_allowed(new_phone):
        if not (len(code) == 4 and code.isdigit()):
            return Response({"code": ["الكود يجب أن يكون 4 أرقام"]}, status=status.HTTP_400_BAD_REQUEST)
        otp = OTP.objects.filter(phone=new_phone, is_used=False).order_by("-id").first()
        if not otp or otp.expires_at < timezone.now():
            return Response({"code": ["أعد طلب رمز جديد"]}, status=status.HTTP_400_BAD_REQUEST)
        otp.is_used = True
        otp.save(update_fields=["is_used"])
        try:
            request.user.phone = new_phone
            request.user.save(update_fields=["phone"])
        except IntegrityError:
            return Response({"phone": ["رقم الجوال مستخدم مسبقاً"]}, status=status.HTTP_400_BAD_REQUEST)
        return Response({"ok": True, "phone": new_phone}, status=status.HTTP_200_OK)

    if matches_dev_test_code(code) or accept_any_otp_code():
        if not (len(code) == 4 and code.isdigit()):
            return Response({"code": ["الكود يجب أن يكون 4 أرقام"]}, status=status.HTTP_400_BAD_REQUEST)
        otp = OTP.objects.filter(phone=new_phone, is_used=False).order_by("-id").first()
        if otp:
            otp.is_used = True
            otp.save(update_fields=["is_used"])
        try:
            request.user.phone = new_phone
            request.user.save(update_fields=["phone"])
        except IntegrityError:
            return Response({"phone": ["رقم الجوال مستخدم مسبقاً"]}, status=status.HTTP_400_BAD_REQUEST)
        return Response({"ok": True, "phone": new_phone}, status=status.HTTP_200_OK)

    otp = OTP.objects.filter(phone=new_phone, is_used=False).order_by("-id").first()
    if not otp:
        return Response({"code": ["الكود غير صحيح"]}, status=status.HTTP_400_BAD_REQUEST)

    if otp.expires_at < timezone.now():
        return Response({"code": ["انتهت صلاحية الكود"]}, status=status.HTTP_400_BAD_REQUEST)

    max_attempts = int(getattr(settings, "OTP_MAX_ATTEMPTS", 5))
    if otp.attempts >= max_attempts:
        otp.is_used = True
        otp.save(update_fields=["is_used"])
        return Response({"code": ["تم تجاوز عدد المحاولات، أعد طلب رمز جديد"]}, status=status.HTTP_429_TOO_MANY_REQUESTS)

    if otp.code != code:
        otp.attempts += 1
        if otp.attempts >= max_attempts:
            otp.is_used = True
            otp.save(update_fields=["attempts", "is_used"])
            return Response({"code": ["تم تجاوز عدد المحاولات، أعد طلب رمز جديد"]}, status=status.HTTP_429_TOO_MANY_REQUESTS)
        otp.save(update_fields=["attempts"])
        return Response({"code": ["الكود غير صحيح"]}, status=status.HTTP_400_BAD_REQUEST)

    otp.is_used = True
    otp.save(update_fields=["is_used"])

    try:
        request.user.phone = new_phone
        request.user.save(update_fields=["phone"])
    except IntegrityError:
        return Response({"phone": ["رقم الجوال مستخدم مسبقاً"]}, status=status.HTTP_400_BAD_REQUEST)

    return Response({"ok": True, "phone": new_phone}, status=status.HTTP_200_OK)


request_phone_change_view.throttle_scope = "otp"
