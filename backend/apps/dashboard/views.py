from __future__ import annotations

import csv
import re
from decimal import Decimal, InvalidOperation
from datetime import date, datetime, time, timedelta
from functools import wraps
from io import StringIO
from uuid import uuid4

from django.conf import settings
from django.contrib import messages
from django.contrib.auth import authenticate, get_user_model, login, logout
from django.core.cache import cache
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.db.models import Count, Prefetch, Q, Sum
from django.http import Http404, HttpResponse, HttpResponseForbidden, JsonResponse, QueryDict
from django.shortcuts import get_object_or_404, redirect, render
from django.urls import reverse
from django.utils import timezone
from django.views.decorators.http import require_POST

from apps.accounts.models import OTP, UserRole
from apps.accounts.otp import accept_any_otp_code, create_otp, verify_otp
from apps.analytics.models import AnalyticsEvent
from apps.analytics.services import extras_kpis, kpis_summary, promo_kpis, provider_kpis, subscription_kpis
from apps.audit.models import AuditAction
from apps.audit.services import log_action
from apps.backoffice.bootstrap import ensure_backoffice_access_catalog
from apps.backoffice.models import AccessLevel, AccessPermission, Dashboard, UserAccessProfile
from apps.backoffice.policies import (
    ContentHideDeletePolicy,
    ContentManagePolicy,
    ReviewModerationPolicy,
)
from apps.marketplace.models import RequestStatus, ServiceRequest
from apps.messaging.models import Message, Thread
from apps.moderation.integrations import record_content_action_case, record_support_target_delete_case, sync_review_case
from apps.notifications.models import DeviceToken
from apps.providers.location_formatter import format_city_display
from apps.providers.models import (
    Category,
    ProviderCategory,
    ProviderFollow,
    ProviderLike,
    ProviderProfile,
    ProviderPortfolioLike,
    ProviderPortfolioItem,
    ProviderPortfolioSave,
    ProviderService,
    ProviderSpotlightLike,
    ProviderSpotlightItem,
    ProviderSpotlightSave,
)
from apps.reviews.models import Review, ReviewModerationStatus
from apps.reviews.services import sync_review_to_unified
from apps.billing.models import Invoice, InvoiceLineItem, InvoiceStatus, PaymentAttempt, PaymentAttemptStatus
from apps.subscriptions.models import PlanTier, Subscription, SubscriptionPlan, SubscriptionStatus
from apps.subscriptions.models import SubscriptionInquiryProfile
from apps.subscriptions.services import (
    delete_subscription_account_for_dashboard,
    activate_subscription_after_payment,
    apply_effective_payment,
    get_effective_active_subscriptions_map,
    start_subscription_renewal_checkout,
    normalize_subscription_duration_count,
    plan_to_db_tier,
    plan_to_tier,
)
from apps.unified_requests.models import UnifiedRequest, UnifiedRequestPriority, UnifiedRequestStatus, UnifiedRequestType
from apps.unified_requests.services import upsert_unified_request
from apps.unified_requests.workflows import canonical_status_for_workflow, is_valid_transition
from apps.support.models import (
    SupportAttachment,
    SupportComment,
    SupportPriority,
    SupportTeam,
    SupportTicket,
    SupportTicketEntrypoint,
    SupportTicketStatus,
    SupportTicketType,
)
from apps.support.services import assign_ticket, change_ticket_status
from apps.content.models import ContentBlockKey, LegalDocumentType, SiteContentBlock, SiteLegalDocument, SiteLinks
from apps.content.services import sanitize_multiline_text, sanitize_text
from apps.excellence.models import ExcellenceBadgeCandidate, ExcellenceBadgeType
from apps.promo.models import (
    PromoAdType,
    PromoAsset,
    PromoAssetType,
    PromoInquiryProfile,
    PromoOpsStatus,
    PromoPosition,
    PromoPricingRule,
    PromoRequest,
    PromoRequestItem,
    PromoRequestStatus,
    PromoSearchScope,
    PromoServiceType,
)
from apps.verification.models import (
    VerifiedBadge,
    VerificationBadgeType,
    VerificationDocument,
    VerificationInquiryProfile,
    VerificationRequirement,
    VerificationRequirementAttachment,
    VerificationRequest,
    VerificationStatus,
)
from apps.verification.serializers import VerificationRequestDetailSerializer
from apps.extras.models import ExtraPurchase, ExtraPurchaseStatus
from apps.extras.option_catalog import UNAVAILABLE_CLIENT_OPTIONS, UNAVAILABLE_FINANCE_OPTIONS
from apps.extras_portal.models import ExtrasPortalSubscription, ExtrasPortalSubscriptionStatus
from apps.extras.services import (
    activate_bundle_portal_subscription_for_request,
    create_manual_extras_invoice,
    extras_bundle_detail_sections_for_request,
    extras_bundle_invoice_for_request,
    extras_bundle_payment_access_url,
    extras_bundle_payload_for_request,
    extras_bundle_target_provider_user,
    notify_bundle_completed,
    notify_bundle_payment_requested,
)
from apps.promo.services import (
    calc_promo_request_quote,
    expire_due_promos,
    ensure_default_pricing_rules,
    set_promo_ops_status,
    _sync_promo_to_unified,
)
from apps.verification.services import (
    _sync_verification_to_unified,
    create_renewal_request_from_verified_badge,
    deactivate_verified_badge,
    decide_requirement,
    finalize_request_and_create_invoice,
    mark_request_in_review,
    verification_invoice_preview_for_request,
)
from apps.excellence.selectors import (
    FEATURED_SERVICE_BADGE_CODE,
    HIGH_ACHIEVEMENT_BADGE_CODE,
    TOP_100_CLUB_BADGE_CODE,
    current_review_window as excellence_current_review_window,
)
from apps.excellence.services import sync_badge_type_catalog
from apps.features.support import support_priority
from apps.features.upload_limits import user_max_upload_mb
from apps.uploads.media_optimizer import optimize_upload_for_storage
from apps.uploads.validators import validate_user_file_size

from .access import (
    active_access_profile_for_user,
    dashboard_allowed,
    dashboard_assignee_user,
    dashboard_portal_eligible,
    normalize_dashboard_code,
    sync_dashboard_user_access,
)
from .auth import (
    SESSION_LOGIN_USER_ID_KEY,
    SESSION_NEXT_URL_KEY,
    SESSION_OTP_VERIFIED_KEY,
    clear_dashboard_auth_session,
    dashboard_staff_required,
)
from .exports import pdf_response, xlsx_response
from .forms import (
    ACCESS_MANAGED_DASHBOARD_CODES,
    AccessProfileForm,
    ContentDesignUploadForm,
    ContentFirstTimeForm,
    ContentFirstTimeMediaForm,
    ContentReviewActionForm,
    ContentSettingsLegalForm,
    ContentSettingsLinksForm,
    DashboardLoginForm,
    DashboardOTPForm,
    ExtrasInquiryActionForm,
    ExtrasRequestActionForm,
    PromoInquiryActionForm,
    PromoModuleItemForm,
    PromoRequestActionForm,
    SubscriptionInquiryActionForm,
    SubscriptionRequestActionForm,
    SupportDashboardActionForm,
    VerificationInquiryActionForm,
    VerificationRequestActionForm,
)
from .security import is_safe_redirect_url


PROMO_REQUEST_SUBMIT_TOKENS_SESSION_KEY = "dashboard_promo_request_submit_tokens"
PROMO_INQUIRY_SUBMIT_TOKENS_SESSION_KEY = "dashboard_promo_inquiry_submit_tokens"
PROMO_MODULE_SUBMIT_TOKENS_SESSION_KEY = "dashboard_promo_module_submit_tokens"
PROMO_MODULE_OPS_SUBMIT_TOKENS_SESSION_KEY = "dashboard_promo_module_ops_submit_tokens"
PROMO_PRICING_SUBMIT_TOKENS_SESSION_KEY = "dashboard_promo_pricing_submit_tokens"
SINGLE_USE_SUBMIT_TOKEN_CACHE_TIMEOUT = 15 * 60
OTP_RESEND_COOLDOWN_SECONDS = 60
EXTRAS_BUNDLE_DRAFT_SESSION_KEY = "dashboard_extras_bundle_draft"


def _want_export(request, expected: str) -> bool:
    token = (request.GET.get("export") or request.GET.get("format") or "").strip().lower()
    return token == expected


def _want_csv(request) -> bool:
    return _want_export(request, "csv")


def _want_xlsx(request) -> bool:
    return _want_export(request, "xlsx")


def _want_pdf(request) -> bool:
    return _want_export(request, "pdf")


def _issue_single_use_submit_token(request, session_key: str, *, limit: int = 20) -> str:
    token = uuid4().hex
    existing_tokens = request.session.get(session_key) or []
    sanitized_tokens = [str(item).strip() for item in existing_tokens if str(item).strip()]
    keep_count = max(0, int(limit or 20) - 1)
    if keep_count:
        sanitized_tokens = sanitized_tokens[-keep_count:]
    else:
        sanitized_tokens = []
    sanitized_tokens.append(token)
    request.session[session_key] = sanitized_tokens
    return token


def _single_use_submit_token_cache_key(session_key: str, token: str) -> str:
    return f"dashboard:single-submit:{session_key}:{token}"


def _consume_single_use_submit_token(request, session_key: str, token: str) -> bool:
    submitted_token = str(token or "").strip()
    if not submitted_token:
        return False

    existing_tokens = request.session.get(session_key) or []
    sanitized_tokens = [str(item).strip() for item in existing_tokens if str(item).strip()]
    if submitted_token not in sanitized_tokens:
        return False

    try:
        token_claimed = cache.add(
            _single_use_submit_token_cache_key(session_key, submitted_token),
            "1",
            timeout=SINGLE_USE_SUBMIT_TOKEN_CACHE_TIMEOUT,
        )
    except Exception:
        token_claimed = True

    if not token_claimed:
        sanitized_tokens.remove(submitted_token)
        request.session[session_key] = sanitized_tokens
        return False

    sanitized_tokens.remove(submitted_token)
    request.session[session_key] = sanitized_tokens
    return True


def _validate_and_optimize_dashboard_attachment(attachment, *, user):
    if attachment is None:
        return attachment
    validate_user_file_size(attachment, user_max_upload_mb(user))
    return optimize_upload_for_storage(attachment)


def _otp_resend_cache_key(user_id: int) -> str:
    return f"dashboard:otp:resend:cooldown:{int(user_id)}"


def _otp_resend_remaining_seconds(user_id: int | None) -> int:
    if not user_id:
        return 0
    cache_key = _otp_resend_cache_key(user_id)
    until_ts = cache.get(cache_key)
    if until_ts is None:
        return 0
    now_ts = int(timezone.now().timestamp())
    remaining = max(0, int(until_ts) - now_ts)
    if remaining <= 0:
        cache.delete(cache_key)
        return 0
    return remaining


def _activate_otp_resend_cooldown(user_id: int, seconds: int = OTP_RESEND_COOLDOWN_SECONDS) -> int:
    cooldown = max(1, int(seconds or OTP_RESEND_COOLDOWN_SECONDS))
    until_ts = int(timezone.now().timestamp()) + cooldown
    cache.set(_otp_resend_cache_key(user_id), until_ts, timeout=cooldown)
    return cooldown


def _promo_module_redirect_with_state(request, module_key: str, *, request_id: int | None = None):
    query_params = request.GET.copy()
    if request_id is not None:
        query_params["request_id"] = str(request_id)
    redirect_url = reverse("dashboard:promo_module", kwargs={"module_key": module_key})
    encoded_query = query_params.urlencode()
    if encoded_query:
        redirect_url = f"{redirect_url}?{encoded_query}"
    return redirect(redirect_url)


def _csv_response(filename: str, headers: list[str], rows: list[list]) -> HttpResponse:
    buffer = StringIO()
    writer = csv.writer(buffer)
    writer.writerow(headers)
    writer.writerows(rows)
    response = HttpResponse(buffer.getvalue(), content_type="text/csv; charset=utf-8")
    response["Content-Disposition"] = f'attachment; filename="{filename}"'
    return response


def _parse_datetime_local(raw_value):
    value = (raw_value or "").strip()
    if not value:
        return None
    candidates = ("%Y-%m-%dT%H:%M", "%Y-%m-%d %H:%M", "%Y-%m-%d")
    for fmt in candidates:
        try:
            parsed = datetime.strptime(value, fmt)
            if fmt == "%Y-%m-%d":
                parsed = datetime.combine(parsed.date(), time(0, 0))
            return timezone.make_aware(parsed, timezone.get_current_timezone())
        except Exception:
            continue
    return None


_ARABIC_DECIMAL_TRANSLATION = str.maketrans("٠١٢٣٤٥٦٧٨٩", "0123456789")


def _normalize_decimal_text(raw_value: str) -> str:
    value = str(raw_value or "").strip()
    if not value:
        return ""
    value = value.translate(_ARABIC_DECIMAL_TRANSLATION)
    value = value.replace("٫", ".").replace("٬", "").replace(",", "")
    value = value.replace(" ", "").replace("\u00A0", "")
    return value


def _dashboard_allowed(user, dashboard_code: str, *, write: bool = False) -> bool:
    return dashboard_allowed(user, dashboard_code, write=write)


def require_dashboard_access(dashboard_code: str, *, write: bool = False):
    normalized_code = normalize_dashboard_code(dashboard_code)

    def decorator(view_func):
        @wraps(view_func)
        def _wrapped(request, *args, **kwargs):
            if not dashboard_allowed(request.user, normalized_code, write=write):
                return HttpResponseForbidden("غير مصرح للوصول.")
            return view_func(request, *args, **kwargs)

        return _wrapped

    return decorator


def _parse_date(raw: str, *, default: date) -> date:
    value = (raw or "").strip()
    if not value:
        return default
    try:
        return date.fromisoformat(value)
    except ValueError:
        return default


def _date_range_from_request(request):
    today = timezone.localdate()
    default_start = today - timedelta(days=30)
    start_date = _parse_date(request.GET.get("start"), default=default_start)
    end_date = _parse_date(request.GET.get("end"), default=today)
    if end_date < start_date:
        start_date, end_date = end_date, start_date
    return start_date, end_date


def _to_aware_window(start_date: date, end_date: date):
    tz = timezone.get_current_timezone()
    start_dt = timezone.make_aware(datetime.combine(start_date, time.min), tz)
    end_dt = timezone.make_aware(datetime.combine(end_date, time.max), tz)
    return start_dt, end_dt


def _dashboard_codes_to_numbers(codes: list[str]) -> str:
    mapping = {
        "admin_control": 1,
        "support": 2,
        "content": 3,
        "promo": 4,
        "verify": 5,
        "subs": 6,
        "extras": 7,
        "client_extras": 8,
    }
    numbers = sorted(mapping[code] for code in codes if code in mapping)
    return ",".join(str(n) for n in numbers)


def _get_user_by_identifier(identifier: str):
    User = get_user_model()
    by_phone = User.objects.filter(phone=identifier).first()
    if by_phone:
        return by_phone
    return User.objects.filter(username=identifier).first()


def _authenticate_dashboard_user(request, identifier: str, password: str):
    user = authenticate(request, username=identifier, password=password)
    if user is None:
        by_username = get_user_model().objects.filter(username=identifier).first()
        if by_username and by_username.phone:
            user = authenticate(request, username=by_username.phone, password=password)
    if user is None:
        return None
    if not getattr(user, "is_active", False):
        return None
    if not (getattr(user, "is_staff", False) or getattr(user, "is_superuser", False)):
        return None
    if not (getattr(user, "is_superuser", False) or dashboard_portal_eligible(user)):
        return None
    return user


def login_view(request):
    if getattr(request.user, "is_authenticated", False) and bool(request.session.get(SESSION_OTP_VERIFIED_KEY)):
        return redirect("dashboard:index")

    form = DashboardLoginForm(request.POST or None)
    if request.method == "POST" and form.is_valid():
        username = (form.cleaned_data.get("username") or "").strip()
        password = form.cleaned_data.get("password") or ""
        user = _authenticate_dashboard_user(request, username, password)

        if user is None:
            messages.error(request, "بيانات الدخول غير صحيحة أو لا تملك صلاحية تشغيل.")
            return render(request, "dashboard/auth/login.html", {"form": form})

        request.session[SESSION_LOGIN_USER_ID_KEY] = user.id

        next_url = (request.GET.get("next") or request.session.get(SESSION_NEXT_URL_KEY) or "").strip()
        if next_url and is_safe_redirect_url(next_url):
            request.session[SESSION_NEXT_URL_KEY] = next_url

        if not accept_any_otp_code():
            create_otp(user.phone or "", request)
            log_action(
                actor=user,
                action=AuditAction.LOGIN_OTP_SENT,
                reference_type="dashboard.auth",
                reference_id=str(user.id),
                request=request,
                extra={"channel": "dashboard"},
            )

        return redirect("dashboard:otp")

    return render(request, "dashboard/auth/login.html", {"form": form})


def otp_view(request):
    if getattr(request.user, "is_authenticated", False) and bool(request.session.get(SESSION_OTP_VERIFIED_KEY)):
        return redirect("dashboard:index")

    user_id = request.session.get(SESSION_LOGIN_USER_ID_KEY)
    pending_user = get_user_model().objects.filter(id=user_id, is_active=True).first() if user_id else None
    if pending_user is None:
        messages.warning(request, "انتهت جلسة الدخول، يرجى المحاولة مجددًا.")
        return redirect("dashboard:login")

    form = DashboardOTPForm(request.POST or None)
    bypass_enabled = accept_any_otp_code()

    if request.method == "POST" and form.is_valid():
        code = form.cleaned_data["code"]
        bypass_used = bool(bypass_enabled and code.isdigit() and len(code) >= 4)
        is_valid = bypass_used
        if not is_valid:
            is_valid = verify_otp(pending_user.phone or "", code)
        if not is_valid:
            messages.error(request, "رمز التحقق غير صحيح أو منتهي.")
            return render(
                request,
                "dashboard/auth/otp.html",
                {
                    "form": form,
                    "dev_accept_any": bypass_enabled,
                    "phone": pending_user.phone,
                    "otp_resend_cooldown_seconds": _otp_resend_remaining_seconds(pending_user.id),
                    "otp_resend_default_cooldown_seconds": OTP_RESEND_COOLDOWN_SECONDS,
                },
            )

        login(request, pending_user, backend="django.contrib.auth.backends.ModelBackend")
        request.session[SESSION_OTP_VERIFIED_KEY] = True
        request.session.pop(SESSION_LOGIN_USER_ID_KEY, None)
        log_action(
            actor=pending_user,
            action=AuditAction.LOGIN_OTP_VERIFIED,
            reference_type="dashboard.auth",
            reference_id=str(pending_user.id),
            request=request,
            extra={"channel": "dashboard", "bypass_used": bool(bypass_used)},
        )

        next_url = (request.session.pop(SESSION_NEXT_URL_KEY, "") or "").strip()
        if is_safe_redirect_url(next_url):
            return redirect(next_url)
        return redirect("dashboard:index")

    return render(
        request,
        "dashboard/auth/otp.html",
        {
            "form": form,
            "dev_accept_any": bypass_enabled,
            "phone": pending_user.phone,
            "otp_resend_cooldown_seconds": _otp_resend_remaining_seconds(pending_user.id),
            "otp_resend_default_cooldown_seconds": OTP_RESEND_COOLDOWN_SECONDS,
        },
    )


def logout_view(request):
    clear_dashboard_auth_session(request)
    logout(request)
    return redirect("dashboard:login")


@dashboard_staff_required
def dashboard_index(request):
    if dashboard_allowed(request.user, "admin_control"):
        return redirect("dashboard:admin_control_home")
    if dashboard_allowed(request.user, "support"):
        return redirect("dashboard:support_dashboard")
    if dashboard_allowed(request.user, "content"):
        return redirect("dashboard:content_dashboard_home")
    if dashboard_allowed(request.user, "promo"):
        return redirect("dashboard:promo_dashboard")
    if dashboard_allowed(request.user, "verify"):
        return redirect("dashboard:verification_dashboard")
    if dashboard_allowed(request.user, "subs"):
        return redirect("dashboard:subscription_dashboard")
    if dashboard_allowed(request.user, "extras"):
        return redirect("dashboard:extras_dashboard")
    if dashboard_allowed(request.user, "analytics"):
        return redirect("dashboard:analytics_insights")
    return HttpResponseForbidden("لا توجد لوحة متاحة لهذا الحساب.")


def _serialize_access_rows():
    rows = []
    profiles = (
        UserAccessProfile.objects.select_related("user")
        .prefetch_related("allowed_dashboards", "granted_permissions")
        .order_by("user__username", "user__phone", "id")
    )
    for profile in profiles:
        user = profile.user
        allowed_codes = list(profile.allowed_dashboards.values_list("code", flat=True))
        if profile.level in {AccessLevel.ADMIN, AccessLevel.QA}:
            dashboard_text = "All"
        else:
            dashboard_text = _dashboard_codes_to_numbers(allowed_codes) or "-"
        if profile.level in {AccessLevel.ADMIN, AccessLevel.POWER}:
            permissions_text = "All"
        else:
            permission_codes = list(profile.granted_permissions.values_list("code", flat=True))
            permissions_text = ", ".join(permission_codes) if permission_codes else "-"
        rows.append(
            {
                "profile_id": profile.id,
                "username": user.username or user.phone or f"user-{user.id}",
                "level": profile.get_level_display(),
                "level_code": profile.level,
                "dashboards_text": dashboard_text,
                "permissions_text": permissions_text,
                "mobile": user.phone or "",
                "password_mask": "***********",
                "password_expiration_date": profile.expires_at.date().isoformat() if profile.expires_at else "",
                "account_revoke_date": profile.revoked_at.date().isoformat() if profile.revoked_at else "",
                "revoked": bool(profile.revoked_at),
            }
        )
    return rows


def _access_summary(rows: list[dict]) -> dict:
    total = len(rows)
    revoked = sum(1 for row in rows if row.get("revoked"))
    active = total - revoked
    by_level: dict[str, int] = {}
    for row in rows:
        key = row.get("level_code") or "unknown"
        by_level[key] = by_level.get(key, 0) + 1
    return {
        "total": total,
        "active": active,
        "revoked": revoked,
        "by_level": by_level,
    }


def _profile_to_form_initial(profile: UserAccessProfile) -> dict:
    user = profile.user
    return {
        "profile_id": profile.id,
        "username": user.username or "",
        "mobile_number": user.phone or "",
        "level": profile.level,
        "dashboards": list(profile.allowed_dashboards.values_list("code", flat=True)),
        "permissions": list(profile.granted_permissions.values_list("code", flat=True)),
        "password_expiration_date": profile.expires_at.date() if profile.expires_at else None,
        "account_revoke_date": profile.revoked_at.date() if profile.revoked_at else None,
    }


def _to_eod_aware_datetime(value: date | None):
    if not value:
        return None
    return timezone.make_aware(
        datetime.combine(value, time(hour=23, minute=59, second=59)),
        timezone.get_current_timezone(),
    )


def _is_active_admin_profile(profile: UserAccessProfile) -> bool:
    if profile.level != AccessLevel.ADMIN:
        return False
    if profile.revoked_at is not None:
        return False
    if profile.expires_at and profile.expires_at <= timezone.now():
        return False
    return True


def _active_admin_count() -> int:
    now = timezone.now()
    return UserAccessProfile.objects.filter(
        level=AccessLevel.ADMIN,
        revoked_at__isnull=True,
    ).filter(
        Q(expires_at__isnull=True) | Q(expires_at__gt=now),
    ).count()


def _would_still_be_active_admin(level: str, revoked_at, expires_at) -> bool:
    if level != AccessLevel.ADMIN:
        return False
    if revoked_at is not None:
        return False
    if expires_at and expires_at <= timezone.now():
        return False
    return True


def _resolve_granted_permissions(level: str, dashboard_codes: list[str], selected_permission_codes: list[str] | None = None):
    active_permissions = AccessPermission.objects.filter(is_active=True)
    if level == AccessLevel.ADMIN:
        return active_permissions
    if level == AccessLevel.POWER:
        return active_permissions
    if level in {AccessLevel.QA, AccessLevel.CLIENT}:
        return AccessPermission.objects.none()
    allowed_codes = [code for code in dashboard_codes if code]
    if not allowed_codes:
        return AccessPermission.objects.none()
    allowed_permissions = active_permissions.filter(dashboard_code__in=allowed_codes)

    # Granular permissions are no longer selected manually in the add/edit form.
    # For user-level accounts, grant all active permissions within allowed dashboards.
    if level == AccessLevel.USER:
        return allowed_permissions

    normalized_permission_codes = [
        str(code).strip() for code in (selected_permission_codes or []) if str(code).strip()
    ]
    if normalized_permission_codes:
        return allowed_permissions.filter(code__in=normalized_permission_codes)
    return allowed_permissions


def _normalize_dashboards_for_level(level: str, dashboard_codes: list[str]) -> list[str]:
    requested_codes = [str(code).strip() for code in (dashboard_codes or []) if str(code).strip()]
    active_codes = set(
        Dashboard.objects.filter(
            is_active=True,
            code__in=ACCESS_MANAGED_DASHBOARD_CODES,
        ).values_list("code", flat=True)
    )
    ordered_active_codes = [code for code in ACCESS_MANAGED_DASHBOARD_CODES if code in active_codes]

    if level == AccessLevel.CLIENT:
        return ["client_extras"] if "client_extras" in active_codes else []
    if level in {AccessLevel.ADMIN, AccessLevel.QA}:
        return [
            code
            for code in ordered_active_codes
            if code not in UserAccessProfile.CLIENT_ONLY_DASHBOARDS
        ]

    normalized_codes: list[str] = []
    for code in requested_codes:
        if code not in active_codes:
            continue
        if code in normalized_codes:
            continue
        normalized_codes.append(code)
    return normalized_codes


def _upsert_access_profile(request, form: AccessProfileForm):
    profile_id = form.cleaned_data.get("profile_id")
    username = (form.cleaned_data.get("username") or "").strip()
    mobile = (form.cleaned_data.get("mobile_number") or "").strip()
    level = form.cleaned_data.get("level")
    dashboards = _normalize_dashboards_for_level(level, form.cleaned_data.get("dashboards") or [])
    permissions = form.cleaned_data.get("permissions") or []
    password = form.cleaned_data.get("password") or ""
    password_expiration_date = form.cleaned_data.get("password_expiration_date")
    account_revoke_date = form.cleaned_data.get("account_revoke_date")
    expires_at_value = _to_eod_aware_datetime(password_expiration_date)
    revoked_at_value = _to_eod_aware_datetime(account_revoke_date)

    User = get_user_model()

    profile = None
    if profile_id:
        profile = UserAccessProfile.objects.select_related("user").filter(id=profile_id).first()
    created_new = False
    if profile:
        if _is_active_admin_profile(profile):
            will_still_be_active_admin = _would_still_be_active_admin(level, revoked_at_value, expires_at_value)
            if not will_still_be_active_admin and _active_admin_count() <= 1:
                messages.error(request, "لا يمكن خفض/تعطيل آخر Admin فعّال في المنصة.")
                return None
        user = profile.user
    else:
        created_new = True
        user = _get_user_by_identifier(mobile) or _get_user_by_identifier(username)
        if user is None:
            user = User.objects.create_user(phone=mobile or None, password=password or None)
            user.username = username

    user.username = username
    user.phone = mobile
    user.is_active = True
    if password:
        user.set_password(password)
    elif created_new:
        # Guard for newly created users when password is unexpectedly missing.
        user.set_unusable_password()
    user.save()

    profile, _ = UserAccessProfile.objects.get_or_create(user=user, defaults={"level": level})
    profile.level = level

    profile.expires_at = expires_at_value
    profile.revoked_at = revoked_at_value

    profile.save()
    profile.allowed_dashboards.set(Dashboard.objects.filter(code__in=dashboards, is_active=True))
    profile.granted_permissions.set(_resolve_granted_permissions(level, dashboards, permissions))

    changed_fields = sync_dashboard_user_access(
        user,
        access_profile=profile,
        force_staff_role_state=True,
    )
    if changed_fields:
        user.save(update_fields=changed_fields)

    messages.success(request, "تم حفظ بيانات المستخدم والصلاحيات بنجاح.")
    return profile


def _deactivate_access_profile(request):
    profile_id = request.POST.get("profile_id")
    profile = UserAccessProfile.objects.select_related("user").filter(id=profile_id).first()
    if not profile:
        messages.error(request, "المستخدم المطلوب غير موجود.")
        return
    if _is_active_admin_profile(profile) and _active_admin_count() <= 1:
        messages.error(request, "لا يمكن تعطيل آخر Admin فعّال في المنصة.")
        return
    profile.revoked_at = timezone.now()
    profile.save(update_fields=["revoked_at", "updated_at"])

    user = profile.user
    user.is_active = False
    user.is_staff = False
    if getattr(user, "role_state", "") == UserRole.STAFF:
        user.role_state = UserRole.CLIENT
        user.save(update_fields=["is_active", "is_staff", "role_state"])
    else:
        user.save(update_fields=["is_active", "is_staff"])
    messages.success(request, "تم تعطيل الحساب وسحب صلاحياته.")


def _toggle_revoke_access_profile(request):
    profile_id = request.POST.get("profile_id")
    profile = UserAccessProfile.objects.select_related("user").filter(id=profile_id).first()
    if not profile:
        messages.error(request, "المستخدم المطلوب غير موجود.")
        return
    if _is_active_admin_profile(profile) and _active_admin_count() <= 1:
        messages.error(request, "لا يمكن سحب صلاحية آخر Admin فعّال في المنصة.")
        return
    profile.revoked_at = None if profile.revoked_at else timezone.now()
    profile.save(update_fields=["revoked_at", "updated_at"])

    user = profile.user
    changed_fields = sync_dashboard_user_access(user, access_profile=profile, force_staff_role_state=True)
    if changed_fields:
        user.save(update_fields=changed_fields)
    messages.success(request, "تم تحديث حالة صلاحية الحساب.")


def _collect_reports(start_date: date, end_date: date) -> dict:
    start_dt, end_dt = _to_aware_window(start_date, end_date)

    requests_qs = ServiceRequest.objects.filter(created_at__range=(start_dt, end_dt))
    support_qs = SupportTicket.objects.filter(created_at__range=(start_dt, end_dt))

    total_users = get_user_model().objects.count()
    users_complete = get_user_model().objects.filter(terms_accepted_at__isnull=False).count()
    users_staff = get_user_model().objects.filter(is_staff=True, is_active=True).count()
    app_logins = OTP.objects.filter(created_at__range=(start_dt, end_dt)).count()

    requests_summary = {
        "new": requests_qs.filter(status=RequestStatus.NEW).count(),
        "in_progress": requests_qs.filter(status=RequestStatus.IN_PROGRESS).count(),
        "completed": requests_qs.filter(status=RequestStatus.COMPLETED).count(),
        "cancelled": requests_qs.filter(status=RequestStatus.CANCELLED).count(),
        "total": requests_qs.count(),
    }

    interaction_summary = {
        "reviews": Review.objects.filter(created_at__range=(start_dt, end_dt)).count(),
        "provider_likes": ProviderLike.objects.filter(created_at__range=(start_dt, end_dt)).count(),
        "portfolio_likes": ProviderPortfolioLike.objects.filter(created_at__range=(start_dt, end_dt)).count(),
        "spotlight_likes": ProviderSpotlightLike.objects.filter(created_at__range=(start_dt, end_dt)).count(),
        "portfolio_saves": ProviderPortfolioSave.objects.filter(created_at__range=(start_dt, end_dt)).count(),
        "spotlight_saves": ProviderSpotlightSave.objects.filter(created_at__range=(start_dt, end_dt)).count(),
        "provider_follows": ProviderFollow.objects.filter(created_at__range=(start_dt, end_dt)).count(),
    }

    support_by_type = (
        support_qs.values("ticket_type")
        .annotate(total=Count("id"))
        .order_by("-total")
    )
    support_types = dict(SupportTicketType.choices)
    support_type_rows = [
        {
            "type_code": row["ticket_type"],
            "type_label": support_types.get(row["ticket_type"], row["ticket_type"]),
            "total": int(row["total"] or 0),
        }
        for row in support_by_type
    ]

    category_rows = (
        Category.objects.filter(is_active=True)
        .annotate(
            specialists=Count("subcategories__providercategory__provider", distinct=True),
            requests=Count(
                "subcategories__servicerequest",
                filter=Q(subcategories__servicerequest__created_at__range=(start_dt, end_dt)),
                distinct=True,
            ),
        )
        .order_by("name")
    )
    category_stats = [
        {
            "name": category.name,
            "specialists": int(category.specialists or 0),
            "requests": int(category.requests or 0),
        }
        for category in category_rows
    ]

    search_events = AnalyticsEvent.objects.filter(
        occurred_at__range=(start_dt, end_dt),
        event_name__icontains="search",
    ).count()
    email_events = AnalyticsEvent.objects.filter(
        occurred_at__range=(start_dt, end_dt),
    ).filter(Q(event_name__icontains="email") | Q(surface__icontains="email")).count()

    kpi_general = kpis_summary(start_date=start_date, end_date=end_date)
    kpi_provider = provider_kpis(start_date=start_date, end_date=end_date, limit=20)
    kpi_promo = promo_kpis(start_date=start_date, end_date=end_date, limit=20)
    kpi_subs = subscription_kpis(start_date=start_date, end_date=end_date, limit=20)
    kpi_extras = extras_kpis(start_date=start_date, end_date=end_date, limit=20)

    app_downloads_summary = {
        "android": DeviceToken.objects.filter(platform="android", is_active=True).values("token").distinct().count(),
        "ios": DeviceToken.objects.filter(platform="ios", is_active=True).values("token").distinct().count(),
        "web": DeviceToken.objects.filter(platform="web", is_active=True).values("token").distinct().count(),
    }
    app_downloads_summary["total"] = (
        app_downloads_summary["android"] + app_downloads_summary["ios"] + app_downloads_summary["web"]
    )

    visitor_summary = {
        "visitor_accounts": get_user_model().objects.filter(role_state=UserRole.VISITOR).count(),
        "phone_only_accounts": get_user_model().objects.filter(role_state=UserRole.PHONE_ONLY).count(),
        "profile_views": AnalyticsEvent.objects.filter(
            occurred_at__range=(start_dt, end_dt),
            event_name="provider.profile_view",
        ).count(),
        "search_clicks": AnalyticsEvent.objects.filter(
            occurred_at__range=(start_dt, end_dt),
            event_name="search.result_click",
        ).count(),
    }

    paid_invoices_qs = Invoice.objects.filter(
        status=InvoiceStatus.PAID,
        paid_at__range=(start_dt, end_dt),
    )
    paid_services_labels = {
        "subscription": "الاشتراكات",
        "verify_request": "طلبات التوثيق",
        "promo_request": "طلبات الترويج",
        "extras": "الخدمات الإضافية",
        "": "غير مصنف",
    }
    paid_services_rows = []
    for row in (
        paid_invoices_qs.values("reference_type")
        .annotate(total=Count("id"))
        .order_by("-total", "reference_type")
    ):
        ref_type = str(row.get("reference_type") or "").strip()
        paid_services_rows.append(
            {
                "type_code": ref_type,
                "type_label": paid_services_labels.get(ref_type, ref_type or "غير مصنف"),
                "total": int(row.get("total") or 0),
            }
        )

    payment_attempts_qs = PaymentAttempt.objects.filter(created_at__range=(start_dt, end_dt))
    payment_summary = {
        "attempts_total": payment_attempts_qs.count(),
        "initiated": payment_attempts_qs.filter(status=PaymentAttemptStatus.INITIATED).count(),
        "redirected": payment_attempts_qs.filter(status=PaymentAttemptStatus.REDIRECTED).count(),
        "success": payment_attempts_qs.filter(status=PaymentAttemptStatus.SUCCESS).count(),
        "failed": payment_attempts_qs.filter(status=PaymentAttemptStatus.FAILED).count(),
        "cancelled": payment_attempts_qs.filter(status=PaymentAttemptStatus.CANCELLED).count(),
        "refunded": payment_attempts_qs.filter(status=PaymentAttemptStatus.REFUNDED).count(),
    }

    paid_totals = paid_invoices_qs.aggregate(invoice_count=Count("id"), amount_sum=Sum("total"))
    payment_summary["paid_invoices"] = int(paid_totals.get("invoice_count") or 0)
    payment_summary["paid_amount_total"] = float(paid_totals.get("amount_sum") or 0)

    specialist_classification = {
        # Temporarily unlinked from subscription tiers until business mapping is finalized.
        "maher": 0,
        "mostashar": 0,
        "moahel": 0,
        "kafo": 0,
        "total_specialists": 0,
        "is_linked": False,
    }

    return {
        "start": start_date.isoformat(),
        "end": end_date.isoformat(),
        "users_summary": {
            "total_users": total_users,
            "users_complete": users_complete,
            "staff_users": users_staff,
            "app_logins": app_logins,
        },
        "requests_summary": requests_summary,
        "interaction_summary": interaction_summary,
        "support_type_rows": support_type_rows,
        "category_stats": category_stats,
        "search_events": search_events,
        "email_events": email_events,
        "app_downloads_summary": app_downloads_summary,
        "visitor_summary": visitor_summary,
        "paid_services_rows": paid_services_rows,
        "payment_summary": payment_summary,
        "specialist_classification": specialist_classification,
        "kpi_general": kpi_general,
        "kpi_provider": kpi_provider,
        "kpi_promo": kpi_promo,
        "kpi_subs": kpi_subs,
        "kpi_extras": kpi_extras,
    }


def _reports_export_rows(report: dict) -> tuple[list[str], list[list]]:
    headers = ["القسم", "المؤشر", "القيمة"]
    rows: list[list] = []

    for key, value in report["users_summary"].items():
        rows.append(["إحصاءات المستخدمين", key, value])
    for key, value in report["requests_summary"].items():
        rows.append(["إحصاءات الطلبات", key, value])
    for key, value in report["interaction_summary"].items():
        rows.append(["إحصاءات التفاعل", key, value])
    rows.append(["إحصاءات البحث", "search_events", report["search_events"]])
    rows.append(["إحصاءات البريد الإلكتروني", "email_events", report["email_events"]])

    for row in report["support_type_rows"]:
        rows.append(["إحصاءات الدعم", row["type_label"], row["total"]])
    for key, value in report.get("app_downloads_summary", {}).items():
        rows.append(["تحميلات التطبيق", key, value])
    for key, value in report.get("visitor_summary", {}).items():
        rows.append(["زوار التطبيق", key, value])
    for row in report.get("paid_services_rows", []):
        rows.append(["الخدمات المدفوعة", row["type_label"], row["total"]])
    for key, value in report.get("payment_summary", {}).items():
        rows.append(["الدفع الإلكتروني", key, value])
    for key, value in report.get("specialist_classification", {}).items():
        rows.append(["تصنيف المختصين", key, value])
    for row in report["category_stats"]:
        rows.append(["التصنيف الرئيسي", f"{row['name']} - عدد المتخصصين", row["specialists"]])
        rows.append(["التصنيف الرئيسي", f"{row['name']} - عدد الطلبات", row["requests"]])

    for key, value in report["kpi_general"].items():
        rows.append(["مؤشرات التشغيل والتجارة", key, value])
    for item in report["kpi_provider"]["items"]:
        rows.append(["KPI المزودين", item["display_name"], item["requests_received"]])
    for item in report["kpi_promo"]["items"]:
        rows.append(["KPI الترويج", item["label"], item["clicks"]])
    for item in report["kpi_subs"]["items"]:
        rows.append(["KPI الاشتراكات", item["plan_code"], item["activations"]])
    for item in report["kpi_extras"]["items"]:
        rows.append(["KPI الخدمات الإضافية", item["sku"], item["purchases"]])

    return headers, rows


@dashboard_staff_required
@require_dashboard_access("admin_control")
def admin_control_home(request):
    ensure_backoffice_access_catalog()
    section = (request.GET.get("section") or "access").strip().lower()
    if section not in {"access", "reports"}:
        section = "access"
    new_form_requested = (request.GET.get("new") or "").strip().lower() in {"1", "true", "yes"}
    access_form = None

    if request.method == "POST":
        action = (request.POST.get("action") or "").strip()
        if not dashboard_allowed(request.user, "admin_control", write=True):
            return HttpResponseForbidden("لا تملك صلاحية التعديل.")

        if action == "save_user":
            access_form = AccessProfileForm(request.POST)
            if access_form.is_valid():
                profile = _upsert_access_profile(request, access_form)
                if profile is not None:
                    return redirect(f"{request.path}?section=access&edit={profile.id}")
            messages.error(request, "يرجى تصحيح الأخطاء في النموذج.")
        elif action == "delete_user":
            _deactivate_access_profile(request)
            return redirect(f"{request.path}?section=access")
        elif action == "toggle_revoke":
            _toggle_revoke_access_profile(request)
            return redirect(f"{request.path}?section=access")

    edit_profile_id = None if new_form_requested else request.GET.get("edit")
    edit_profile = None
    if edit_profile_id and str(edit_profile_id).isdigit():
        edit_profile = UserAccessProfile.objects.select_related("user").filter(id=int(edit_profile_id)).first()

    if access_form is None:
        access_form = AccessProfileForm(initial=_profile_to_form_initial(edit_profile) if edit_profile else None)
    access_form_has_errors = access_form.is_bound and bool(access_form.errors)
    access_form_open = bool(edit_profile or new_form_requested or access_form_has_errors)
    access_rows = _serialize_access_rows()
    access_summary = _access_summary(access_rows)

    start_date, end_date = _date_range_from_request(request)
    reports = _collect_reports(start_date, end_date)
    headers, export_rows = _reports_export_rows(reports)

    if section == "reports":
        if _want_csv(request):
            return _csv_response("platform_report.csv", headers, export_rows)
        if _want_xlsx(request):
            return xlsx_response("platform_report.xlsx", "reports", headers, export_rows)
        if _want_pdf(request):
            return pdf_response("platform_report.pdf", "إحصاءات وتقارير المنصة", headers, export_rows, landscape=True)

    return render(
        request,
        "dashboard/admin_control_home.html",
        {
            "section": section,
            "access_rows": access_rows,
            "access_summary": access_summary,
            "access_form": access_form,
            "access_form_has_errors": access_form_has_errors,
            "access_form_open": access_form_open,
            "edit_profile": edit_profile,
            "reports": reports,
        },
    )


@dashboard_staff_required
@require_dashboard_access("analytics")
def analytics_insights(request):
    from apps.core.feature_flags import analytics_kpi_surfaces_enabled

    if not analytics_kpi_surfaces_enabled():
        raise Http404("غير موجود")

    start_date, end_date = _date_range_from_request(request)
    provider_data = provider_kpis(start_date=start_date, end_date=end_date, limit=20)
    promo_data = promo_kpis(start_date=start_date, end_date=end_date, limit=20)
    subs_data = subscription_kpis(start_date=start_date, end_date=end_date, limit=20)
    extras_data = extras_kpis(start_date=start_date, end_date=end_date, limit=20)

    return render(
        request,
        "dashboard/analytics_insights.html",
        {
            "start": start_date.isoformat(),
            "end": end_date.isoformat(),
            "provider_data": provider_data,
            "promo_data": promo_data,
            "subs_data": subs_data,
            "extras_data": extras_data,
        },
    )


SUPPORT_PRIORITY_TO_NUMBER = {
    SupportPriority.LOW: 1,
    SupportPriority.NORMAL: 2,
    SupportPriority.HIGH: 3,
}

SUPPORT_TICKET_TYPE_TO_TEAM_LABEL = {
    SupportTicketType.TECH: "فريق الدعم والمساعدة",
    SupportTicketType.SUBS: "فريق إدارة الترقية والاشتراكات",
    SupportTicketType.VERIFY: "فريق التوثيق",
    SupportTicketType.SUGGEST: "فريق إدارة المحتوى",
    SupportTicketType.ADS: "فريق إدارة الإعلانات والترويج",
    SupportTicketType.COMPLAINT: "فريق إدارة المحتوى",
    SupportTicketType.EXTRAS: "فريق إدارة الخدمات الإضافية",
}


def _format_dt(dt) -> str:
    if not dt:
        return "-"
    local_dt = timezone.localtime(dt)
    return local_dt.strftime("%d/%m/%Y - %H:%M")


def _support_priority_number(priority: str) -> int:
    return int(SUPPORT_PRIORITY_TO_NUMBER.get(priority, 1))


def _support_priority_row_class(priority: str) -> str:
    number = _support_priority_number(priority)
    if number == 3:
        return "priority-3"
    if number == 2:
        return "priority-2"
    return "priority-1"


def _dashboard_user_identifier(user_obj, *, prefer_phone: bool = False) -> str:
    if user_obj is None:
        return "-"

    primary = getattr(user_obj, "phone", "") if prefer_phone else getattr(user_obj, "username", "")
    secondary = getattr(user_obj, "username", "") if prefer_phone else getattr(user_obj, "phone", "")
    label = str(primary or secondary or f"user-{getattr(user_obj, 'id', '0')}").strip()
    return label or "-"


def _dashboard_requester_display_name(user_obj) -> str:
    if user_obj is None:
        return "-"

    provider_profile = getattr(user_obj, "provider_profile", None)
    provider_name = str(getattr(provider_profile, "display_name", "") or "").strip()
    if provider_name:
        return provider_name

    full_name = " ".join(
        part.strip()
        for part in [
            str(getattr(user_obj, "first_name", "") or ""),
            str(getattr(user_obj, "last_name", "") or ""),
        ]
        if part and part.strip()
    ).strip()
    if full_name:
        return full_name

    return _dashboard_user_identifier(user_obj, prefer_phone=True)


def _support_requester_label(ticket: SupportTicket) -> str:
    return _dashboard_requester_display_name(ticket.requester)


def _support_assignee_label(ticket: SupportTicket) -> str:
    if not ticket.assigned_to:
        return "غير مكلف"
    return (ticket.assigned_to.username or ticket.assigned_to.phone or f"user-{ticket.assigned_to.id}").strip()


def _support_team_label(ticket: SupportTicket) -> str:
    if ticket.assigned_team:
        return ticket.assigned_team.name_ar
    return SUPPORT_TICKET_TYPE_TO_TEAM_LABEL.get(ticket.ticket_type, "فريق الدعم والمساعدة")


def _support_attachment_rows(ticket: SupportTicket) -> list[dict]:
    image_exts = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".svg"}
    rows: list[dict] = []
    for attachment in ticket.attachments.select_related("uploaded_by").order_by("-id"):
        file_obj = getattr(attachment, "file", None)
        name = ""
        url = ""
        ext = ""
        if file_obj is not None:
            name = str(getattr(file_obj, "name", "") or "").split("/")[-1]
            try:
                url = str(file_obj.url or "")
            except Exception:
                url = ""
            if "." in name:
                ext = f".{name.rsplit('.', 1)[-1].lower()}"

        uploaded_by = getattr(attachment, "uploaded_by", None)
        uploader_label = "-"
        if uploaded_by:
            uploader_label = (
                getattr(uploaded_by, "username", "")
                or getattr(uploaded_by, "phone", "")
                or f"user-{uploaded_by.id}"
            )

        rows.append(
            {
                "id": attachment.id,
                "name": name or f"attachment-{attachment.id}",
                "url": url,
                "ext": ext.lstrip("."),
                "is_image": ext in image_exts,
                "uploaded_by": uploader_label,
                "created_at": _format_dt(attachment.created_at),
            }
        )
    return rows


def _support_queryset_for_user(user):
    qs = (
        SupportTicket.objects.select_related("requester", "requester__provider_profile", "assigned_team", "assigned_to")
        .filter(entrypoint=SupportTicketEntrypoint.CONTACT_PLATFORM)
        .order_by("-created_at", "-id")
    )
    access_profile = active_access_profile_for_user(user)
    if access_profile and access_profile.level == AccessLevel.USER:
        qs = qs.filter(Q(assigned_to=user) | Q(assigned_to__isnull=True))
    return qs


def _dashboard_assignee_choices(dashboard_code: str) -> list[tuple[str, str]]:
    normalized_code = normalize_dashboard_code(dashboard_code)
    choices: list[tuple[str, str]] = []
    seen_ids: set[int] = set()

    for profile in UserAccessProfile.objects.select_related("user").prefetch_related("allowed_dashboards").all():
        user = profile.user
        if not getattr(user, "is_active", False):
            continue
        if not (getattr(user, "is_staff", False) or getattr(user, "is_superuser", False)):
            continue

        has_access = profile.level == AccessLevel.ADMIN or profile.is_allowed(normalized_code)
        if not has_access:
            continue
        if user.id in seen_ids:
            continue
        seen_ids.add(user.id)
        label = (user.username or user.phone or f"user-{user.id}").strip()
        choices.append((str(user.id), label))

    superusers = get_user_model().objects.filter(is_superuser=True, is_active=True)
    for user in superusers:
        if user.id in seen_ids:
            continue
        seen_ids.add(user.id)
        label = (user.username or user.phone or f"user-{user.id}").strip()
        choices.append((str(user.id), label))

    choices.sort(key=lambda item: item[1].lower())
    return choices


def _support_assignee_choices() -> list[tuple[str, str]]:
    return _dashboard_assignee_choices("support")


SUPPORT_TEAM_CODE_TO_DASHBOARD_FALLBACK = {
    "support": "support",
    "content": "content",
    "promo": "promo",
    "verification": "verify",
    "verify": "verify",
    "finance": "subs",
    "subs": "subs",
    "extras": "extras",
}


SUPPORT_DASHBOARD_CODE_ALIASES = {
    "verification": "verify",
    "verify": "verify",
    "finance": "subs",
    "subscription": "subs",
    "subscriptions": "subs",
    "subs": "subs",
}


def _normalize_support_dashboard_code(dashboard_code: str, *, default: str = "") -> str:
    normalized = normalize_dashboard_code(str(dashboard_code or "").strip())
    if not normalized:
        return default
    return SUPPORT_DASHBOARD_CODE_ALIASES.get(normalized, normalized)


def _support_dashboard_code_candidates(dashboard_code: str) -> list[str]:
    normalized_target = _normalize_support_dashboard_code(dashboard_code, default="")
    if not normalized_target:
        return []

    candidates = {normalized_target}
    for raw_code, canonical_code in SUPPORT_DASHBOARD_CODE_ALIASES.items():
        if canonical_code == normalized_target:
            candidates.add(raw_code)
    return sorted(candidates)


def _fallback_dashboard_code_for_team_code(team_code: str) -> str:
    normalized_team_code = str(team_code or "").strip().lower()
    if not normalized_team_code:
        return "support"

    mapped_dashboard_code = SUPPORT_TEAM_CODE_TO_DASHBOARD_FALLBACK.get(normalized_team_code)
    if mapped_dashboard_code:
        return mapped_dashboard_code
    return _normalize_support_dashboard_code(normalized_team_code, default="support")


def _support_teams_queryset():
    active_qs = SupportTeam.objects.filter(is_active=True).order_by("sort_order", "id")
    if active_qs.exists():
        return active_qs
    return SupportTeam.objects.order_by("sort_order", "id")


def _support_team_dashboard_code(team_id) -> str:
    try:
        normalized_team_id = int(team_id)
    except (TypeError, ValueError):
        return "support"

    team = SupportTeam.objects.filter(id=normalized_team_id).only("code", "dashboard_code").first()
    if team is None:
        return "support"
    explicit_dashboard_code = _normalize_support_dashboard_code(getattr(team, "dashboard_code", ""), default="")
    if explicit_dashboard_code:
        return explicit_dashboard_code
    return _fallback_dashboard_code_for_team_code(getattr(team, "code", ""))


def _support_assignee_choices_by_team() -> dict[str, list[tuple[str, str]]]:
    mapping: dict[str, list[tuple[str, str]]] = {}
    for team in _support_teams_queryset():
        dashboard_code = _support_team_dashboard_code(team.id)
        mapping[str(team.id)] = _dashboard_assignee_choices(dashboard_code)
    return mapping


def _support_team_choices() -> list[tuple[str, str]]:
    return [(str(team.id), team.name_ar) for team in _support_teams_queryset()]


def _support_team_for_dashboard(dashboard_code: str, *, fallback_codes: list[str] | None = None) -> SupportTeam | None:
    target_candidates = _support_dashboard_code_candidates(dashboard_code)
    if not target_candidates:
        return None

    teams = list(_support_teams_queryset())
    for team in teams:
        team_dashboard_code = _normalize_support_dashboard_code(getattr(team, "dashboard_code", ""), default="")
        if team_dashboard_code and team_dashboard_code in target_candidates:
            return team

    for code in fallback_codes or []:
        normalized_code = str(code or "").strip().lower()
        if not normalized_code:
            continue
        for team in teams:
            if str(getattr(team, "code", "") or "").strip().lower() == normalized_code:
                return team
    return None


def _support_ticket_dashboard_q(dashboard_code: str, *, fallback_team_codes: list[str] | None = None):
    query = Q(pk__in=[])

    for candidate in _support_dashboard_code_candidates(dashboard_code):
        query |= Q(assigned_team__dashboard_code__iexact=candidate)

    for raw_code in fallback_team_codes or []:
        normalized_code = str(raw_code or "").strip()
        if not normalized_code:
            continue
        query |= (
            (Q(assigned_team__dashboard_code__exact="") | Q(assigned_team__dashboard_code__isnull=True))
            & Q(assigned_team__code__iexact=normalized_code)
        )

    return query

def _promo_support_team() -> SupportTeam | None:
    return _support_team_for_dashboard("promo", fallback_codes=["promo"])


def _serialize_support_rows(tickets: list[SupportTicket]) -> list[dict]:
    subscriptions_by_user_id = _effective_subscriptions_map_for_users(
        [getattr(ticket, "requester", None) for ticket in tickets]
    )
    rows = []
    for ticket in tickets:
        priority_number = _dashboard_priority_number_for_user(
            ticket.requester,
            subscriptions_by_user_id=subscriptions_by_user_id,
        )
        rows.append(
            {
                "id": ticket.id,
                "code": ticket.code or f"HD{ticket.id:04d}",
                "requester": _support_requester_label(ticket),
                "priority_number": priority_number,
                "priority_class": _dashboard_priority_class_for_user(
                    ticket.requester,
                    subscriptions_by_user_id=subscriptions_by_user_id,
                ),
                "ticket_type": ticket.get_ticket_type_display(),
                "created_at": _format_dt(ticket.created_at),
                "status": ticket.get_status_display(),
                "status_code": ticket.status,
                "team": _support_team_label(ticket),
                "assignee": _support_assignee_label(ticket),
                "assigned_at": _format_dt(ticket.assigned_at),
            }
        )
    return rows


def _support_export_rows(tickets: list[SupportTicket]) -> tuple[list[str], list[list]]:
    headers = [
        "رقم الطلب",
        "اسم العميل",
        "الأولوية",
        "نوع الطلب",
        "تاريخ ووقت استلام الطلب",
        "حالة الطلب",
        "فريق الدعم",
        "المكلف بالطلب",
        "تاريخ ووقت التكليف",
    ]
    rows: list[list] = []
    for row in _serialize_support_rows(tickets):
        rows.append(
            [
                row["code"],
                row["requester"],
                row["priority_number"],
                row["ticket_type"],
                row["created_at"],
                row["status"],
                row["team"],
                row["assignee"],
                row["assigned_at"],
            ]
        )
    return headers, rows


def _support_summary(tickets: list[SupportTicket]) -> dict:
    by_status: dict[str, int] = {}
    for ticket in tickets:
        by_status[ticket.status] = by_status.get(ticket.status, 0) + 1
    return {
        "total": len(tickets),
        "new": by_status.get(SupportTicketStatus.NEW, 0),
        "in_progress": by_status.get(SupportTicketStatus.IN_PROGRESS, 0),
        "returned": by_status.get(SupportTicketStatus.RETURNED, 0),
        "closed": by_status.get(SupportTicketStatus.CLOSED, 0),
    }


def _subscription_inquiry_status_label(status_code: str) -> str:
    return {
        SupportTicketStatus.NEW: "جديد",
        SupportTicketStatus.IN_PROGRESS: "تحت المعالجة",
        SupportTicketStatus.RETURNED: "معاد للعميل",
        SupportTicketStatus.CLOSED: "مكتمل",
    }.get(str(status_code or "").strip(), "-")


def _subscription_inquiry_rows(tickets: list[SupportTicket]) -> list[dict]:
    rows = _serialize_support_rows(tickets)
    for row in rows:
        row["status"] = _subscription_inquiry_status_label(row.get("status_code") or "")
    return rows


def _subscription_redirect_with_state(request, *, inquiry_id: int | None = None):
    query = (request.POST.get("redirect_query") or request.GET.urlencode()).strip()
    base = reverse("dashboard:subscription_dashboard")
    params = QueryDict(query, mutable=True)
    if inquiry_id is not None:
        params["inquiry"] = str(inquiry_id)

    normalized_query = params.urlencode()
    target = f"{base}?{normalized_query}" if normalized_query else base
    return redirect(f"{target}#subscriptionInquiries")


def _subscription_close_inquiry_url(request) -> str:
    params = QueryDict(request.GET.urlencode(), mutable=True)
    params.pop("inquiry", None)
    params["tab"] = SUBSCRIPTION_DASHBOARD_TAB_OPERATIONS
    base = reverse("dashboard:subscription_dashboard")
    normalized_query = params.urlencode()
    target = f"{base}?{normalized_query}" if normalized_query else base
    return f"{target}#subscriptionInquiries"


SUBSCRIPTION_REQUEST_STATUS_CHOICES = [
    (UnifiedRequestStatus.NEW, "جديد"),
    (UnifiedRequestStatus.IN_PROGRESS, "تحت المعالجة"),
    (UnifiedRequestStatus.CLOSED, "مكتمل"),
]

SUBSCRIPTION_DASHBOARD_TAB_OPERATIONS = "operations"
SUBSCRIPTION_DASHBOARD_TAB_ACCOUNTS = "subscriber_accounts"


def _subscription_nav_items(active_key: str) -> list[dict]:
    items = [
        {
            "key": SUBSCRIPTION_DASHBOARD_TAB_OPERATIONS,
            "label": "تفعيل الاشتراكات",
            "description": "استفسارات الاشتراكات وطلبات التشغيل والتفعيل.",
            "url": reverse("dashboard:subscription_dashboard"),
        },
        {
            "key": SUBSCRIPTION_DASHBOARD_TAB_ACCOUNTS,
            "label": "بيانات حسابات المشتركين",
            "description": "عرض حسابات المشتركين بعد التفعيل أو الترقية.",
            "url": f"{reverse('dashboard:subscription_dashboard')}?tab={SUBSCRIPTION_DASHBOARD_TAB_ACCOUNTS}",
        },
    ]
    for item in items:
        item["active"] = item["key"] == active_key
    return items


def _subscription_dashboard_url_with_state(
    request,
    *,
    request_id: int | None = None,
    account_id: int | None = None,
    anchor: str = "subscriptionRequests",
    query: str = "",
    tab: str | None = None,
) -> str:
    raw_query = str(query or request.GET.urlencode()).strip()
    params = QueryDict(raw_query, mutable=True)
    if tab:
        params["tab"] = tab
    if request_id is None:
        params.pop("request", None)
    else:
        params["request"] = str(request_id)

    if account_id is None:
        params.pop("account", None)
    else:
        params["account"] = str(account_id)

    base = reverse("dashboard:subscription_dashboard")
    normalized_query = params.urlencode()
    target = f"{base}?{normalized_query}" if normalized_query else base
    return f"{target}#{anchor}" if anchor else target


def _subscription_request_redirect_with_state(
    request,
    *,
    request_id: int | None = None,
    account_id: int | None = None,
    anchor: str = "subscriptionRequests",
    tab: str = SUBSCRIPTION_DASHBOARD_TAB_OPERATIONS,
):
    query = (request.POST.get("redirect_query") or request.GET.urlencode()).strip()
    return redirect(
        _subscription_dashboard_url_with_state(
            request,
            request_id=request_id,
            account_id=account_id,
            anchor=anchor,
            query=query,
            tab=tab,
        )
    )


def _subscription_request_status_label(status_code: str) -> str:
    normalized = str(status_code or "").strip().lower()
    return {
        UnifiedRequestStatus.NEW: "جديد",
        UnifiedRequestStatus.IN_PROGRESS: "تحت المعالجة",
        UnifiedRequestStatus.CLOSED: "مكتمل",
    }.get(normalized, "جديد")


def _subscription_request_operational_status(sub: Subscription | None, request_obj: UnifiedRequest | None) -> str:
    normalized = canonical_status_for_workflow(
        request_type=UnifiedRequestType.SUBSCRIPTION,
        status=getattr(request_obj, "status", ""),
    )
    if normalized in {UnifiedRequestStatus.NEW, UnifiedRequestStatus.IN_PROGRESS, UnifiedRequestStatus.CLOSED}:
        return normalized
    if sub is None:
        return UnifiedRequestStatus.NEW
    if sub.status == SubscriptionStatus.AWAITING_REVIEW:
        return UnifiedRequestStatus.NEW
    if sub.status in {SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE, SubscriptionStatus.EXPIRED, SubscriptionStatus.CANCELLED}:
        return UnifiedRequestStatus.CLOSED
    return UnifiedRequestStatus.NEW


def _subscription_payment_status_label(sub: Subscription | None) -> str:
    invoice = getattr(sub, "invoice", None)
    if invoice is None:
        return "لا توجد فاتورة"
    if invoice.is_payment_effective():
        return "مدفوع ومعتمد"
    return invoice.get_status_display()


def _subscription_duration_label(plan_obj: SubscriptionPlan | None, duration_count: int) -> str:
    normalized_duration = max(1, int(duration_count or 1))
    period = getattr(plan_obj, "period", "year")
    if period == "month":
        if normalized_duration == 1:
            return "لمدة شهر واحد"
        if normalized_duration == 2:
            return "لمدة شهرين"
        if 3 <= normalized_duration <= 10:
            return f"لمدة {normalized_duration} أشهر"
        return f"لمدة {normalized_duration} شهرًا"

    if normalized_duration == 1:
        return "لمدة سنة واحدة"
    if normalized_duration == 2:
        return "لمدة سنتين"
    if 3 <= normalized_duration <= 10:
        return f"لمدة {normalized_duration} سنوات"
    return f"لمدة {normalized_duration} سنة"


def _subscription_provider_name(sub: Subscription) -> str:
    return _dashboard_requester_display_name(getattr(sub, "user", None))


def _subscription_payment_amount_text(invoice: Invoice | None) -> str:
    if invoice is None:
        return "-"
    raw_amount = getattr(invoice, "payment_amount", None)
    if raw_amount in {None, "", 0, Decimal("0.00")}:
        raw_amount = getattr(invoice, "total", None)
    try:
        amount_text = f"{Decimal(raw_amount):.2f}"
    except (InvalidOperation, TypeError, ValueError):
        return "-"
    currency = str(getattr(invoice, "payment_currency", "") or getattr(invoice, "currency", "") or "").strip().upper()
    return f"{amount_text} {currency}".strip()


def _subscription_payment_message(sub: Subscription, invoice: Invoice | None = None) -> str:
    invoice = invoice if invoice is not None else getattr(sub, "invoice", None)
    if invoice is None:
        return "لا توجد فاتورة مرتبطة بهذا الاشتراك حتى الآن."

    if invoice.is_payment_effective():
        payment_date = getattr(invoice, "payment_confirmed_at", None) or getattr(invoice, "paid_at", None)
        amount_text = _subscription_payment_amount_text(invoice)
        if payment_date and amount_text != "-":
            return f"تمت عملية السداد بنجاح في تاريخ {_format_dt(payment_date)} بقيمة {amount_text}."
        if payment_date:
            return f"تمت عملية السداد بنجاح في تاريخ {_format_dt(payment_date)}."
        if amount_text != "-":
            return f"تمت عملية السداد بنجاح بقيمة {amount_text}."
        return "تمت عملية السداد بنجاح."

    if invoice.status == InvoiceStatus.REFUNDED:
        return "تم استرجاع قيمة هذه الفاتورة، لذلك لا توجد عملية سداد فعالة حاليًا."
    return f"حالة السداد الحالية: {invoice.get_status_display()}."


def _subscription_account_delete_disabled_reason(sub: Subscription) -> str:
    if sub.status in {SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE}:
        return "لا يمكن حذف اشتراك نشط أو ضمن فترة السماح."

    invoice = getattr(sub, "invoice", None)
    if invoice is not None and (
        invoice.is_payment_effective()
        or invoice.status in {InvoiceStatus.PAID, InvoiceStatus.REFUNDED}
    ):
        return "لا يمكن حذف اشتراك تمت تسوية سداده أو استرجاعه."
    return ""


def _resolved_subscription_end_at(sub: Subscription):
    if getattr(sub, "end_at", None):
        return sub.end_at
    start_at = getattr(sub, "start_at", None)
    if not start_at:
        return None
    try:
        return sub.calc_end_date(start_at)
    except Exception:
        return None


def _subscription_invoice_fallback_maps(subscriptions: list[Subscription]) -> tuple[dict[int, Invoice], dict[int, Invoice]]:
    subscription_ids = [sub.id for sub in subscriptions if getattr(sub, "id", None)]
    user_ids = [sub.user_id for sub in subscriptions if getattr(sub, "user_id", None)]
    if not subscription_ids and not user_ids:
        return {}, {}

    invoices = list(
        Invoice.objects.filter(reference_type="subscription")
        .filter(
            Q(reference_id__in=[str(sub_id) for sub_id in subscription_ids])
            | Q(user_id__in=user_ids)
        )
        .order_by("-payment_confirmed_at", "-paid_at", "-id")
    )

    exact_map: dict[int, Invoice] = {}
    latest_effective_by_user: dict[int, Invoice] = {}
    for invoice in invoices:
        reference_id = str(getattr(invoice, "reference_id", "") or "").strip()
        if reference_id.isdigit():
            sub_id = int(reference_id)
            if sub_id in subscription_ids and sub_id not in exact_map:
                exact_map[sub_id] = invoice

        if invoice.user_id and invoice.user_id not in latest_effective_by_user and invoice.is_payment_effective():
            latest_effective_by_user[invoice.user_id] = invoice

    return exact_map, latest_effective_by_user


def _resolved_subscription_invoice(
    sub: Subscription,
    *,
    exact_invoice_map: dict[int, Invoice],
    latest_effective_by_user: dict[int, Invoice],
) -> Invoice | None:
    direct_invoice = getattr(sub, "invoice", None)
    if direct_invoice is not None:
        return direct_invoice
    exact_invoice = exact_invoice_map.get(sub.id)
    if exact_invoice is not None:
        return exact_invoice
    return latest_effective_by_user.get(getattr(sub, "user_id", None))


def _subscription_request_content_text(sub: Subscription | None, request_obj: UnifiedRequest | None) -> str:
    invoice = getattr(sub, "invoice", None)
    invoice_description = str(getattr(invoice, "description", "") or "").strip()
    summary = str(getattr(request_obj, "summary", "") or "").strip()
    plan_title = getattr(getattr(sub, "plan", None), "title", "") or getattr(getattr(sub, "plan", None), "code", "") or "-"
    duration_count = int(getattr(sub, "duration_count", 1) or 1)
    payment_label = _subscription_payment_status_label(sub)

    lines = [item for item in [summary, invoice_description] if item]
    lines.append(f"نوع الاشتراك: {plan_title}")
    lines.append(f"مدة الاشتراك: {duration_count}")
    lines.append(f"حالة الدفع: {payment_label}")
    return "\n".join(lines)


def _subscription_request_plan_choices() -> list[tuple[str, str]]:
    ordered_plans = [
        plan
        for plan in SubscriptionPlan.objects.filter(is_active=True).order_by("id")
        if plan_to_db_tier(plan) in {PlanTier.BASIC, PlanTier.RIYADI, PlanTier.PRO}
    ]
    ordered_plans.sort(
        key=lambda plan: (
            _subscription_priority_number_for_plan(plan),
            getattr(plan, "price", 0),
            plan.id,
        )
    )
    return [(str(plan.id), getattr(plan, "title", "") or getattr(plan, "code", "")) for plan in ordered_plans]


def _resolve_selected_ticket(base_qs, request, ticket_id: int | None):
    selected_id = ticket_id
    if selected_id is None:
        raw = (request.GET.get("ticket") or "").strip()
        if raw.isdigit():
            selected_id = int(raw)
    if selected_id is None:
        return None
    return base_qs.filter(id=selected_id).first()


def _support_redirect_with_state(request, ticket_id: int | None = None):
    query = (request.POST.get("redirect_query") or request.GET.urlencode()).strip()
    base = request.path
    if not query:
        return redirect(base)
    if ticket_id is not None and "ticket=" not in query:
        query = f"{query}&ticket={ticket_id}"
    return redirect(f"{base}?{query}")


@dashboard_staff_required
@require_dashboard_access("support")
def support_dashboard(request, ticket_id: int | None = None):
    base_qs = _support_queryset_for_user(request.user)

    status_filter = (request.GET.get("status") or "").strip()
    type_filter = (request.GET.get("type") or "").strip()
    priority_filter = (request.GET.get("priority") or "").strip()
    query_filter = (request.GET.get("q") or "").strip()

    tickets_qs = base_qs
    if status_filter:
        tickets_qs = tickets_qs.filter(status=status_filter)
    if type_filter:
        tickets_qs = tickets_qs.filter(ticket_type=type_filter)
    if priority_filter in {"1", "2", "3"}:
        reverse_map = {"1": SupportPriority.LOW, "2": SupportPriority.NORMAL, "3": SupportPriority.HIGH}
        tickets_qs = tickets_qs.filter(priority=reverse_map[priority_filter])
    if query_filter:
        tickets_qs = tickets_qs.filter(
            Q(code__icontains=query_filter)
            | Q(description__icontains=query_filter)
            | Q(requester__provider_profile__display_name__icontains=query_filter)
            | Q(requester__username__icontains=query_filter)
            | Q(requester__phone__icontains=query_filter)
        )

    tickets = list(tickets_qs)
    selected_ticket = _resolve_selected_ticket(base_qs, request, ticket_id)

    team_choices = _support_team_choices()
    assignee_choices_by_team = _support_assignee_choices_by_team()
    assignee_map: dict[str, str] = {}
    for choices in assignee_choices_by_team.values():
        for value, label in choices:
            assignee_map[str(value)] = label
    assignee_choices = sorted(assignee_map.items(), key=lambda item: item[1].lower())
    can_write = dashboard_allowed(request.user, "support", write=True)

    support_form = None
    if selected_ticket:
        support_form = SupportDashboardActionForm(
            initial={
                "status": selected_ticket.status,
                "assigned_team": str(selected_ticket.assigned_team_id or ""),
                "assigned_to": str(selected_ticket.assigned_to_id or ""),
                "description": selected_ticket.description or "",
            },
            assignee_choices=assignee_choices,
            team_choices=team_choices,
        )
    else:
        support_form = SupportDashboardActionForm(assignee_choices=assignee_choices, team_choices=team_choices)

    if request.method == "POST":
        if not can_write:
            return HttpResponseForbidden("لا تملك صلاحية تعديل طلبات الدعم.")

        raw_ticket_id = (request.POST.get("ticket_id") or "").strip()
        if not raw_ticket_id.isdigit():
            messages.error(request, "لا يمكن تحديد الطلب المطلوب تحديثه.")
            return _support_redirect_with_state(request)
        target_ticket = base_qs.filter(id=int(raw_ticket_id)).first()
        if target_ticket is None:
            messages.error(request, "الطلب غير متاح لهذا الحساب.")
            return _support_redirect_with_state(request)

        access_profile = active_access_profile_for_user(request.user)
        if access_profile and access_profile.level == AccessLevel.USER:
            if target_ticket.assigned_to_id and target_ticket.assigned_to_id != request.user.id:
                return HttpResponseForbidden("غير مصرح: الطلب ليس ضمن المهام المكلف بها.")

        post_form = SupportDashboardActionForm(
            request.POST,
            request.FILES,
            assignee_choices=assignee_choices,
            team_choices=team_choices,
        )
        if not post_form.is_valid():
            selected_ticket = target_ticket
            support_form = post_form
            messages.error(request, "يرجى مراجعة حقول نموذج المعالجة.")
        else:
            action = (request.POST.get("action") or "save_ticket").strip()

            team_id_raw = (post_form.cleaned_data.get("assigned_team") or "").strip()
            assigned_to_raw = (post_form.cleaned_data.get("assigned_to") or "").strip()
            desired_status = post_form.cleaned_data.get("status")
            note = post_form.cleaned_data.get("assignee_comment") or ""
            new_description = post_form.cleaned_data.get("description") or target_ticket.description or ""
            attachment = post_form.cleaned_data.get("attachment")

            if action == "close_ticket":
                desired_status = SupportTicketStatus.CLOSED
            elif action == "return_ticket":
                desired_status = SupportTicketStatus.RETURNED

            team_id = int(team_id_raw) if team_id_raw.isdigit() else target_ticket.assigned_team_id
            assigned_to_id = int(assigned_to_raw) if assigned_to_raw.isdigit() else target_ticket.assigned_to_id

            if team_id is not None and assigned_to_id is not None:
                allowed_assignees = {
                    int(value)
                    for value, _ in assignee_choices_by_team.get(str(team_id), [])
                    if str(value).isdigit()
                }
                if assigned_to_id not in allowed_assignees:
                    messages.error(request, "المكلف المختار غير مرتبط بفريق الدعم المحدد.")
                    return _support_redirect_with_state(request, ticket_id=target_ticket.id)

            if assigned_to_id is not None:
                assignee_dashboard_code = _support_team_dashboard_code(team_id)
                assignee = dashboard_assignee_user(assigned_to_id, assignee_dashboard_code, write=True)
                if assignee is None:
                    messages.error(request, "المكلف المختار لا يملك صلاحية لوحة الفريق المحدد.")
                    return _support_redirect_with_state(request, ticket_id=target_ticket.id)
                if access_profile and access_profile.level == AccessLevel.USER and assignee.id != request.user.id:
                    return HttpResponseForbidden("لا يمكنك تعيين الطلب لمستخدم آخر.")

            if team_id is not None and not SupportTeam.objects.filter(id=team_id).exists():
                messages.error(request, "فريق الدعم المحدد غير صالح.")
                return _support_redirect_with_state(request, ticket_id=target_ticket.id)

            target_ticket = assign_ticket(
                ticket=target_ticket,
                team_id=team_id,
                user_id=assigned_to_id,
                by_user=request.user,
                note=note,
            )

            if new_description != (target_ticket.description or ""):
                target_ticket.description = new_description
                target_ticket.last_action_by = request.user
                target_ticket.save(update_fields=["description", "last_action_by", "updated_at"])

            if desired_status and desired_status != target_ticket.status:
                try:
                    target_ticket = change_ticket_status(
                        ticket=target_ticket,
                        new_status=desired_status,
                        by_user=request.user,
                        note=note,
                    )
                except ValueError as exc:
                    messages.error(request, str(exc))
                    return _support_redirect_with_state(request, ticket_id=target_ticket.id)

            if note:
                SupportComment.objects.create(
                    ticket=target_ticket,
                    text=note[:300],
                    is_internal=True,
                    created_by=request.user,
                )

            if attachment is not None:
                try:
                    attachment = _validate_and_optimize_dashboard_attachment(attachment, user=request.user)
                except DjangoValidationError as exc:
                    messages.error(request, str(exc))
                    return _support_redirect_with_state(request, ticket_id=target_ticket.id)
                SupportAttachment.objects.create(
                    ticket=target_ticket,
                    file=attachment,
                    uploaded_by=request.user,
                )

            messages.success(request, f"تم تحديث الطلب {target_ticket.code or target_ticket.id} بنجاح.")
            return _support_redirect_with_state(request, ticket_id=target_ticket.id)

    headers, rows = _support_export_rows(tickets)
    if _want_csv(request):
        return _csv_response("support_dashboard.csv", headers, rows)
    if _want_xlsx(request):
        return xlsx_response("support_dashboard.xlsx", "support", headers, rows)
    if _want_pdf(request):
        return pdf_response("support_dashboard.pdf", "لوحة فريق الدعم والمساعدة", headers, rows, landscape=True)

    return render(
        request,
        "dashboard/support_dashboard.html",
        {
            "tickets": _serialize_support_rows(tickets),
            "selected_ticket": selected_ticket,
            "selected_ticket_requester_name": _support_requester_label(selected_ticket) if selected_ticket else "",
            "selected_ticket_attachments": _support_attachment_rows(selected_ticket) if selected_ticket else [],
            "support_form": support_form,
            "summary": _support_summary(tickets),
            "can_write": can_write,
            "status_choices": SupportTicketStatus.choices,
            "ticket_type_choices": SupportTicketType.choices,
            "priority_choices": [("1", "1 - الأساسية"), ("2", "2 - الريادية"), ("3", "3 - الاحترافية")],
            "filters": {
                "status": status_filter,
                "type": type_filter,
                "priority": priority_filter,
                "q": query_filter,
            },
            "team_panels": _dashboard_team_panels(),
            "redirect_query": request.GET.urlencode(),
            "team_assignee_map": assignee_choices_by_team,
        },
    )


SUBSCRIPTION_PRIORITY_TO_NUMBER = {
    "basic": 1,
    "low": 1,
    "normal": 1,
    "riyadi": 2,
    "leading": 2,
    "pioneer": 2,
    "pro": 3,
    "professional": 3,
    "high": 3,
}


def _subscription_priority_number(raw_value: str) -> int:
    return int(SUBSCRIPTION_PRIORITY_TO_NUMBER.get(str(raw_value or "").strip().lower(), 1))


def _subscription_priority_number_for_plan(plan: SubscriptionPlan | None) -> int:
    if plan is None:
        return 1
    return _subscription_priority_number(plan_to_db_tier(plan))


def _subscription_unified_priority_for_plan(plan: SubscriptionPlan | None) -> str:
    normalized_tier = plan_to_db_tier(plan)
    return {
        PlanTier.BASIC: "basic",
        PlanTier.RIYADI: "leading",
        PlanTier.PRO: "professional",
    }.get(normalized_tier, "basic")


def _priority_row_class_from_number(priority_number: int) -> str:
    if int(priority_number or 1) >= 3:
        return "priority-3"
    if int(priority_number or 1) == 2:
        return "priority-2"
    return "priority-1"


def _effective_subscriptions_map_for_users(users) -> dict[int, Subscription]:
    user_ids = sorted(
        {
            int(getattr(user, "id", 0) or 0)
            for user in users
            if getattr(user, "id", None)
        }
    )
    return get_effective_active_subscriptions_map(user_ids)


def _dashboard_priority_number_for_user(user, *, subscriptions_by_user_id: dict[int, Subscription] | None = None) -> int:
    user_id = int(getattr(user, "id", 0) or 0)
    if not user_id:
        return 1
    if subscriptions_by_user_id is not None:
        sub = subscriptions_by_user_id.get(user_id)
        return _subscription_priority_number_for_plan(getattr(sub, "plan", None))
    return _support_priority_number(support_priority(user))


def _dashboard_priority_class_for_user(user, *, subscriptions_by_user_id: dict[int, Subscription] | None = None) -> str:
    return _priority_row_class_from_number(
        _dashboard_priority_number_for_user(user, subscriptions_by_user_id=subscriptions_by_user_id)
    )


def _subscription_unified_queryset_for_user(user):
    qs = (
        UnifiedRequest.objects.select_related("requester", "requester__provider_profile", "assigned_user", "metadata_record")
        .filter(request_type=UnifiedRequestType.SUBSCRIPTION)
        .order_by("-updated_at", "-id")
    )
    access_profile = active_access_profile_for_user(user)
    if access_profile and access_profile.level == AccessLevel.USER:
        qs = qs.filter(Q(assigned_user=user) | Q(assigned_user__isnull=True))
    return qs


def _subscription_related_map(unified_requests: list[UnifiedRequest]) -> dict[int, Subscription]:
    subscription_ids: list[int] = []
    for row in unified_requests:
        try:
            subscription_ids.append(int(str(row.source_object_id or "").strip()))
        except (TypeError, ValueError):
            continue
    if not subscription_ids:
        return {}
    return {
        sub.id: sub
        for sub in Subscription.objects.select_related("user", "plan", "invoice").filter(id__in=subscription_ids)
    }


def _subscription_accounts_queryset_for_user(user):
    qs = Subscription.objects.select_related("user", "user__provider_profile", "plan", "invoice").order_by("-updated_at", "-id")
    access_profile = active_access_profile_for_user(user)
    if access_profile and access_profile.level == AccessLevel.USER:
        allowed_ids: list[int] = []
        for row in _subscription_unified_queryset_for_user(user):
            try:
                allowed_ids.append(int(str(row.source_object_id or "").strip()))
            except (TypeError, ValueError):
                continue
        if not allowed_ids:
            return qs.none()
        qs = qs.filter(id__in=allowed_ids)
    return qs


def _subscription_request_assignee_label(request_obj: UnifiedRequest | None) -> str:
    assignee = getattr(request_obj, "assigned_user", None)
    if assignee is None:
        return "غير مكلف"
    return (getattr(assignee, "username", "") or getattr(assignee, "phone", "") or f"user-{assignee.id}").strip()


def _subscription_request_status_details(sub: Subscription | None, request_obj: UnifiedRequest) -> tuple[str, str]:
    normalized = _subscription_request_operational_status(sub, request_obj)
    return normalized, _subscription_request_status_label(normalized)


def _subscription_request_rows(subscription_requests: list[UnifiedRequest]) -> list[dict]:
    subscriptions_map = _subscription_related_map(subscription_requests)
    rows: list[dict] = []
    for request_obj in subscription_requests:
        try:
            source_id = int(str(request_obj.source_object_id or "").strip())
        except (TypeError, ValueError):
            source_id = 0
        sub = subscriptions_map.get(source_id)
        request_status_code, request_status_label = _subscription_request_status_details(sub, request_obj)
        priority_number = (
            _subscription_priority_number_for_plan(getattr(sub, "plan", None))
            if sub is not None
            else _subscription_priority_number(request_obj.priority)
        )
        rows.append(
            {
                "id": request_obj.id,
                "code": request_obj.code or f"SD{request_obj.id:06d}",
                "requester": _promo_requester_label(request_obj.requester),
                "priority_number": priority_number,
                "priority_class": _priority_row_class_from_number(priority_number),
                "approved_at": _format_dt(getattr(sub, "created_at", None) or request_obj.created_at),
                "request_status_code": request_status_code,
                "request_status": request_status_label,
                "assignee": _subscription_request_assignee_label(request_obj),
                "assigned_at": _format_dt(request_obj.assigned_at),
                "plan_title": getattr(getattr(sub, "plan", None), "title", "") or "-",
                "duration_count": int(getattr(sub, "duration_count", 1) or 1) if sub is not None else 1,
                "subscription_status": sub.get_status_display() if sub is not None else "-",
                "payment_status": _subscription_payment_status_label(sub),
                "invoice_code": getattr(getattr(sub, "invoice", None), "code", "") or "-",
                "subscription_id": getattr(sub, "id", None),
                "can_activate": bool(
                    sub is not None
                    and sub.status == SubscriptionStatus.AWAITING_REVIEW
                    and getattr(getattr(sub, "invoice", None), "is_payment_effective", lambda: False)()
                ),
            }
        )
    return rows


def _subscription_account_rows(subscriptions: list[Subscription]) -> list[dict]:
    unified_map: dict[int, UnifiedRequest] = {}
    source_ids = [str(sub.id) for sub in subscriptions]
    if source_ids:
        for row in UnifiedRequest.objects.select_related("assigned_user").filter(
            request_type=UnifiedRequestType.SUBSCRIPTION,
            source_object_id__in=source_ids,
        ):
            try:
                unified_map[int(str(row.source_object_id or "").strip())] = row
            except (TypeError, ValueError):
                continue

    exact_invoice_map, latest_effective_by_user = _subscription_invoice_fallback_maps(subscriptions)

    rows: list[dict] = []
    for sub in subscriptions:
        request_obj = unified_map.get(int(sub.id))
        priority_number = _subscription_priority_number_for_plan(sub.plan)
        invoice = _resolved_subscription_invoice(
            sub,
            exact_invoice_map=exact_invoice_map,
            latest_effective_by_user=latest_effective_by_user,
        )
        resolved_end_at = _resolved_subscription_end_at(sub)
        delete_disabled_reason = _subscription_account_delete_disabled_reason(sub)
        provider_profile = getattr(getattr(sub, "user", None), "provider_profile", None)
        rows.append(
            {
                "id": sub.id,
                "request_id": getattr(request_obj, "id", None),
                "request_code": (getattr(request_obj, "code", "") or f"SD{sub.id:06d}"),
                "requester": _promo_requester_label(sub.user),
                "provider_name": _subscription_provider_name(sub),
                "priority_number": priority_number,
                "priority_class": _priority_row_class_from_number(priority_number),
                "plan_title": getattr(sub.plan, "title", "") or getattr(sub.plan, "code", "") or "-",
                "plan_code": getattr(sub.plan, "code", "") or "-",
                "tier_label": dict(PlanTier.choices).get(getattr(sub.plan, "tier", ""), getattr(sub.plan, "tier", "-") or "-"),
                "duration_count": int(getattr(sub, "duration_count", 1) or 1),
                "duration_label": _subscription_duration_label(getattr(sub, "plan", None), getattr(sub, "duration_count", 1)),
                "status": sub.get_status_display(),
                "invoice_code": getattr(invoice, "code", "") or "-",
                "start_at": _format_dt(sub.start_at),
                "end_at": _format_dt(resolved_end_at),
                "grace_end_at": _format_dt(sub.grace_end_at),
                "updated_at": _format_dt(sub.updated_at),
                "assignee": _subscription_request_assignee_label(request_obj),
                "payment_effective": bool(invoice is not None and invoice.is_payment_effective()),
                "payment_message": _subscription_payment_message(sub, invoice=invoice),
                "can_renew": provider_profile is not None,
                "renew_disabled_reason": "" if provider_profile is not None else "لا يمكن إنشاء طلب تجديد قبل اكتمال ملف مزود الخدمة.",
                "can_delete": delete_disabled_reason == "",
                "delete_disabled_reason": delete_disabled_reason,
                "is_current": sub.status in {SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE},
            }
        )
    return rows


def _subscription_requests_summary(rows: list[dict]) -> dict:
    by_status: dict[str, int] = {}
    for row in rows:
        key = str(row.get("request_status_code") or "").strip().lower()
        by_status[key] = by_status.get(key, 0) + 1
    return {
        "total": len(rows),
        "new": by_status.get(UnifiedRequestStatus.NEW, 0),
        "in_progress": by_status.get(UnifiedRequestStatus.IN_PROGRESS, 0),
        "completed": by_status.get(UnifiedRequestStatus.CLOSED, 0),
    }


def _subscription_accounts_summary(rows: list[Subscription]) -> dict:
    by_status: dict[str, int] = {}
    for row in rows:
        key = str(row.status or "").strip().lower()
        by_status[key] = by_status.get(key, 0) + 1
    return {
        "total": len(rows),
        "pending_payment": by_status.get(SubscriptionStatus.PENDING_PAYMENT, 0),
        "awaiting_review": by_status.get(SubscriptionStatus.AWAITING_REVIEW, 0),
        "active": by_status.get(SubscriptionStatus.ACTIVE, 0),
        "grace": by_status.get(SubscriptionStatus.GRACE, 0),
        "expired": by_status.get(SubscriptionStatus.EXPIRED, 0),
        "cancelled": by_status.get(SubscriptionStatus.CANCELLED, 0),
    }


@dashboard_staff_required
@require_dashboard_access("subs")
def subscription_dashboard(request):
    subscription_team = _support_team_for_dashboard("subs", fallback_codes=["subs", "finance"])
    can_write = dashboard_allowed(request.user, "subs", write=True)
    assignee_choices = _dashboard_assignee_choices("subs")
    plan_choices = _subscription_request_plan_choices()
    subscription_team_name = getattr(subscription_team, "name_ar", "فريق إدارة الاشتراكات")

    if request.method == "POST":
        if not can_write:
            return HttpResponseForbidden("لا تملك صلاحية تعديل طلبات الاشتراكات.")

        action = (request.POST.get("action") or "").strip()
        redirect_query = (request.POST.get("redirect_query") or "").strip()
        redirect_url = reverse("dashboard:subscription_dashboard")
        if redirect_query:
            redirect_url = f"{redirect_url}?{redirect_query}"

        if action == "save_subscription_request":
            raw_request_id = (request.POST.get("request_id") or "").strip()
            if not raw_request_id.isdigit():
                messages.error(request, "تعذر تحديد طلب الاشتراك المطلوب تحديثه.")
                return _subscription_request_redirect_with_state(request)

            target_request = (
                _subscription_unified_queryset_for_user(request.user)
                .filter(
                    request_type=UnifiedRequestType.SUBSCRIPTION,
                    source_app="subscriptions",
                    source_model="Subscription",
                    id=int(raw_request_id),
                )
                .select_related("requester", "assigned_user", "metadata_record")
                .first()
            )
            if target_request is None:
                messages.error(request, "طلب الاشتراك المحدد غير متاح لهذا الحساب.")
                return _subscription_request_redirect_with_state(request)

            raw_subscription_id = str(target_request.source_object_id or "").strip()
            if not raw_subscription_id.isdigit():
                messages.error(request, "تعذر تحديد سجل الاشتراك المرتبط بهذا الطلب.")
                return _subscription_request_redirect_with_state(request, request_id=target_request.id)

            post_form = SubscriptionRequestActionForm(
                request.POST,
                assignee_choices=assignee_choices,
                plan_choices=plan_choices,
            )
            if not post_form.is_valid():
                messages.error(request, "يرجى مراجعة حقول تفاصيل طلب الاشتراك.")
                return _subscription_request_redirect_with_state(request, request_id=target_request.id)

            assigned_to_raw = (post_form.cleaned_data.get("assigned_to") or "").strip()
            if not assigned_to_raw.isdigit():
                messages.error(request, "يرجى اختيار المكلف بالطلب من فريق إدارة الاشتراكات.")
                return _subscription_request_redirect_with_state(request, request_id=target_request.id)

            assigned_to_id = int(assigned_to_raw)
            assignee = dashboard_assignee_user(assigned_to_id, "subs", write=True)
            if assignee is None:
                messages.error(request, "المكلف المختار لا يملك صلاحية لوحة الاشتراكات.")
                return _subscription_request_redirect_with_state(request, request_id=target_request.id)

            target_plan_id = str(post_form.cleaned_data.get("plan_id") or "").strip()
            available_plan_ids = {plan_id for plan_id, _ in plan_choices}
            if target_plan_id not in available_plan_ids:
                messages.error(request, "الباقة المختارة غير متاحة داخل لوحة الاشتراكات.")
                return _subscription_request_redirect_with_state(request, request_id=target_request.id)

            target_plan = SubscriptionPlan.objects.filter(pk=int(target_plan_id), is_active=True).first()
            if target_plan is None:
                messages.error(request, "تعذر العثور على الباقة المطلوبة.")
                return _subscription_request_redirect_with_state(request, request_id=target_request.id)

            try:
                duration_count = normalize_subscription_duration_count(post_form.cleaned_data.get("duration_count"))
            except ValueError as exc:
                messages.error(request, str(exc))
                return _subscription_request_redirect_with_state(request, request_id=target_request.id)

            desired_status = str(post_form.cleaned_data.get("status") or UnifiedRequestStatus.NEW).strip().lower()
            if desired_status not in {UnifiedRequestStatus.NEW, UnifiedRequestStatus.IN_PROGRESS, UnifiedRequestStatus.CLOSED}:
                desired_status = UnifiedRequestStatus.NEW

            with transaction.atomic():
                sub = (
                    Subscription.objects.select_for_update()
                    .filter(pk=int(raw_subscription_id))
                    .first()
                )
                if sub is None:
                    messages.error(request, "الاشتراك المرتبط بطلب التشغيل غير موجود.")
                    return _subscription_request_redirect_with_state(request, request_id=target_request.id)

                request_status_code = _subscription_request_operational_status(sub, target_request)
                if request_status_code == UnifiedRequestStatus.CLOSED or sub.status in {SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE}:
                    messages.warning(request, "هذا الطلب مكتمل بالفعل وتم نقل معالجته إلى بيانات حسابات المشتركين.")
                    return _subscription_request_redirect_with_state(
                        request,
                        account_id=sub.id,
                        anchor="subscriberAccounts",
                        tab=SUBSCRIPTION_DASHBOARD_TAB_ACCOUNTS,
                    )

                update_fields: list[str] = []
                if sub.plan_id != target_plan.id:
                    sub.plan = target_plan
                    update_fields.append("plan")
                if int(sub.duration_count or 1) != duration_count:
                    sub.duration_count = duration_count
                    update_fields.append("duration_count")
                if update_fields:
                    update_fields.append("updated_at")
                    sub.save(update_fields=update_fields)

                payment_effective = bool(sub.invoice and sub.invoice.is_payment_effective())
                if not is_valid_transition(
                    request_type=UnifiedRequestType.SUBSCRIPTION,
                    from_status=request_status_code,
                    to_status=desired_status,
                ):
                    if request_status_code == UnifiedRequestStatus.NEW and desired_status == UnifiedRequestStatus.CLOSED:
                        messages.error(request, "يجب نقل طلب الاشتراك أولًا إلى تحت المعالجة قبل تحويله إلى مكتمل.")
                    else:
                        messages.error(request, "تسلسل حالة الطلب غير صحيح لطلب الاشتراك الحالي.")
                    return _subscription_request_redirect_with_state(request, request_id=target_request.id)
                if desired_status == UnifiedRequestStatus.CLOSED and not payment_effective:
                    messages.error(request, "لا يمكن إكمال طلب الاشتراك قبل اعتماد الدفع.")
                    return _subscription_request_redirect_with_state(request, request_id=target_request.id)

                upsert_unified_request(
                    request_type=UnifiedRequestType.SUBSCRIPTION,
                    requester=sub.user,
                    source_app="subscriptions",
                    source_model="Subscription",
                    source_object_id=sub.id,
                    status=desired_status,
                    priority=_subscription_unified_priority_for_plan(sub.plan),
                    summary=f"اشتراك {getattr(sub.plan, 'title', getattr(sub.plan, 'code', ''))}".strip(),
                    metadata={
                        "subscription_id": sub.id,
                        "plan_id": sub.plan_id,
                        "plan_code": getattr(sub.plan, "code", "") or "",
                        "subscription_status": sub.status,
                        "invoice_id": sub.invoice_id,
                        "duration_count": sub.duration_count,
                        "start_at": sub.start_at.isoformat() if sub.start_at else None,
                        "end_at": sub.end_at.isoformat() if sub.end_at else None,
                        "grace_end_at": sub.grace_end_at.isoformat() if sub.grace_end_at else None,
                    },
                    assigned_team_code="subs",
                    assigned_team_name=subscription_team_name,
                    assigned_user=assignee,
                    changed_by=request.user,
                )

                if desired_status == UnifiedRequestStatus.CLOSED:
                    if sub.status != SubscriptionStatus.AWAITING_REVIEW:
                        sub = apply_effective_payment(sub=sub)
                    sub = activate_subscription_after_payment(
                        sub=sub,
                        changed_by=request.user,
                        assigned_user=assignee,
                    )
                    messages.success(request, "تم حفظ تفاصيل الطلب وتفعيل الاشتراك بنجاح، وتم نقل الطلب إلى بيانات حسابات المشتركين.")
                    return _subscription_request_redirect_with_state(
                        request,
                        account_id=sub.id,
                        anchor="subscriberAccounts",
                        tab=SUBSCRIPTION_DASHBOARD_TAB_ACCOUNTS,
                    )

            messages.success(request, f"تم تحديث طلب الاشتراك {target_request.code or target_request.id} بنجاح.")
            return _subscription_request_redirect_with_state(request, request_id=target_request.id)

        if action == "save_subscription_inquiry":
            raw_ticket_id = (request.POST.get("ticket_id") or "").strip()
            if not raw_ticket_id.isdigit():
                messages.error(request, "تعذر تحديد الاستفسار المطلوب تحديثه.")
                return _subscription_redirect_with_state(request)

            target_ticket = _support_queryset_for_user(request.user).filter(
                ticket_type=SupportTicketType.SUBS,
                id=int(raw_ticket_id),
            ).first()
            if target_ticket is None:
                messages.error(request, "الاستفسار المحدد غير متاح لهذا الحساب.")
                return _subscription_redirect_with_state(request)

            access_profile = active_access_profile_for_user(request.user)
            if access_profile and access_profile.level == AccessLevel.USER:
                if target_ticket.assigned_to_id and target_ticket.assigned_to_id != request.user.id:
                    return HttpResponseForbidden("غير مصرح: الاستفسار ليس ضمن المهام المكلف بها.")

            post_form = SubscriptionInquiryActionForm(request.POST, assignee_choices=assignee_choices)
            if not post_form.is_valid():
                messages.error(request, "يرجى مراجعة حقول تفاصيل استفسار الاشتراك.")
                return _subscription_redirect_with_state(request, inquiry_id=target_ticket.id)

            assigned_to_raw = (post_form.cleaned_data.get("assigned_to") or "").strip()
            assigned_to_id = int(assigned_to_raw) if assigned_to_raw.isdigit() else target_ticket.assigned_to_id
            if assigned_to_id is not None:
                assignee = dashboard_assignee_user(assigned_to_id, "subs", write=True)
                if assignee is None:
                    messages.error(request, "المكلف المختار لا يملك صلاحية لوحة الاشتراكات.")
                    return _subscription_redirect_with_state(request, inquiry_id=target_ticket.id)

            team_id = subscription_team.id if subscription_team is not None else target_ticket.assigned_team_id
            note = post_form.cleaned_data.get("operator_comment") or ""
            target_ticket = assign_ticket(
                ticket=target_ticket,
                team_id=team_id,
                user_id=assigned_to_id,
                by_user=request.user,
                note=note,
            )

            new_description = post_form.cleaned_data.get("description") or target_ticket.description or ""
            if new_description != (target_ticket.description or ""):
                target_ticket.description = new_description
                target_ticket.last_action_by = request.user
                target_ticket.save(update_fields=["description", "last_action_by", "updated_at"])

            desired_status = post_form.cleaned_data.get("status")
            if desired_status and desired_status != target_ticket.status:
                try:
                    target_ticket = change_ticket_status(
                        ticket=target_ticket,
                        new_status=desired_status,
                        by_user=request.user,
                        note=note,
                    )
                except ValueError as exc:
                    messages.error(request, str(exc))
                    return _subscription_redirect_with_state(request, inquiry_id=target_ticket.id)

            profile, _ = SubscriptionInquiryProfile.objects.get_or_create(ticket=target_ticket)
            profile.operator_comment = note[:300]
            profile.save(update_fields=["operator_comment", "updated_at"])

            messages.success(request, f"تم تحديث استفسار الاشتراك {target_ticket.code or target_ticket.id} بنجاح.")
            return _subscription_redirect_with_state(request, inquiry_id=target_ticket.id)

        if action == "renew_subscription_account":
            raw_subscription_id = (request.POST.get("subscription_id") or "").strip()
            if not raw_subscription_id.isdigit():
                messages.error(request, "تعذر تحديد الاشتراك المطلوب تجديده.")
                return _subscription_request_redirect_with_state(
                    request,
                    anchor="subscriberAccounts",
                    tab=SUBSCRIPTION_DASHBOARD_TAB_ACCOUNTS,
                )

            target_sub = _subscription_accounts_queryset_for_user(request.user).filter(pk=int(raw_subscription_id)).first()
            if target_sub is None:
                messages.error(request, "الاشتراك المطلوب غير متاح لك.")
                return _subscription_request_redirect_with_state(
                    request,
                    anchor="subscriberAccounts",
                    tab=SUBSCRIPTION_DASHBOARD_TAB_ACCOUNTS,
                )

            try:
                renewal_sub = start_subscription_renewal_checkout(user=target_sub.user, plan=target_sub.plan)
            except PermissionError as exc:
                messages.error(request, str(exc))
                return _subscription_request_redirect_with_state(
                    request,
                    account_id=target_sub.id,
                    anchor="subscriberAccounts",
                    tab=SUBSCRIPTION_DASHBOARD_TAB_ACCOUNTS,
                )

            renewal_request = (
                UnifiedRequest.objects.filter(
                    request_type=UnifiedRequestType.SUBSCRIPTION,
                    source_app="subscriptions",
                    source_model="Subscription",
                    source_object_id=str(renewal_sub.id),
                )
                .order_by("-id")
                .first()
            )

            if renewal_sub.id == target_sub.id and renewal_sub.status in {SubscriptionStatus.PENDING_PAYMENT, SubscriptionStatus.AWAITING_REVIEW}:
                messages.info(request, "يوجد طلب تجديد قائم بالفعل لهذه الباقة.")
            else:
                messages.success(request, "تم إنشاء طلب تجديد الباقة بنجاح.")

            return redirect(
                _subscription_dashboard_url_with_state(
                    request,
                    request_id=getattr(renewal_request, "id", None),
                    account_id=None,
                    anchor="subscriptionRequests",
                    query=redirect_query,
                    tab=SUBSCRIPTION_DASHBOARD_TAB_OPERATIONS,
                )
            )

        if action == "delete_subscription_account":
            raw_subscription_id = (request.POST.get("subscription_id") or "").strip()
            if not raw_subscription_id.isdigit():
                messages.error(request, "تعذر تحديد الباقة المطلوب حذفها.")
                return _subscription_request_redirect_with_state(
                    request,
                    anchor="subscriberAccounts",
                    tab=SUBSCRIPTION_DASHBOARD_TAB_ACCOUNTS,
                )

            target_sub = _subscription_accounts_queryset_for_user(request.user).filter(pk=int(raw_subscription_id)).first()
            if target_sub is None:
                messages.error(request, "الباقة المطلوبة غير متاحة لك.")
                return _subscription_request_redirect_with_state(
                    request,
                    anchor="subscriberAccounts",
                    tab=SUBSCRIPTION_DASHBOARD_TAB_ACCOUNTS,
                )

            try:
                delete_subscription_account_for_dashboard(sub=target_sub, changed_by=request.user)
            except ValueError as exc:
                messages.error(request, str(exc))
                return _subscription_request_redirect_with_state(
                    request,
                    account_id=target_sub.id,
                    anchor="subscriberAccounts",
                    tab=SUBSCRIPTION_DASHBOARD_TAB_ACCOUNTS,
                )

            messages.success(request, "تم حذف الباقة من بيانات حسابات المشتركين.")
            return _subscription_request_redirect_with_state(
                request,
                account_id=None,
                anchor="subscriberAccounts",
                tab=SUBSCRIPTION_DASHBOARD_TAB_ACCOUNTS,
            )

        if action == "activate_subscription_request":
            raw_subscription_id = (request.POST.get("subscription_id") or "").strip()
            if not raw_subscription_id.isdigit():
                messages.error(request, "تعذر تحديد الاشتراك المطلوب تفعيله.")
                return redirect(f"{redirect_url}#subscriptionRequests")

            sub = Subscription.objects.select_related("invoice").filter(pk=int(raw_subscription_id)).first()
            if sub is None:
                messages.error(request, "الاشتراك المطلوب غير موجود.")
                return redirect(f"{redirect_url}#subscriptionRequests")

            target_request = _subscription_unified_queryset_for_user(request.user).filter(
                source_app="subscriptions",
                source_model="Subscription",
                source_object_id=str(sub.id),
            ).select_related("assigned_user").first()
            if target_request is None:
                messages.error(request, "هذا الطلب غير متاح لك.")
                return redirect(f"{redirect_url}#subscriptionRequests")

            operational_status = _subscription_request_operational_status(sub, target_request)
            if operational_status == UnifiedRequestStatus.NEW:
                messages.error(request, "يجب نقل طلب الاشتراك أولًا إلى تحت المعالجة قبل اعتماده كمكتمل وتفعيل الاشتراك.")
                return redirect(f"{redirect_url}#subscriptionRequests")
            if operational_status == UnifiedRequestStatus.CLOSED or sub.status in {SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE}:
                messages.warning(request, "تمت معالجة هذا الطلب مسبقًا ونقله إلى بيانات حسابات المشتركين.")
                return redirect(
                    _subscription_dashboard_url_with_state(
                        request,
                        account_id=sub.id,
                        anchor="subscriberAccounts",
                        query=redirect_query,
                        tab=SUBSCRIPTION_DASHBOARD_TAB_ACCOUNTS,
                    )
                )

            try:
                if sub.status != SubscriptionStatus.AWAITING_REVIEW:
                    sub = apply_effective_payment(sub=sub)
                activate_subscription_after_payment(
                    sub=sub,
                    changed_by=request.user,
                    assigned_user=target_request.assigned_user or request.user,
                )
            except ValueError as exc:
                messages.error(request, str(exc))
            else:
                messages.success(request, "تم اعتماد الطلب وتفعيل الاشتراك بنجاح.")

            return redirect(
                _subscription_dashboard_url_with_state(
                    request,
                    account_id=sub.id,
                    anchor="subscriberAccounts",
                    query=redirect_query,
                    tab=SUBSCRIPTION_DASHBOARD_TAB_ACCOUNTS,
                )
            )

    inquiry_q = (request.GET.get("inquiry_q") or "").strip()
    request_q = (request.GET.get("request_q") or "").strip()
    account_q = (request.GET.get("account_q") or "").strip()
    requested_tab = (request.GET.get("tab") or "").strip().lower()
    active_tab = (
        requested_tab
        if requested_tab in {SUBSCRIPTION_DASHBOARD_TAB_OPERATIONS, SUBSCRIPTION_DASHBOARD_TAB_ACCOUNTS}
        else SUBSCRIPTION_DASHBOARD_TAB_OPERATIONS
    )
    request_status_filter = canonical_status_for_workflow(
        request_type=UnifiedRequestType.SUBSCRIPTION,
        status=(request.GET.get("request_status") or "").strip(),
    )
    account_status_filter = (request.GET.get("account_status") or "").strip()
    focused_account_id_raw = (request.GET.get("account") or "").strip()
    focused_account_id = int(focused_account_id_raw) if focused_account_id_raw.isdigit() else None

    subscription_inquiries_base_qs = _support_queryset_for_user(request.user).filter(ticket_type=SupportTicketType.SUBS)
    selected_inquiry_id_raw = (request.GET.get("inquiry") or "").strip()
    selected_inquiry = (
        subscription_inquiries_base_qs.filter(id=int(selected_inquiry_id_raw)).first()
        if selected_inquiry_id_raw.isdigit()
        else None
    )

    subscription_inquiries_qs = subscription_inquiries_base_qs
    if inquiry_q:
        subscription_inquiries_qs = subscription_inquiries_qs.filter(
            Q(code__icontains=inquiry_q)
            | Q(description__icontains=inquiry_q)
            | Q(requester__provider_profile__display_name__icontains=inquiry_q)
            | Q(requester__username__icontains=inquiry_q)
            | Q(requester__phone__icontains=inquiry_q)
        )
    subscription_inquiries = list(subscription_inquiries_qs.order_by("-created_at", "-id"))
    inquiry_profile = getattr(selected_inquiry, "subscription_profile", None) if selected_inquiry else None
    inquiry_form = SubscriptionInquiryActionForm(
        initial={
            "status": selected_inquiry.status if selected_inquiry else SupportTicketStatus.NEW,
            "assigned_to": str(selected_inquiry.assigned_to_id or "") if selected_inquiry else "",
            "description": (selected_inquiry.description or "") if selected_inquiry else "",
            "operator_comment": (inquiry_profile.operator_comment or "") if inquiry_profile else "",
        },
        assignee_choices=assignee_choices,
    )

    subscription_requests_base_qs = _subscription_unified_queryset_for_user(request.user).filter(
        request_type=UnifiedRequestType.SUBSCRIPTION,
        source_app="subscriptions",
        source_model="Subscription",
    )
    selected_request_id_raw = (request.GET.get("request") or "").strip()
    selected_request = (
        subscription_requests_base_qs.filter(id=int(selected_request_id_raw)).first()
        if selected_request_id_raw.isdigit()
        else None
    )

    selected_request_subscription = None
    if selected_request is not None:
        raw_subscription_id = str(selected_request.source_object_id or "").strip()
        if raw_subscription_id.isdigit():
            selected_request_subscription = (
                Subscription.objects.select_related("user", "user__provider_profile", "plan", "invoice")
                .filter(pk=int(raw_subscription_id))
                .first()
            )

    selected_request_status_code = _subscription_request_operational_status(
        selected_request_subscription,
        selected_request,
    ) if selected_request is not None else UnifiedRequestStatus.NEW
    selected_request_is_completed = bool(
        selected_request is not None
        and (
            selected_request_status_code == UnifiedRequestStatus.CLOSED
            or getattr(selected_request_subscription, "status", None) in {SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE}
        )
    )
    selected_request_form = (
        SubscriptionRequestActionForm(
            initial={
                "status": selected_request_status_code,
                "assigned_to": str(getattr(selected_request, "assigned_user_id", "") or ""),
                "plan_id": str(getattr(selected_request_subscription, "plan_id", "") or ""),
                "duration_count": int(getattr(selected_request_subscription, "duration_count", 1) or 1),
            },
            assignee_choices=assignee_choices,
            plan_choices=plan_choices,
        )
        if selected_request is not None and selected_request_subscription is not None
        else None
    )

    request_query_params = request.GET.copy()
    request_query_params.pop("request", None)
    request_query_params.pop("account", None)
    request_detail_base_query = request_query_params.urlencode()
    close_request_url = _subscription_dashboard_url_with_state(
        request,
        request_id=None,
        account_id=None,
        anchor="subscriptionRequests",
        tab=SUBSCRIPTION_DASHBOARD_TAB_OPERATIONS,
    )
    account_query_params = request.GET.copy()
    account_query_params.pop("account", None)
    account_detail_base_query = account_query_params.urlencode()
    close_account_url = _subscription_dashboard_url_with_state(
        request,
        request_id=selected_request.id if selected_request is not None else None,
        account_id=None,
        anchor="subscriberAccounts",
        tab=SUBSCRIPTION_DASHBOARD_TAB_ACCOUNTS,
    )

    subscription_requests_qs = subscription_requests_base_qs
    if request_q:
        subscription_requests_qs = subscription_requests_qs.filter(
            Q(code__icontains=request_q)
            | Q(summary__icontains=request_q)
            | Q(requester__provider_profile__display_name__icontains=request_q)
            | Q(requester__username__icontains=request_q)
            | Q(requester__phone__icontains=request_q)
        )
    subscription_requests = list(subscription_requests_qs)
    subscription_request_rows = _subscription_request_rows(subscription_requests)
    if request_status_filter:
        subscription_request_rows = [
            row for row in subscription_request_rows if row.get("request_status_code") == request_status_filter
        ]
    for row in subscription_request_rows:
        row["is_selected"] = bool(selected_request is not None and row.get("id") == selected_request.id)

    subscription_accounts_qs = _subscription_accounts_queryset_for_user(request.user)
    if account_q:
        subscription_accounts_qs = subscription_accounts_qs.filter(
            Q(user__provider_profile__display_name__icontains=account_q)
            | Q(user__username__icontains=account_q)
            | Q(user__phone__icontains=account_q)
            | Q(plan__title__icontains=account_q)
            | Q(plan__code__icontains=account_q)
            | Q(invoice__code__icontains=account_q)
        )
    if account_status_filter:
        subscription_accounts_qs = subscription_accounts_qs.filter(status=account_status_filter)
    subscription_accounts = list(subscription_accounts_qs)
    subscription_account_rows = _subscription_account_rows(subscription_accounts)
    for row in subscription_account_rows:
        row["is_selected"] = bool(focused_account_id is not None and row.get("id") == focused_account_id)

    latest_helpdesk_code = (
        SupportTicket.objects.filter(ticket_type=SupportTicketType.SUBS)
        .exclude(code="")
        .order_by("-id")
        .values_list("code", flat=True)
        .first()
        or "HD000001"
    )

    context = {
        "hero_title": "لوحة فريق إدارة الاشتراكات",
        "hero_subtitle": "تشغيل استفسارات الاشتراكات وطلبات الترقية والاشتراك من لوحة موحدة مع صفحة فرعية مستقلة لبيانات حسابات المشتركين.",
        "can_write": can_write,
        "nav_items": _subscription_nav_items(active_tab),
        "subscription_team_label": subscription_team_name,
        "subscription_inquiries": _subscription_inquiry_rows(subscription_inquiries),
        "subscription_requests": subscription_request_rows,
        "subscription_accounts": subscription_account_rows,
        "selected_inquiry": selected_inquiry,
        "selected_inquiry_requester_name": _promo_requester_label(selected_inquiry.requester) if selected_inquiry else "",
        "selected_inquiry_status_label": _subscription_inquiry_status_label(
            selected_inquiry.status if selected_inquiry else ""
        ),
        "selected_request": selected_request,
        "selected_request_requester_name": _promo_requester_label(selected_request.requester) if selected_request else "",
        "selected_request_subscription": selected_request_subscription,
        "selected_request_status_label": _subscription_request_status_label(selected_request_status_code),
        "selected_request_form": selected_request_form,
        "selected_request_can_save": bool(can_write and not selected_request_is_completed and selected_request_form is not None),
        "selected_request_content_text": _subscription_request_content_text(selected_request_subscription, selected_request)
        if selected_request is not None
        else "",
        "selected_request_payment_status_label": _subscription_payment_status_label(selected_request_subscription)
        if selected_request is not None
        else "",
        "selected_request_close_url": close_request_url,
        "request_detail_base_query": request_detail_base_query,
        "selected_account_close_url": close_account_url,
        "account_detail_base_query": account_detail_base_query,
        "inquiry_form": inquiry_form,
        "close_inquiry_url": _subscription_close_inquiry_url(request),
        "inquiry_summary": _support_summary(subscription_inquiries),
        "request_summary": _subscription_requests_summary(subscription_request_rows),
        "account_summary": _subscription_accounts_summary(subscription_accounts),
        "request_codes": [
            {"code": latest_helpdesk_code, "label": "استفسارات الاشتراكات"},
            {"code": _latest_request_code("SD", request_type=UnifiedRequestType.SUBSCRIPTION), "label": "طلبات الترقية والاشتراكات"},
        ],
        "filters": {
            "tab": active_tab,
            "inquiry_q": inquiry_q,
            "request_q": request_q,
            "account_q": account_q,
            "request_status": request_status_filter,
            "account_status": account_status_filter,
        },
        "request_status_choices": SUBSCRIPTION_REQUEST_STATUS_CHOICES,
        "account_status_choices": SubscriptionStatus.choices,
        "redirect_query": request.GET.urlencode(),
    }
    return render(request, "dashboard/subscription_dashboard.html", context)


EXTRAS_REQUEST_STATUS_CHOICES = [
    (UnifiedRequestStatus.NEW, "جديد"),
    (UnifiedRequestStatus.IN_PROGRESS, "تحت المعالجة"),
    (UnifiedRequestStatus.CLOSED, "مكتمل"),
]

EXTRAS_REQUEST_ALLOWED_TRANSITIONS = {
    UnifiedRequestStatus.NEW: (UnifiedRequestStatus.NEW, UnifiedRequestStatus.IN_PROGRESS),
    UnifiedRequestStatus.IN_PROGRESS: (UnifiedRequestStatus.IN_PROGRESS, UnifiedRequestStatus.CLOSED),
    UnifiedRequestStatus.CLOSED: (UnifiedRequestStatus.CLOSED,),
}


def _extras_vat_percent():
    """Return the current extras VAT percent from PlatformConfig."""
    from apps.core.models import PlatformConfig
    return PlatformConfig.load().extras_vat_percent


def _parse_manual_invoice_lines(post_data) -> list[dict]:
    """Extract manual invoice line items from POST data.

    Expects pairs of ``invoice_line_title[]`` and ``invoice_line_amount[]``.
    Blank rows are silently skipped.  Returns a list of dicts with ``title``
    and ``amount`` keys for non-empty rows.
    """
    from decimal import Decimal, InvalidOperation

    titles = post_data.getlist("invoice_line_title[]")
    amounts = post_data.getlist("invoice_line_amount[]")
    lines: list[dict] = []
    for title_raw, amount_raw in zip(titles, amounts):
        title = str(title_raw or "").strip()[:160]
        amount_str = str(amount_raw or "").strip()
        if not title and not amount_str:
            continue
        try:
            amount = Decimal(amount_str)
        except (InvalidOperation, ValueError):
            amount = Decimal("0")
        if title and amount > Decimal("0"):
            lines.append({"title": title, "amount": amount})
    return lines


def _extras_request_status_choices_for(current_status: str):
    normalized_status = canonical_status_for_workflow(
        request_type=UnifiedRequestType.EXTRAS,
        status=current_status,
    )
    label_by_status = dict(EXTRAS_REQUEST_STATUS_CHOICES)
    return [
        (status_code, label_by_status.get(status_code, status_code))
        for status_code in EXTRAS_REQUEST_ALLOWED_TRANSITIONS.get(normalized_status, (normalized_status,))
    ]


def _extras_request_status_help_text(current_status: str) -> str:
    normalized_status = canonical_status_for_workflow(
        request_type=UnifiedRequestType.EXTRAS,
        status=current_status,
    )
    if normalized_status == UnifiedRequestStatus.NEW:
        return "المتاح الآن: إبقاء الطلب جديدًا أو نقله إلى تحت المعالجة فقط."
    if normalized_status == UnifiedRequestStatus.IN_PROGRESS:
        return "المتاح الآن: إبقاء الطلب تحت المعالجة أو نقله إلى مكتمل فقط."
    return "الطلب مكتمل، ولا يمكن نقله إلى حالة أخرى."


def _extras_support_team() -> SupportTeam | None:
    return _support_team_for_dashboard("extras", fallback_codes=["extras"])


def _extras_team_name(team: SupportTeam | None) -> str:
    return getattr(team, "name_ar", "فريق إدارة الخدمات الإضافية")


def _extras_inquiries_queryset_for_user(user):
    return _support_queryset_for_user(user).filter(
        _support_ticket_dashboard_q("extras", fallback_team_codes=["extras"])
        | Q(assigned_team__isnull=True, ticket_type=SupportTicketType.EXTRAS)
    ).distinct()


def _extras_unified_queryset_for_user(user):
    qs = (
        UnifiedRequest.objects.select_related("requester", "requester__provider_profile", "assigned_user", "metadata_record")
        .filter(request_type=UnifiedRequestType.EXTRAS)
        .order_by("-updated_at", "-id")
    )
    access_profile = active_access_profile_for_user(user)
    if access_profile and access_profile.level == AccessLevel.USER:
        qs = qs.filter(Q(assigned_user=user) | Q(assigned_user__isnull=True))
    return qs


def _extras_purchase_map(unified_requests: list[UnifiedRequest]) -> dict[int, ExtraPurchase]:
    purchase_ids: list[int] = []
    for request_obj in unified_requests:
        raw_purchase_id = str(request_obj.source_object_id or "").strip()
        if not raw_purchase_id.isdigit():
            continue
        purchase_ids.append(int(raw_purchase_id))
    if not purchase_ids:
        return {}
    return {
        purchase.id: purchase
        for purchase in ExtraPurchase.objects.select_related("user", "user__provider_profile", "invoice").filter(id__in=purchase_ids)
    }


def _extras_request_status_label(status_code: str) -> str:
    normalized = str(status_code or "").strip().lower()
    return {
        UnifiedRequestStatus.NEW: "جديد",
        UnifiedRequestStatus.IN_PROGRESS: "تحت المعالجة",
        UnifiedRequestStatus.RETURNED: "معاد للعميل",
        UnifiedRequestStatus.CLOSED: "مكتمل",
    }.get(normalized, "جديد")


def _extras_payment_status_label(purchase: ExtraPurchase | None) -> str:
    if purchase is None:
        return "-"
    invoice = getattr(purchase, "invoice", None)
    if invoice is None:
        return "لا توجد فاتورة"
    if invoice.is_payment_effective():
        return "مدفوع ومعتمد"
    return invoice.get_status_display()


def _extras_request_operator_comment(request_obj: UnifiedRequest | None) -> str:
    payload = getattr(getattr(request_obj, "metadata_record", None), "payload", None)
    if not isinstance(payload, dict):
        return ""
    return str(payload.get("operator_comment", "") or "").strip()[:300]


def _extras_request_active_bundle_sections(request_obj: UnifiedRequest | None) -> list[dict]:
    if request_obj is None:
        return []
    sections: list[dict] = []
    for section in extras_bundle_detail_sections_for_request(request_obj):
        section_key = str(section.get("key") or "").strip()
        section_items = list(section.get("items") or [])
        if not section_key or not section_items:
            continue
        sections.append(
            {
                "key": section_key,
                "title": str(section.get("title") or "").strip(),
                "items": section_items,
                "meta_lines": list(section.get("meta_lines") or []),
            }
        )
    return sections


def _extras_request_section_detail(request_obj: UnifiedRequest | None, section_key: str) -> dict | None:
    normalized_key = str(section_key or "").strip().lower()
    if not normalized_key:
        return None
    for section in _extras_request_active_bundle_sections(request_obj):
        if str(section.get("key") or "").strip().lower() == normalized_key:
            return section
    return None


def _extras_request_rows(extras_requests: list[UnifiedRequest]) -> list[dict]:
    purchase_map = _extras_purchase_map(extras_requests)
    subscriptions_by_user_id = _effective_subscriptions_map_for_users(
        [getattr(request_obj, "requester", None) for request_obj in extras_requests]
    )
    rows: list[dict] = []
    for request_obj in extras_requests:
        raw_purchase_id = str(request_obj.source_object_id or "").strip()
        purchase_id = int(raw_purchase_id) if raw_purchase_id.isdigit() else 0
        purchase = purchase_map.get(purchase_id)
        bundle_sections = _extras_request_active_bundle_sections(request_obj)
        request_status_code = canonical_status_for_workflow(
            request_type=UnifiedRequestType.EXTRAS,
            status=request_obj.status,
        )
        priority_number = _dashboard_priority_number_for_user(
            request_obj.requester,
            subscriptions_by_user_id=subscriptions_by_user_id,
        )
        rows.append(
            {
                "id": request_obj.id,
                "code": request_obj.code or f"P{request_obj.id:06d}",
                "requester": _promo_requester_label(request_obj.requester),
                "priority_number": priority_number,
                "priority_class": _dashboard_priority_class_for_user(
                    request_obj.requester,
                    subscriptions_by_user_id=subscriptions_by_user_id,
                ),
                "created_at": _format_dt(getattr(purchase, "created_at", None) or request_obj.created_at),
                "request_status_code": request_status_code,
                "request_status": _extras_request_status_label(request_status_code),
                "assignee": _subscription_request_assignee_label(request_obj),
                "assigned_at": _format_dt(request_obj.assigned_at),
                "service_title": (getattr(purchase, "title", "") or request_obj.summary or "-").strip(),
                "service_sku": getattr(purchase, "sku", "") or "-",
                "purchase_status": purchase.get_status_display() if purchase is not None else "-",
                "purchase_type": purchase.get_extra_type_display() if purchase is not None else "-",
                "payment_status": _extras_payment_status_label(purchase),
                "invoice_code": getattr(getattr(purchase, "invoice", None), "code", "") or "-",
                "bundle_section_keys": [section["key"] for section in bundle_sections],
                "bundle_section_titles": [section["title"] for section in bundle_sections if section.get("title")],
                "bundle_section_titles_text": " / ".join(
                    section["title"] for section in bundle_sections if section.get("title")
                ),
                "bundle_item_count": sum(len(section.get("items") or []) for section in bundle_sections),
                "start_at": _format_dt(getattr(purchase, "start_at", None)),
                "end_at": _format_dt(getattr(purchase, "end_at", None)),
                "credits_total": int(getattr(purchase, "credits_total", 0) or 0),
                "credits_used": int(getattr(purchase, "credits_used", 0) or 0),
                "purchase_id": purchase.id if purchase is not None else None,
            }
        )
    return rows


def _extras_requests_summary(rows: list[dict]) -> dict:
    by_status: dict[str, int] = {}
    for row in rows:
        key = str(row.get("request_status_code") or "").strip().lower()
        by_status[key] = by_status.get(key, 0) + 1
    return {
        "total": len(rows),
        "new": by_status.get(UnifiedRequestStatus.NEW, 0),
        "in_progress": by_status.get(UnifiedRequestStatus.IN_PROGRESS, 0),
        "returned": by_status.get(UnifiedRequestStatus.RETURNED, 0),
        "closed": by_status.get(UnifiedRequestStatus.CLOSED, 0),
    }


def _extras_request_rows_for_section(rows: list[dict], section_key: str) -> list[dict]:
    normalized_key = str(section_key or "").strip().lower()
    if not normalized_key:
        return list(rows)
    return [
        row
        for row in rows
        if normalized_key in {str(value or "").strip().lower() for value in row.get("bundle_section_keys") or []}
    ]


def _extras_dashboard_url_with_state(
    request,
    *,
    inquiry_id: int | None = None,
    request_id: int | None = None,
    anchor: str = "",
    query: str = "",
) -> str:
    raw_query = str(query or request.GET.urlencode()).strip()
    params = QueryDict(raw_query, mutable=True)

    if inquiry_id is None:
        params.pop("inquiry", None)
    else:
        params["inquiry"] = str(inquiry_id)

    if request_id is None:
        params.pop("request", None)
    else:
        params["request"] = str(request_id)

    base = reverse("dashboard:extras_dashboard")
    normalized_query = params.urlencode()
    target = f"{base}?{normalized_query}" if normalized_query else base
    return f"{target}#{anchor}" if anchor else target


def _extras_redirect_with_state(
    request,
    *,
    inquiry_id: int | None = None,
    request_id: int | None = None,
    anchor: str = "extrasInquiries",
):
    query = (request.POST.get("redirect_query") or request.GET.urlencode()).strip()
    return redirect(
        _extras_dashboard_url_with_state(
            request,
            inquiry_id=inquiry_id,
            request_id=request_id,
            anchor=anchor,
            query=query,
        )
    )


def _extras_close_inquiry_url(request, *, selected_request_id: int | None = None) -> str:
    return _extras_dashboard_url_with_state(
        request,
        inquiry_id=None,
        request_id=selected_request_id,
        anchor="extrasInquiries",
    )


def _extras_close_request_url(request, *, selected_inquiry_id: int | None = None) -> str:
    return _extras_dashboard_url_with_state(
        request,
        inquiry_id=selected_inquiry_id,
        request_id=None,
        anchor="extrasRequests",
    )


EXTRAS_DASHBOARD_SECTION_OVERVIEW = "overview"
EXTRAS_DASHBOARD_SECTION_REPORTS = "reports"
EXTRAS_DASHBOARD_SECTION_CLIENTS = "clients"
EXTRAS_DASHBOARD_SECTION_FINANCE = "finance"
EXTRAS_DASHBOARD_SECTION_SUBSCRIBERS = "subscribers"
EXTRAS_DASHBOARD_SECTION_REQUEST_SUMMARY = "request_summary"
EXTRAS_DASHBOARD_SECTION_REQUEST_CREATED = "request_created"
EXTRAS_DASHBOARD_SECTIONS = {
    EXTRAS_DASHBOARD_SECTION_OVERVIEW,
    EXTRAS_DASHBOARD_SECTION_REPORTS,
    EXTRAS_DASHBOARD_SECTION_CLIENTS,
    EXTRAS_DASHBOARD_SECTION_FINANCE,
    EXTRAS_DASHBOARD_SECTION_SUBSCRIBERS,
    EXTRAS_DASHBOARD_SECTION_REQUEST_SUMMARY,
    EXTRAS_DASHBOARD_SECTION_REQUEST_CREATED,
}
EXTRAS_DASHBOARD_MAIN_SECTION = EXTRAS_DASHBOARD_SECTION_OVERVIEW

EXTRAS_REPORT_OPTIONS: tuple[tuple[str, str], ...] = (
    ("platform_metrics", "مؤشرات المنصة"),
    ("platform_visits", "عدد الزيارات لمنصتي"),
    ("platform_favorites", "عدد التفضيلات لمحتوى منصتي"),
    ("orders_breakdown", "عدد الطلبات (الجديدة - تحت التنفيذ - المكتملة - الملغية)"),
    ("platform_shares", "عدد مرات مشاركة منصتي"),
    ("service_requesters", "قائمة بمعرفات من طلب خدماتي"),
    ("potential_clients", "قائمة بمعرفات من تم تميزه كعميل محتمل"),
    ("content_favoriters", "قائمة بمعرفات من عمل تفضيل لمحتوى منصتي"),
    ("platform_followers", "قائمة بمعرفات من عمل متابعة لمنصتي"),
    ("content_sharers", "قائمة بمعرفات من عمل مشاركة لمنصتي"),
    ("positive_reviewers", "قائمة بمعرفات أصحاب التقييم الإيجابي لخدماتي"),
    ("content_commenters", "قائمة بمعرفات المعلقين على محتوى منصتي"),
)

EXTRAS_REPORT_OPTION_GROUPS: tuple[tuple[str, tuple[str, ...]], ...] = (
    (
        "مؤشرات المنصة",
        (
            "platform_metrics",
            "platform_visits",
            "platform_favorites",
            "orders_breakdown",
            "platform_shares",
        ),
    ),
    (
        "القوائم والمعرفات المطلوبة",
        (
            "service_requesters",
            "potential_clients",
            "content_favoriters",
            "platform_followers",
            "content_sharers",
            "positive_reviewers",
            "content_commenters",
        ),
    ),
)

EXTRAS_CLIENT_OPTIONS: tuple[tuple[str, str], ...] = (
    ("platform_clients_list", "قوائم عملاء منصتي"),
    ("historical_clients", "قائمة بجميع العملاء الذين سبق لهم تقديم طلب خدمة تشمل معرفاتهم ووسائل التواصل معهم"),
    ("all_followers", "قائمة بكل متابعي المختص"),
    ("potential_clients_contact", "قائمة بالعملاء المحتملين (المرشحين من قائمة التواصل)"),
    ("export_clients", "تصدير المعلومات إلى ملف PDF أو Excel"),
    ("list_services", "خدمات القوائم"),
    ("grouping", "التصنيف على شكل مجموعات (خدمة محددة - مهم - متكرر ...)"),
    ("bulk_messages", "إرسال الرسائل الجماعية لعملائي"),
    ("recurring_reminders", "خيار تذكير مرتبط بالعملاء وخدمتهم المتكررة (مثل الصيانة الدوري) يشمل مواعيد ورسائل تنبيه"),
    ("loyalty_program", "برنامج الولاء"),
    ("loyalty_points", "وضع نظام نقاط لعملائي مرتبط بعدد طلباتهم"),
)

EXTRAS_FINANCE_OPTIONS: tuple[tuple[str, str], ...] = (
    ("bank_qr_registration", "خدمة تسجيل الحساب البنكي للمختص (QR)"),
    ("electronic_payments", "خدمات الدفع الإلكتروني"),
    ("electronic_invoices", "الفواتير الإلكترونية لعمليات الدفع من خلال منصة مختص"),
    ("financial_statement", "كشف حساب شامل (اسم العميل - التاريخ - المبلغ المستلم - المبلغ الباقي - المبلغ النهائي)"),
    ("finance_export", "تصدير البيانات المالية للعمليات المنفذة من خلال منصة مختص إلى ملف PDF أو Excel"),
)


def _extras_nav_items(active_key: str) -> list[dict]:
    base = reverse("dashboard:extras_dashboard")
    items = [
        {
            "key": EXTRAS_DASHBOARD_SECTION_REPORTS,
            "label": "التقارير",
            "description": "القائمة الفرعية الخاصة بالتقارير.",
            "url": f"{base}?section={EXTRAS_DASHBOARD_SECTION_REPORTS}",
        },
        {
            "key": EXTRAS_DASHBOARD_SECTION_CLIENTS,
            "label": "إدارة العملاء",
            "description": "القائمة الفرعية الخاصة بإدارة العملاء.",
            "url": f"{base}?section={EXTRAS_DASHBOARD_SECTION_CLIENTS}",
        },
        {
            "key": EXTRAS_DASHBOARD_SECTION_FINANCE,
            "label": "الإدارة المالية",
            "description": "القائمة الفرعية الخاصة بالإدارة المالية.",
            "url": f"{base}?section={EXTRAS_DASHBOARD_SECTION_FINANCE}",
        },
        {
            "key": EXTRAS_DASHBOARD_SECTION_SUBSCRIBERS,
            "label": "بيانات مشتركي الخدمات الإضافية",
            "description": "القائمة الفرعية الخاصة بمشتركي الخدمات الإضافية.",
            "url": f"{base}?section={EXTRAS_DASHBOARD_SECTION_SUBSCRIBERS}",
        },
    ]
    for item in items:
        item["active"] = item["key"] == active_key
    return items


def _extras_purchases_queryset_for_user(user):
    qs = ExtraPurchase.objects.select_related("user", "user__provider_profile", "invoice").order_by("-updated_at", "-id")
    access_profile = active_access_profile_for_user(user)
    if access_profile and access_profile.level == AccessLevel.USER:
        allowed_ids: list[int] = []
        for row in _extras_unified_queryset_for_user(user):
            raw_purchase_id = str(row.source_object_id or "").strip()
            if raw_purchase_id.isdigit():
                allowed_ids.append(int(raw_purchase_id))
        if not allowed_ids:
            return qs.none()
        qs = qs.filter(id__in=allowed_ids)
    return qs


def _extras_amount_text(amount, currency: str | None = None) -> str:
    try:
        value = Decimal(amount)
    except (InvalidOperation, TypeError, ValueError):
        return "-"
    currency_code = str(currency or "SAR").strip().upper()
    return f"{value:.2f} {currency_code}".strip()


def _extras_invoice_details(invoice: Invoice | None, *, request_obj: UnifiedRequest | None = None) -> dict | None:
    if invoice is None:
        return None

    latest_attempt = (
        PaymentAttempt.objects.filter(invoice=invoice)
        .exclude(checkout_url="")
        .order_by("-created_at")
        .first()
    )
    checkout_url = ""
    metadata_payload = getattr(getattr(request_obj, "metadata_record", None), "payload", None)
    if isinstance(metadata_payload, dict):
        checkout_url = str(metadata_payload.get("checkout_url") or "").strip()
    if not checkout_url and latest_attempt is not None:
        checkout_url = str(getattr(latest_attempt, "checkout_url", "") or "").strip()
    if checkout_url and request_obj is not None:
        checkout_url = extras_bundle_payment_access_url(
            request_obj=request_obj,
            invoice=invoice,
            checkout_url=checkout_url,
        )

    payment_confirmed_at = getattr(invoice, "payment_confirmed_at", None) or getattr(invoice, "paid_at", None)
    status_label = "مدفوع ومعتمد" if invoice.is_payment_effective() else invoice.get_status_display()

    return {
        "code": getattr(invoice, "code", "") or "-",
        "status_label": status_label,
        "description": str(getattr(invoice, "description", "") or "").strip(),
        "subtotal_text": _extras_amount_text(getattr(invoice, "subtotal", None), getattr(invoice, "currency", None)),
        "vat_percent_text": f"{Decimal(str(getattr(invoice, 'vat_percent', 0) or 0)):.2f}%",
        "vat_amount_text": _extras_amount_text(getattr(invoice, "vat_amount", None), getattr(invoice, "currency", None)),
        "total_text": _extras_amount_text(getattr(invoice, "total", None), getattr(invoice, "currency", None)),
        "created_at": _format_dt(getattr(invoice, "created_at", None)),
        "payment_confirmed_at": _format_dt(payment_confirmed_at),
        "checkout_url": checkout_url,
        "attempt_status": latest_attempt.get_status_display() if latest_attempt is not None else "-",
        "lines": [
            {
                "title": str(line.title or "").strip() or f"بند {index}",
                "amount_text": _extras_amount_text(line.amount, getattr(invoice, "currency", None)),
            }
            for index, line in enumerate(invoice.lines.all(), start=1)
        ],
    }


def _extras_request_billing_state(
    request_obj: UnifiedRequest | None,
    *,
    invoice: Invoice | None = None,
    invoice_details: dict | None = None,
) -> dict:
    normalized_status = (
        canonical_status_for_workflow(
            request_type=UnifiedRequestType.EXTRAS,
            status=getattr(request_obj, "status", ""),
        )
        if request_obj is not None
        else UnifiedRequestStatus.NEW
    )
    invoice_details = invoice_details or _extras_invoice_details(invoice, request_obj=request_obj)

    if invoice is not None and invoice.is_payment_effective():
        return {
            "label": "مدفوع ومعتمد",
            "tone": "success",
            "next_step": "إكمال التنفيذ ثم إغلاق الطلب",
            "description": "تم اعتماد السداد لهذا الطلب. يمكن الآن استكمال التنفيذ ثم تحويل الحالة إلى مكتمل بعد إنهاء الخدمة.",
        }

    if invoice is not None:
        return {
            "label": "فاتورة صادرة وبانتظار السداد",
            "tone": "info",
            "next_step": "متابعة السداد أو تحديث الفاتورة",
            "description": (
                "تم إنشاء فاتورة يدوية لهذا الطلب وإرسال رابط الدفع للعميل. "
                "يمكن تحديث البنود قبل السداد عند الحاجة."
            ),
            "checkout_url": (invoice_details or {}).get("checkout_url", ""),
        }

    if normalized_status == UnifiedRequestStatus.IN_PROGRESS:
        return {
            "label": "بانتظار التسعير اليدوي",
            "tone": "warning",
            "next_step": "إصدار الفاتورة من المكلف",
            "description": (
                "الطلب تحت المعالجة، لكن لم يتم تحديد التسعير بعد. "
                "أدخل البنود والمبالغ يدويًا ثم أصدر الفاتورة عند جاهزية العرض المالي."
            ),
        }

    if normalized_status == UnifiedRequestStatus.CLOSED:
        return {
            "label": "مغلق بدون فاتورة",
            "tone": "muted",
            "next_step": "مراجعة السجل المالي",
            "description": "هذا الطلب مغلق حاليًا ولا توجد عليه فاتورة محفوظة داخل السجل الحالي.",
        }

    return {
        "label": "بانتظار التسعير",
        "tone": "warning",
        "next_step": "نقل الطلب إلى تحت المعالجة",
        "description": (
            "لا يتم إنشاء فاتورة تلقائيًا في الخدمات الإضافية. "
            "يبدأ المكلف بمراجعة الطلب ثم ينتقل إلى التسعير اليدوي حسب نطاق العمل المطلوب."
        ),
    }


def _extras_purchase_rows(purchases: list[ExtraPurchase]) -> list[dict]:
    source_ids = [str(purchase.id) for purchase in purchases if getattr(purchase, "id", None)]
    request_map: dict[int, UnifiedRequest] = {}
    if source_ids:
        for request_obj in UnifiedRequest.objects.filter(
            request_type=UnifiedRequestType.EXTRAS,
            source_app="extras",
            source_model="ExtraPurchase",
            source_object_id__in=source_ids,
        ):
            raw_purchase_id = str(request_obj.source_object_id or "").strip()
            if raw_purchase_id.isdigit():
                request_map[int(raw_purchase_id)] = request_obj

    rows: list[dict] = []
    for purchase in purchases:
        invoice = getattr(purchase, "invoice", None)
        request_obj = request_map.get(int(purchase.id))
        rows.append(
            {
                "id": purchase.id,
                "request_id": getattr(request_obj, "id", None),
                "request_code": getattr(request_obj, "code", "") or f"P{purchase.id:06d}",
                "requester": _promo_requester_label(purchase.user),
                "service_title": (purchase.title or purchase.sku or "-").strip(),
                "service_sku": purchase.sku or "-",
                "purchase_status_code": purchase.status,
                "purchase_status": purchase.get_status_display(),
                "payment_status": _extras_payment_status_label(purchase),
                "subtotal_text": _extras_amount_text(purchase.subtotal, purchase.currency),
                "invoice_total_text": _extras_amount_text(
                    getattr(invoice, "total", None),
                    getattr(invoice, "currency", None) or purchase.currency,
                ),
                "invoice_code": getattr(invoice, "code", "") or "-",
                "start_at": _format_dt(purchase.start_at),
                "end_at": _format_dt(purchase.end_at),
                "credits_total": int(purchase.credits_total or 0),
                "credits_used": int(purchase.credits_used or 0),
                "credits_left": int(purchase.credits_left()),
                "updated_at": _format_dt(purchase.updated_at),
            }
        )
    return rows


def _extras_finance_summary(rows: list[dict]) -> dict:
    paid_count = 0
    for row in rows:
        if row.get("payment_status") == "مدفوع ومعتمد":
            paid_count += 1
    return {
        "total": len(rows),
        "paid": paid_count,
        "pending": max(0, len(rows) - paid_count),
    }


def _extras_portal_subscriptions_queryset_for_user(user):
    qs = ExtrasPortalSubscription.objects.select_related("provider", "provider__user", "provider__user__provider_profile").order_by("-updated_at", "-id")
    access_profile = active_access_profile_for_user(user)
    if access_profile and access_profile.level == AccessLevel.USER:
        allowed_requester_ids = {
            int(row.requester_id)
            for row in _extras_unified_queryset_for_user(user)
            if getattr(row, "requester_id", None)
        }
        if not allowed_requester_ids:
            return qs.none()
        qs = qs.filter(provider__user_id__in=allowed_requester_ids)
    return qs


def _extras_subscription_payment_status_label(invoice: Invoice | None) -> str:
    if invoice is None:
        return "لا توجد فاتورة"
    if invoice.is_payment_effective():
        return "مدفوع ومعتمد"
    return invoice.get_status_display()


def _extras_subscription_payment_message(invoice: Invoice | None) -> str:
    if invoice is None:
        return "لا توجد فاتورة مرتبطة بآخر طلب مكتمل لهذه الخدمة حتى الآن."
    if invoice.is_payment_effective():
        paid_at = getattr(invoice, "payment_confirmed_at", None) or getattr(invoice, "paid_at", None)
        amount_text = _subscription_payment_amount_text(invoice)
        if paid_at and amount_text != "-":
            return f"تمت عملية السداد بنجاح في تاريخ {_format_dt(paid_at)} بقيمة {amount_text}."
        if paid_at:
            return f"تمت عملية السداد بنجاح في تاريخ {_format_dt(paid_at)}."
        if amount_text != "-":
            return f"تمت عملية السداد بنجاح بقيمة {amount_text}."
        return "تمت عملية السداد بنجاح."
    return f"حالة السداد الحالية: {invoice.get_status_display()}."


def _extras_subscription_latest_bundle_request_map(subscriptions: list[ExtrasPortalSubscription]) -> dict[int, UnifiedRequest]:
    requester_ids = {
        int(subscription.provider.user_id)
        for subscription in subscriptions
        if getattr(subscription.provider, "user_id", None)
    }
    if not requester_ids:
        return {}

    latest_by_requester_id: dict[int, UnifiedRequest] = {}
    requests = UnifiedRequest.objects.filter(
        request_type=UnifiedRequestType.EXTRAS,
        requester_id__in=requester_ids,
        status=UnifiedRequestStatus.CLOSED,
    ).order_by("requester_id", "-updated_at", "-id")
    for request_obj in requests:
        requester_id = int(request_obj.requester_id or 0)
        if requester_id in latest_by_requester_id:
            continue
        if extras_bundle_payload_for_request(request_obj):
            latest_by_requester_id[requester_id] = request_obj
    return latest_by_requester_id


def _extras_subscription_section_key(title: str, *, index: int) -> str:
    normalized = str(title or "").strip()
    mapping = {
        "التقارير": "reports",
        "إدارة العملاء": "clients",
        "الإدارة المالية": "finance",
    }
    return mapping.get(normalized, f"service-{index}")


def _extras_subscription_fallback_sections(subscription: ExtrasPortalSubscription) -> list[dict]:
    titles = [segment.strip() for segment in str(subscription.plan_title or "").split("/") if segment.strip()]
    sections: list[dict] = []
    for index, title in enumerate(titles, start=1):
        sections.append(
            {
                "key": _extras_subscription_section_key(title, index=index),
                "title": title,
                "items": [{"title": title, "duration": "-"}],
                "meta_lines": [],
            }
        )
    return sections


def _extras_subscription_rows(subscriptions: list[ExtrasPortalSubscription]) -> list[dict]:
    latest_requests = _extras_subscription_latest_bundle_request_map(subscriptions)
    rows: list[dict] = []

    for subscription in subscriptions:
        provider = getattr(subscription, "provider", None)
        user_obj = getattr(provider, "user", None)
        latest_request = latest_requests.get(int(getattr(provider, "user_id", 0) or 0))
        invoice = extras_bundle_invoice_for_request(latest_request) if latest_request is not None else None
        section_rows = extras_bundle_detail_sections_for_request(latest_request) if latest_request is not None else []
        if not section_rows:
            section_rows = _extras_subscription_fallback_sections(subscription)

        provider_name = str(getattr(provider, "display_name", "") or "").strip() or _promo_requester_label(user_obj)
        requester_label = _promo_requester_label(user_obj) if user_obj is not None else provider_name
        payment_status_label = _extras_subscription_payment_status_label(invoice)
        payment_message = _extras_subscription_payment_message(invoice)
        payment_effective = bool(invoice is not None and invoice.is_payment_effective())
        disabled_reason = "إجراءات التجديد والحذف ستُربط بعد إضافة مسار مستقل لكل خدمة داخل اشتراك الخدمات الإضافية."

        for index, section in enumerate(section_rows, start=1):
            service_key = str(section.get("key") or _extras_subscription_section_key(section.get("title", ""), index=index)).strip() or f"service-{index}"
            items = list(section.get("items") or [])
            meta_lines = [
                str(value or "").strip()
                for value in (section.get("meta_lines") or [])
                if str(value or "").strip()
            ]
            duration_label = next(
                (str(item.get("duration") or "").strip() for item in items if str(item.get("duration") or "").strip()),
                "-",
            )
            request_code = getattr(latest_request, "code", "") or f"S{subscription.id:06d}"
            row_id = f"{subscription.id}:{service_key}"
            search_text = " ".join(
                filter(
                    None,
                    [
                        requester_label,
                        provider_name,
                        service_key,
                        str(section.get("title") or ""),
                        str(subscription.plan_title or ""),
                        request_code,
                        getattr(user_obj, "phone", "") or "",
                        getattr(invoice, "code", "") or "",
                    ],
                )
            ).casefold()
            rows.append(
                {
                    "id": row_id,
                    "dom_id": row_id.replace(":", "-"),
                    "subscription_id": subscription.id,
                    "request_id": getattr(latest_request, "id", None),
                    "request_code": request_code,
                    "requester": requester_label,
                    "provider_name": provider_name,
                    "provider_phone": getattr(user_obj, "phone", "") or "-",
                    "service_key": service_key,
                    "service_title": str(section.get("title") or "الخدمة الإضافية").strip() or "الخدمة الإضافية",
                    "service_count": len(items),
                    "subscription_status_code": subscription.status,
                    "subscription_status": subscription.get_status_display(),
                    "payment_status": payment_status_label,
                    "payment_effective": payment_effective,
                    "payment_message": payment_message,
                    "invoice_code": getattr(invoice, "code", "") or "-",
                    "invoice_total_text": _extras_amount_text(
                        getattr(invoice, "total", None),
                        getattr(invoice, "currency", None),
                    ),
                    "start_at": _format_dt(subscription.started_at),
                    "end_at": _format_dt(subscription.ends_at),
                    "raw_end_at": subscription.ends_at,
                    "duration_label": duration_label,
                    "notes": str(subscription.notes or "").strip(),
                    "plan_title": str(subscription.plan_title or "").strip() or "-",
                    "items": items,
                    "meta_lines": meta_lines,
                    "can_renew": False,
                    "can_delete": False,
                    "renew_disabled_reason": disabled_reason,
                    "delete_disabled_reason": disabled_reason,
                    "search_text": search_text,
                }
            )
    return rows


def _extras_subscribers_summary(rows: list[dict]) -> dict:
    by_status: dict[str, int] = {}
    ending_soon = 0
    now = timezone.now()
    soon_threshold = now + timedelta(days=30)
    for row in rows:
        status_code = str(row.get("subscription_status_code") or "").strip().lower()
        by_status[status_code] = by_status.get(status_code, 0) + 1
        raw_end_at = row.get("raw_end_at")
        if (
            status_code == ExtrasPortalSubscriptionStatus.ACTIVE
            and isinstance(raw_end_at, datetime)
            and now <= raw_end_at <= soon_threshold
        ):
            ending_soon += 1
    return {
        "total": len(rows),
        "active": by_status.get(ExtrasPortalSubscriptionStatus.ACTIVE, 0),
        "inactive": by_status.get(ExtrasPortalSubscriptionStatus.INACTIVE, 0),
        "ending_soon": ending_soon,
    }


def _extras_option_map(options: tuple[tuple[str, str], ...]) -> dict[str, str]:
    return {key: label for key, label in options}


def _extras_parse_option_selection(raw_values: list[str], options: tuple[tuple[str, str], ...]) -> list[str]:
    allowed = set(_extras_option_map(options).keys())
    selected: list[str] = []
    for value in raw_values:
        normalized = str(value or "").strip()
        if not normalized or normalized not in allowed:
            continue
        if normalized in selected:
            continue
        selected.append(normalized)
    return selected


def _extras_report_option_groups() -> list[dict]:
    labels_map = _extras_option_map(EXTRAS_REPORT_OPTIONS)
    groups: list[dict] = []
    for title, keys in EXTRAS_REPORT_OPTION_GROUPS:
        groups.append(
            {
                "title": title,
                "options": [
                    {"key": key, "label": labels_map[key]}
                    for key in keys
                    if key in labels_map
                ],
            }
        )
    return groups


def _extras_bundle_default_draft() -> dict:
    return {
        "specialist_identifier": "",
        "reports": {
            "options": [],
            "start_at": "",
            "end_at": "",
        },
        "clients": {
            "options": [],
            "subscription_years": 1,
            "bulk_message_count": 0,
        },
        "finance": {
            "options": [],
            "subscription_years": 1,
            "qr_first_name": "",
            "qr_last_name": "",
            "iban": "",
        },
    }


def _extras_bundle_load_draft(request) -> dict:
    payload = request.session.get(EXTRAS_BUNDLE_DRAFT_SESSION_KEY)
    draft = _extras_bundle_default_draft()
    if not isinstance(payload, dict):
        return draft

    specialist_identifier = str(payload.get("specialist_identifier", "") or "").strip()
    if specialist_identifier:
        draft["specialist_identifier"] = specialist_identifier

    for section_key in ("reports", "clients", "finance"):
        raw_section = payload.get(section_key)
        if not isinstance(raw_section, dict):
            continue
        draft[section_key].update(raw_section)
    return draft


def _extras_bundle_save_draft(request, draft: dict) -> None:
    request.session[EXTRAS_BUNDLE_DRAFT_SESSION_KEY] = draft


def _extras_bundle_selected_labels(selected_keys: list[str], options: tuple[tuple[str, str], ...]) -> list[str]:
    labels_map = _extras_option_map(options)
    labels: list[str] = []
    for key in selected_keys:
        if key in labels_map:
            labels.append(labels_map[key])
    return labels


def _extras_bundle_summary_sections(draft: dict) -> list[dict]:
    report_labels = _extras_bundle_selected_labels(draft.get("reports", {}).get("options", []), EXTRAS_REPORT_OPTIONS)
    client_labels = _extras_bundle_selected_labels(draft.get("clients", {}).get("options", []), EXTRAS_CLIENT_OPTIONS)
    finance_labels = _extras_bundle_selected_labels(draft.get("finance", {}).get("options", []), EXTRAS_FINANCE_OPTIONS)

    report_start_at = _parse_datetime_local(draft.get("reports", {}).get("start_at"))
    report_end_at = _parse_datetime_local(draft.get("reports", {}).get("end_at"))
    if report_start_at:
        report_labels.append(f"بداية التقرير: {_format_dt(report_start_at)}")
    if report_end_at:
        report_labels.append(f"نهاية التقرير: {_format_dt(report_end_at)}")

    clients_years = max(1, int(draft.get("clients", {}).get("subscription_years", 1) or 1))
    clients_bulk_count = max(0, int(draft.get("clients", {}).get("bulk_message_count", 0) or 0))
    if client_labels:
        client_labels.append(f"مدة الاشتراك (بالسنوات): {clients_years}")
        client_labels.append(f"عدد الرسائل الجماعية: {clients_bulk_count}")

    finance_years = max(1, int(draft.get("finance", {}).get("subscription_years", 1) or 1))
    if finance_labels:
        finance_labels.append(f"مدة الاشتراك (بالسنوات): {finance_years}")
        qr_first_name = str(draft.get("finance", {}).get("qr_first_name", "") or "").strip()
        qr_last_name = str(draft.get("finance", {}).get("qr_last_name", "") or "").strip()
        iban = str(draft.get("finance", {}).get("iban", "") or "").strip()
        if qr_first_name:
            finance_labels.append(f"الاسم الأول: {qr_first_name}")
        if qr_last_name:
            finance_labels.append(f"الاسم الثاني: {qr_last_name}")
        if iban:
            finance_labels.append(f"IBAN: {iban}")

    return [
        {"key": EXTRAS_DASHBOARD_SECTION_REPORTS, "title": "التقارير", "items": report_labels},
        {"key": EXTRAS_DASHBOARD_SECTION_CLIENTS, "title": "إدارة العملاء", "items": client_labels},
        {"key": EXTRAS_DASHBOARD_SECTION_FINANCE, "title": "الإدارة المالية", "items": finance_labels},
    ]


def _extras_bundle_has_selection(draft: dict) -> bool:
    for section in ("reports", "clients", "finance"):
        if draft.get(section, {}).get("options"):
            return True
    return False


def _extras_datetime_input_value(raw_value: str) -> str:
    dt = _parse_datetime_local(raw_value)
    if not dt:
        return ""
    local_dt = timezone.localtime(dt)
    return local_dt.strftime("%Y-%m-%dT%H:%M")


def _extras_add_years(dt: datetime, years: int) -> datetime:
    try:
        return dt.replace(year=dt.year + years)
    except ValueError:
        return dt.replace(year=dt.year + years, month=2, day=28)


def _extras_human_datetime(dt: datetime | None) -> str:
    if dt is None:
        return "-"
    return timezone.localtime(dt).strftime("%d/%m/%Y - %H:%M")


def _extras_resolve_specialist(identifier: str):
    normalized_identifier = str(identifier or "").strip()
    if not normalized_identifier:
        return None
    User = get_user_model()
    by_phone = (
        User.objects.filter(phone=normalized_identifier, is_active=True, provider_profile__isnull=False)
        .select_related("provider_profile")
        .first()
    )
    if by_phone is not None:
        return by_phone
    return (
        User.objects.filter(username=normalized_identifier, is_active=True, provider_profile__isnull=False)
        .select_related("provider_profile")
        .first()
    )


def _extras_specialist_search_rows(query: str, *, limit: int = 8) -> list[dict]:
    normalized_query = str(query or "").strip()
    if len(normalized_query) < 2:
        return []

    User = get_user_model()
    users = (
        User.objects.filter(is_active=True, provider_profile__isnull=False)
        .select_related("provider_profile")
        .filter(
            Q(username__icontains=normalized_query)
            | Q(phone__icontains=normalized_query)
            | Q(provider_profile__display_name__icontains=normalized_query)
        )
        .order_by("username", "phone", "id")[: max(1, int(limit or 8))]
    )

    rows: list[dict] = []
    for user_obj in users:
        provider_profile = getattr(user_obj, "provider_profile", None)
        display_name = str(getattr(provider_profile, "display_name", "") or "").strip()
        username = str(getattr(user_obj, "username", "") or "").strip()
        phone = str(getattr(user_obj, "phone", "") or "").strip()
        identifier = username or phone
        if not identifier:
            continue
        display_text_parts = [segment for segment in [display_name, username, phone] if segment]
        rows.append(
            {
                "identifier": identifier,
                "username": username,
                "phone": phone,
                "display_name": display_name or username or phone,
                "display_text": " - ".join(display_text_parts) if display_text_parts else identifier,
            }
        )
    return rows


@dashboard_staff_required
@require_dashboard_access("extras")
def extras_specialist_search_api(request):
    query = (request.GET.get("q") or "").strip()
    rows = _extras_specialist_search_rows(query)
    return JsonResponse(
        {
            "ok": True,
            "q": query,
            "rows": rows,
        },
        json_dumps_params={"ensure_ascii": False},
    )


@dashboard_staff_required
@require_dashboard_access("extras")
def extras_dashboard(request):
    extras_team = _extras_support_team()
    extras_team_name = _extras_team_name(extras_team)
    can_write = dashboard_allowed(request.user, "extras", write=True)
    assignee_choices = _dashboard_assignee_choices("extras")
    bundle_draft = _extras_bundle_load_draft(request)

    specialist_identifier_from_query = (
        (request.GET.get("specialist") or "").strip()
        or (request.GET.get("specialist_username") or "").strip()
    )
    if specialist_identifier_from_query:
        bundle_draft["specialist_identifier"] = specialist_identifier_from_query
        _extras_bundle_save_draft(request, bundle_draft)

    requested_section = (request.GET.get("section") or "").strip().lower()
    active_section = requested_section if requested_section in EXTRAS_DASHBOARD_SECTIONS else EXTRAS_DASHBOARD_MAIN_SECTION

    def _extras_redirect_to_section(
        section_key: str,
        *,
        params: dict[str, str | int] | None = None,
        anchor: str = "",
    ):
        query_params = QueryDict("", mutable=True)
        query_params["section"] = section_key
        specialist_identifier = str(bundle_draft.get("specialist_identifier", "") or "").strip()
        if specialist_identifier:
            query_params["specialist"] = specialist_identifier
        for key, value in (params or {}).items():
            normalized_value = str(value or "").strip()
            if normalized_value:
                query_params[str(key)] = normalized_value
        base = reverse("dashboard:extras_dashboard")
        query = query_params.urlencode()
        target = f"{base}?{query}" if query else base
        return redirect(f"{target}#{anchor}" if anchor else target)

    if request.method == "POST":
        if not can_write:
            return HttpResponseForbidden("لا تملك صلاحية تعديل طلبات الخدمات الإضافية.")

        action = (request.POST.get("action") or "").strip()
        if "specialist_identifier" in request.POST:
            posted_specialist_identifier = (request.POST.get("specialist_identifier") or "").strip()
            bundle_draft["specialist_identifier"] = posted_specialist_identifier
            _extras_bundle_save_draft(request, bundle_draft)

        if action == "save_extras_bundle_reports":
            selected_options = _extras_parse_option_selection(
                request.POST.getlist("reports_options"),
                EXTRAS_REPORT_OPTIONS,
            )
            raw_start_at = (request.POST.get("reports_start_at") or "").strip()
            raw_end_at = (request.POST.get("reports_end_at") or "").strip()
            start_at = _parse_datetime_local(raw_start_at)
            end_at = _parse_datetime_local(raw_end_at)
            if raw_start_at and not start_at:
                messages.error(request, "صيغة بداية التقرير غير صحيحة.")
                return _extras_redirect_to_section(EXTRAS_DASHBOARD_SECTION_REPORTS)
            if raw_end_at and not end_at:
                messages.error(request, "صيغة نهاية التقرير غير صحيحة.")
                return _extras_redirect_to_section(EXTRAS_DASHBOARD_SECTION_REPORTS)
            if start_at and end_at and end_at < start_at:
                messages.error(request, "تاريخ نهاية التقرير يجب أن يكون بعد تاريخ البداية.")
                return _extras_redirect_to_section(EXTRAS_DASHBOARD_SECTION_REPORTS)

            bundle_draft["reports"] = {
                "options": selected_options,
                "start_at": start_at.isoformat() if start_at else "",
                "end_at": end_at.isoformat() if end_at else "",
            }
            _extras_bundle_save_draft(request, bundle_draft)
            if (request.POST.get("continue_to_summary") or "").strip() == "1":
                return _extras_redirect_to_section(EXTRAS_DASHBOARD_SECTION_REQUEST_SUMMARY)
            messages.success(request, "تم حفظ اختيارات باقة التقارير.")
            return _extras_redirect_to_section(EXTRAS_DASHBOARD_SECTION_REPORTS)

        if action == "save_extras_bundle_clients":
            selected_options = _extras_parse_option_selection(
                request.POST.getlist("clients_options"),
                EXTRAS_CLIENT_OPTIONS,
            )
            raw_years = (request.POST.get("clients_subscription_years") or "1").strip()
            raw_bulk_count = (request.POST.get("clients_bulk_message_count") or "0").strip()
            try:
                clients_years = max(1, min(10, int(raw_years or "1")))
            except (TypeError, ValueError):
                clients_years = 1
            try:
                bulk_count = max(0, min(100000, int(raw_bulk_count or "0")))
            except (TypeError, ValueError):
                bulk_count = 0

            bundle_draft["clients"] = {
                "options": selected_options,
                "subscription_years": clients_years,
                "bulk_message_count": bulk_count,
            }
            _extras_bundle_save_draft(request, bundle_draft)
            if (request.POST.get("continue_to_summary") or "").strip() == "1":
                return _extras_redirect_to_section(EXTRAS_DASHBOARD_SECTION_REQUEST_SUMMARY)
            messages.success(request, "تم حفظ اختيارات باقة إدارة العملاء.")
            return _extras_redirect_to_section(EXTRAS_DASHBOARD_SECTION_CLIENTS)

        if action == "save_extras_bundle_finance":
            selected_options = _extras_parse_option_selection(
                request.POST.getlist("finance_options"),
                EXTRAS_FINANCE_OPTIONS,
            )
            raw_years = (request.POST.get("finance_subscription_years") or "1").strip()
            qr_first_name = str(request.POST.get("finance_qr_first_name") or "").strip()[:50]
            qr_last_name = str(request.POST.get("finance_qr_last_name") or "").strip()[:50]
            iban = re.sub(r"\s+", "", str(request.POST.get("finance_iban") or "")).upper()[:34]
            try:
                finance_years = max(1, min(10, int(raw_years or "1")))
            except (TypeError, ValueError):
                finance_years = 1

            bundle_draft["finance"] = {
                "options": selected_options,
                "subscription_years": finance_years,
                "qr_first_name": qr_first_name,
                "qr_last_name": qr_last_name,
                "iban": iban,
            }
            _extras_bundle_save_draft(request, bundle_draft)
            if (request.POST.get("continue_to_summary") or "").strip() == "1":
                return _extras_redirect_to_section(EXTRAS_DASHBOARD_SECTION_REQUEST_SUMMARY)
            messages.success(request, "تم حفظ اختيارات باقة الإدارة المالية.")
            return _extras_redirect_to_section(EXTRAS_DASHBOARD_SECTION_FINANCE)

        if action == "clear_extras_bundle_draft":
            redirect_section = (request.POST.get("redirect_section") or "").strip().lower()
            if redirect_section not in EXTRAS_DASHBOARD_SECTIONS:
                redirect_section = EXTRAS_DASHBOARD_SECTION_CLIENTS
            if redirect_section in {
                EXTRAS_DASHBOARD_SECTION_REQUEST_SUMMARY,
                EXTRAS_DASHBOARD_SECTION_REQUEST_CREATED,
            }:
                redirect_section = EXTRAS_DASHBOARD_MAIN_SECTION
            request.session.pop(EXTRAS_BUNDLE_DRAFT_SESSION_KEY, None)
            bundle_draft = _extras_bundle_default_draft()
            messages.info(request, "تم إلغاء الاختيارات الحالية.")
            return _extras_redirect_to_section(redirect_section)

        if action == "submit_extras_bundle_request":
            if not _extras_bundle_has_selection(bundle_draft):
                messages.error(request, "اختر بندًا واحدًا على الأقل قبل إنشاء الطلب.")
                return _extras_redirect_to_section(EXTRAS_DASHBOARD_SECTION_REQUEST_SUMMARY)

            specialist_identifier = str(bundle_draft.get("specialist_identifier", "") or "").strip()
            if not specialist_identifier:
                messages.error(request, "حدد مزود الخدمة أولاً قبل إنشاء طلب الخدمات الإضافية.")
                return _extras_redirect_to_section(EXTRAS_DASHBOARD_SECTION_REQUEST_SUMMARY)

            specialist_user = _extras_resolve_specialist(specialist_identifier)
            if specialist_user is None:
                messages.error(request, "تعذر العثور على مزود الخدمة المحدد. راجع اسم مزود الخدمة ثم أعد المحاولة.")
                return _extras_redirect_to_section(EXTRAS_DASHBOARD_SECTION_REQUEST_SUMMARY)

            requester_user = specialist_user
            summary_sections = _extras_bundle_summary_sections(bundle_draft)
            selected_section_titles = [row["title"] for row in summary_sections if row.get("items")]
            summary_text = (
                f"طلب خدمات إضافية - {' / '.join(selected_section_titles)}"
                if selected_section_titles
                else "طلب خدمات إضافية"
            )

            metadata_payload = {
                "flow_type": "extras_bundle_wizard",
                "specialist_identifier": specialist_identifier,
                "specialist_label": (
                    getattr(specialist_user, "username", "")
                    or getattr(specialist_user, "phone", "")
                    or ""
                )
                if specialist_user is not None
                else "",
                "reports": bundle_draft.get("reports", {}),
                "clients": bundle_draft.get("clients", {}),
                "finance": bundle_draft.get("finance", {}),
                "summary_sections": summary_sections,
            }

            created_request = upsert_unified_request(
                request_type=UnifiedRequestType.EXTRAS,
                requester=requester_user,
                source_app="dashboard",
                source_model="ExtrasServiceRequest",
                source_object_id=uuid4().hex,
                status=UnifiedRequestStatus.NEW,
                priority=UnifiedRequestPriority.NORMAL,
                summary=summary_text,
                metadata=metadata_payload,
                assigned_team_code="extras",
                assigned_team_name=extras_team_name,
                assigned_user=request.user,
                changed_by=request.user,
            )
            request.session.pop(EXTRAS_BUNDLE_DRAFT_SESSION_KEY, None)
            messages.success(request, f"تم إنشاء طلب الخدمات الإضافية {created_request.code} بنجاح.")
            return _extras_redirect_to_section(
                EXTRAS_DASHBOARD_SECTION_REQUEST_CREATED,
                params={"created_request": created_request.id},
            )

        if action == "save_extras_inquiry":
            raw_ticket_id = (request.POST.get("ticket_id") or "").strip()
            if not raw_ticket_id.isdigit():
                messages.error(request, "تعذر تحديد الاستفسار المطلوب تحديثه.")
                return _extras_redirect_with_state(request)

            target_ticket = _extras_inquiries_queryset_for_user(request.user).filter(
                ticket_type=SupportTicketType.EXTRAS,
                id=int(raw_ticket_id),
            ).first()
            if target_ticket is None:
                messages.error(request, "الاستفسار المحدد غير متاح لهذا الحساب.")
                return _extras_redirect_with_state(request)

            access_profile = active_access_profile_for_user(request.user)
            if access_profile and access_profile.level == AccessLevel.USER:
                if target_ticket.assigned_to_id and target_ticket.assigned_to_id != request.user.id:
                    return HttpResponseForbidden("غير مصرح: الاستفسار ليس ضمن المهام المكلف بها.")

            post_form = ExtrasInquiryActionForm(request.POST, assignee_choices=assignee_choices)
            if not post_form.is_valid():
                messages.error(request, "يرجى مراجعة حقول تفاصيل استفسار الخدمات الإضافية.")
                return _extras_redirect_with_state(request, inquiry_id=target_ticket.id)

            assigned_to_raw = (post_form.cleaned_data.get("assigned_to") or "").strip()
            assigned_to_id = int(assigned_to_raw) if assigned_to_raw.isdigit() else target_ticket.assigned_to_id
            if assigned_to_id is not None:
                assignee = dashboard_assignee_user(assigned_to_id, "extras", write=True)
                if assignee is None:
                    messages.error(request, "المكلف المختار لا يملك صلاحية لوحة الخدمات الإضافية.")
                    return _extras_redirect_with_state(request, inquiry_id=target_ticket.id)

            team_id = extras_team.id if extras_team is not None else target_ticket.assigned_team_id
            note = post_form.cleaned_data.get("operator_comment") or ""
            target_ticket = assign_ticket(
                ticket=target_ticket,
                team_id=team_id,
                user_id=assigned_to_id,
                by_user=request.user,
                note=note,
            )

            new_description = post_form.cleaned_data.get("description") or target_ticket.description or ""
            if new_description != (target_ticket.description or ""):
                target_ticket.description = new_description
                target_ticket.last_action_by = request.user
                target_ticket.save(update_fields=["description", "last_action_by", "updated_at"])

            desired_status = post_form.cleaned_data.get("status")
            if desired_status and desired_status != target_ticket.status:
                try:
                    target_ticket = change_ticket_status(
                        ticket=target_ticket,
                        new_status=desired_status,
                        by_user=request.user,
                        note=note,
                    )
                except ValueError as exc:
                    messages.error(request, str(exc))
                    return _extras_redirect_with_state(request, inquiry_id=target_ticket.id)

            messages.success(request, f"تم تحديث استفسار الخدمات الإضافية {target_ticket.code or target_ticket.id} بنجاح.")
            return _extras_redirect_with_state(request, inquiry_id=target_ticket.id)

        if action == "save_extras_request":
            raw_request_id = (request.POST.get("request_id") or "").strip()
            if not raw_request_id.isdigit():
                messages.error(request, "تعذر تحديد طلب الخدمات الإضافية المطلوب تحديثه.")
                return _extras_redirect_with_state(request, anchor="extrasRequests")

            target_request = _extras_unified_queryset_for_user(request.user).filter(
                request_type=UnifiedRequestType.EXTRAS,
                id=int(raw_request_id),
            ).first()
            if target_request is None:
                messages.error(request, "طلب الخدمات الإضافية المحدد غير متاح لهذا الحساب.")
                return _extras_redirect_with_state(request, anchor="extrasRequests")

            current_status = canonical_status_for_workflow(
                request_type=UnifiedRequestType.EXTRAS,
                status=target_request.status,
            )
            post_form = ExtrasRequestActionForm(
                request.POST,
                assignee_choices=assignee_choices,
                status_choices=_extras_request_status_choices_for(current_status),
            )
            if not post_form.is_valid():
                if "status" in post_form.errors:
                    messages.error(request, _extras_request_status_help_text(current_status))
                else:
                    messages.error(request, "يرجى مراجعة حقول تفاصيل طلب الخدمات الإضافية.")
                return _extras_redirect_with_state(request, request_id=target_request.id, anchor="extrasRequests")

            assigned_to_raw = (post_form.cleaned_data.get("assigned_to") or "").strip()
            if not assigned_to_raw.isdigit():
                messages.error(request, "يرجى اختيار المكلف بالطلب من فريق إدارة الخدمات الإضافية.")
                return _extras_redirect_with_state(request, request_id=target_request.id, anchor="extrasRequests")

            assignee = dashboard_assignee_user(int(assigned_to_raw), "extras", write=True)
            if assignee is None:
                messages.error(request, "المكلف المختار لا يملك صلاحية لوحة الخدمات الإضافية.")
                return _extras_redirect_with_state(request, request_id=target_request.id, anchor="extrasRequests")

            desired_status = canonical_status_for_workflow(
                request_type=UnifiedRequestType.EXTRAS,
                status=post_form.cleaned_data.get("status") or UnifiedRequestStatus.NEW,
            )
            if desired_status not in {
                UnifiedRequestStatus.NEW,
                UnifiedRequestStatus.IN_PROGRESS,
                UnifiedRequestStatus.CLOSED,
            }:
                desired_status = UnifiedRequestStatus.NEW

            allowed_transitions = EXTRAS_REQUEST_ALLOWED_TRANSITIONS
            if desired_status not in allowed_transitions.get(current_status, {current_status}):
                if current_status == UnifiedRequestStatus.NEW:
                    messages.error(request, "يمكن نقل الطلب من جديد إلى تحت المعالجة فقط.")
                elif current_status == UnifiedRequestStatus.IN_PROGRESS:
                    messages.error(request, "يمكن إكمال الطلب فقط بعد اعتماده تحت المعالجة وسداد الفاتورة.")
                else:
                    messages.error(request, "الطلب المكتمل لا يمكن تعديله من جديد.")
                return _extras_redirect_with_state(request, request_id=target_request.id, anchor="extrasRequests")

            raw_purchase_id = str(target_request.source_object_id or "").strip()
            target_purchase = (
                ExtraPurchase.objects.select_related("user", "invoice")
                .filter(pk=int(raw_purchase_id))
                .first()
                if raw_purchase_id.isdigit()
                else None
            )
            bundle_payload = extras_bundle_payload_for_request(target_request)
            is_bundle_request = bool(bundle_payload)

            metadata_payload: dict = {}
            existing_metadata = getattr(getattr(target_request, "metadata_record", None), "payload", None)
            if isinstance(existing_metadata, dict):
                metadata_payload.update(existing_metadata)

            if target_purchase is not None:
                metadata_payload.update(
                    {
                        "purchase_id": target_purchase.id,
                        "sku": target_purchase.sku,
                        "extra_type": target_purchase.extra_type,
                        "purchase_status": target_purchase.status,
                        "invoice_id": target_purchase.invoice_id,
                        "credits_total": int(target_purchase.credits_total or 0),
                        "credits_used": int(target_purchase.credits_used or 0),
                        "start_at": target_purchase.start_at.isoformat() if target_purchase.start_at else None,
                        "end_at": target_purchase.end_at.isoformat() if target_purchase.end_at else None,
                    }
                )

            target_invoice = getattr(target_purchase, "invoice", None)

            if desired_status == UnifiedRequestStatus.CLOSED:
                if current_status != UnifiedRequestStatus.IN_PROGRESS:
                    messages.error(request, "يجب نقل الطلب أولًا إلى تحت المعالجة قبل تحويله إلى مكتمل.")
                    return _extras_redirect_with_state(request, request_id=target_request.id, anchor="extrasRequests")
                if target_request.assigned_user_id != request.user.id:
                    messages.error(request, "فقط المكلف الحالي بالطلب يمكنه تحويله إلى مكتمل.")
                    return _extras_redirect_with_state(request, request_id=target_request.id, anchor="extrasRequests")
                if target_invoice is None and is_bundle_request:
                    target_invoice = extras_bundle_invoice_for_request(target_request)
                if target_invoice is None or not target_invoice.is_payment_effective():
                    messages.error(request, "لا يمكن تحويل الطلب إلى مكتمل قبل اعتماد السداد فعليًا.")
                    return _extras_redirect_with_state(request, request_id=target_request.id, anchor="extrasRequests")
                if extras_bundle_target_provider_user(target_request) is None:
                    messages.error(request, "لا يمكن إكمال الطلب قبل ربطه بمزود خدمة صالح يمتلك ملف مزود مفعل.")
                    return _extras_redirect_with_state(request, request_id=target_request.id, anchor="extrasRequests")
                metadata_payload.update(
                    {
                        "invoice_id": target_invoice.id,
                        "invoice_code": target_invoice.code,
                        "invoice_status": target_invoice.status,
                        "payment_effective": True,
                        "completed_at": timezone.now().isoformat(),
                        "completed_by_user_id": request.user.id,
                    }
                )

            operator_comment = post_form.cleaned_data.get("operator_comment") or ""
            if operator_comment:
                metadata_payload["operator_comment"] = operator_comment
            else:
                metadata_payload.pop("operator_comment", None)

            summary_text = (
                getattr(target_purchase, "title", "")
                or target_request.summary
                or target_request.code
                or "طلب خدمات إضافية"
            ).strip()

            updated_request = upsert_unified_request(
                request_type=UnifiedRequestType.EXTRAS,
                requester=getattr(target_purchase, "user", None) or target_request.requester,
                source_app=(target_request.source_app or "extras"),
                source_model=(target_request.source_model or "ExtraPurchase"),
                source_object_id=target_request.source_object_id,
                status=desired_status,
                priority=(target_request.priority or "normal"),
                summary=summary_text,
                metadata=metadata_payload,
                assigned_team_code="extras",
                assigned_team_name=extras_team_name,
                assigned_user=assignee,
                changed_by=request.user,
            )

            if desired_status == UnifiedRequestStatus.CLOSED and is_bundle_request:
                activate_bundle_portal_subscription_for_request(request_obj=updated_request)
                notify_bundle_completed(request_obj=updated_request, actor=request.user)

            messages.success(request, f"تم تحديث طلب الخدمات الإضافية {target_request.code or target_request.id} بنجاح.")
            return _extras_redirect_with_state(request, request_id=target_request.id, anchor="extrasRequests")

        if action == "issue_extras_invoice":
            raw_request_id = (request.POST.get("request_id") or "").strip()
            if not raw_request_id.isdigit():
                messages.error(request, "تعذر تحديد طلب الخدمات الإضافية المطلوب إصدار فاتورته.")
                return _extras_redirect_with_state(request, anchor="extrasRequests")

            target_request = _extras_unified_queryset_for_user(request.user).filter(
                request_type=UnifiedRequestType.EXTRAS,
                id=int(raw_request_id),
            ).first()
            if target_request is None:
                messages.error(request, "طلب الخدمات الإضافية المحدد غير متاح لهذا الحساب.")
                return _extras_redirect_with_state(request, anchor="extrasRequests")

            current_status = canonical_status_for_workflow(
                request_type=UnifiedRequestType.EXTRAS,
                status=target_request.status,
            )
            if current_status not in {UnifiedRequestStatus.NEW, UnifiedRequestStatus.IN_PROGRESS}:
                messages.error(request, "يمكن إصدار فاتورة يدوية فقط للطلبات الجديدة أو التي تحت المعالجة.")
                return _extras_redirect_with_state(request, request_id=target_request.id, anchor="extrasRequests")

            post_form = ExtrasRequestActionForm(
                request.POST,
                assignee_choices=assignee_choices,
                status_choices=_extras_request_status_choices_for(current_status),
            )
            if not post_form.is_valid():
                messages.error(request, "يرجى مراجعة حقول تفاصيل طلب الخدمات الإضافية قبل إصدار الفاتورة.")
                return _extras_redirect_with_state(request, request_id=target_request.id, anchor="extrasRequests")

            assigned_to_raw = (post_form.cleaned_data.get("assigned_to") or "").strip()
            if not assigned_to_raw.isdigit():
                messages.error(request, "يرجى اختيار المكلف بالطلب من فريق إدارة الخدمات الإضافية قبل إصدار الفاتورة.")
                return _extras_redirect_with_state(request, request_id=target_request.id, anchor="extrasRequests")

            assignee = dashboard_assignee_user(int(assigned_to_raw), "extras", write=True)
            if assignee is None:
                messages.error(request, "المكلف المختار لا يملك صلاحية لوحة الخدمات الإضافية.")
                return _extras_redirect_with_state(request, request_id=target_request.id, anchor="extrasRequests")

            existing_invoice = extras_bundle_invoice_for_request(target_request)
            if existing_invoice is not None and existing_invoice.is_payment_effective():
                messages.error(request, "الطلب يملك فاتورة مدفوعة مسبقًا ولا يمكن إصدار فاتورة جديدة.")
                return _extras_redirect_with_state(request, request_id=target_request.id, anchor="extrasRequests")

            manual_line_items = _parse_manual_invoice_lines(request.POST)
            if not manual_line_items:
                messages.error(request, "يجب إدخال بند واحد على الأقل (عنوان ومبلغ) لإصدار الفاتورة.")
                return _extras_redirect_with_state(request, request_id=target_request.id, anchor="extrasRequests")

            try:
                target_invoice, payment_attempt = create_manual_extras_invoice(
                    request_obj=target_request,
                    by_user=request.user,
                    line_items=manual_line_items,
                    invoice_title=post_form.cleaned_data.get("invoice_title") or "",
                    invoice_description=post_form.cleaned_data.get("invoice_description") or "",
                )
            except (ValueError, Exception) as exc:
                messages.error(request, str(exc))
                return _extras_redirect_with_state(request, request_id=target_request.id, anchor="extrasRequests")

            existing_metadata = getattr(getattr(target_request, "metadata_record", None), "payload", None)
            metadata_payload = dict(existing_metadata) if isinstance(existing_metadata, dict) else {}
            raw_purchase_id = str(target_request.source_object_id or "").strip()
            target_purchase = (
                ExtraPurchase.objects.select_related("user", "invoice")
                .filter(pk=int(raw_purchase_id))
                .first()
                if raw_purchase_id.isdigit()
                else None
            )
            if target_purchase is not None:
                metadata_payload.update(
                    {
                        "purchase_id": target_purchase.id,
                        "sku": target_purchase.sku,
                        "extra_type": target_purchase.extra_type,
                        "purchase_status": target_purchase.status,
                        "invoice_id": target_purchase.invoice_id,
                        "credits_total": int(target_purchase.credits_total or 0),
                        "credits_used": int(target_purchase.credits_used or 0),
                        "start_at": target_purchase.start_at.isoformat() if target_purchase.start_at else None,
                        "end_at": target_purchase.end_at.isoformat() if target_purchase.end_at else None,
                    }
                )
            metadata_payload.update(
                {
                    "invoice_id": target_invoice.id,
                    "invoice_code": target_invoice.code,
                    "invoice_status": target_invoice.status,
                    "payment_effective": bool(target_invoice.is_payment_effective()),
                    "checkout_url": extras_bundle_payment_access_url(
                        request_obj=target_request,
                        invoice=target_invoice,
                        checkout_url=getattr(payment_attempt, "checkout_url", "") if payment_attempt is not None else "",
                    ),
                    "payment_attempt_id": str(payment_attempt.id) if payment_attempt is not None else "",
                }
            )
            operator_comment = post_form.cleaned_data.get("operator_comment") or ""
            if operator_comment:
                metadata_payload["operator_comment"] = operator_comment
            else:
                metadata_payload.pop("operator_comment", None)

            upsert_unified_request(
                request_type=UnifiedRequestType.EXTRAS,
                requester=getattr(target_purchase, "user", None) or target_request.requester,
                source_app=(target_request.source_app or "extras"),
                source_model=(target_request.source_model or "ExtraPurchase"),
                source_object_id=target_request.source_object_id,
                status=UnifiedRequestStatus.IN_PROGRESS,
                priority=(target_request.priority or "normal"),
                summary=(target_request.summary or target_request.code or "طلب خدمات إضافية").strip(),
                metadata=metadata_payload,
                assigned_team_code="extras",
                assigned_team_name=extras_team_name,
                assigned_user=assignee,
                changed_by=request.user,
            )

            notify_bundle_payment_requested(
                request_obj=target_request,
                actor=request.user,
                invoice=target_invoice,
                checkout_url=getattr(payment_attempt, "checkout_url", "") if payment_attempt is not None else "",
            )

            messages.success(request, f"تم إصدار فاتورة يدوية للطلب {target_request.code or target_request.id} وإرسال رابط الدفع للعميل.")
            return _extras_redirect_with_state(request, request_id=target_request.id, anchor="extrasRequests")

        messages.error(request, "الإجراء المطلوب غير مدعوم داخل لوحة الخدمات الإضافية.")
        return _extras_redirect_with_state(request)

    inquiry_q = (request.GET.get("inquiry_q") or "").strip()
    request_q = (request.GET.get("request_q") or "").strip()
    finance_q = (request.GET.get("finance_q") or "").strip()
    subscribers_q = (request.GET.get("subscribers_q") or "").strip()
    request_status_filter = canonical_status_for_workflow(
        request_type=UnifiedRequestType.EXTRAS,
        status=(request.GET.get("request_status") or "").strip(),
    )
    if request_status_filter not in {
        UnifiedRequestStatus.NEW,
        UnifiedRequestStatus.IN_PROGRESS,
        UnifiedRequestStatus.CLOSED,
    }:
        request_status_filter = ""

    extras_inquiries_base_qs = _extras_inquiries_queryset_for_user(request.user).filter(
        ticket_type=SupportTicketType.EXTRAS
    )
    selected_inquiry_id_raw = (request.GET.get("inquiry") or "").strip()
    selected_inquiry = (
        extras_inquiries_base_qs.filter(id=int(selected_inquiry_id_raw)).first()
        if selected_inquiry_id_raw.isdigit()
        else None
    )

    extras_inquiries_qs = extras_inquiries_base_qs
    if inquiry_q:
        extras_inquiries_qs = extras_inquiries_qs.filter(
            Q(code__icontains=inquiry_q)
            | Q(description__icontains=inquiry_q)
            | Q(requester__provider_profile__display_name__icontains=inquiry_q)
            | Q(requester__username__icontains=inquiry_q)
            | Q(requester__phone__icontains=inquiry_q)
        )
    extras_inquiries = list(extras_inquiries_qs.order_by("-created_at", "-id"))
    inquiry_form = ExtrasInquiryActionForm(
        initial={
            "status": selected_inquiry.status if selected_inquiry else SupportTicketStatus.NEW,
            "assigned_to": str(selected_inquiry.assigned_to_id or "") if selected_inquiry else "",
            "description": (selected_inquiry.description or "") if selected_inquiry else "",
            "operator_comment": "",
        },
        assignee_choices=assignee_choices,
    )

    extras_requests_base_qs = _extras_unified_queryset_for_user(request.user)
    selected_request_id_raw = (request.GET.get("request") or "").strip()
    selected_request = (
        extras_requests_base_qs.filter(id=int(selected_request_id_raw)).first()
        if selected_request_id_raw.isdigit()
        else None
    )

    selected_request_purchase = None
    if selected_request is not None:
        raw_purchase_id = str(selected_request.source_object_id or "").strip()
        if raw_purchase_id.isdigit():
            selected_request_purchase = (
                ExtraPurchase.objects.select_related("user", "user__provider_profile", "invoice")
                .filter(pk=int(raw_purchase_id))
                .first()
            )

    selected_request_bundle_sections = (
        extras_bundle_detail_sections_for_request(selected_request)
        if selected_request is not None
        else []
    )
    selected_request_invoice = (
        getattr(selected_request_purchase, "invoice", None)
        if selected_request_purchase is not None
        else extras_bundle_invoice_for_request(selected_request)
        if selected_request is not None
        else None
    )
    selected_request_invoice_details = _extras_invoice_details(
        selected_request_invoice,
        request_obj=selected_request,
    )
    selected_request_billing_state = _extras_request_billing_state(
        selected_request,
        invoice=selected_request_invoice,
        invoice_details=selected_request_invoice_details,
    )
    if selected_request_invoice_details is not None:
        selected_request_payment_status_label = selected_request_invoice_details["status_label"]
    else:
        selected_request_payment_status_label = "لا توجد فاتورة"
    selected_request_invoice_action_label = (
        "تحديث الفاتورة"
        if selected_request_invoice is not None and not selected_request_invoice.is_payment_effective()
        else "إصدار الفاتورة"
    )

    selected_request_status_code = (
        canonical_status_for_workflow(
            request_type=UnifiedRequestType.EXTRAS,
            status=selected_request.status,
        )
        if selected_request is not None
        else UnifiedRequestStatus.NEW
    )
    selected_request_invoice_title = (
        str(getattr(selected_request_invoice, "title", "") or "").strip()
        if selected_request_invoice is not None
        else (
            (
                f"عرض سعر {selected_request_purchase.title}"
                if selected_request_purchase is not None and getattr(selected_request_purchase, "title", "")
                else ""
            )
            or (
                f"عرض سعر {selected_request.summary}"
                if selected_request is not None and getattr(selected_request, "summary", "")
                else ""
            )
            or "عرض سعر طلب خدمات إضافية"
        )
    )
    selected_request_invoice_description = (
        str(getattr(selected_request_invoice, "description", "") or "").strip()
        if selected_request_invoice is not None
        else (
            str(getattr(selected_request, "summary", "") or "").strip()
            if selected_request is not None
            else ""
        )
    )
    selected_request_form = (
        ExtrasRequestActionForm(
            initial={
                "status": selected_request_status_code,
                "assigned_to": str(getattr(selected_request, "assigned_user_id", "") or ""),
                "operator_comment": _extras_request_operator_comment(selected_request),
                "invoice_title": selected_request_invoice_title,
                "invoice_description": selected_request_invoice_description,
            },
            assignee_choices=assignee_choices,
            status_choices=_extras_request_status_choices_for(selected_request_status_code),
        )
        if selected_request is not None
        else None
    )

    inquiry_query_params = request.GET.copy()
    inquiry_query_params.pop("inquiry", None)
    inquiry_detail_base_query = inquiry_query_params.urlencode()

    request_query_params = request.GET.copy()
    request_query_params.pop("request", None)
    request_detail_base_query = request_query_params.urlencode()

    extras_requests_qs = extras_requests_base_qs
    if request_q:
        extras_requests_qs = extras_requests_qs.filter(
            Q(code__icontains=request_q)
            | Q(summary__icontains=request_q)
            | Q(requester__provider_profile__display_name__icontains=request_q)
            | Q(requester__username__icontains=request_q)
            | Q(requester__phone__icontains=request_q)
        )
    extras_requests = list(extras_requests_qs)
    extras_request_rows = _extras_request_rows(extras_requests)
    if request_status_filter:
        extras_request_rows = [
            row for row in extras_request_rows if row.get("request_status_code") == request_status_filter
        ]
    active_section_request_rows = list(extras_request_rows)
    active_section_request_summary = _extras_requests_summary(active_section_request_rows)
    selected_request_matches_active_section = True
    selected_request_focus_section = None
    if active_section in {
        EXTRAS_DASHBOARD_SECTION_REPORTS,
        EXTRAS_DASHBOARD_SECTION_CLIENTS,
        EXTRAS_DASHBOARD_SECTION_FINANCE,
    }:
        active_section_request_rows = _extras_request_rows_for_section(extras_request_rows, active_section)
        active_section_request_summary = _extras_requests_summary(active_section_request_rows)
        selected_request_focus_section = _extras_request_section_detail(selected_request, active_section)
        selected_request_matches_active_section = bool(
            selected_request is not None and selected_request_focus_section is not None
        )
    for row in extras_request_rows:
        row["is_selected"] = bool(selected_request is not None and row.get("id") == selected_request.id)
    for row in active_section_request_rows:
        row["is_selected"] = bool(
            selected_request_matches_active_section
            and selected_request is not None
            and row.get("id") == selected_request.id
        )

    extras_purchases_base_qs = _extras_purchases_queryset_for_user(request.user)
    extras_finance_qs = extras_purchases_base_qs
    if finance_q:
        extras_finance_qs = extras_finance_qs.filter(
            Q(sku__icontains=finance_q)
            | Q(title__icontains=finance_q)
            | Q(user__provider_profile__display_name__icontains=finance_q)
            | Q(user__username__icontains=finance_q)
            | Q(user__phone__icontains=finance_q)
            | Q(invoice__code__icontains=finance_q)
        )
    extras_finance_rows = _extras_purchase_rows(list(extras_finance_qs))

    selected_subscriber_id = (request.GET.get("subscriber") or "").strip()
    extras_subscribers_rows = _extras_subscription_rows(list(_extras_portal_subscriptions_queryset_for_user(request.user)))
    if subscribers_q:
        subscribers_q_normalized = subscribers_q.casefold()
        extras_subscribers_rows = [
            row for row in extras_subscribers_rows if subscribers_q_normalized in row.get("search_text", "")
        ]
    selected_subscriber_row = None
    for row in extras_subscribers_rows:
        row.pop("search_text", None)
        row["is_selected"] = row.get("id") == selected_subscriber_id
        if row["is_selected"]:
            selected_subscriber_row = row

    subscriber_query_params = request.GET.copy()
    subscriber_query_params.pop("subscriber", None)
    subscriber_detail_base_query = subscriber_query_params.urlencode()
    selected_subscriber_close_url = (
        f"{request.path}?{subscriber_detail_base_query}" if subscriber_detail_base_query else request.path
    )

    specialist_identifier = str(bundle_draft.get("specialist_identifier", "") or "").strip()
    specialist_user = _extras_resolve_specialist(specialist_identifier)
    specialist_lookup_error = (
        "تعذر العثور على مزود الخدمة المحدد. أدخل اسم المستخدم أو رقم الجوال الصحيح."
        if specialist_identifier and specialist_user is None
        else ""
    )
    specialist_display_name = ""
    if specialist_user is not None:
        provider_profile = getattr(specialist_user, "provider_profile", None)
        specialist_display_name = (
            str(getattr(provider_profile, "display_name", "") or "").strip()
            or str(getattr(specialist_user, "username", "") or "").strip()
            or str(getattr(specialist_user, "phone", "") or "").strip()
        )
    report_start_at = _parse_datetime_local(bundle_draft.get("reports", {}).get("start_at", ""))
    report_end_at = _parse_datetime_local(bundle_draft.get("reports", {}).get("end_at", ""))
    client_years = max(1, int(bundle_draft.get("clients", {}).get("subscription_years", 1) or 1))
    client_preview_start_at = timezone.localtime(timezone.now())
    client_preview_end_at = _extras_add_years(client_preview_start_at, client_years)
    finance_years = max(1, int(bundle_draft.get("finance", {}).get("subscription_years", 1) or 1))
    finance_preview_start_at = timezone.localtime(timezone.now())
    finance_preview_end_at = _extras_add_years(finance_preview_start_at, finance_years)

    bundle_summary_sections = _extras_bundle_summary_sections(bundle_draft)
    bundle_has_selections = _extras_bundle_has_selection(bundle_draft)
    report_bundle_summary = next(
        (section for section in bundle_summary_sections if section.get("key") == EXTRAS_DASHBOARD_SECTION_REPORTS),
        {"items": []},
    )
    client_bundle_summary = next(
        (section for section in bundle_summary_sections if section.get("key") == EXTRAS_DASHBOARD_SECTION_CLIENTS),
        {"items": [], "meta_lines": []},
    )
    finance_bundle_summary = next(
        (section for section in bundle_summary_sections if section.get("key") == EXTRAS_DASHBOARD_SECTION_FINANCE),
        {"items": []},
    )
    created_request_id_raw = (request.GET.get("created_request") or "").strip()
    created_request = (
        _extras_unified_queryset_for_user(request.user).filter(id=int(created_request_id_raw)).first()
        if created_request_id_raw.isdigit()
        else None
    )

    if active_section == EXTRAS_DASHBOARD_SECTION_REQUEST_SUMMARY:
        active_section = EXTRAS_DASHBOARD_SECTION_CLIENTS
    elif active_section == EXTRAS_DASHBOARD_SECTION_REQUEST_CREATED:
        active_section = EXTRAS_DASHBOARD_MAIN_SECTION

    if active_section in {
        EXTRAS_DASHBOARD_SECTION_CLIENTS,
        EXTRAS_DASHBOARD_SECTION_REPORTS,
        EXTRAS_DASHBOARD_SECTION_FINANCE,
    } and not specialist_display_name:
        specialist_display_name = "لم يتم تحديد مزود الخدمة بعد"

    finance_qr_first_name = str(bundle_draft.get("finance", {}).get("qr_first_name", "") or "").strip()
    finance_qr_last_name = str(bundle_draft.get("finance", {}).get("qr_last_name", "") or "").strip()
    finance_iban = str(bundle_draft.get("finance", {}).get("iban", "") or "").strip()
    if specialist_user is not None:
        if not finance_qr_first_name:
            finance_qr_first_name = str(getattr(specialist_user, "first_name", "") or "").strip()
        if not finance_qr_last_name:
            finance_qr_last_name = str(getattr(specialist_user, "last_name", "") or "").strip()
        if not finance_iban:
            provider_profile = getattr(specialist_user, "provider_profile", None)
            settings_obj = getattr(provider_profile, "extras_portal_finance_settings", None) if provider_profile is not None else None
            finance_iban = str(getattr(settings_obj, "iban", "") or "").strip()

    hero_subtitle = {
        EXTRAS_DASHBOARD_SECTION_OVERVIEW: "الصفحة الرئيسية تعرض فقط قائمة استفسارات الخدمات الإضافية وقائمة طلبات الخدمات الإضافية.",
        EXTRAS_DASHBOARD_SECTION_REPORTS: "يعرض هذا القسم طلبات التقارير الخاصة بالخدمات الإضافية مع إمكانية مراجعة البنود، متابعة الحالة، والتسعير اليدوي من نفس الصفحة.",
        EXTRAS_DASHBOARD_SECTION_CLIENTS: "يعرض هذا القسم طلبات إدارة العملاء مع أدوات تشغيل ومراجعة إدارية، مع الإبقاء على نموذج إعداد طلب جديد داخل نفس المسار.",
        EXTRAS_DASHBOARD_SECTION_FINANCE: "يعرض هذا القسم طلبات الإدارة المالية الجاهزة للمعالجة الإدارية، مع استمرار دعم إعداد طلبات جديدة وخيارات البيانات المالية.",
        EXTRAS_DASHBOARD_SECTION_SUBSCRIBERS: "يعرض هذا القسم سجلات المشتركين الفعلية للخدمات الإضافية اعتمادًا على اشتراك البوابة وآخر طلب مكتمل وفاتورته المعتمدة.",
    }.get(active_section, "")
    active_section_label = {
        EXTRAS_DASHBOARD_SECTION_OVERVIEW: "الرئيسية",
        EXTRAS_DASHBOARD_SECTION_REPORTS: "التقارير",
        EXTRAS_DASHBOARD_SECTION_CLIENTS: "إدارة العملاء",
        EXTRAS_DASHBOARD_SECTION_FINANCE: "الإدارة المالية",
        EXTRAS_DASHBOARD_SECTION_SUBSCRIBERS: "بيانات مشتركي الخدمات الإضافية",
    }.get(active_section, "")

    latest_helpdesk_code = (
        SupportTicket.objects.filter(ticket_type=SupportTicketType.EXTRAS)
        .exclude(code="")
        .order_by("-id")
        .values_list("code", flat=True)
        .first()
        or "HD000001"
    )

    context = {
        "hero_title": "لوحة فريق إدارة الخدمات الإضافية",
        "hero_subtitle": hero_subtitle,
        "can_write": can_write,
        "extras_team_label": extras_team_name,
        "nav_items": _extras_nav_items(active_section),
        "active_section": active_section,
        "active_section_label": active_section_label,
        "extras_inquiries": _subscription_inquiry_rows(extras_inquiries),
        "extras_requests": extras_request_rows,
        "active_section_request_rows": active_section_request_rows,
        "active_section_request_summary": active_section_request_summary,
        "extras_finance_rows": extras_finance_rows,
        "extras_subscribers_rows": extras_subscribers_rows,
        "selected_subscriber_row": selected_subscriber_row,
        "selected_inquiry": selected_inquiry,
        "selected_inquiry_requester_name": _promo_requester_label(selected_inquiry.requester) if selected_inquiry else "",
        "selected_inquiry_status_label": _subscription_inquiry_status_label(
            selected_inquiry.status if selected_inquiry else ""
        ),
        "selected_request": selected_request,
        "selected_request_requester_name": _promo_requester_label(selected_request.requester) if selected_request else "",
        "selected_request_purchase": selected_request_purchase,
        "selected_request_invoice": selected_request_invoice,
        "selected_request_invoice_details": selected_request_invoice_details,
        "selected_request_billing_state": selected_request_billing_state,
        "selected_request_invoice_action_label": selected_request_invoice_action_label,
        "selected_request_payment_status_label": selected_request_payment_status_label,
        "selected_request_bundle_sections": selected_request_bundle_sections,
        "selected_request_focus_section": selected_request_focus_section,
        "selected_request_matches_active_section": selected_request_matches_active_section,
        "selected_request_form": selected_request_form,
        "selected_request_status_label": _extras_request_status_label(selected_request_status_code),
        "selected_request_status_help_text": (
            _extras_request_status_help_text(selected_request_status_code)
            if selected_request is not None
            else ""
        ),
        "selected_request_can_save": bool(
            can_write
            and selected_request_form is not None
            and selected_request_status_code in {UnifiedRequestStatus.NEW, UnifiedRequestStatus.IN_PROGRESS}
        ),
        "selected_request_can_invoice": bool(
            can_write
            and selected_request is not None
            and selected_request_status_code in {UnifiedRequestStatus.NEW, UnifiedRequestStatus.IN_PROGRESS}
            and (selected_request_invoice is None or not selected_request_invoice.is_payment_effective())
        ),
        "selected_request_has_paid_invoice": bool(
            selected_request_invoice is not None and selected_request_invoice.is_payment_effective()
        ),
        "extras_vat_percent": _extras_vat_percent(),
        "report_options": [{"key": key, "label": label} for key, label in EXTRAS_REPORT_OPTIONS],
        "report_option_groups": _extras_report_option_groups(),
        "client_options": [{"key": key, "label": label, "unavailable": key in UNAVAILABLE_CLIENT_OPTIONS} for key, label in EXTRAS_CLIENT_OPTIONS],
        "finance_options": [{"key": key, "label": label, "unavailable": key in UNAVAILABLE_FINANCE_OPTIONS} for key, label in EXTRAS_FINANCE_OPTIONS],
        "bundle_selected_report_options": list(bundle_draft.get("reports", {}).get("options", [])),
        "bundle_selected_client_options": list(bundle_draft.get("clients", {}).get("options", [])),
        "bundle_selected_finance_options": list(bundle_draft.get("finance", {}).get("options", [])),
        "bundle_form_values": {
            "reports_start_at": _extras_datetime_input_value(bundle_draft.get("reports", {}).get("start_at", "")),
            "reports_end_at": _extras_datetime_input_value(bundle_draft.get("reports", {}).get("end_at", "")),
            "clients_subscription_years": client_years,
            "clients_bulk_message_count": max(0, int(bundle_draft.get("clients", {}).get("bulk_message_count", 0) or 0)),
            "finance_subscription_years": finance_years,
            "finance_qr_first_name": finance_qr_first_name,
            "finance_qr_last_name": finance_qr_last_name,
            "finance_iban": finance_iban,
        },
        "bundle_summary_sections": bundle_summary_sections,
        "bundle_has_selections": bundle_has_selections,
        "report_bundle_summary": report_bundle_summary,
        "report_preview_start_at": _extras_human_datetime(report_start_at),
        "report_preview_end_at": _extras_human_datetime(report_end_at),
        "client_bundle_summary": client_bundle_summary,
        "client_preview_start_at": _extras_human_datetime(client_preview_start_at),
        "client_preview_end_at": _extras_human_datetime(client_preview_end_at),
        "finance_bundle_summary": finance_bundle_summary,
        "finance_preview_start_at": _extras_human_datetime(finance_preview_start_at),
        "finance_preview_end_at": _extras_human_datetime(finance_preview_end_at),
        "specialist_identifier": specialist_identifier,
        "specialist_display_name": specialist_display_name,
        "specialist_lookup_error": specialist_lookup_error,
        "extras_specialist_search_api_url": reverse("dashboard:extras_specialist_search_api"),
        "created_request": created_request,
        "created_request_code": getattr(created_request, "code", "") or "",
        "inquiry_form": inquiry_form,
        "close_inquiry_url": _extras_close_inquiry_url(
            request,
            selected_request_id=getattr(selected_request, "id", None),
        ),
        "close_request_url": _extras_close_request_url(
            request,
            selected_inquiry_id=getattr(selected_inquiry, "id", None),
        ),
        "inquiry_detail_base_query": inquiry_detail_base_query,
        "request_detail_base_query": request_detail_base_query,
        "subscriber_detail_base_query": subscriber_detail_base_query,
        "selected_subscriber_close_url": selected_subscriber_close_url,
        "inquiry_summary": _support_summary(extras_inquiries),
        "request_summary": _extras_requests_summary(extras_request_rows),
        "finance_summary": _extras_finance_summary(extras_finance_rows),
        "subscribers_summary": _extras_subscribers_summary(extras_subscribers_rows),
        "request_codes": [
            {"code": latest_helpdesk_code, "label": "استفسارات الخدمات الإضافية"},
            {"code": _latest_request_code("P", request_type=UnifiedRequestType.EXTRAS), "label": "طلبات الخدمات الإضافية"},
        ],
        "filters": {
            "section": active_section,
            "inquiry_q": inquiry_q,
            "request_q": request_q,
            "finance_q": finance_q,
            "subscribers_q": subscribers_q,
            "request_status": request_status_filter,
        },
        "request_status_choices": EXTRAS_REQUEST_STATUS_CHOICES,
        "redirect_query": request.GET.urlencode(),
    }
    return render(request, "dashboard/extras_dashboard.html", context)


PROMO_MODULE_DEFINITIONS = (
    {
        "key": "home_banner",
        "service_type": PromoServiceType.HOME_BANNER,
        "label": "بنر الصفحة الرئيسية",
        "description": "رفع تصميم البنر وجدولة الظهور على الصفحة الرئيسية.",
    },
    {
        "key": "featured_specialists",
        "service_type": PromoServiceType.FEATURED_SPECIALISTS,
        "label": "شريط أبرز المختصين",
        "description": "إعطاء أولوية ظهور للمختصين في الشريط العلوي.",
    },
    {
        "key": "portfolio_showcase",
        "service_type": PromoServiceType.PORTFOLIO_SHOWCASE,
        "label": "شريط البنرات والمشاريع",
        "description": "إبراز المشاريع والبنرات المختارة بجدولة زمنية.",
    },
    {
        "key": "snapshots",
        "service_type": PromoServiceType.SNAPSHOTS,
        "label": "شريط اللمحات",
        "description": "رفع اللمحات الحديثة والتحكم بمعدل ظهورها.",
    },
    {
        "key": "search_results",
        "service_type": PromoServiceType.SEARCH_RESULTS,
        "label": "الظهور في قوائم البحث",
        "description": "اختيار ترتيب الظهور داخل نتائج البحث وقائمته.",
    },
    {
        "key": "promo_messages",
        "service_type": PromoServiceType.PROMO_MESSAGES,
        "label": "الرسائل الدعائية",
        "description": "جدولة رسائل التنبيه أو المحادثات مع نص ومواد داعمة.",
    },
    {
        "key": "sponsorship",
        "service_type": PromoServiceType.SPONSORSHIP,
        "label": "الرعاية",
        "description": "إدارة حملات الرعاية (اسم الراعي، الرابط، مدة الرعاية).",
    },
)
PROMO_MODULE_META_BY_KEY = {row["key"]: row for row in PROMO_MODULE_DEFINITIONS}
PROMO_TARGETED_SERVICE_TYPES = {
    PromoServiceType.FEATURED_SPECIALISTS,
    PromoServiceType.PORTFOLIO_SHOWCASE,
    PromoServiceType.SNAPSHOTS,
    PromoServiceType.SEARCH_RESULTS,
}


def _promo_nav_items(active_key: str) -> list[dict]:
    items = []
    for module in PROMO_MODULE_DEFINITIONS:
        items.append(
            {
                "key": module["key"],
                "label": module["label"],
                "description": module["description"],
                "url": reverse("dashboard:promo_module", kwargs={"module_key": module["key"]}),
            }
        )
    items.append(
        {
            "key": "pricing",
            "label": "الأسعار",
            "description": "جدول تسعير خدمات الترويج المعتمدة.",
            "url": reverse("dashboard:promo_pricing"),
        }
    )
    for item in items:
        item["active"] = item["key"] == active_key
    return items


def _promo_base_context(active_key: str) -> dict:
    latest_helpdesk_code = (
        SupportTicket.objects.exclude(code="").order_by("-id").values_list("code", flat=True).first()
        or "HD000001"
    )
    latest_promo_code = (
        PromoRequest.objects.exclude(code="").order_by("-id").values_list("code", flat=True).first()
        or "MD000001"
    )

    return {
        "nav_items": _promo_nav_items(active_key),
        "request_codes": [
            {"code": latest_helpdesk_code, "label": "استفسارات الترويج"},
            {"code": latest_promo_code, "label": "طلبات الترويج"},
        ],
    }


def _promo_inquiries_queryset_for_user(user):
    return _support_queryset_for_user(user).filter(
        _support_ticket_dashboard_q("promo", fallback_team_codes=["promo"])
        | Q(assigned_team__isnull=True, ticket_type=SupportTicketType.ADS)
    ).distinct()


def _promo_requests_queryset_for_user(user):
    qs = (
        PromoRequest.objects.select_related("requester", "requester__provider_profile", "assigned_to", "invoice")
        .prefetch_related("items", "assets", "assets__uploaded_by", "assets__item")
        .order_by("-updated_at", "-id")
    )
    access_profile = active_access_profile_for_user(user)
    if access_profile and access_profile.level == AccessLevel.USER:
        qs = qs.filter(Q(assigned_to=user) | Q(assigned_to__isnull=True))
    return qs


def _promo_requester_label(user_obj) -> str:
    return _dashboard_requester_display_name(user_obj)


def _promo_assignee_label(promo_request: PromoRequest) -> str:
    if promo_request.assigned_to:
        return (promo_request.assigned_to.username or promo_request.assigned_to.phone or "").strip() or "غير مكلف"
    return "غير مكلف"


def _promo_inquiry_rows(tickets: list[SupportTicket]) -> list[dict]:
    subscriptions_by_user_id = _effective_subscriptions_map_for_users(
        [getattr(ticket, "requester", None) for ticket in tickets]
    )
    rows: list[dict] = []
    for ticket in tickets:
        team_label = _support_team_label(ticket)
        team_label = team_label.replace("فريق ", "") if team_label.startswith("فريق ") else team_label
        priority_number = _dashboard_priority_number_for_user(
            ticket.requester,
            subscriptions_by_user_id=subscriptions_by_user_id,
        )
        rows.append(
            {
                "id": ticket.id,
                "code": ticket.code or f"HD{ticket.id:06d}",
                "requester": _support_requester_label(ticket),
                "priority_number": priority_number,
                "priority_class": _dashboard_priority_class_for_user(
                    ticket.requester,
                    subscriptions_by_user_id=subscriptions_by_user_id,
                ),
                "ticket_type": ticket.get_ticket_type_display(),
                "created_at": _format_dt(ticket.created_at),
                "status": ticket.get_status_display(),
                "team": team_label,
                "assignee": _support_assignee_label(ticket),
                "assigned_at": _format_dt(ticket.assigned_at),
            }
        )
    return rows


def _promo_request_rows(requests: list[PromoRequest]) -> list[dict]:
    subscriptions_by_user_id = _effective_subscriptions_map_for_users(
        [getattr(promo_request, "requester", None) for promo_request in requests]
    )
    rows: list[dict] = []
    for promo_request in requests:
        priority_number = _dashboard_priority_number_for_user(
            promo_request.requester,
            subscriptions_by_user_id=subscriptions_by_user_id,
        )
        ops_status_label = _promo_request_ops_status_label(promo_request)
        rows.append(
            {
                "id": promo_request.id,
                "code": promo_request.code or f"MD{promo_request.id:06d}",
                "requester": _promo_requester_label(promo_request.requester),
                "priority_number": priority_number,
                "priority_class": _dashboard_priority_class_for_user(
                    promo_request.requester,
                    subscriptions_by_user_id=subscriptions_by_user_id,
                ),
                "created_at": _format_dt(promo_request.created_at),
                "approved_at": _format_dt(promo_request.reviewed_at or promo_request.created_at),
                "request_status": _promo_request_operational_status_label(promo_request),
                "ops_status": ops_status_label,
                "team": "إدارة الترويج",
                "assignee": _promo_assignee_label(promo_request),
                "assigned_at": _format_dt(promo_request.assigned_at),
                "invoice_status": getattr(promo_request.invoice, "status", "") or "بدون فاتورة",
            }
        )
    return rows


def _promo_inquiry_summary(tickets: list[SupportTicket]) -> dict:
    by_status: dict[str, int] = {}
    for ticket in tickets:
        by_status[ticket.status] = by_status.get(ticket.status, 0) + 1
    return {
        "total": len(tickets),
        "new": by_status.get(SupportTicketStatus.NEW, 0),
        "in_progress": by_status.get(SupportTicketStatus.IN_PROGRESS, 0),
        "returned": by_status.get(SupportTicketStatus.RETURNED, 0),
        "closed": by_status.get(SupportTicketStatus.CLOSED, 0),
    }


def _promo_requests_summary(requests: list[PromoRequest]) -> dict:
    by_status: dict[str, int] = {}
    invoice_pending = 0
    active_campaigns = 0
    for promo_request in requests:
        by_status[promo_request.ops_status] = by_status.get(promo_request.ops_status, 0) + 1
        if promo_request.invoice and not promo_request.invoice.is_payment_effective():
            invoice_pending += 1
        if promo_request.status == PromoRequestStatus.ACTIVE:
            active_campaigns += 1
    return {
        "total": len(requests),
        "new": by_status.get(PromoOpsStatus.NEW, 0),
        "in_progress": by_status.get(PromoOpsStatus.IN_PROGRESS, 0),
        "completed": by_status.get(PromoOpsStatus.COMPLETED, 0),
        "invoice_pending": invoice_pending,
        "active_campaigns": active_campaigns,
    }


def _promo_request_operational_status_code(promo_request: PromoRequest | None) -> str:
    if promo_request is None:
        return PromoRequestStatus.NEW

    payment_effective = bool(promo_request.invoice and promo_request.invoice.is_payment_effective())
    request_status = str(promo_request.status or "").strip()
    ops_status = str(promo_request.ops_status or PromoOpsStatus.NEW).strip()

    if request_status in {
        PromoRequestStatus.REJECTED,
        PromoRequestStatus.CANCELLED,
        PromoRequestStatus.EXPIRED,
        PromoRequestStatus.COMPLETED,
    }:
        return request_status

    if request_status == PromoRequestStatus.ACTIVE or ops_status == PromoOpsStatus.COMPLETED:
        return PromoRequestStatus.ACTIVE

    if payment_effective:
        if ops_status == PromoOpsStatus.IN_PROGRESS:
            return PromoOpsStatus.IN_PROGRESS
        return "awaiting_review"

    if request_status == PromoRequestStatus.IN_REVIEW:
        return PromoRequestStatus.IN_REVIEW
    if request_status in {PromoRequestStatus.QUOTED, PromoRequestStatus.PENDING_PAYMENT}:
        return request_status
    return PromoRequestStatus.NEW


def _promo_request_operational_status_label(promo_request: PromoRequest | None) -> str:
    status_code = _promo_request_operational_status_code(promo_request)
    return {
        "awaiting_review": "بانتظار المراجعة",
        PromoOpsStatus.IN_PROGRESS: "تحت المعالجة",
        PromoRequestStatus.NEW: "جديد",
        PromoRequestStatus.IN_REVIEW: "قيد المراجعة",
        PromoRequestStatus.QUOTED: "تم التسعير",
        PromoRequestStatus.PENDING_PAYMENT: "بانتظار الدفع",
        PromoRequestStatus.ACTIVE: "مفعل",
        PromoRequestStatus.COMPLETED: "مكتمل",
        PromoRequestStatus.REJECTED: "مرفوض",
        PromoRequestStatus.EXPIRED: "منتهي",
        PromoRequestStatus.CANCELLED: "ملغي",
    }.get(status_code, status_code or "-")


def _promo_request_ops_status_label(promo_request: PromoRequest | None) -> str:
    if promo_request is None:
        return "-"
    if promo_request.status == PromoRequestStatus.EXPIRED:
        return promo_request.get_status_display()
    return promo_request.get_ops_status_display()


def _promo_request_payment_status_label(promo_request: PromoRequest | None) -> str:
    if promo_request is None:
        return ""

    invoice = getattr(promo_request, "invoice", None)
    if invoice is not None:
        return "مدفوعة" if invoice.is_payment_effective() else "بانتظار الدفع"

    if promo_request.status in {PromoRequestStatus.QUOTED, PromoRequestStatus.PENDING_PAYMENT}:
        return "بانتظار الدفع"

    return ""


def _promo_inquiry_export_rows(tickets: list[SupportTicket]) -> tuple[list[str], list[list]]:
    headers = [
        "رقم الطلب",
        "اسم العميل",
        "الأولوية",
        "نوع الطلب",
        "تاريخ ووقت استلام الطلب",
        "حالة الطلب",
        "فريق الدعم",
        "المكلف بالطلب",
        "تاريخ ووقت التكليف",
    ]
    rows: list[list] = []
    for row in _promo_inquiry_rows(tickets):
        rows.append(
            [
                row["code"],
                row["requester"],
                row["priority_number"],
                row["ticket_type"],
                row["created_at"],
                row["status"],
                row["team"],
                row["assignee"],
                row["assigned_at"],
            ]
        )
    return headers, rows


def _promo_request_export_rows(requests: list[PromoRequest]) -> tuple[list[str], list[list]]:
    headers = [
        "رقم الطلب",
        "اسم العميل",
        "الأولوية",
        "تاريخ وقت اعتماد الطلب",
        "حالة الطلب",
        "المكلف بالطلب",
        "تاريخ وقت التكليف",
    ]
    rows: list[list] = []
    for row in _promo_request_rows(requests):
        rows.append(
            [
                row["code"],
                row["requester"],
                row["priority_number"],
                row["approved_at"],
                row["request_status"],
                row["assignee"],
                row["assigned_at"],
            ]
        )
    return headers, rows


def _promo_redirect_with_state(request, *, request_id: int | None = None, inquiry_id: int | None = None):
    query = (request.POST.get("redirect_query") or request.GET.urlencode()).strip()
    base = request.path
    params = QueryDict(query, mutable=True)
    if inquiry_id is not None:
        params["inquiry"] = str(inquiry_id)
    if request_id is not None:
        params["request"] = str(request_id)

    normalized_query = params.urlencode()
    return redirect(f"{base}?{normalized_query}") if normalized_query else redirect(base)


def _promo_asset_type_for_upload(uploaded_file) -> str:
    ext = str(getattr(uploaded_file, "name", "") or "").lower().rsplit(".", 1)[-1]
    if ext in {"jpg", "jpeg", "png", "webp", "gif"}:
        return PromoAssetType.IMAGE
    if ext in {"mp4", "mov", "avi"}:
        return PromoAssetType.VIDEO
    if ext == "pdf":
        return PromoAssetType.PDF
    return PromoAssetType.OTHER


def _promo_quote_snapshot(promo_request: PromoRequest) -> dict | None:
    try:
        payload = calc_promo_request_quote(pr=promo_request)
    except ValueError:
        return None
    from apps.billing.pricing import get_vat_percent

    subtotal = Decimal(str(payload.get("subtotal") or "0.00")).quantize(Decimal("0.01"))
    vat_percent = Decimal(str(get_vat_percent("promo"))).quantize(Decimal("0.01"))
    vat_amount = (subtotal * vat_percent / Decimal("100")).quantize(Decimal("0.01"))
    total = (subtotal + vat_amount).quantize(Decimal("0.01"))
    quote_items = []
    for row in payload.get("items", []) or []:
        item = row.get("item")
        if not item:
            continue
        quote_items.append(
            {
                "service_label": item.get_service_type_display(),
                "title": item.title or item.get_service_type_display(),
                "subtotal": item.subtotal,
                "duration_days": item.duration_days,
            }
        )
    return {
        "subtotal": subtotal,
        "vat_percent": vat_percent,
        "vat_amount": vat_amount,
        "total": total,
        "days": int(payload.get("days") or 0),
        "items": quote_items,
    }

def _promo_items_missing_required_assets(selected_request: PromoRequest | None) -> list[str]:
    if selected_request is None:
        return []

    required_service_types = {
        PromoServiceType.HOME_BANNER,
        PromoServiceType.SPONSORSHIP,
    }

    missing_labels: list[str] = []
    for item in selected_request.items.all():
        if item.service_type in required_service_types and not item.assets.exists():
            missing_labels.append(item.get_service_type_display())

    # إزالة التكرار مع الحفاظ على الترتيب
    unique_labels: list[str] = []
    seen: set[str] = set()
    for label in missing_labels:
        if label not in seen:
            seen.add(label)
            unique_labels.append(label)
    return unique_labels


def _promo_ops_choices_for_request(selected_request: PromoRequest | None) -> list[tuple[str, str]]:
    base_choices = list(PromoOpsStatus.choices)
    if selected_request is None:
        return base_choices

    current_status = selected_request.ops_status or PromoOpsStatus.NEW
    allowed_by_current = {
        PromoOpsStatus.NEW: {PromoOpsStatus.NEW, PromoOpsStatus.IN_PROGRESS},
        PromoOpsStatus.IN_PROGRESS: {PromoOpsStatus.IN_PROGRESS, PromoOpsStatus.COMPLETED},
        PromoOpsStatus.COMPLETED: {PromoOpsStatus.COMPLETED},
    }
    allowed = allowed_by_current.get(current_status)
    if not allowed:
        return base_choices
    return [choice for choice in base_choices if choice[0] in allowed]

@dashboard_staff_required
@require_dashboard_access("promo")
def promo_dashboard(request, request_id: int | None = None):
    expire_due_promos()
    can_write = dashboard_allowed(request.user, "promo", write=True)
    access_profile = active_access_profile_for_user(request.user)
    assignee_choices = _dashboard_assignee_choices("promo")
    promo_team = _promo_support_team()
    team_choices = [(str(promo_team.id), promo_team.name_ar)] if promo_team else []

    inquiries_base_qs = _promo_inquiries_queryset_for_user(request.user)
    promo_requests_base_qs = _promo_requests_queryset_for_user(request.user)

    inquiry_q = (request.GET.get("inquiry_q") or "").strip()
    request_q = (request.GET.get("request_q") or "").strip()
    ops_filter = (request.GET.get("ops") or "").strip()

    inquiries_qs = inquiries_base_qs
    if inquiry_q:
        inquiries_qs = inquiries_qs.filter(
            Q(code__icontains=inquiry_q)
            | Q(description__icontains=inquiry_q)
            | Q(requester__provider_profile__display_name__icontains=inquiry_q)
            | Q(requester__username__icontains=inquiry_q)
            | Q(requester__phone__icontains=inquiry_q)
        )
    inquiries = list(inquiries_qs.order_by("-created_at", "-id"))

    promo_requests_qs = promo_requests_base_qs
    if request_q:
        promo_requests_qs = promo_requests_qs.filter(
            Q(code__icontains=request_q)
            | Q(title__icontains=request_q)
            | Q(requester__provider_profile__display_name__icontains=request_q)
            | Q(requester__username__icontains=request_q)
            | Q(requester__phone__icontains=request_q)
        )
    if ops_filter and ops_filter != "all":
        promo_requests_qs = promo_requests_qs.filter(ops_status=ops_filter)
    elif ops_filter != "all":
        # Default: show only new ops_status on main page; in_progress/completed
        # requests are managed from their respective module sub-pages.
        promo_requests_qs = promo_requests_qs.filter(ops_status=PromoOpsStatus.NEW)
    promo_requests = list(promo_requests_qs)

    selected_inquiry_id_raw = (request.GET.get("inquiry") or "").strip()
    selected_inquiry = inquiries_base_qs.filter(id=int(selected_inquiry_id_raw)).first() if selected_inquiry_id_raw.isdigit() else None

    selected_request = None
    if request_id is not None:
        selected_request = promo_requests_base_qs.filter(id=request_id).first()
    if selected_request is None:
        selected_request_id_raw = (request.GET.get("request") or "").strip()
        if selected_request_id_raw.isdigit():
            selected_request = promo_requests_base_qs.filter(id=int(selected_request_id_raw)).first()

    linked_request_choices = [
        (str(row.id), f"{row.code or f'MD{row.id:06d}'} - {_promo_requester_label(row.requester)}")
        for row in promo_requests_base_qs[:200]
    ]

    inquiry_profile = getattr(selected_inquiry, "promo_profile", None) if selected_inquiry else None
    promo_team_id = promo_team.id if promo_team is not None else None
    initial_team_id = promo_team_id
    if initial_team_id is None and selected_inquiry is not None:
        initial_team_id = selected_inquiry.assigned_team_id

    inquiry_form = PromoInquiryActionForm(
        initial={
            "status": selected_inquiry.status if selected_inquiry else SupportTicketStatus.NEW,
            "assigned_team": str(initial_team_id or ""),
            "assigned_to": str(selected_inquiry.assigned_to_id or "") if selected_inquiry else "",
            "description": (selected_inquiry.description or "") if selected_inquiry else "",
            "operator_comment": (inquiry_profile.operator_comment or "") if inquiry_profile else "",
            "detailed_request_url": (inquiry_profile.detailed_request_url or "") if inquiry_profile else "",
            "linked_request_id": str(inquiry_profile.linked_request_id or "") if inquiry_profile else "",
        },
        assignee_choices=assignee_choices,
        team_choices=team_choices,
        linked_request_choices=linked_request_choices,
    )
    request_form = PromoRequestActionForm(
        initial={
            "assigned_to": str(selected_request.assigned_to_id or "") if selected_request else "",
            "ops_status": selected_request.ops_status if selected_request else PromoOpsStatus.NEW,
            "ops_note": (selected_request.quote_note or "") if selected_request else "",
        },
        assignee_choices=assignee_choices,
        ops_choices=_promo_ops_choices_for_request(selected_request),
    )

    if request.method == "POST":
        if not can_write:
            return HttpResponseForbidden("لا تملك صلاحية تعديل لوحة الترويج.")
        action = (request.POST.get("action") or "").strip()

        if action in {"save_inquiry", "close_inquiry"}:
            raw_ticket_id = (request.POST.get("ticket_id") or "").strip()
            if not raw_ticket_id.isdigit():
                messages.error(request, "تعذر تحديد الاستفسار المطلوب تحديثه.")
                return _promo_redirect_with_state(request)
            target_ticket = inquiries_base_qs.filter(id=int(raw_ticket_id)).first()
            if target_ticket is None:
                messages.error(request, "الاستفسار المحدد غير متاح لهذا الحساب.")
                return _promo_redirect_with_state(request)
            if access_profile and access_profile.level == AccessLevel.USER:
                if target_ticket.assigned_to_id and target_ticket.assigned_to_id != request.user.id:
                    return HttpResponseForbidden("غير مصرح: الاستفسار ليس ضمن المهام المكلف بها.")

            submitted_form_token = (request.POST.get("promo_inquiry_form_token") or "").strip()
            if not _consume_single_use_submit_token(
                request,
                PROMO_INQUIRY_SUBMIT_TOKENS_SESSION_KEY,
                submitted_form_token,
            ):
                messages.warning(request, "تم تجاهل محاولة الإرسال المكررة للاستفسار. حدّث الصفحة قبل إعادة الحفظ.")
                return _promo_redirect_with_state(request, inquiry_id=target_ticket.id)

            post_data = request.POST.copy()
            if promo_team is not None:
                post_data["assigned_team"] = str(promo_team.id)

            post_form = PromoInquiryActionForm(
                post_data,
                request.FILES,
                assignee_choices=assignee_choices,
                team_choices=team_choices,
                linked_request_choices=linked_request_choices,
            )
            if not post_form.is_valid():
                selected_inquiry = target_ticket
                inquiry_form = post_form
                messages.error(request, "يرجى مراجعة حقول نموذج الاستفسار.")
                return _promo_redirect_with_state(request, inquiry_id=target_ticket.id)

            desired_status = post_form.cleaned_data.get("status")
            if action == "close_inquiry":
                desired_status = SupportTicketStatus.CLOSED

            assigned_to_raw = (post_form.cleaned_data.get("assigned_to") or "").strip()
            team_id = promo_team.id if promo_team is not None else target_ticket.assigned_team_id
            assigned_to_id = int(assigned_to_raw) if assigned_to_raw.isdigit() else target_ticket.assigned_to_id

            if assigned_to_id is not None:
                assignee = dashboard_assignee_user(assigned_to_id, "promo", write=True)
                if assignee is None:
                    messages.error(request, "المكلف المختار لا يملك صلاحية لوحة الترويج.")
                    return _promo_redirect_with_state(request, inquiry_id=target_ticket.id)

            if team_id is not None and not SupportTeam.objects.filter(id=team_id).exists():
                messages.error(request, "فريق الدعم المحدد غير صالح.")
                return _promo_redirect_with_state(request, inquiry_id=target_ticket.id)

            note = post_form.cleaned_data.get("operator_comment") or ""
            target_ticket = assign_ticket(
                ticket=target_ticket,
                team_id=team_id,
                user_id=assigned_to_id,
                by_user=request.user,
                note=note,
            )

            new_description = post_form.cleaned_data.get("description") or target_ticket.description or ""
            if new_description != (target_ticket.description or ""):
                target_ticket.description = new_description
                target_ticket.last_action_by = request.user
                target_ticket.save(update_fields=["description", "last_action_by", "updated_at"])

            if desired_status and desired_status != target_ticket.status:
                try:
                    target_ticket = change_ticket_status(
                        ticket=target_ticket,
                        new_status=desired_status,
                        by_user=request.user,
                        note=note,
                    )
                except ValueError as exc:
                    messages.error(request, str(exc))
                    return _promo_redirect_with_state(request, inquiry_id=target_ticket.id)

            if note:
                SupportComment.objects.create(
                    ticket=target_ticket,
                    text=note[:300],
                    is_internal=True,
                    created_by=request.user,
                )

            attachment = post_form.cleaned_data.get("attachment")
            if attachment is not None:
                try:
                    attachment = _validate_and_optimize_dashboard_attachment(attachment, user=request.user)
                except DjangoValidationError as exc:
                    messages.error(request, str(exc))
                    return _promo_redirect_with_state(request, inquiry_id=target_ticket.id)
                SupportAttachment.objects.create(
                    ticket=target_ticket,
                    file=attachment,
                    uploaded_by=request.user,
                )

            linked_request_id_raw = (post_form.cleaned_data.get("linked_request_id") or "").strip()
            linked_request = PromoRequest.objects.filter(id=int(linked_request_id_raw)).first() if linked_request_id_raw.isdigit() else None
            profile, _ = PromoInquiryProfile.objects.get_or_create(ticket=target_ticket)
            profile.linked_request = linked_request
            profile.detailed_request_url = post_form.cleaned_data.get("detailed_request_url") or ""
            profile.operator_comment = note[:300]
            profile.save(
                update_fields=[
                    "linked_request",
                    "detailed_request_url",
                    "operator_comment",
                    "updated_at",
                ]
            )

            messages.success(request, f"تم تحديث استفسار الترويج {target_ticket.code or target_ticket.id} بنجاح.")
            return _promo_redirect_with_state(
                request,
                inquiry_id=target_ticket.id,
                request_id=(linked_request.id if linked_request else None),
            )

        if action in {"save_request", "quote_request", "activate_request", "complete_request", "reject_request"}:
            raw_request_id = (request.POST.get("promo_request_id") or "").strip()
            if not raw_request_id.isdigit():
                messages.error(request, "تعذر تحديد طلب الترويج المطلوب.")
                return _promo_redirect_with_state(request)
            target_request = promo_requests_base_qs.filter(id=int(raw_request_id)).first()
            if target_request is None:
                messages.error(request, "طلب الترويج المحدد غير متاح لهذا الحساب.")
                return _promo_redirect_with_state(request)
            if access_profile and access_profile.level == AccessLevel.USER:
                if target_request.assigned_to_id and target_request.assigned_to_id != request.user.id:
                    return HttpResponseForbidden("غير مصرح: الطلب ليس ضمن المهام المكلف بها.")

            legacy_actions = {"quote_request", "activate_request", "complete_request", "reject_request"}
            if action in legacy_actions:
                messages.error(
                    request,
                    "تم إيقاف الإجراء القديم. الإجراء المتاح الآن هو حفظ المكلف وحالة التنفيذ فقط.",
                )
                return _promo_redirect_with_state(request, request_id=target_request.id)

            if action == "save_request":
                submitted_form_token = (request.POST.get("promo_form_token") or "").strip()
                if not _consume_single_use_submit_token(
                    request,
                    PROMO_REQUEST_SUBMIT_TOKENS_SESSION_KEY,
                    submitted_form_token,
                ):
                    messages.warning(request, "تم تجاهل محاولة الحفظ المكررة. حدّث الصفحة قبل إعادة الحفظ.")
                    return _promo_redirect_with_state(request, request_id=target_request.id)

            _save_blocked_statuses = {
                PromoRequestStatus.ACTIVE,
                PromoRequestStatus.COMPLETED,
                PromoRequestStatus.EXPIRED,
                PromoRequestStatus.CANCELLED,
                PromoRequestStatus.REJECTED,
            }
            if action == "save_request" and target_request.status in _save_blocked_statuses:
                messages.warning(
                    request,
                    f"لا يمكن تعديل طلب ترويج بحالة «{target_request.get_status_display()}».",
                )
                return _promo_redirect_with_state(request, request_id=target_request.id)
            if action == "save_request" and target_request.ops_status == PromoOpsStatus.COMPLETED:
                messages.warning(request, "طلب الترويج المكتمل لا يقبل الحفظ مرة أخرى.")
                return _promo_redirect_with_state(request, request_id=target_request.id)

            post_form = PromoRequestActionForm(
                request.POST,
                assignee_choices=assignee_choices,
                ops_choices=_promo_ops_choices_for_request(target_request),
            )
            if not post_form.is_valid():
                selected_request = target_request
                request_form = post_form
                messages.error(request, "يرجى مراجعة حقول نموذج طلب الترويج.")
                return _promo_redirect_with_state(request, request_id=target_request.id)

            assigned_to_raw = (post_form.cleaned_data.get("assigned_to") or "").strip()
            assigned_to_id = int(assigned_to_raw) if assigned_to_raw.isdigit() else None
            if assigned_to_id is not None:
                assignee = dashboard_assignee_user(assigned_to_id, "promo", write=True)
                if assignee is None:
                    messages.error(request, "المكلف المختار لا يملك صلاحية لوحة الترويج.")
                    return _promo_redirect_with_state(request, request_id=target_request.id)
                if access_profile and access_profile.level == AccessLevel.USER and assignee.id != request.user.id:
                    return HttpResponseForbidden("لا يمكنك تعيين الطلب لمستخدم آخر.")
            else:
                assignee = None

            updates: list[str] = []
            ops_note = post_form.cleaned_data.get("ops_note") or ""
            if action == "save_request":
                desired_ops_status = post_form.cleaned_data.get("ops_status") or target_request.ops_status
                if desired_ops_status != target_request.ops_status:
                    try:
                        target_request = set_promo_ops_status(
                            pr=target_request,
                            new_status=desired_ops_status,
                            by_user=request.user,
                            note=ops_note,
                        )
                    except ValueError as exc:
                        messages.error(request, str(exc))
                        return _promo_redirect_with_state(request, request_id=target_request.id)

                next_note = ops_note[:300]
                if next_note != (target_request.quote_note or ""):
                    target_request.quote_note = next_note
                    updates.append("quote_note")

            if assigned_to_id != target_request.assigned_to_id:
                target_request.assigned_to = assignee
                target_request.assigned_at = timezone.now() if assignee else None
                updates.extend(["assigned_to", "assigned_at"])

            if updates:
                updates.append("updated_at")
                target_request.save(update_fields=updates)
                _sync_promo_to_unified(pr=target_request, changed_by=request.user)

            messages.success(request, f"تم تحديث طلب الترويج {target_request.code or target_request.id} بنجاح.")
            return _promo_redirect_with_state(request, request_id=target_request.id)

    export_scope = (request.GET.get("scope") or "").strip().lower()
    if export_scope == "inquiries":
        headers, rows = _promo_inquiry_export_rows(inquiries)
        if _want_csv(request):
            return _csv_response("promo_inquiries.csv", headers, rows)
        if _want_xlsx(request):
            return xlsx_response("promo_inquiries.xlsx", "promo_inquiries", headers, rows)
        if _want_pdf(request):
            return pdf_response("promo_inquiries.pdf", "قائمة استفسارات الترويج", headers, rows, landscape=True)
    if export_scope == "requests":
        headers, rows = _promo_request_export_rows(promo_requests)
        if _want_csv(request):
            return _csv_response("promo_requests.csv", headers, rows)
        if _want_xlsx(request):
            return xlsx_response("promo_requests.xlsx", "promo_requests", headers, rows)
        if _want_pdf(request):
            return pdf_response("promo_requests.pdf", "قائمة طلبات الترويج", headers, rows, landscape=True)

    selected_request_quote = _promo_quote_snapshot(selected_request) if selected_request else None
    selected_request_items = list(selected_request.items.order_by("sort_order", "id")) if selected_request else []
    selected_request_assets = (
        list(selected_request.assets.select_related("item", "uploaded_by").order_by("-uploaded_at", "-id"))
        if selected_request
        else []
    )
    selected_inquiry_attachments = (
        list(selected_inquiry.attachments.order_by("-id")[:8]) if selected_inquiry else []
    )
    selected_inquiry_comments = list(selected_inquiry.comments.order_by("-id")[:8]) if selected_inquiry else []
    close_request_params = request.GET.copy()
    close_request_params.pop("request", None)
    close_request_query = close_request_params.urlencode()
    close_request_url = f"{request.path}?{close_request_query}" if close_request_query else request.path
    promo_inquiry_form_token = (
        _issue_single_use_submit_token(request, PROMO_INQUIRY_SUBMIT_TOKENS_SESSION_KEY)
        if can_write and selected_inquiry is not None
        else ""
    )
    _request_terminal_statuses = {
        PromoRequestStatus.ACTIVE,
        PromoRequestStatus.COMPLETED,
        PromoRequestStatus.EXPIRED,
        PromoRequestStatus.CANCELLED,
        PromoRequestStatus.REJECTED,
    }
    _selected_request_is_mutable = bool(
        selected_request is not None
        and selected_request.status not in _request_terminal_statuses
        and selected_request.ops_status != PromoOpsStatus.COMPLETED
    )
    promo_request_form_token = (
        _issue_single_use_submit_token(request, PROMO_REQUEST_SUBMIT_TOKENS_SESSION_KEY)
        if can_write and _selected_request_is_mutable
        else ""
    )

    context = _promo_base_context("home")
    context.update(
        {
            "hero_title": "لوحة فريق إدارة الترويج",
            "hero_subtitle": "إدارة الاستفسارات، تحويلها لطلبات ترويج، تشغيل التنفيذ، ومتابعة التسعير والفوترة.",
            "can_write": can_write,
            "selected_request_can_save": bool(
                can_write and _selected_request_is_mutable
            ),
            "inquiries": _promo_inquiry_rows(inquiries),
            "promo_requests": _promo_request_rows(promo_requests),
            "inquiry_summary": _promo_inquiry_summary(inquiries),
            "request_summary": _promo_requests_summary(promo_requests),
            "selected_inquiry": selected_inquiry,
            "selected_inquiry_requester_name": _promo_requester_label(selected_inquiry.requester) if selected_inquiry else "",
            "selected_request": selected_request,
            "selected_request_requester_name": _promo_requester_label(selected_request.requester) if selected_request else "",
            "selected_request_status_label": _promo_request_operational_status_label(selected_request),
            "selected_request_ops_status_label": _promo_request_ops_status_label(selected_request),
            "selected_request_payment_status_label": _promo_request_payment_status_label(selected_request),
            "selected_request_items": selected_request_items,
            "promo_support_team": promo_team,
            "selected_request_assets": selected_request_assets,
            "selected_request_quote": selected_request_quote,
            "promo_inquiry_form_token": promo_inquiry_form_token,
            "promo_request_form_token": promo_request_form_token,
            "selected_inquiry_attachments": selected_inquiry_attachments,
            "selected_inquiry_comments": selected_inquiry_comments,
            "inquiry_form": inquiry_form,
            "request_form": request_form,
            "filters": {
                "inquiry_q": inquiry_q,
                "request_q": request_q,
                "ops": ops_filter,
            },
            "close_request_url": close_request_url,
            "team_panels": _dashboard_team_panels(),
            "redirect_query": request.GET.urlencode(),
        }
    )
    return render(request, "dashboard/promo_dashboard.html", context)


def _verification_priority_row_class(priority_number: int) -> str:
    if int(priority_number or 1) >= 3:
        return "priority-3"
    if int(priority_number or 1) == 2:
        return "priority-2"
    return "priority-1"


def _verification_support_team() -> SupportTeam | None:
    return _support_team_for_dashboard("verify", fallback_codes=["verification", "verify"])


def _verification_nav_items(active_key: str) -> list[dict]:
    items = [
        {
            "key": "verification",
            "label": "التوثيق",
            "description": "قائمة استفسارات التوثيق وطلبات التوثيق التشغيلية.",
            "url": reverse("dashboard:verification_dashboard"),
        },
        {
            "key": "verified_accounts",
            "label": "بيانات الحسابات الموثقة",
            "description": "عرض الحسابات التي تمتلك شارات توثيق فعالة.",
            "url": f"{reverse('dashboard:verification_dashboard')}?tab=verified_accounts",
        },
    ]
    for item in items:
        item["active"] = item["key"] == active_key
    return items


def _verification_base_context(active_key: str) -> dict:
    latest_helpdesk_code = (
        SupportTicket.objects.exclude(code="").order_by("-id").values_list("code", flat=True).first()
        or "HD000001"
    )
    latest_verification_code = (
        VerificationRequest.objects.exclude(code="").order_by("-id").values_list("code", flat=True).first()
        or "AD000001"
    )
    return {
        "nav_items": _verification_nav_items(active_key),
        "request_codes": [
            {"code": latest_helpdesk_code, "label": "استفسارات التوثيق"},
            {"code": latest_verification_code, "label": "طلبات التوثيق"},
        ],
    }


def _verification_inquiries_queryset_for_user(user):
    return (
        _support_queryset_for_user(user)
        .filter(
            _support_ticket_dashboard_q("verify", fallback_team_codes=["verification", "verify"])
            | Q(assigned_team__isnull=True, ticket_type=SupportTicketType.VERIFY)
        )
        .select_related("verification_profile", "verification_profile__linked_request")
        .distinct()
    )


def _verification_requests_queryset_for_user(user):
    qs = (
        VerificationRequest.objects.select_related("requester", "requester__provider_profile", "assigned_to", "invoice")
        .prefetch_related(
            "documents",
            "requirements",
            "requirements__attachments",
            "linked_inquiries",
            "linked_inquiries__ticket",
            "invoice__lines",
        )
        .order_by("-updated_at", "-id")
    )
    access_profile = active_access_profile_for_user(user)
    if access_profile and access_profile.level == AccessLevel.USER:
        qs = qs.filter(Q(assigned_to=user) | Q(assigned_to__isnull=True))
    return qs


def _verification_inquiry_rows(tickets: list[SupportTicket]) -> list[dict]:
    subscriptions_by_user_id = _effective_subscriptions_map_for_users(
        [getattr(ticket, "requester", None) for ticket in tickets]
    )
    rows: list[dict] = []
    for ticket in tickets:
        team_label = _support_team_label(ticket)
        team_label = team_label.replace("فريق ", "") if team_label.startswith("فريق ") else team_label
        linked_request = getattr(getattr(ticket, "verification_profile", None), "linked_request", None)
        priority_number = _dashboard_priority_number_for_user(
            ticket.requester,
            subscriptions_by_user_id=subscriptions_by_user_id,
        )
        rows.append(
            {
                "id": ticket.id,
                "code": ticket.code or f"HD{ticket.id:06d}",
                "requester": _support_requester_label(ticket),
                "priority_number": priority_number,
                "priority_class": _dashboard_priority_class_for_user(
                    ticket.requester,
                    subscriptions_by_user_id=subscriptions_by_user_id,
                ),
                "ticket_type": ticket.get_ticket_type_display(),
                "created_at": _format_dt(ticket.created_at),
                "status": ticket.get_status_display(),
                "team": team_label,
                "assignee": _support_assignee_label(ticket),
                "assigned_at": _format_dt(ticket.assigned_at),
                "linked_request_code": linked_request.code if linked_request else "",
            }
        )
    return rows


def _verification_request_rows(requests: list[VerificationRequest]) -> list[dict]:
    subscriptions_by_user_id = _effective_subscriptions_map_for_users(
        [getattr(verification_request, "requester", None) for verification_request in requests]
    )
    rows: list[dict] = []
    for verification_request in requests:
        priority_number = _dashboard_priority_number_for_user(
            verification_request.requester,
            subscriptions_by_user_id=subscriptions_by_user_id,
        )
        rows.append(
            {
                "id": verification_request.id,
                "code": verification_request.code or f"AD{verification_request.id:06d}",
                "requester": _promo_requester_label(verification_request.requester),
                "priority_number": priority_number,
                "priority_class": _dashboard_priority_class_for_user(
                    verification_request.requester,
                    subscriptions_by_user_id=subscriptions_by_user_id,
                ),
                "approved_at": _format_dt(
                    verification_request.approved_at
                    or verification_request.reviewed_at
                    or verification_request.requested_at
                ),
                "request_status": _verification_request_ops_status_label(verification_request),
                "request_status_key": _verification_request_ops_status_key(verification_request),
                "assignee": (
                    (verification_request.assigned_to.username or verification_request.assigned_to.phone or "").strip()
                    if verification_request.assigned_to
                    else "غير مكلف"
                )
                or "غير مكلف",
                "assigned_at": _format_dt(verification_request.assigned_at),
            }
        )
    return rows


VERIFICATION_REQUEST_OPS_STATUS_NEW = "new"
VERIFICATION_REQUEST_OPS_STATUS_IN_REVIEW = "in_review"
VERIFICATION_REQUEST_OPS_STATUS_COMPLETED = "completed"

VERIFICATION_REQUEST_OPS_STATUS_LABELS = {
    VERIFICATION_REQUEST_OPS_STATUS_NEW: "جديد",
    VERIFICATION_REQUEST_OPS_STATUS_IN_REVIEW: "تحت المعالجة",
    VERIFICATION_REQUEST_OPS_STATUS_COMPLETED: "مكتمل",
}

VERIFICATION_REQUEST_COMPLETED_INTERNAL_STATUSES = {
    VerificationStatus.APPROVED,
    VerificationStatus.PENDING_PAYMENT,
    VerificationStatus.ACTIVE,
    VerificationStatus.EXPIRED,
    VerificationStatus.REJECTED,
}


def _verification_request_ops_status_key(verification_request: VerificationRequest | None) -> str:
    if verification_request is None:
        return VERIFICATION_REQUEST_OPS_STATUS_NEW

    raw_status = str(verification_request.status or "").strip()
    if raw_status == VerificationStatus.NEW:
        return VERIFICATION_REQUEST_OPS_STATUS_NEW
    if raw_status in VERIFICATION_REQUEST_COMPLETED_INTERNAL_STATUSES:
        return VERIFICATION_REQUEST_OPS_STATUS_COMPLETED
    return VERIFICATION_REQUEST_OPS_STATUS_IN_REVIEW


def _verification_request_ops_status_label(verification_request: VerificationRequest | None) -> str:
    status_key = _verification_request_ops_status_key(verification_request)
    return VERIFICATION_REQUEST_OPS_STATUS_LABELS.get(status_key, VERIFICATION_REQUEST_OPS_STATUS_LABELS[VERIFICATION_REQUEST_OPS_STATUS_IN_REVIEW])


VERIFICATION_REQUEST_EDITABLE_STATUSES = {
    VerificationStatus.NEW,
    VerificationStatus.IN_REVIEW,
    VerificationStatus.REJECTED,
}


def _verification_request_is_editable(verification_request: VerificationRequest | None) -> bool:
    if verification_request is None:
        return False
    return str(verification_request.status or "").strip() in VERIFICATION_REQUEST_EDITABLE_STATUSES


def _verification_datetime_local_input_value(value) -> str:
    if value is None:
        return ""
    try:
        current_tz = timezone.get_current_timezone()
        normalized = timezone.localtime(value, current_tz) if timezone.is_aware(value) else timezone.make_aware(value, current_tz)
    except Exception:
        return ""
    return normalized.strftime("%Y-%m-%dT%H:%M")


def _verification_requirement_review_rows(
    verification_request: VerificationRequest,
    *,
    badge_type: str,
) -> list[dict]:
    rows: list[dict] = []
    for requirement in verification_request.requirements.all():
        if requirement.badge_type != badge_type:
            continue
        attachments = list(requirement.attachments.all())
        current_state = ""
        if requirement.is_approved is True:
            current_state = "approve"
        elif requirement.is_approved is False:
            current_state = "reject"
        latest_attachment = attachments[-1] if attachments else None
        rows.append(
            {
                "id": requirement.id,
                "code": requirement.code,
                "title": requirement.title,
                "badge_type": requirement.badge_type,
                "badge_label": requirement.get_badge_type_display(),
                "decision_value": current_state,
                "decision_note": requirement.decision_note or "",
                "attachment_count": len(attachments),
                "attachments": attachments,
                "latest_attachment_at": _format_dt(getattr(latest_attachment, "uploaded_at", None)),
                "evidence_expires_at_label": _format_dt(requirement.evidence_expires_at),
                "evidence_expires_at_value": _verification_datetime_local_input_value(requirement.evidence_expires_at),
            }
        )
    return rows


def _verification_request_review_payload(verification_request: VerificationRequest | None) -> dict:
    if verification_request is None:
        return {
            "blue_rows": [],
            "green_rows": [],
            "blue_profile": None,
            "blue_documents": [],
            "all_decided": False,
        }

    blue_profile_obj = getattr(verification_request, "blue_profile", None)
    blue_profile = None
    if blue_profile_obj is not None:
        is_business = str(blue_profile_obj.subject_type or "").strip() == "business"
        blue_profile = {
            "subject_type_display": blue_profile_obj.get_subject_type_display(),
            "verified_name": blue_profile_obj.verified_name,
            "official_number": blue_profile_obj.official_number,
            "official_date": blue_profile_obj.official_date,
            "official_number_label": "رقم السجل التجاري" if is_business else "رقم الهوية / الإقامة",
            "official_date_label": "تاريخه" if is_business else "تاريخ الميلاد",
        }
    blue_rows = _verification_requirement_review_rows(verification_request, badge_type=VerificationBadgeType.BLUE)
    green_rows = _verification_requirement_review_rows(verification_request, badge_type=VerificationBadgeType.GREEN)
    blue_documents = []
    for document in verification_request.documents.all():
        if str(document.doc_type or "").strip().lower() in {"id", "cr", "iban", "other"}:
            blue_documents.append(document)

    all_decided = all(item.get("decision_value") in {"approve", "reject"} for item in [*blue_rows, *green_rows]) and bool(
        blue_rows or green_rows
    )
    return {
        "blue_rows": blue_rows,
        "green_rows": green_rows,
        "blue_profile": blue_profile,
        "blue_documents": blue_documents,
        "all_decided": all_decided,
    }


def _verification_request_decision_summary(verification_request: VerificationRequest | None) -> dict:
    if verification_request is None:
        return {
            "approved": [],
            "rejected": [],
            "pending": [],
            "pricing": None,
        }

    approved_rows: list[dict] = []
    rejected_rows: list[dict] = []
    pending_rows: list[dict] = []
    for requirement in verification_request.requirements.all():
        row = {
            "id": requirement.id,
            "code": requirement.code,
            "title": requirement.title,
            "badge_type": requirement.badge_type,
            "badge_label": requirement.get_badge_type_display(),
            "decision_note": requirement.decision_note or "",
        }
        if requirement.is_approved is True:
            approved_rows.append(row)
        elif requirement.is_approved is False:
            rejected_rows.append(row)
        else:
            pending_rows.append(row)

    pricing_preview = verification_invoice_preview_for_request(vr=verification_request) if approved_rows else None
    if pricing_preview:
        amount_by_code = {
            str(line["item_code"]): f"{Decimal(str(line['amount'])).quantize(Decimal('0.00'))}"
            for line in pricing_preview["lines"]
        }
        for row in approved_rows:
            row["amount"] = amount_by_code.get(row["code"], "0.00")
        pricing_preview = {
            **pricing_preview,
            "subtotal": f"{Decimal(str(pricing_preview['subtotal'])).quantize(Decimal('0.00'))}",
            "vat_percent": f"{Decimal(str(pricing_preview['vat_percent'])).quantize(Decimal('0.00'))}",
            "vat_amount": f"{Decimal(str(pricing_preview['vat_amount'])).quantize(Decimal('0.00'))}",
            "total": f"{Decimal(str(pricing_preview['total'])).quantize(Decimal('0.00'))}",
        }

    return {
        "approved": approved_rows,
        "rejected": rejected_rows,
        "pending": pending_rows,
        "pricing": pricing_preview,
    }


def _verification_verified_badges_queryset_for_user(user):
    now = timezone.now()
    qs = (
        VerifiedBadge.objects.filter(is_active=True, expires_at__gt=now)
        .select_related("user", "request", "request__invoice", "request__blue_profile", "user__provider_profile")
        .prefetch_related(
            Prefetch(
                "request__requirements",
                queryset=VerificationRequirement.objects.order_by("sort_order", "id").prefetch_related(
                    Prefetch(
                        "attachments",
                        queryset=VerificationRequirementAttachment.objects.order_by("id"),
                    )
                ),
            ),
            Prefetch(
                "request__documents",
                queryset=VerificationDocument.objects.order_by("id"),
            ),
            Prefetch(
                "request__invoice__lines",
                queryset=InvoiceLineItem.objects.order_by("sort_order", "id"),
            ),
        )
        .order_by("-activated_at", "-id")
    )
    access_profile = active_access_profile_for_user(user)
    if access_profile and access_profile.level == AccessLevel.USER:
        qs = qs.filter(Q(request__assigned_to=user) | Q(request__assigned_to__isnull=True))
    return qs


def _verification_verified_name_for_badge(badge: VerifiedBadge) -> str:
    verification_request = getattr(badge, "request", None)
    blue_profile = getattr(verification_request, "blue_profile", None)
    if blue_profile and (blue_profile.verified_name or "").strip():
        return (blue_profile.verified_name or "").strip()
    provider_profile = getattr(getattr(badge, "user", None), "provider_profile", None)
    display_name = (getattr(provider_profile, "display_name", "") or "").strip() if provider_profile else ""
    return display_name or _promo_requester_label(getattr(badge, "user", None))


def _verification_requirement_for_badge(badge: VerifiedBadge):
    verification_request = getattr(badge, "request", None)
    if verification_request is None:
        return None
    cached_requirements = getattr(verification_request, "_prefetched_objects_cache", {}).get("requirements")
    iterable = cached_requirements if cached_requirements is not None else verification_request.requirements.order_by("sort_order", "id").prefetch_related("attachments")
    for requirement in iterable:
        if requirement.code == badge.verification_code:
            return requirement
    return None


def _verification_verified_account_rows(user, *, q: str = "") -> list[dict]:
    normalized_query = str(q or "").strip().lower()
    rows: list[dict] = []
    for badge in _verification_verified_badges_queryset_for_user(user):
        requester_name = _promo_requester_label(badge.user)
        verified_name = _verification_verified_name_for_badge(badge)
        request_code = badge.request.code if badge.request and badge.request.code else (f"AD{badge.request_id:06d}" if badge.request_id else "")
        haystack = " ".join(
            token
            for token in [
                requester_name,
                verified_name,
                badge.verification_code,
                badge.verification_title,
                badge.get_badge_type_display(),
                request_code,
            ]
            if token
        ).lower()
        if normalized_query and normalized_query not in haystack:
            continue
        rows.append(
            {
                "id": badge.id,
                "badge_id": badge.id,
                "user_id": badge.user_id,
                "request_id": badge.request_id,
                "request_code": request_code,
                "requester_name": requester_name,
                "verified_name": verified_name,
                "verification_code": badge.verification_code or "-",
                "verification_title": badge.verification_title or "-",
                "badge_type": badge.badge_type,
                "badge_type_label": badge.get_badge_type_display(),
                "badge_type_class": "brand" if badge.badge_type == VerificationBadgeType.BLUE else "mint",
                "activated_at": badge.activated_at,
                "expires_at": badge.expires_at,
            }
        )
    return rows


def _verification_inquiry_summary(tickets: list[SupportTicket]) -> dict:
    by_status: dict[str, int] = {}
    for ticket in tickets:
        by_status[ticket.status] = by_status.get(ticket.status, 0) + 1
    return {
        "total": len(tickets),
        "new": by_status.get(SupportTicketStatus.NEW, 0),
        "in_progress": by_status.get(SupportTicketStatus.IN_PROGRESS, 0),
        "returned": by_status.get(SupportTicketStatus.RETURNED, 0),
        "closed": by_status.get(SupportTicketStatus.CLOSED, 0),
    }


def _verification_request_summary(requests: list[VerificationRequest]) -> dict:
    by_status: dict[str, int] = {}
    by_ops_status: dict[str, int] = {
        VERIFICATION_REQUEST_OPS_STATUS_NEW: 0,
        VERIFICATION_REQUEST_OPS_STATUS_IN_REVIEW: 0,
        VERIFICATION_REQUEST_OPS_STATUS_COMPLETED: 0,
    }
    for verification_request in requests:
        by_status[verification_request.status] = by_status.get(verification_request.status, 0) + 1
        status_key = _verification_request_ops_status_key(verification_request)
        by_ops_status[status_key] = by_ops_status.get(status_key, 0) + 1
    return {
        "total": len(requests),
        "new": by_ops_status.get(VERIFICATION_REQUEST_OPS_STATUS_NEW, 0),
        "in_review": by_ops_status.get(VERIFICATION_REQUEST_OPS_STATUS_IN_REVIEW, 0),
        "completed": by_ops_status.get(VERIFICATION_REQUEST_OPS_STATUS_COMPLETED, 0),
        "approved": by_status.get("approved", 0),
        "pending_payment": by_status.get("pending_payment", 0),
        "active": by_status.get("active", 0),
        "rejected": by_status.get("rejected", 0),
    }


def _verification_verified_accounts_summary(rows: list[dict]) -> dict:
    return {
        "total": len(rows),
        "blue": sum(1 for row in rows if row.get("badge_type") == VerificationBadgeType.BLUE),
        "green": sum(1 for row in rows if row.get("badge_type") == VerificationBadgeType.GREEN),
        "accounts": len({row.get("user_id") for row in rows if row.get("user_id")}),
    }


def _verification_inquiry_export_rows(tickets: list[SupportTicket]) -> tuple[list[str], list[list]]:
    headers = [
        "رقم الطلب",
        "اسم العميل",
        "الأولوية",
        "نوع الطلب",
        "تاريخ ووقت استلام الطلب",
        "حالة الطلب",
        "فريق الدعم",
        "المكلف بالطلب",
        "تاريخ ووقت التكليف",
    ]
    rows: list[list] = []
    for row in _verification_inquiry_rows(tickets):
        rows.append(
            [
                row["code"],
                row["requester"],
                row["priority_number"],
                row["ticket_type"],
                row["created_at"],
                row["status"],
                row["team"],
                row["assignee"],
                row["assigned_at"],
            ]
        )
    return headers, rows


def _verification_request_export_rows(requests: list[VerificationRequest]) -> tuple[list[str], list[list]]:
    headers = [
        "رقم الطلب",
        "اسم العميل",
        "الأولوية",
        "تاريخ ووقت اعتماد الطلب",
        "حالة الطلب",
        "المكلف بالطلب",
        "تاريخ ووقت التكليف",
    ]
    rows: list[list] = []
    for row in _verification_request_rows(requests):
        rows.append(
            [
                row["code"],
                row["requester"],
                row["priority_number"],
                row["approved_at"],
                row["request_status"],
                row["assignee"],
                row["assigned_at"],
            ]
        )
    return headers, rows


def _verification_verified_accounts_export_rows(rows: list[dict]) -> tuple[list[str], list[list]]:
    headers = [
        "اسم العميل",
        "رمز التوثيق",
        "نوع التوثيق",
        "تاريخ تفعيل التوثيق",
        "تاريخ نهاية تفعيل التوثيق",
        "رقم طلب التوثيق المصدر",
    ]
    data_rows: list[list] = []
    for row in rows:
        data_rows.append(
            [
                row["requester_name"],
                row["verification_code"],
                row["badge_type_label"],
                _format_dt(row["activated_at"]),
                _format_dt(row["expires_at"]),
                row["request_code"] or "-",
            ]
        )
    return headers, data_rows


def _verification_document_rows_for_badge(badge: VerifiedBadge) -> list[dict]:
    rows: list[dict] = []
    seen_keys: set[tuple[str, str]] = set()

    requirement = _verification_requirement_for_badge(badge)
    if requirement is not None:
        cached_attachments = getattr(requirement, "_prefetched_objects_cache", {}).get("attachments")
        attachments = cached_attachments if cached_attachments is not None else requirement.attachments.order_by("id")
        for index, attachment in enumerate(attachments, start=1):
            file_name = getattr(getattr(attachment, "file", None), "name", "") or ""
            key = ("attachment", file_name)
            if not file_name or key in seen_keys:
                continue
            seen_keys.add(key)
            rows.append(
                {
                    "title": requirement.title or f"مرفق توثيق {index}",
                    "label": file_name.rsplit("/", 1)[-1] or f"مرفق {index}",
                    "url": attachment.file.url,
                    "uploaded_at": attachment.uploaded_at,
                    "uploaded_at_label": _format_dt(attachment.uploaded_at),
                    "kind": "attachment",
                }
            )

    if badge.badge_type == VerificationBadgeType.BLUE:
        verification_request = getattr(badge, "request", None)
        if verification_request is not None:
            cached_documents = getattr(verification_request, "_prefetched_objects_cache", {}).get("documents")
            documents = cached_documents if cached_documents is not None else verification_request.documents.order_by("id")
            for index, document in enumerate(documents, start=1):
                file_name = getattr(getattr(document, "file", None), "name", "") or ""
                key = ("document", file_name)
                if not file_name or key in seen_keys:
                    continue
                seen_keys.add(key)
                rows.append(
                    {
                        "title": document.title or document.get_doc_type_display() or f"مستند داعم {index}",
                        "label": file_name.rsplit("/", 1)[-1] or f"مستند {index}",
                        "url": document.file.url,
                        "uploaded_at": document.uploaded_at,
                        "uploaded_at_label": _format_dt(document.uploaded_at),
                        "kind": "document",
                    }
                )
    return rows


def _verification_payment_summary_for_badge(badge: VerifiedBadge):
    verification_request = getattr(badge, "request", None)
    invoice = getattr(verification_request, "invoice", None) if verification_request is not None else None
    if not invoice or not invoice.is_payment_effective():
        return None

    cached_lines = getattr(invoice, "_prefetched_objects_cache", {}).get("lines")
    invoice_lines = cached_lines if cached_lines is not None else invoice.lines.order_by("sort_order", "id")
    matched_line = next((line for line in invoice_lines if (line.item_code or "") == (badge.verification_code or "")), None)
    amount_value = matched_line.amount if matched_line is not None else (invoice.payment_amount or invoice.total or Decimal("0.00"))
    amount_text = f"{Decimal(str(amount_value or '0.00')).quantize(Decimal('0.00'))}"
    paid_at = invoice.payment_confirmed_at or invoice.paid_at
    currency = (invoice.payment_currency or invoice.currency or "SAR").strip() or "SAR"
    invoice_code = invoice.code or f"IV{invoice.id:06d}"
    return {
        "invoice_id": invoice.id,
        "invoice_code": invoice_code,
        "amount": amount_text,
        "currency": currency,
        "paid_at": paid_at,
        "paid_at_label": _format_dt(paid_at),
        "message": f"تمت عملية سداد الرسوم بنجاح في تاريخ {_format_dt(paid_at)} بقيمة {amount_text} {currency}.",
    }


def _verification_verified_account_detail_payload(badge: VerifiedBadge | None):
    if badge is None:
        return None

    requirement = _verification_requirement_for_badge(badge)
    request_code = badge.request.code if badge.request and badge.request.code else (f"AD{badge.request_id:06d}" if badge.request_id else "")
    return {
        "id": badge.id,
        "requester_name": _promo_requester_label(badge.user),
        "verified_name": _verification_verified_name_for_badge(badge),
        "verification_code": badge.verification_code or "-",
        "verification_title": requirement.title if requirement is not None else (badge.verification_title or "-"),
        "badge_type": badge.badge_type,
        "badge_type_label": badge.get_badge_type_display(),
        "activated_at": badge.activated_at,
        "activated_at_label": _format_dt(badge.activated_at),
        "expires_at": badge.expires_at,
        "expires_at_label": _format_dt(badge.expires_at),
        "evidence_expires_at_label": _format_dt(requirement.evidence_expires_at) if requirement and requirement.evidence_expires_at else "-",
        "request_id": badge.request_id,
        "request_code": request_code,
        "documents": _verification_document_rows_for_badge(badge),
        "last_payment": _verification_payment_summary_for_badge(badge),
    }


def _verification_redirect_with_state(
    request,
    *,
    request_id: int | None = None,
    inquiry_id: int | None = None,
    extra_params: dict[str, str | None] | None = None,
):
    query = (request.POST.get("redirect_query") or request.GET.urlencode()).strip()
    base = request.path
    params = QueryDict(query, mutable=True)
    if inquiry_id is not None:
        params["inquiry"] = str(inquiry_id)
    if request_id is not None:
        params["request"] = str(request_id)
    if extra_params:
        for key, value in extra_params.items():
            if value in (None, ""):
                params.pop(key, None)
            else:
                params[key] = str(value)
    normalized_query = params.urlencode()
    return redirect(f"{base}?{normalized_query}") if normalized_query else redirect(base)


def _verification_ajax_response(*, ok: bool, message: str = "", status: int = 200, **extra):
    payload = {"ok": bool(ok)}
    if message:
        payload["message"] = message
    payload.update(extra)
    return JsonResponse(payload, status=status, json_dumps_params={"ensure_ascii": False})


def _extract_first_http_url(text: str) -> str:
    match = re.search(r"https?://[^\s]+", text or "")
    if not match:
        return ""
    return match.group(0).rstrip(".,);]")


@dashboard_staff_required
@require_dashboard_access("verify")
def verification_dashboard(request):
    can_write = dashboard_allowed(request.user, "verify", write=True)
    access_profile = active_access_profile_for_user(request.user)
    is_ajax_request = request.headers.get("X-Requested-With") == "XMLHttpRequest"
    assignee_choices = _dashboard_assignee_choices("verify")
    verification_team = _verification_support_team()
    team_choices = [(str(verification_team.id), verification_team.name_ar)] if verification_team else []

    inquiries_base_qs = _verification_inquiries_queryset_for_user(request.user)
    verification_requests_base_qs = _verification_requests_queryset_for_user(request.user)
    verified_badges_base_qs = _verification_verified_badges_queryset_for_user(request.user)

    inquiry_q = (request.GET.get("inquiry_q") or "").strip()
    request_q = (request.GET.get("request_q") or "").strip()
    accounts_q = (request.GET.get("accounts_q") or "").strip()
    tab = (request.GET.get("tab") or "verification").strip().lower()
    if tab not in {"verification", "verified_accounts"}:
        tab = "verification"

    inquiries_qs = inquiries_base_qs
    if inquiry_q:
        inquiries_qs = inquiries_qs.filter(
            Q(code__icontains=inquiry_q)
            | Q(description__icontains=inquiry_q)
            | Q(requester__provider_profile__display_name__icontains=inquiry_q)
            | Q(requester__username__icontains=inquiry_q)
            | Q(requester__phone__icontains=inquiry_q)
        )
    inquiries = list(inquiries_qs.order_by("-created_at", "-id"))

    verification_requests_qs = verification_requests_base_qs
    if request_q:
        verification_requests_qs = verification_requests_qs.filter(
            Q(code__icontains=request_q)
            | Q(admin_note__icontains=request_q)
            | Q(requester__provider_profile__display_name__icontains=request_q)
            | Q(requester__username__icontains=request_q)
            | Q(requester__phone__icontains=request_q)
        )
    verification_requests = list(verification_requests_qs)
    verified_accounts = _verification_verified_account_rows(request.user, q=accounts_q)

    selected_inquiry_id_raw = (request.GET.get("inquiry") or "").strip()
    selected_inquiry = inquiries_base_qs.filter(id=int(selected_inquiry_id_raw)).first() if selected_inquiry_id_raw.isdigit() else None

    selected_request = None
    selected_request_id_raw = (request.GET.get("request") or "").strip()
    if selected_request_id_raw.isdigit():
        selected_request = verification_requests_base_qs.filter(id=int(selected_request_id_raw)).first()

    selected_verified_badge = None
    selected_verified_badge_id_raw = (request.GET.get("verified_badge") or "").strip()
    if selected_verified_badge_id_raw.isdigit():
        selected_verified_badge = verified_badges_base_qs.filter(id=int(selected_verified_badge_id_raw)).first()
    request_stage = (request.GET.get("request_stage") or "").strip().lower()
    if request_stage not in {"review", "summary"}:
        request_stage = "summary" if selected_request and not _verification_request_is_editable(selected_request) else "review"

    linked_request_choices = [
        (str(row.id), f"{row.code or f'AD{row.id:06d}'} - {_promo_requester_label(row.requester)}")
        for row in verification_requests_base_qs[:200]
    ]

    inquiry_profile = getattr(selected_inquiry, "verification_profile", None) if selected_inquiry else None
    verification_team_id = verification_team.id if verification_team is not None else None
    initial_team_id = verification_team_id
    if initial_team_id is None and selected_inquiry is not None:
        initial_team_id = selected_inquiry.assigned_team_id

    inquiry_form = VerificationInquiryActionForm(
        initial={
            "status": selected_inquiry.status if selected_inquiry else SupportTicketStatus.NEW,
            "assigned_team": str(initial_team_id or ""),
            "assigned_to": str(selected_inquiry.assigned_to_id or "") if selected_inquiry else "",
            "description": (selected_inquiry.description or "") if selected_inquiry else "",
            "operator_comment": (inquiry_profile.operator_comment or "") if inquiry_profile else "",
            "detailed_request_url": (inquiry_profile.detailed_request_url or "") if inquiry_profile else "",
            "linked_request_id": str(inquiry_profile.linked_request_id or "") if inquiry_profile else "",
        },
        assignee_choices=assignee_choices,
        team_choices=team_choices,
        linked_request_choices=linked_request_choices,
    )
    request_form = VerificationRequestActionForm(
        initial={
            "assigned_to": str(selected_request.assigned_to_id or "") if selected_request else "",
            "status": _verification_request_ops_status_key(selected_request) if selected_request else VERIFICATION_REQUEST_OPS_STATUS_NEW,
            "admin_note": (selected_request.admin_note or "") if selected_request else "",
        },
        assignee_choices=assignee_choices,
    )

    if request.method == "POST":
        if not can_write:
            return HttpResponseForbidden("لا تملك صلاحية تعديل لوحة التوثيق.")
        action = (request.POST.get("action") or "").strip()

        if action == "save_inquiry":
            raw_ticket_id = (request.POST.get("ticket_id") or "").strip()
            if not raw_ticket_id.isdigit():
                messages.error(request, "تعذر تحديد استفسار التوثيق المطلوب تحديثه.")
                return _verification_redirect_with_state(request)
            target_ticket = inquiries_base_qs.filter(id=int(raw_ticket_id)).first()
            if target_ticket is None:
                messages.error(request, "الاستفسار المحدد غير متاح لهذا الحساب.")
                return _verification_redirect_with_state(request)
            if access_profile and access_profile.level == AccessLevel.USER:
                if target_ticket.assigned_to_id and target_ticket.assigned_to_id != request.user.id:
                    return HttpResponseForbidden("غير مصرح: الاستفسار ليس ضمن المهام المكلف بها.")

            post_data = request.POST.copy()
            if verification_team is not None:
                post_data["assigned_team"] = str(verification_team.id)

            post_form = VerificationInquiryActionForm(
                post_data,
                request.FILES,
                assignee_choices=assignee_choices,
                team_choices=team_choices,
                linked_request_choices=linked_request_choices,
            )
            if not post_form.is_valid():
                selected_inquiry = target_ticket
                inquiry_form = post_form
                messages.error(request, "يرجى مراجعة حقول نموذج استفسار التوثيق.")
                return _verification_redirect_with_state(request, inquiry_id=target_ticket.id)

            desired_status = post_form.cleaned_data.get("status")

            assigned_to_raw = (post_form.cleaned_data.get("assigned_to") or "").strip()
            assigned_to_id = int(assigned_to_raw) if assigned_to_raw.isdigit() else None
            if assigned_to_id is not None:
                assignee = dashboard_assignee_user(assigned_to_id, "verify", write=True)
                if assignee is None:
                    messages.error(request, "المكلف المختار لا يملك صلاحية لوحة التوثيق.")
                    return _verification_redirect_with_state(request, inquiry_id=target_ticket.id)

            team_id = verification_team.id if verification_team is not None else None
            note = post_form.cleaned_data.get("operator_comment") or ""
            target_ticket = assign_ticket(
                ticket=target_ticket,
                team_id=team_id,
                user_id=assigned_to_id,
                by_user=request.user,
                note=note,
            )

            new_description = post_form.cleaned_data.get("description") or target_ticket.description or ""
            if new_description != (target_ticket.description or ""):
                target_ticket.description = new_description
                target_ticket.last_action_by = request.user
                target_ticket.save(update_fields=["description", "last_action_by", "updated_at"])

            if desired_status and desired_status != target_ticket.status:
                try:
                    target_ticket = change_ticket_status(
                        ticket=target_ticket,
                        new_status=desired_status,
                        by_user=request.user,
                        note=note,
                    )
                except ValueError as exc:
                    messages.error(request, str(exc))
                    return _verification_redirect_with_state(request, inquiry_id=target_ticket.id)

            if note:
                SupportComment.objects.create(
                    ticket=target_ticket,
                    text=note[:300],
                    is_internal=True,
                    created_by=request.user,
                )

            attachment = post_form.cleaned_data.get("attachment")
            if attachment is not None:
                try:
                    attachment = _validate_and_optimize_dashboard_attachment(attachment, user=request.user)
                except DjangoValidationError as exc:
                    messages.error(request, str(exc))
                    return _verification_redirect_with_state(request, inquiry_id=target_ticket.id)
                SupportAttachment.objects.create(
                    ticket=target_ticket,
                    file=attachment,
                    uploaded_by=request.user,
                )

            linked_request_id_raw = (post_form.cleaned_data.get("linked_request_id") or "").strip()
            linked_request = (
                VerificationRequest.objects.filter(id=int(linked_request_id_raw)).first()
                if linked_request_id_raw.isdigit()
                else None
            )
            profile, _ = VerificationInquiryProfile.objects.get_or_create(ticket=target_ticket)
            profile.linked_request = linked_request
            comment_detail_url = _extract_first_http_url(note)
            stored_detail_url = (post_form.cleaned_data.get("detailed_request_url") or "").strip()
            profile.detailed_request_url = comment_detail_url or ("" if note else stored_detail_url)
            profile.operator_comment = note[:300]
            profile.save(update_fields=["linked_request", "detailed_request_url", "operator_comment", "updated_at"])

            messages.success(request, f"تم تحديث استفسار التوثيق {target_ticket.code or target_ticket.id} بنجاح.")
            return _verification_redirect_with_state(
                request,
                inquiry_id=target_ticket.id,
                request_id=(linked_request.id if linked_request else None),
            )

        if action in {"save_request", "continue_request_review", "finalize_request"}:
            raw_request_id = (request.POST.get("verification_request_id") or "").strip()
            if not raw_request_id.isdigit():
                if is_ajax_request and action == "save_request":
                    return _verification_ajax_response(ok=False, message="تعذر تحديد طلب التوثيق المطلوب.", status=400)
                messages.error(request, "تعذر تحديد طلب التوثيق المطلوب.")
                return _verification_redirect_with_state(request)
            target_request = verification_requests_base_qs.filter(id=int(raw_request_id)).first()
            if target_request is None:
                if is_ajax_request and action == "save_request":
                    return _verification_ajax_response(ok=False, message="طلب التوثيق المحدد غير متاح لهذا الحساب.", status=404)
                messages.error(request, "طلب التوثيق المحدد غير متاح لهذا الحساب.")
                return _verification_redirect_with_state(request)
            if access_profile and access_profile.level == AccessLevel.USER:
                if target_request.assigned_to_id and target_request.assigned_to_id != request.user.id:
                    if is_ajax_request and action == "save_request":
                        return _verification_ajax_response(ok=False, message="غير مصرح: الطلب ليس ضمن المهام المكلف بها.", status=403)
                    return HttpResponseForbidden("غير مصرح: الطلب ليس ضمن المهام المكلف بها.")

            posted_request_stage = (request.POST.get("request_stage") or "review").strip().lower()
            if posted_request_stage not in {"review", "summary"}:
                posted_request_stage = "review"
            post_form = VerificationRequestActionForm(
                request.POST,
                assignee_choices=assignee_choices,
            )
            if not post_form.is_valid():
                selected_request = target_request
                request_form = post_form
                if is_ajax_request and action == "save_request":
                    return _verification_ajax_response(ok=False, message="يرجى مراجعة حقول نموذج طلب التوثيق.", status=400)
                messages.error(request, "يرجى مراجعة حقول نموذج طلب التوثيق.")
                return _verification_redirect_with_state(
                    request,
                    request_id=target_request.id,
                    extra_params={"request_stage": posted_request_stage},
                )

            assigned_to_raw = (post_form.cleaned_data.get("assigned_to") or "").strip()
            assigned_to_id = int(assigned_to_raw) if assigned_to_raw.isdigit() else None
            if assigned_to_id is not None:
                assignee = dashboard_assignee_user(assigned_to_id, "verify", write=True)
                if assignee is None:
                    if is_ajax_request and action == "save_request":
                        return _verification_ajax_response(ok=False, message="المكلف المختار لا يملك صلاحية لوحة التوثيق.", status=400)
                    messages.error(request, "المكلف المختار لا يملك صلاحية لوحة التوثيق.")
                    return _verification_redirect_with_state(request, request_id=target_request.id)
                if access_profile and access_profile.level == AccessLevel.USER and assignee.id != request.user.id:
                    if is_ajax_request and action == "save_request":
                        return _verification_ajax_response(ok=False, message="لا يمكنك تعيين الطلب لمستخدم آخر.", status=403)
                    return HttpResponseForbidden("لا يمكنك تعيين الطلب لمستخدم آخر.")
            else:
                assignee = None

            updates: list[str] = []
            status_changed_manually = False
            next_admin_note = (post_form.cleaned_data.get("admin_note") or "")[:300]
            if assigned_to_id != target_request.assigned_to_id:
                target_request.assigned_to = assignee
                target_request.assigned_at = timezone.now() if assignee else None
                updates.extend(["assigned_to", "assigned_at"])

            requested_status = (post_form.cleaned_data.get("status") or "").strip()
            if requested_status:
                if not _verification_request_is_editable(target_request):
                    if is_ajax_request and action == "save_request":
                        return _verification_ajax_response(ok=False, message="لا يمكن تعديل حالة هذا الطلب في مرحلته الحالية.", status=409)
                    messages.error(request, "لا يمكن تعديل حالة هذا الطلب في مرحلته الحالية.")
                    return _verification_redirect_with_state(
                        request,
                        request_id=target_request.id,
                        extra_params={"request_stage": posted_request_stage},
                    )

                if requested_status == VERIFICATION_REQUEST_OPS_STATUS_COMPLETED:
                    if is_ajax_request and action == "save_request":
                        return _verification_ajax_response(ok=False, message="حالة مكتمل تُحتسب تلقائيًا بعد اعتماد الطلب في مرحلة الملخص النهائي.", status=400)
                    messages.error(request, "حالة مكتمل تُحتسب تلقائيًا بعد اعتماد الطلب في مرحلة الملخص النهائي.")
                    return _verification_redirect_with_state(
                        request,
                        request_id=target_request.id,
                        extra_params={"request_stage": posted_request_stage},
                    )

                mapped_status = (
                    VerificationStatus.NEW
                    if requested_status == VERIFICATION_REQUEST_OPS_STATUS_NEW
                    else VerificationStatus.IN_REVIEW
                )
                if mapped_status != target_request.status:
                    target_request.status = mapped_status
                    updates.append("status")
                    status_changed_manually = True

            if next_admin_note != (target_request.admin_note or ""):
                target_request.admin_note = next_admin_note
                updates.append("admin_note")

            if updates:
                updates.append("updated_at")
                target_request.save(update_fields=updates)
                _sync_verification_to_unified(vr=target_request, changed_by=request.user)

            if action in {"save_request", "continue_request_review"} and not status_changed_manually:
                target_request = mark_request_in_review(vr=target_request, changed_by=request.user)

            if action in {"save_request", "continue_request_review"}:
                if not _verification_request_is_editable(target_request):
                    if is_ajax_request and action == "save_request":
                        return _verification_ajax_response(ok=False, message="هذا الطلب في مرحلة لاحقة ولا يمكن تعديل بنوده من شاشة المراجعة.", status=409)
                    messages.error(request, "هذا الطلب في مرحلة لاحقة ولا يمكن تعديل بنوده من شاشة المراجعة.")
                    return _verification_redirect_with_state(
                        request,
                        request_id=target_request.id,
                        extra_params={"request_stage": "summary"},
                    )

                decision_rows = []
                validation_errors: list[str] = []
                for requirement in target_request.requirements.all():
                    current_state = requirement.is_approved if requirement.is_approved in (True, False) else None
                    raw_decision = (request.POST.get(f"decision_{requirement.id}") or "").strip().lower()
                    desired_state = current_state
                    if raw_decision == "approve":
                        desired_state = True
                    elif raw_decision == "reject":
                        desired_state = False

                    reason_key = f"reject_reason_{requirement.id}"
                    has_reason_input = reason_key in request.POST
                    desired_note = (
                        (request.POST.get(reason_key) or "").strip()[:300]
                        if has_reason_input
                        else (requirement.decision_note or "")
                    )

                    evidence_key = f"evidence_expires_at_{requirement.id}"
                    has_evidence_input = evidence_key in request.POST
                    desired_evidence = requirement.evidence_expires_at
                    if has_evidence_input:
                        raw_evidence = (request.POST.get(evidence_key) or "").strip()
                        desired_evidence = _parse_datetime_local(raw_evidence) if raw_evidence else None
                    if requirement.badge_type != VerificationBadgeType.GREEN:
                        desired_evidence = None

                    if action == "continue_request_review" and desired_state is None:
                        validation_errors.append(f"حدد اعتمادًا أو رفضًا للبند {requirement.code}.")

                    decision_rows.append(
                        {
                            "requirement": requirement,
                            "current_state": current_state,
                            "desired_state": desired_state,
                            "current_note": requirement.decision_note or "",
                            "desired_note": desired_note,
                            "current_evidence": requirement.evidence_expires_at,
                            "desired_evidence": desired_evidence,
                        }
                    )

                if validation_errors:
                    if is_ajax_request and action == "save_request":
                        return _verification_ajax_response(ok=False, message=validation_errors[0], status=400)
                    for error in validation_errors:
                        messages.error(request, error)
                    return _verification_redirect_with_state(
                        request,
                        request_id=target_request.id,
                        extra_params={"request_stage": "review"},
                    )

                changed_decisions = False
                for row in decision_rows:
                    desired_state = row["desired_state"]
                    if desired_state is None:
                        continue
                    if (
                        desired_state != row["current_state"]
                        or row["desired_note"] != row["current_note"]
                        or row["desired_evidence"] != row["current_evidence"]
                    ):
                        decide_requirement(
                            req=row["requirement"],
                            is_approved=bool(desired_state),
                            note=row["desired_note"],
                            by_user=request.user,
                            evidence_expires_at=row["desired_evidence"],
                        )
                        changed_decisions = True

                if changed_decisions:
                    mark_request_in_review(vr=target_request, changed_by=request.user)

                target_request = verification_requests_base_qs.filter(id=target_request.id).first() or target_request
                next_stage = "summary" if action == "continue_request_review" else "review"
                message_text = (
                    f"تم تجهيز ملخص طلب التوثيق {target_request.code or target_request.id}."
                    if action == "continue_request_review"
                    else f"تم تحديث مراجعة طلب التوثيق {target_request.code or target_request.id} بنجاح."
                )
                if is_ajax_request and action == "save_request":
                    return _verification_ajax_response(
                        ok=True,
                        message=message_text,
                        request_stage=next_stage,
                        status_label=_verification_request_ops_status_label(target_request),
                    )
                messages.success(request, message_text)
                return _verification_redirect_with_state(
                    request,
                    request_id=target_request.id,
                    extra_params={"request_stage": next_stage},
                )

            if target_request.status in {VerificationStatus.PENDING_PAYMENT, VerificationStatus.ACTIVE}:
                messages.info(request, "تم اعتماد هذا الطلب مسبقًا وتظهر لك نسخة القراءة فقط من الملخص.")
                return _verification_redirect_with_state(
                    request,
                    request_id=target_request.id,
                    extra_params={"request_stage": "summary"},
                )

            pending_items = list(target_request.requirements.filter(is_approved__isnull=True))
            if pending_items:
                messages.error(request, "أكمل اعتماد أو رفض جميع البنود أولًا قبل إصدار ملخص الاعتماد النهائي.")
                return _verification_redirect_with_state(
                    request,
                    request_id=target_request.id,
                    extra_params={"request_stage": "review"},
                )

            rejected_items = list(target_request.requirements.filter(is_approved=False))
            missing_reasons: list[str] = []
            for requirement in rejected_items:
                reason_key = f"reject_reason_{requirement.id}"
                desired_note = (request.POST.get(reason_key) or "").strip()[:300]
                if reason_key in request.POST:
                    if not desired_note:
                        missing_reasons.append(requirement.code)
                    elif desired_note != (requirement.decision_note or ""):
                        decide_requirement(
                            req=requirement,
                            is_approved=False,
                            note=desired_note,
                            by_user=request.user,
                            evidence_expires_at=requirement.evidence_expires_at,
                        )
                elif not (requirement.decision_note or "").strip():
                    missing_reasons.append(requirement.code)

            if missing_reasons:
                messages.error(request, f"أدخل سبب الرفض للبنود التالية: {', '.join(missing_reasons)}.")
                return _verification_redirect_with_state(
                    request,
                    request_id=target_request.id,
                    extra_params={"request_stage": "summary"},
                )

            target_request = verification_requests_base_qs.filter(id=target_request.id).first() or target_request
            try:
                target_request = finalize_request_and_create_invoice(vr=target_request, by_user=request.user)
            except ValueError as exc:
                messages.error(request, str(exc))
                return _verification_redirect_with_state(
                    request,
                    request_id=target_request.id,
                    extra_params={"request_stage": "summary"},
                )

            messages.success(
                request,
                f"تم اعتماد طلب التوثيق {target_request.code or target_request.id} وتحويله إلى {target_request.get_status_display()}.",
            )
            return _verification_redirect_with_state(
                request,
                request_id=target_request.id,
                extra_params={"request_stage": "summary"},
            )

        if action in {"renew_verified_badge", "delete_verified_badge"}:
            raw_badge_id = (request.POST.get("verified_badge_id") or "").strip()
            if not raw_badge_id.isdigit():
                messages.error(request, "تعذر تحديد سجل التوثيق المطلوب.")
                return _verification_redirect_with_state(request, extra_params={"tab": "verified_accounts"})

            target_badge = verified_badges_base_qs.filter(id=int(raw_badge_id)).first()
            if target_badge is None:
                messages.error(request, "سجل التوثيق المحدد غير متاح أو لم يعد مفعلًا.")
                return _verification_redirect_with_state(
                    request,
                    extra_params={"tab": "verified_accounts", "verified_badge": None},
                )

            if access_profile and access_profile.level == AccessLevel.USER:
                if target_badge.request.assigned_to_id and target_badge.request.assigned_to_id != request.user.id:
                    return HttpResponseForbidden("غير مصرح: هذا السجل ليس ضمن نطاق الطلبات المكلف بها.")

            if action == "delete_verified_badge":
                deactivate_verified_badge(badge=target_badge, by_user=request.user)
                messages.success(
                    request,
                    f"تم حذف تفعيل رمز التوثيق {target_badge.verification_code or target_badge.id} من قائمة الحسابات الموثقة.",
                )
                return _verification_redirect_with_state(
                    request,
                    extra_params={
                        "tab": "verified_accounts",
                        "verified_badge": None,
                        "request": None,
                        "inquiry": None,
                        "request_stage": None,
                    },
                )

            try:
                renewal_request = create_renewal_request_from_verified_badge(
                    badge=target_badge,
                    assigned_to=request.user,
                    by_user=request.user,
                )
            except ValueError as exc:
                messages.error(request, str(exc))
                return _verification_redirect_with_state(
                    request,
                    extra_params={"tab": "verified_accounts", "verified_badge": target_badge.id},
                )

            messages.success(
                request,
                f"تم إنشاء طلب تجديد جديد للرمز {target_badge.verification_code or target_badge.id} برقم {renewal_request.code or renewal_request.id}.",
            )
            return _verification_redirect_with_state(
                request,
                request_id=renewal_request.id,
                extra_params={
                    "tab": "verification",
                    "verified_badge": None,
                    "inquiry": None,
                    "request_stage": "review",
                },
            )

    export_scope = (request.GET.get("scope") or "").strip().lower()
    if export_scope == "inquiries":
        headers, rows = _verification_inquiry_export_rows(inquiries)
        if _want_csv(request):
            return _csv_response("verification_inquiries.csv", headers, rows)
        if _want_xlsx(request):
            return xlsx_response("verification_inquiries.xlsx", "verification_inquiries", headers, rows)
        if _want_pdf(request):
            return pdf_response("verification_inquiries.pdf", "قائمة استفسارات التوثيق", headers, rows, landscape=True)
    if export_scope == "requests":
        headers, rows = _verification_request_export_rows(verification_requests)
        if _want_csv(request):
            return _csv_response("verification_requests.csv", headers, rows)
        if _want_xlsx(request):
            return xlsx_response("verification_requests.xlsx", "verification_requests", headers, rows)
        if _want_pdf(request):
            return pdf_response("verification_requests.pdf", "قائمة طلبات التوثيق", headers, rows, landscape=True)
    if export_scope == "verified_accounts":
        headers, rows = _verification_verified_accounts_export_rows(verified_accounts)
        if _want_csv(request):
            return _csv_response("verified_accounts.csv", headers, rows)
        if _want_xlsx(request):
            return xlsx_response("verified_accounts.xlsx", "verified_accounts", headers, rows)
        if _want_pdf(request):
            return pdf_response("verified_accounts.pdf", "بيانات الحسابات الموثقة", headers, rows, landscape=True)

    selected_inquiry_attachments = list(selected_inquiry.attachments.order_by("-id")[:8]) if selected_inquiry else []
    selected_inquiry_comments = list(selected_inquiry.comments.order_by("-id")[:8]) if selected_inquiry else []
    linked_inquiries_for_request = (
        list(selected_request.linked_inquiries.select_related("ticket").order_by("-updated_at", "-id"))
        if selected_request
        else []
    )
    selected_request_review = _verification_request_review_payload(selected_request)
    selected_request_decision_summary = _verification_request_decision_summary(selected_request)
    if (
        selected_request
        and request_stage == "summary"
        and selected_request_decision_summary.get("pending")
        and _verification_request_is_editable(selected_request)
    ):
        request_stage = "review"
    selected_request_invoice_summary = (
        VerificationRequestDetailSerializer(selected_request).data.get("invoice_summary")
        if selected_request
        else None
    )
    if selected_request_invoice_summary and selected_request_decision_summary.get("approved"):
        invoice_amounts_by_code = {
            str(line.get("item_code") or ""): str(line.get("amount") or "0.00")
            for line in (selected_request_invoice_summary.get("lines") or [])
        }
        for row in selected_request_decision_summary["approved"]:
            if row["code"] in invoice_amounts_by_code:
                row["amount"] = invoice_amounts_by_code[row["code"]]
    selected_request_financial_summary = selected_request_invoice_summary or selected_request_decision_summary.get("pricing")
    close_request_params = request.GET.copy()
    close_request_params.pop("request", None)
    close_request_query = close_request_params.urlencode()
    close_request_url = f"{request.path}?{close_request_query}" if close_request_query else request.path
    request_review_params = request.GET.copy()
    if selected_request is not None:
        request_review_params["request"] = str(selected_request.id)
    request_review_params["request_stage"] = "review"
    request_review_query = request_review_params.urlencode()
    request_review_url = f"{request.path}?{request_review_query}" if request_review_query else request.path
    request_summary_params = request.GET.copy()
    if selected_request is not None:
        request_summary_params["request"] = str(selected_request.id)
    request_summary_params["request_stage"] = "summary"
    request_summary_query = request_summary_params.urlencode()
    request_summary_url = f"{request.path}?{request_summary_query}" if request_summary_query else request.path
    close_inquiry_params = request.GET.copy()
    close_inquiry_params.pop("inquiry", None)
    close_inquiry_query = close_inquiry_params.urlencode()
    close_inquiry_url = f"{request.path}?{close_inquiry_query}" if close_inquiry_query else request.path
    selected_verified_badge_detail = _verification_verified_account_detail_payload(selected_verified_badge)
    close_verified_badge_params = request.GET.copy()
    close_verified_badge_params.pop("verified_badge", None)
    close_verified_badge_query = close_verified_badge_params.urlencode()
    close_verified_badge_url = f"{request.path}?{close_verified_badge_query}" if close_verified_badge_query else request.path

    context = _verification_base_context(tab)
    context.update(
        {
            "hero_title": "لوحة فريق إدارة التوثيق",
            "hero_subtitle": "متابعة استفسارات التوثيق من صفحة التواصل، مراجعة طلبات التوثيق من مزودي الخدمة، وربطها بالحسابات الموثقة.",
            "can_write": can_write,
            "inquiries": _verification_inquiry_rows(inquiries),
            "verification_requests": _verification_request_rows(verification_requests),
            "verified_accounts": verified_accounts,
            "inquiry_summary": _verification_inquiry_summary(inquiries),
            "request_summary": _verification_request_summary(verification_requests),
            "verified_accounts_summary": _verification_verified_accounts_summary(verified_accounts),
            "selected_inquiry": selected_inquiry,
            "selected_inquiry_requester_name": _promo_requester_label(selected_inquiry.requester) if selected_inquiry else "",
            "selected_request": selected_request,
            "selected_request_requester_name": _promo_requester_label(selected_request.requester) if selected_request else "",
            "selected_request_status_label": _verification_request_ops_status_label(selected_request) if selected_request else "",
            "selected_verified_badge": selected_verified_badge,
            "selected_verified_badge_detail": selected_verified_badge_detail,
            "selected_request_is_editable": _verification_request_is_editable(selected_request),
            "selected_request_invoice_summary": selected_request_invoice_summary,
            "selected_request_financial_summary": selected_request_financial_summary,
            "selected_request_review": selected_request_review,
            "selected_request_decision_summary": selected_request_decision_summary,
            "request_stage": request_stage,
            "linked_inquiries_for_request": linked_inquiries_for_request,
            "verification_support_team": verification_team,
            "selected_inquiry_attachments": selected_inquiry_attachments,
            "selected_inquiry_comments": selected_inquiry_comments,
            "inquiry_form": inquiry_form,
            "request_form": request_form,
            "request_review_url": request_review_url,
            "request_summary_url": request_summary_url,
            "close_verified_badge_url": close_verified_badge_url,
            "filters": {
                "inquiry_q": inquiry_q,
                "request_q": request_q,
                "accounts_q": accounts_q,
                "tab": tab,
            },
            "close_request_url": close_request_url,
            "close_inquiry_url": close_inquiry_url,
            "redirect_query": request.GET.urlencode(),
        }
    )
    return render(request, "dashboard/verification_dashboard.html", context)


def _promo_module_rows(items: list[PromoRequestItem]) -> list[dict]:
    rows: list[dict] = []
    now = timezone.now()
    for item in items:
        promo_request = item.request
        channels: list[str] = []
        if item.use_notification_channel:
            channels.append("تنبيه")
        if item.use_chat_channel:
            channels.append("محادثات")

        if item.message_dispatch_error:
            dispatch_status = f"تعذر الإرسال: {item.message_dispatch_error}"
        elif item.message_sent_at:
            dispatch_status = f"تم الإرسال ({int(item.message_recipients_count or 0)} مستلم)"
        elif item.send_at and item.send_at > now:
            dispatch_status = "مجدول"
        elif item.send_at:
            dispatch_status = "بانتظار التنفيذ"
        else:
            dispatch_status = "-"

        rows.append(
            {
                "id": item.id,
                "request_id": promo_request.id,
                "request_code": promo_request.code or f"MD{promo_request.id:06d}",
                "requester": _promo_requester_label(promo_request.requester),
                "title": item.title or item.get_service_type_display(),
                "service_type": item.get_service_type_display(),
                "start_at": _format_dt(item.start_at or promo_request.start_at),
                "end_at": _format_dt(item.end_at or promo_request.end_at),
                "send_at": _format_dt(item.send_at),
                "status": promo_request.get_ops_status_display(),
                "request_status": promo_request.get_status_display(),
                "request_status_raw": promo_request.status,
                "ops_status_raw": promo_request.ops_status,
                "search_scope": item.get_search_scope_display() if item.search_scope else "-",
                "search_position": item.get_search_position_display() if item.search_position else "-",
                "channels": " + ".join(channels) if channels else "-",
                "dispatch_status": dispatch_status,
            }
        )
    return rows


PROMO_MODULE_LEGACY_AD_TYPES_BY_SERVICE: dict[str, set[str]] = {
    PromoServiceType.HOME_BANNER: {
        PromoAdType.BANNER_HOME,
    },
    PromoServiceType.FEATURED_SPECIALISTS: {
        PromoAdType.FEATURED_TOP5,
        PromoAdType.FEATURED_TOP10,
        PromoAdType.BOOST_PROFILE,
    },
    PromoServiceType.PROMO_MESSAGES: {
        PromoAdType.PUSH_NOTIFICATION,
    },
}


def _promo_datetime_local_input_value(dt) -> str:
    if not dt:
        return ""
    try:
        local_dt = timezone.localtime(dt)
    except Exception:
        local_dt = dt
    return local_dt.strftime("%Y-%m-%dT%H:%M")


def _promo_module_request_candidates_queryset(requests_base_qs, *, service_type: str):
    service_type_value = str(service_type or "").strip()
    if not service_type_value:
        return requests_base_qs.none()
    filter_q = Q(items__service_type=service_type_value)
    legacy_ad_types = PROMO_MODULE_LEGACY_AD_TYPES_BY_SERVICE.get(service_type_value, set())
    if legacy_ad_types:
        filter_q |= Q(ad_type__in=legacy_ad_types)
    # Exclude requests in terminal / immutable states
    immutable_statuses = {
        PromoRequestStatus.ACTIVE,
        PromoRequestStatus.COMPLETED,
        PromoRequestStatus.EXPIRED,
        PromoRequestStatus.CANCELLED,
        PromoRequestStatus.REJECTED,
    }
    return (
        requests_base_qs.filter(filter_q)
        .exclude(status__in=immutable_statuses)
        .exclude(ops_status=PromoOpsStatus.COMPLETED)
        .distinct()
        .order_by("-created_at", "-id")
    )


def _promo_selected_request_item_for_service(selected_request: PromoRequest | None, *, service_type: str) -> PromoRequestItem | None:
    if selected_request is None:
        return None
    matches = [row for row in selected_request.items.all() if row.service_type == service_type]
    if not matches:
        return None
    matches.sort(key=lambda row: (int(row.sort_order or 0), int(row.id or 0)))
    return matches[-1]


def _promo_module_initial_data_from_request(
    *,
    service_type: str,
    selected_request: PromoRequest | None,
    selected_item: PromoRequestItem | None,
) -> dict:
    if selected_request is None:
        return {"request_id": ""}

    requester_identifier = (
        _promo_requester_label(selected_request.requester)
        if getattr(selected_request, "requester", None)
        else ""
    )
    requester_provider = getattr(getattr(selected_request, "requester", None), "provider_profile", None)
    target_provider_id = (
        getattr(selected_item, "target_provider_id", None)
        or getattr(selected_request, "target_provider_id", None)
        or (getattr(requester_provider, "id", None) if requester_provider else None)
        or ""
    )

    search_scopes: list[str] = []
    if service_type == PromoServiceType.SEARCH_RESULTS:
        for row in selected_request.items.all():
            if row.service_type != service_type:
                continue
            scope = str(row.search_scope or "").strip()
            if scope and scope not in search_scopes:
                search_scopes.append(scope)

    use_notification_channel = False
    use_chat_channel = False
    if selected_item is not None:
        use_notification_channel = bool(selected_item.use_notification_channel)
        use_chat_channel = bool(selected_item.use_chat_channel)
    elif selected_request.ad_type == PromoAdType.PUSH_NOTIFICATION:
        use_notification_channel = True

    initial = {
        "request_id": selected_request.id,
        "requester_identifier": requester_identifier,
        "title": (
            (selected_item.title if selected_item else "")
            or selected_request.title
            or ""
        ),
        "start_at": _promo_datetime_local_input_value((selected_item.start_at if selected_item else None) or selected_request.start_at),
        "end_at": _promo_datetime_local_input_value((selected_item.end_at if selected_item else None) or selected_request.end_at),
        "send_at": _promo_datetime_local_input_value((selected_item.send_at if selected_item else None) or selected_request.start_at),
        "search_scope": (selected_item.search_scope if selected_item else "") or (search_scopes[0] if search_scopes else ""),
        "search_scopes": search_scopes,
        "search_position": (
            (selected_item.search_position if selected_item else "")
            or selected_request.position
            or ""
        ),
        "target_provider_id": target_provider_id,
        "target_portfolio_item_id": (
            getattr(selected_item, "target_portfolio_item_id", None)
            or getattr(selected_request, "target_portfolio_item_id", None)
            or ""
        ),
        "target_spotlight_item_id": (
            getattr(selected_item, "target_spotlight_item_id", None)
            or getattr(selected_request, "target_spotlight_item_id", None)
            or ""
        ),
        "target_category": (
            (selected_item.target_category if selected_item else "")
            or selected_request.target_category
            or ""
        ),
        "target_city": (
            ""
            if service_type == PromoServiceType.SEARCH_RESULTS
            else (
                (selected_item.target_city if selected_item else "")
                or selected_request.target_city
                or ""
            )
        ),
        "target_city_display": format_city_display(
            ""
            if service_type == PromoServiceType.SEARCH_RESULTS
            else (
                (selected_item.target_city if selected_item else "")
                or selected_request.target_city
                or ""
            )
        ),
        "redirect_url": (
            (selected_item.redirect_url if selected_item else "")
            or selected_request.redirect_url
            or ""
        ),
        "message_title": (
            (selected_item.message_title if selected_item else "")
            or selected_request.message_title
            or ""
        ),
        "message_body": (
            (selected_item.message_body if selected_item else "")
            or selected_request.message_body
            or ""
        ),
        "use_notification_channel": use_notification_channel,
        "use_chat_channel": use_chat_channel,
        "sponsor_name": (selected_item.sponsor_name if selected_item else "") or "",
        "sponsor_url": (selected_item.sponsor_url if selected_item else "") or "",
        "sponsorship_months": int((selected_item.sponsorship_months if selected_item else 0) or 0),
        "attachment_specs": (selected_item.attachment_specs if selected_item else "") or "",
        "operator_note": (selected_item.operator_note if selected_item else "") or "",
        "mobile_scale": int(selected_request.mobile_scale or 100),
        "tablet_scale": int(selected_request.tablet_scale or 100),
        "desktop_scale": int(selected_request.desktop_scale or 100),
    }
    return initial


def _promo_module_selected_portfolio_item_data(
    *,
    selected_request: PromoRequest | None,
    selected_item: PromoRequestItem | None,
) -> dict:
    empty_item_data = {
        "id": "",
        "file_url": "",
        "thumbnail_url": "",
        "file_type": "",
        "caption": "",
    }
    target_item = None
    if selected_item is not None and getattr(selected_item, "target_portfolio_item", None) is not None:
        target_item = selected_item.target_portfolio_item
    elif selected_request is not None and getattr(selected_request, "target_portfolio_item", None) is not None:
        target_item = selected_request.target_portfolio_item
    if target_item is None:
        return empty_item_data
    file_field = getattr(target_item, "file", None)
    thumb_field = getattr(target_item, "thumbnail", None)
    return {
        "id": int(target_item.id),
        "file_url": getattr(file_field, "url", "") if file_field else "",
        "thumbnail_url": getattr(thumb_field, "url", "") if thumb_field else "",
        "file_type": str(getattr(target_item, "file_type", "") or "").strip().lower(),
        "caption": str(getattr(target_item, "caption", "") or "").strip(),
    }


def _promo_module_selected_spotlight_item_data(
    *,
    selected_request: PromoRequest | None,
    selected_item: PromoRequestItem | None,
) -> dict:
    empty_item_data = {
        "id": "",
        "file_url": "",
        "thumbnail_url": "",
        "file_type": "",
        "caption": "",
    }
    target_item = None
    if selected_item is not None and getattr(selected_item, "target_spotlight_item", None) is not None:
        target_item = selected_item.target_spotlight_item
    elif selected_request is not None and getattr(selected_request, "target_spotlight_item", None) is not None:
        target_item = selected_request.target_spotlight_item
    if target_item is None:
        return empty_item_data
    file_field = getattr(target_item, "file", None)
    thumb_field = getattr(target_item, "thumbnail", None)
    return {
        "id": int(target_item.id),
        "file_url": getattr(file_field, "url", "") if file_field else "",
        "thumbnail_url": getattr(thumb_field, "url", "") if thumb_field else "",
        "file_type": str(getattr(target_item, "file_type", "") or "").strip().lower(),
        "caption": str(getattr(target_item, "caption", "") or "").strip(),
    }


def _promo_module_assets_for_selected_request(
    *,
    selected_request: PromoRequest | None,
    service_type: str,
) -> list[PromoAsset]:
    if selected_request is None:
        return []

    service_assets = [
        asset
        for asset in selected_request.assets.all()
        if getattr(asset, "item", None) and getattr(asset.item, "service_type", "") == service_type
    ]
    if service_assets:
        service_assets.sort(key=lambda row: int(row.id or 0), reverse=True)
        return service_assets

    unassigned_assets = [asset for asset in selected_request.assets.all() if getattr(asset, "item", None) is None]
    if not unassigned_assets:
        return []

    legacy_types = PROMO_MODULE_LEGACY_AD_TYPES_BY_SERVICE.get(service_type, set())
    if selected_request.ad_type in legacy_types:
        unassigned_assets.sort(key=lambda row: int(row.id or 0), reverse=True)
        return unassigned_assets
    return []


def _promo_module_request_preview_payload(
    *,
    selected_request: PromoRequest | None,
    service_type: str,
) -> dict:
    if selected_request is None:
        return {
            "request": {
                "id": "",
                "code": "",
                "requester_label": "",
                "target_provider_id": "",
                "target_provider_label": "",
            },
            "asset": {"url": "", "type": "", "name": ""},
            "portfolio_item": {},
            "spotlight_item": {},
        }

    selected_item = _promo_selected_request_item_for_service(
        selected_request,
        service_type=service_type,
    )
    target_provider_id = (
        getattr(selected_item, "target_provider_id", None)
        or getattr(selected_request, "target_provider_id", None)
        or getattr(getattr(selected_request.requester, "provider_profile", None), "id", None)
        or ""
    )
    target_provider = None
    if selected_item is not None and getattr(selected_item, "target_provider", None) is not None:
        target_provider = selected_item.target_provider
    elif getattr(selected_request, "target_provider", None) is not None:
        target_provider = selected_request.target_provider
    elif getattr(selected_request.requester, "provider_profile", None) is not None:
        target_provider = selected_request.requester.provider_profile

    target_provider_label = ""
    if target_provider is not None:
        target_provider_label = (
            str(getattr(target_provider, "display_name", "") or "").strip()
            or str(getattr(getattr(target_provider, "user", None), "username", "") or "").strip()
            or _promo_requester_label(getattr(target_provider, "user", None))
        )

    assets = _promo_module_assets_for_selected_request(
        selected_request=selected_request,
        service_type=service_type,
    )
    asset = assets[0] if assets else None
    asset_url = ""
    asset_type = ""
    asset_name = ""
    if asset is not None:
        asset_type = str(getattr(asset, "asset_type", "") or "")
        asset_name = str(getattr(getattr(asset, "file", None), "name", "") or "")
        try:
            asset_url = asset.file.url if getattr(asset, "file", None) else ""
        except Exception:
            asset_url = ""

    return {
        "request": {
            "id": str(selected_request.id or ""),
            "code": selected_request.code or f"MD{selected_request.id:06d}",
            "requester_label": _promo_requester_label(selected_request.requester),
            "target_provider_id": str(target_provider_id or ""),
            "target_provider_label": target_provider_label,
        },
        "asset": {
            "url": asset_url,
            "type": asset_type,
            "name": asset_name,
        },
        "portfolio_item": _promo_module_selected_portfolio_item_data(
            selected_request=selected_request,
            selected_item=selected_item,
        ),
        "spotlight_item": _promo_module_selected_spotlight_item_data(
            selected_request=selected_request,
            selected_item=selected_item,
        ),
    }


def _promo_module_action(request) -> str:
    raw = (request.POST.get("workflow_action") or request.POST.get("action") or "").strip().lower()
    if raw in {"preview_item", "approve_item", "save_item"}:
        return raw
    return "approve_item"


def _promo_module_preview_payload(*, service_type: str, module_meta: dict, cleaned: dict) -> dict:
    scope_labels = dict(PromoSearchScope.choices)
    scopes = cleaned.get("resolved_search_scopes") or []
    channels: list[str] = []
    if cleaned.get("use_notification_channel"):
        channels.append("رسائل التنبيه الدعائية")
    if cleaned.get("use_chat_channel"):
        channels.append("رسائل المحادثات الدعائية")

    media_file = cleaned.get("media_file")
    return {
        "title": (cleaned.get("title") or module_meta["label"]).strip() or module_meta["label"],
        "service_label": dict(PromoServiceType.choices).get(service_type, module_meta["label"]),
        "request_id": cleaned.get("request_id") or "",
        "requester_name": (cleaned.get("requester_identifier") or "").strip(),
        "requester_identifier": (cleaned.get("requester_identifier") or "").strip(),
        "start_at": _format_dt(cleaned.get("start_at")),
        "end_at": _format_dt(cleaned.get("end_at")),
        "send_at": _format_dt(cleaned.get("send_at")),
        "search_scopes_text": "، ".join(scope_labels.get(scope, scope) for scope in scopes) if scopes else "—",
        "search_position_text": dict(PromoPosition.choices).get(cleaned.get("search_position") or "", "—"),
        "target_provider_id": cleaned.get("target_provider_id") or "",
        "target_category": cleaned.get("target_category") or "",
        "message_title": cleaned.get("message_title") or "",
        "message_body": cleaned.get("message_body") or "",
        "channels_text": " + ".join(channels) if channels else "—",
        "sponsor_name": cleaned.get("sponsor_name") or "",
        "sponsor_url": cleaned.get("sponsor_url") or "",
        "sponsorship_months": int(cleaned.get("sponsorship_months") or 0),
        "redirect_url": cleaned.get("redirect_url") or "",
        "attachment_specs": cleaned.get("attachment_specs") or "",
        "operator_note": cleaned.get("operator_note") or "",
        "media_name": getattr(media_file, "name", "") if media_file is not None else "",
    }


@dashboard_staff_required
@require_dashboard_access("promo")
def promo_module(request, module_key: str):
    module_meta = PROMO_MODULE_META_BY_KEY.get((module_key or "").strip())
    if not module_meta:
        raise Http404("وحدة الترويج غير موجودة.")
    service_type = module_meta["service_type"]
    can_write = dashboard_allowed(request.user, "promo", write=True)

    requests_base_qs = _promo_requests_queryset_for_user(request.user)
    query_filter = (request.GET.get("q") or "").strip()
    selected_request_id_raw = (request.GET.get("request_id") or "").strip()
    selected_request = requests_base_qs.filter(id=int(selected_request_id_raw)).first() if selected_request_id_raw.isdigit() else None
    module_requests_qs = _promo_module_request_candidates_queryset(
        requests_base_qs,
        service_type=service_type,
    )
    if selected_request is None:
        selected_request = module_requests_qs.first()
    selected_request_item = _promo_selected_request_item_for_service(
        selected_request,
        service_type=service_type,
    )
    selected_portfolio_item_data = _promo_module_selected_portfolio_item_data(
        selected_request=selected_request,
        selected_item=selected_request_item,
    )
    selected_spotlight_item_data = _promo_module_selected_spotlight_item_data(
        selected_request=selected_request,
        selected_item=selected_request_item,
    )
    selected_request_module_assets = _promo_module_assets_for_selected_request(
        selected_request=selected_request,
        service_type=service_type,
    )
    selected_home_banner_asset = (
        selected_request_module_assets[0]
        if service_type == PromoServiceType.HOME_BANNER and selected_request_module_assets
        else None
    )
    selected_message_asset = (
        selected_request_module_assets[0]
        if service_type == PromoServiceType.PROMO_MESSAGES and selected_request_module_assets
        else None
    )
    selected_sponsorship_asset = (
        selected_request_module_assets[0]
        if service_type == PromoServiceType.SPONSORSHIP and selected_request_module_assets
        else None
    )

    module_items_qs = (
        PromoRequestItem.objects.select_related("request", "request__requester", "request__requester__provider_profile")
        .filter(request__in=requests_base_qs, service_type=service_type)
        .order_by("-created_at", "-id")
    )
    if query_filter:
        module_items_qs = module_items_qs.filter(
            Q(request__code__icontains=query_filter)
            | Q(title__icontains=query_filter)
            | Q(request__requester__provider_profile__display_name__icontains=query_filter)
            | Q(request__requester__username__icontains=query_filter)
            | Q(request__requester__phone__icontains=query_filter)
        )
    module_items = list(module_items_qs[:200])

    module_form = PromoModuleItemForm(
        service_type=service_type,
        initial=_promo_module_initial_data_from_request(
            service_type=service_type,
            selected_request=selected_request,
            selected_item=selected_request_item,
        ),
    )
    preview_payload = None
    provider_portfolio_api_template = reverse("providers:provider_portfolio", kwargs={"provider_id": 0}).replace(
        "/0/portfolio/",
        "/__provider_id__/portfolio/",
    )

    if request.method == "POST":
        posted_request_id_raw = (request.POST.get("request_id") or "").strip()
        if posted_request_id_raw.isdigit():
            selected_request = requests_base_qs.filter(id=int(posted_request_id_raw)).first() or selected_request
            selected_request_item = _promo_selected_request_item_for_service(
                selected_request,
                service_type=service_type,
            )
            selected_portfolio_item_data = _promo_module_selected_portfolio_item_data(
                selected_request=selected_request,
                selected_item=selected_request_item,
            )
            selected_spotlight_item_data = _promo_module_selected_spotlight_item_data(
                selected_request=selected_request,
                selected_item=selected_request_item,
            )
            selected_request_module_assets = _promo_module_assets_for_selected_request(
                selected_request=selected_request,
                service_type=service_type,
            )
            selected_home_banner_asset = (
                selected_request_module_assets[0]
                if service_type == PromoServiceType.HOME_BANNER and selected_request_module_assets
                else None
            )
            selected_message_asset = (
                selected_request_module_assets[0]
                if service_type == PromoServiceType.PROMO_MESSAGES and selected_request_module_assets
                else None
            )
            selected_sponsorship_asset = (
                selected_request_module_assets[0]
                if service_type == PromoServiceType.SPONSORSHIP and selected_request_module_assets
                else None
            )

        if not can_write:
            return HttpResponseForbidden("لا تملك صلاحية إدارة وحدات الترويج.")

        # Handle ops_status update from module page
        posted_action = (request.POST.get("action") or "").strip()
        if posted_action == "update_ops_status":
            ops_request_id = (request.POST.get("promo_request_id") or "").strip()
            ops_form_token = (request.POST.get("promo_ops_form_token") or "").strip()
            if not _consume_single_use_submit_token(
                request,
                PROMO_MODULE_OPS_SUBMIT_TOKENS_SESSION_KEY,
                ops_form_token,
            ):
                messages.warning(request, "تم تجاهل محاولة التحديث المكررة. حدّث الصفحة.")
                sel_id = int(ops_request_id) if ops_request_id.isdigit() else None
                return _promo_module_redirect_with_state(request, module_key, request_id=sel_id)
            if ops_request_id.isdigit():
                ops_target = requests_base_qs.filter(id=int(ops_request_id)).first()
                if ops_target is not None:
                    desired_ops = (request.POST.get("ops_status") or "").strip()
                    if desired_ops and desired_ops != ops_target.ops_status:
                        try:
                            ops_target = set_promo_ops_status(
                                pr=ops_target,
                                new_status=desired_ops,
                                by_user=request.user,
                                note="",
                            )
                            _sync_promo_to_unified(pr=ops_target, changed_by=request.user)
                            messages.success(request, f"تم تحديث حالة التنفيذ للطلب {ops_target.code or ops_target.id}.")
                        except ValueError as exc:
                            messages.error(request, str(exc))
                    return _promo_module_redirect_with_state(request, module_key, request_id=ops_target.id)
            messages.error(request, "تعذر تحديد الطلب.")
            return _promo_module_redirect_with_state(request, module_key)

        module_action = _promo_module_action(request)
        if module_action != "preview_item":
            submitted_form_token = (request.POST.get("promo_module_form_token") or "").strip()
            if not _consume_single_use_submit_token(
                request,
                PROMO_MODULE_SUBMIT_TOKENS_SESSION_KEY,
                submitted_form_token,
            ):
                messages.warning(request, "تم تجاهل محاولة الحفظ المكررة لهذه الوحدة. حدّث الصفحة قبل إعادة الإرسال.")
                selected_request_id = int(posted_request_id_raw) if posted_request_id_raw.isdigit() else None
                return _promo_module_redirect_with_state(request, module_key, request_id=selected_request_id)
        module_form = PromoModuleItemForm(request.POST, request.FILES, service_type=service_type)
        if module_form.is_valid():
            cleaned = module_form.cleaned_data
            request_id = cleaned.get("request_id")
            promo_request = requests_base_qs.filter(id=int(request_id)).first() if request_id else None
            if promo_request is None:
                module_form.add_error("request_id", "رقم طلب الترويج المحدد غير متاح.")
            elif module_action != "preview_item":
                # --- status guards: prevent item creation on terminal / already-active requests ---
                _immutable_statuses = {
                    PromoRequestStatus.ACTIVE,
                    PromoRequestStatus.COMPLETED,
                    PromoRequestStatus.EXPIRED,
                    PromoRequestStatus.CANCELLED,
                    PromoRequestStatus.REJECTED,
                }
                if promo_request.status in _immutable_statuses:
                    messages.error(
                        request,
                        f"لا يمكن إضافة بنود جديدة لطلب بحالة «{promo_request.get_status_display()}».",
                    )
                    return _promo_module_redirect_with_state(request, module_key, request_id=promo_request.id)
                if promo_request.ops_status == PromoOpsStatus.COMPLETED:
                    messages.error(
                        request,
                        f"لا يمكن تعديل بنود طلب حالة تنفيذه «{promo_request.get_ops_status_display()}».",
                    )
                    return _promo_module_redirect_with_state(request, module_key, request_id=promo_request.id)
                # For PROMO_MESSAGES: prevent creating a duplicate item if one was already sent
                if service_type == PromoServiceType.PROMO_MESSAGES:
                    already_sent = promo_request.items.filter(
                        service_type=PromoServiceType.PROMO_MESSAGES,
                        message_sent_at__isnull=False,
                    ).exists()
                    if already_sent:
                        messages.error(
                            request,
                            "يوجد بند رسائل دعائية تم إرساله مسبقًا في هذا الطلب. لا يمكن إضافة بند آخر.",
                        )
                        return _promo_module_redirect_with_state(request, module_key, request_id=promo_request.id)

            target_provider = None
            target_provider_id = cleaned.get("target_provider_id")
            if target_provider_id:
                target_provider = ProviderProfile.objects.filter(id=int(target_provider_id)).first()
                if target_provider is None:
                    module_form.add_error("target_provider_id", "معرف المختص المستهدف غير صحيح.")

            target_portfolio_item = None
            target_portfolio_item_id = cleaned.get("target_portfolio_item_id")
            if target_portfolio_item_id:
                target_portfolio_item = (
                    ProviderPortfolioItem.objects.select_related("provider", "provider__user")
                    .filter(id=int(target_portfolio_item_id))
                    .first()
                )
                if target_portfolio_item is None:
                    module_form.add_error("target_portfolio_item_id", "الصورة المختارة من معرض الأعمال غير متاحة.")
                else:
                    target_media_type = str(getattr(target_portfolio_item, "file_type", "") or "").lower()
                    if service_type == PromoServiceType.PORTFOLIO_SHOWCASE and target_media_type != "image":
                        module_form.add_error("target_portfolio_item_id", "يمكن اختيار الصور فقط لهذا الشريط.")
                    elif service_type == PromoServiceType.SNAPSHOTS and target_media_type not in {"image", "video"}:
                        module_form.add_error("target_portfolio_item_id", "يمكن اختيار صورة أو فيديو فقط لشريط اللمحات.")
                    else:
                        if target_provider is not None and target_portfolio_item.provider_id != target_provider.id:
                            module_form.add_error("target_portfolio_item_id", "الوسيط المختار لا يتبع مزود الخدمة المحدد.")
                        elif target_provider is None:
                            target_provider = target_portfolio_item.provider

            target_spotlight_item = None
            target_spotlight_item_id = cleaned.get("target_spotlight_item_id")
            if target_spotlight_item_id:
                target_spotlight_item = (
                    ProviderSpotlightItem.objects.select_related("provider", "provider__user")
                    .filter(id=int(target_spotlight_item_id))
                    .first()
                )
                if target_spotlight_item is None:
                    module_form.add_error("target_spotlight_item_id", "الريل المختار من اللمحات غير متاح.")
                else:
                    target_media_type = str(getattr(target_spotlight_item, "file_type", "") or "").lower()
                    if service_type == PromoServiceType.SNAPSHOTS and target_media_type not in {"image", "video"}:
                        module_form.add_error("target_spotlight_item_id", "يمكن اختيار ريل صورة أو فيديو فقط لشريط اللمحات.")
                    else:
                        if target_provider is not None and target_spotlight_item.provider_id != target_provider.id:
                            module_form.add_error("target_spotlight_item_id", "الريل المختار لا يتبع مزود الخدمة المحدد.")
                        elif target_provider is None:
                            target_provider = target_spotlight_item.provider

            if (
                target_provider is None
                and promo_request is not None
                and getattr(promo_request.requester, "provider_profile", None) is not None
                and service_type in PROMO_TARGETED_SERVICE_TYPES
            ):
                target_provider = promo_request.requester.provider_profile

            if module_form.errors:
                messages.error(request, "يرجى مراجعة الحقول المحددة.")
            elif module_action == "preview_item":
                preview_payload = _promo_module_preview_payload(
                    service_type=service_type,
                    module_meta=module_meta,
                    cleaned=cleaned,
                )
                messages.info(request, "تم تجهيز معاينة البند. راجع الملخص ثم اضغط اعتماد للتنفيذ.")
            else:
                try:
                    search_scopes = [str(scope).strip() for scope in (cleaned.get("resolved_search_scopes") or []) if str(scope).strip()]
                    if service_type == PromoServiceType.SEARCH_RESULTS:
                        scopes_to_create = search_scopes
                    else:
                        scopes_to_create = [(cleaned.get("search_scope") or "").strip()]
                    scopes_to_create = [scope for scope in scopes_to_create if scope]
                    if not scopes_to_create:
                        scopes_to_create = [""]

                    next_sort = (
                        promo_request.items.filter(service_type=service_type).order_by("-sort_order").values_list("sort_order", flat=True).first()
                        or 0
                    )
                    created_items: list[PromoRequestItem] = []
                    scope_labels = dict(PromoSearchScope.choices)
                    for scope in scopes_to_create:
                        item_title = (cleaned.get("title") or module_meta["label"])[:160]
                        if service_type == PromoServiceType.SEARCH_RESULTS and scope:
                            scope_suffix = scope_labels.get(scope, scope)
                            item_title = f"{item_title} - {scope_suffix}"[:160]

                        item_fields = dict(
                            title=item_title,
                            start_at=cleaned.get("start_at"),
                            end_at=cleaned.get("end_at"),
                            send_at=cleaned.get("send_at"),
                            search_position=cleaned.get("search_position") or "",
                            target_provider=target_provider,
                            target_portfolio_item=target_portfolio_item,
                            target_spotlight_item=target_spotlight_item,
                            target_category=cleaned.get("target_category") or "",
                            target_city=(
                                ""
                                if service_type == PromoServiceType.SEARCH_RESULTS
                                else (cleaned.get("target_city") or "")
                            ),
                            redirect_url=cleaned.get("redirect_url") or "",
                            message_title=cleaned.get("message_title") or "",
                            message_body=cleaned.get("message_body") or "",
                            use_notification_channel=bool(cleaned.get("use_notification_channel")),
                            use_chat_channel=bool(cleaned.get("use_chat_channel")),
                            sponsor_name=cleaned.get("sponsor_name") or "",
                            sponsor_url=cleaned.get("sponsor_url") or "",
                            sponsorship_months=int(cleaned.get("sponsorship_months") or 0),
                            attachment_specs=cleaned.get("attachment_specs") or "",
                            operator_note=cleaned.get("operator_note") or "",
                        )

                        # Upsert: update existing item instead of creating duplicates
                        existing_item = promo_request.items.filter(
                            service_type=service_type,
                            search_scope=scope,
                        ).order_by("id").first()

                        if existing_item is not None:
                            for field_name, field_value in item_fields.items():
                                setattr(existing_item, field_name, field_value)
                            existing_item.save(update_fields=list(item_fields.keys()) + ["updated_at"])
                            created_items.append(existing_item)
                        else:
                            next_sort = int(next_sort) + 10
                            created_items.append(
                                PromoRequestItem.objects.create(
                                    request=promo_request,
                                    service_type=service_type,
                                    search_scope=scope,
                                    sort_order=next_sort,
                                    **item_fields,
                                )
                            )

                    media_file = cleaned.get("media_file")
                    if media_file is not None and created_items:
                        PromoAsset.objects.create(
                            request=promo_request,
                            item=created_items[0],
                            asset_type=_promo_asset_type_for_upload(media_file),
                            title=created_items[0].title,
                            file=media_file,
                            uploaded_by=request.user,
                        )

                    start_candidates = [point for point in [promo_request.start_at] if point]
                    end_candidates = [point for point in [promo_request.end_at] if point]
                    for created_item in created_items:
                        if created_item.start_at:
                            start_candidates.append(created_item.start_at)
                        if created_item.send_at:
                            start_candidates.append(created_item.send_at)
                            end_candidates.append(created_item.send_at + timedelta(hours=1))
                        if created_item.end_at:
                            end_candidates.append(created_item.end_at)

                    promo_request.start_at = min(start_candidates) if start_candidates else promo_request.start_at
                    promo_request.end_at = max(end_candidates) if end_candidates else promo_request.end_at
                    if promo_request.end_at <= promo_request.start_at:
                        promo_request.end_at = promo_request.start_at + timedelta(days=1)

                    first_item = created_items[0]
                    if not promo_request.target_provider_id and first_item.target_provider_id:
                        promo_request.target_provider = first_item.target_provider
                    if not promo_request.target_portfolio_item_id and first_item.target_portfolio_item_id:
                        promo_request.target_portfolio_item = first_item.target_portfolio_item
                    if not promo_request.target_spotlight_item_id and first_item.target_spotlight_item_id:
                        promo_request.target_spotlight_item = first_item.target_spotlight_item
                    if not promo_request.target_category and first_item.target_category:
                        promo_request.target_category = first_item.target_category
                    if (
                        service_type != PromoServiceType.SEARCH_RESULTS
                        and not promo_request.target_city
                        and first_item.target_city
                    ):
                        promo_request.target_city = first_item.target_city
                    if not promo_request.redirect_url and first_item.redirect_url:
                        promo_request.redirect_url = first_item.redirect_url
                    promo_request.save(
                        update_fields=[
                            "start_at",
                            "end_at",
                            "target_provider",
                            "target_portfolio_item",
                            "target_spotlight_item",
                            "target_category",
                            "target_city",
                            "redirect_url",
                            "updated_at",
                        ]
                    )
                    _sync_promo_to_unified(pr=promo_request, changed_by=request.user)

                    quote_snapshot = _promo_quote_snapshot(promo_request)
                    created_count = len(created_items)
                    if quote_snapshot is None:
                        messages.success(
                            request,
                            f"تم اعتماد {created_count} بند في الطلب {promo_request.code or promo_request.id}.",
                        )
                    else:
                        messages.success(
                            request,
                            (
                                f"تم اعتماد {created_count} بند وحساب التقدير المالي. "
                                f"الإجمالي: {quote_snapshot['total']} SAR (يشمل الضريبة)."
                            ),
                        )
                    return redirect('dashboard:promo_request_detail', request_id=promo_request.id)
                except ValueError as exc:
                    messages.error(request, str(exc))
        else:
            messages.error(request, "يرجى مراجعة حقول نموذج وحدة الترويج.")

    # Determine if the selected request is in an immutable (terminal) state
    _terminal_statuses = {
        PromoRequestStatus.ACTIVE,
        PromoRequestStatus.COMPLETED,
        PromoRequestStatus.EXPIRED,
        PromoRequestStatus.CANCELLED,
        PromoRequestStatus.REJECTED,
    }
    _terminal_ops = {PromoOpsStatus.COMPLETED}
    selected_request_is_immutable = False
    selected_request_immutable_reason = ""
    if selected_request is not None:
        if selected_request.status in _terminal_statuses:
            selected_request_is_immutable = True
            selected_request_immutable_reason = (
                f"الطلب {selected_request.code or selected_request.id} بحالة "
                f"«{selected_request.get_status_display()}» ولا يمكن التعديل عليه أو إضافة بنود جديدة."
            )
        elif selected_request.ops_status in _terminal_ops:
            selected_request_is_immutable = True
            selected_request_immutable_reason = (
                f"الطلب {selected_request.code or selected_request.id} حالة تنفيذه "
                f"«{selected_request.get_ops_status_display()}» ولا يمكن التعديل عليه."
            )

    context = _promo_base_context(module_key)
    context.update(
        {
            "hero_title": f"لوحة فريق إدارة الترويج - {module_meta['label']}",
            "hero_subtitle": module_meta["description"],
            "module_meta": module_meta,
            "module_form": module_form,
            "module_rows": _promo_module_rows(module_items),
            "can_write": can_write,
            "filters": {"q": query_filter},
            "selected_request": selected_request,
            "selected_request_is_immutable": selected_request_is_immutable,
            "selected_request_immutable_reason": selected_request_immutable_reason,
            "selected_requester_label": _promo_requester_label(selected_request.requester) if selected_request else "",
            "selected_request_item": selected_request_item,
            "selected_portfolio_item_data": selected_portfolio_item_data,
            "selected_spotlight_item_data": selected_spotlight_item_data,
            "selected_request_module_assets": selected_request_module_assets,
            "selected_home_banner_asset": selected_home_banner_asset,
            "selected_message_asset": selected_message_asset,
            "selected_sponsorship_asset": selected_sponsorship_asset,
            "selected_request_quote": _promo_quote_snapshot(selected_request) if selected_request else None,
            "selected_request_payment_status_label": _promo_request_payment_status_label(selected_request),
            "preview_payload": preview_payload,
            "is_featured_module": service_type == PromoServiceType.FEATURED_SPECIALISTS,
            "is_portfolio_module": service_type == PromoServiceType.PORTFOLIO_SHOWCASE,
            "is_snapshots_module": service_type == PromoServiceType.SNAPSHOTS,
            "is_search_module": service_type == PromoServiceType.SEARCH_RESULTS,
            "is_messages_module": service_type == PromoServiceType.PROMO_MESSAGES,
            "is_sponsorship_module": service_type == PromoServiceType.SPONSORSHIP,
            "is_live_preview_action_module": service_type in {
                PromoServiceType.HOME_BANNER,
                PromoServiceType.PROMO_MESSAGES,
                PromoServiceType.SPONSORSHIP,
            },
            "is_module_review_flow": service_type in {PromoServiceType.PROMO_MESSAGES, PromoServiceType.SPONSORSHIP},
            "provider_portfolio_api_template": provider_portfolio_api_template,
            "provider_detail_api_template": reverse("providers:provider_detail", kwargs={"pk": 0}).replace(
                "/0/",
                "/__provider_id__/",
            ),
            "provider_spotlights_api_template": reverse("providers:provider_spotlights", kwargs={"provider_id": 0}).replace(
                "/0/spotlights/",
                "/__provider_id__/spotlights/",
            ),
            "module_preview_api_url": reverse(
                "dashboard:promo_module_request_preview_api",
                kwargs={"module_key": module_key},
            ),
            "promo_module_form_token": (
                _issue_single_use_submit_token(request, PROMO_MODULE_SUBMIT_TOKENS_SESSION_KEY)
                if can_write
                else ""
            ),
            "ops_status_choices": PromoOpsStatus.choices,
            "promo_ops_form_token": (
                _issue_single_use_submit_token(request, PROMO_MODULE_OPS_SUBMIT_TOKENS_SESSION_KEY)
                if can_write and selected_request is not None and not selected_request_is_immutable
                else ""
            ),
        }
    )
    return render(request, "dashboard/promo_module.html", context)


@dashboard_staff_required
@require_dashboard_access("promo")
def promo_module_request_preview_api(request, module_key: str):
    module_meta = PROMO_MODULE_META_BY_KEY.get((module_key or "").strip())
    if not module_meta:
        raise Http404("وحدة الترويج غير موجودة.")

    request_id_raw = (request.GET.get("request_id") or "").strip()
    if not request_id_raw.isdigit():
        return JsonResponse(
            {"ok": False, "error": "رقم الطلب غير صالح."},
            status=400,
            json_dumps_params={"ensure_ascii": False},
        )

    requests_base_qs = _promo_requests_queryset_for_user(request.user)
    selected_request = requests_base_qs.filter(id=int(request_id_raw)).first()
    if selected_request is None:
        return JsonResponse(
            {"ok": False, "error": "طلب الترويج المحدد غير متاح."},
            status=404,
            json_dumps_params={"ensure_ascii": False},
        )

    payload = _promo_module_request_preview_payload(
        selected_request=selected_request,
        service_type=module_meta["service_type"],
    )
    return JsonResponse(
        {"ok": True, **payload},
        json_dumps_params={"ensure_ascii": False},
    )


@dashboard_staff_required
@require_dashboard_access("promo")
def promo_pricing(request):
    ensure_default_pricing_rules()
    pricing_rules = list(PromoPricingRule.objects.filter(is_active=True).order_by("sort_order", "id"))
    can_write = dashboard_allowed(request.user, "promo", write=True)

    if request.method == "POST":
        if not can_write:
            return HttpResponseForbidden("لا تملك صلاحية تعديل تسعيرات الترويج.")

        submitted_form_token = (request.POST.get("promo_pricing_form_token") or "").strip()
        if not _consume_single_use_submit_token(
            request,
            PROMO_PRICING_SUBMIT_TOKENS_SESSION_KEY,
            submitted_form_token,
        ):
            messages.warning(request, "تم تجاهل محاولة حفظ التسعيرات المكررة. حدّث الصفحة قبل إعادة الحفظ.")
            return redirect("dashboard:promo_pricing")

        validation_errors: list[str] = []
        parsed_amounts: dict[int, Decimal] = {}

        for rule in pricing_rules:
            field_name = f"amount_{rule.id}"
            normalized_value = _normalize_decimal_text(request.POST.get(field_name, ""))
            if not normalized_value:
                validation_errors.append(f"يرجى إدخال قيمة سعرية للبند: {rule.title}.")
                continue
            try:
                amount_value = Decimal(normalized_value).quantize(Decimal("0.01"))
            except (InvalidOperation, ValueError):
                validation_errors.append(f"صيغة السعر غير صحيحة للبند: {rule.title}.")
                continue
            if amount_value < 0:
                validation_errors.append(f"لا يمكن إدخال سعر سالب للبند: {rule.title}.")
                continue
            parsed_amounts[rule.id] = amount_value

        if validation_errors:
            for error_text in validation_errors[:4]:
                messages.error(request, error_text)
            extra_errors_count = len(validation_errors) - 4
            if extra_errors_count > 0:
                messages.error(request, f"يوجد {extra_errors_count} أخطاء إضافية. راجع جميع القيم قبل الحفظ.")
        else:
            updated_count = 0
            for rule in pricing_rules:
                new_amount = parsed_amounts.get(rule.id, rule.amount)
                if rule.amount == new_amount:
                    continue
                rule.amount = new_amount
                rule.save(update_fields=["amount", "updated_at"])
                updated_count += 1
            if updated_count:
                messages.success(request, f"تم تحديث {updated_count} بند تسعير بنجاح.")
            else:
                messages.info(request, "لم يتم إجراء أي تعديل على التسعيرات.")
            return redirect("dashboard:promo_pricing")

    by_service: dict[str, list[PromoPricingRule]] = {}
    for rule in pricing_rules:
        by_service.setdefault(rule.service_type, []).append(rule)

    context = _promo_base_context("pricing")
    context.update(
        {
            "hero_title": "أسعار خدمات الترويج",
            "hero_subtitle": "تسعير ديناميكي معتمد للوحدات الإعلانية داخل لوحة الترويج.",
            "home_banner_rule": (by_service.get(PromoServiceType.HOME_BANNER) or [None])[0],
            "featured_rules": by_service.get(PromoServiceType.FEATURED_SPECIALISTS, []),
            "portfolio_rules": by_service.get(PromoServiceType.PORTFOLIO_SHOWCASE, []),
            "snapshot_rules": by_service.get(PromoServiceType.SNAPSHOTS, []),
            "search_rules": by_service.get(PromoServiceType.SEARCH_RESULTS, []),
            "message_rules": by_service.get(PromoServiceType.PROMO_MESSAGES, []),
            "sponsorship_rules": by_service.get(PromoServiceType.SPONSORSHIP, []),
            "can_write": can_write,
            "promo_pricing_form_token": (
                _issue_single_use_submit_token(request, PROMO_PRICING_SUBMIT_TOKENS_SESSION_KEY)
                if can_write
                else ""
            ),
        }
    )
    return render(request, "dashboard/promo_pricing.html", context)


CONTENT_TEAM_LABELS = {
    "support": "فريق الدعم والمساعدة",
    "technical": "فريق الدعم والمساعدة",
    "content": "فريق إدارة المحتوى",
    "promo": "فريق إدارة الإعلانات والترويج",
    "verification": "فريق التوثيق",
    "subs": "فريق إدارة الترقية والاشتراكات",
    "finance": "فريق إدارة الترقية والاشتراكات",
    "extras": "فريق إدارة الخدمات الإضافية",
}
CONTENT_MANAGED_TEAM_NAMES = [
    "فريق الدعم والمساعدة",
    "فريق إدارة المحتوى",
    "فريق إدارة الإعلانات والترويج",
    "فريق التوثيق",
    "فريق إدارة الترقية والاشتراكات",
    "فريق إدارة الخدمات الإضافية",
]
def _latest_request_code(prefix: str, *, request_type: str | None = None) -> str:
    query = UnifiedRequest.objects.exclude(code="")
    if request_type:
        query = query.filter(request_type=request_type)
    value = query.order_by("-id").values_list("code", flat=True).first()
    return value or f"{prefix}000001"


def _content_request_codes() -> list[dict]:
    helpdesk_code = (
        SupportTicket.objects.exclude(code="").order_by("-id").values_list("code", flat=True).first()
        or "HD000001"
    )
    promo_code = (
        PromoRequest.objects.exclude(code="").order_by("-id").values_list("code", flat=True).first()
        or "MD000001"
    )
    verification_code = (
        VerificationRequest.objects.exclude(code="").order_by("-id").values_list("code", flat=True).first()
        or "AD000001"
    )
    subscription_code = _latest_request_code("SD", request_type=UnifiedRequestType.SUBSCRIPTION)
    extras_code = _latest_request_code("P", request_type=UnifiedRequestType.EXTRAS)

    return [
        {"code": helpdesk_code, "label": "طلبات الدعم والمساعدة"},
        {"code": promo_code, "label": "طلبات الإعلانات والترويج"},
        {"code": verification_code, "label": "طلبات التوثيق"},
        {"code": subscription_code, "label": "طلبات الترقية والاشتراكات"},
        {"code": extras_code, "label": "طلبات الخدمات الإضافية"},
    ]


def _dashboard_team_panels() -> list[dict]:
    return [
        {
            "key": "support",
            "team": "فريق الدعم والمساعدة",
            "summary": "إدارة البلاغات والتذاكر المفتوحة ومتابعة الردود والإسناد.",
            "dashboards": [
                {"label": "لوحة الدعم والمساعدة", "url": reverse("dashboard:support_dashboard")},
                {"label": "إدارة التقييم والمراجعات", "url": reverse("dashboard:content_reviews_dashboard")},
            ],
            "worklists": [
                "طلبات الدعم والمساعدة",
                "بلاغات المحادثات والشكاوى",
                "إغلاق الطلبات أو إعادتها للعميل",
            ],
        },
        {
            "key": "content",
            "team": "فريق إدارة المحتوى",
            "summary": "تشغيل محتوى المنصة، صفحات البداية، والمراجعات التشغيلية.",
            "dashboards": [
                {"label": "لوحة إدارة المحتوى", "url": reverse("dashboard:content_dashboard_home")},
                {"label": "إدارة التمييز", "url": reverse("dashboard:content_excellence")},
            ],
            "worklists": [
                "محتوى صفحة الدخول لأول مرة",
                "محتوى بروفة التعريف",
                "قوائم الجودة والتقييمات",
            ],
        },
        {
            "key": "promo",
            "team": "فريق إدارة الإعلانات والترويج",
            "summary": "متابعة استفسارات الترويج وطلبات الترويج وتنفيذها تشغيليًا حتى الإغلاق.",
            "dashboards": [
                {"label": "لوحة إدارة الترويج", "url": reverse("dashboard:promo_dashboard")},
                {"label": "تسعير خدمات الترويج", "url": reverse("dashboard:promo_pricing")},
            ],
            "worklists": [
                "قائمة استفسارات الترويج",
                "قائمة طلبات الترويج",
                "حالة التنفيذ: جديد ← تحت المعالجة ← مكتمل",
            ],
        },
        {
            "key": "verification",
            "team": "فريق التوثيق",
            "summary": "متابعة حالات التوثيق والتحقق من استيفاء المتطلبات النظامية.",
            "dashboards": [
                {"label": "لوحة فريق التوثيق", "url": reverse("dashboard:verification_dashboard")},
            ],
            "worklists": [
                "طلبات التوثيق",
                "حالات الاعتماد أو الإرجاع",
                "التدقيق على البيانات المرفقة",
            ],
        },
        {
            "key": "subs",
            "team": "فريق إدارة الترقية والاشتراكات",
            "summary": "إدارة طلبات الاشتراك والترقية وما يرتبط بها من فواتير تشغيلية.",
            "dashboards": [
                {"label": "لوحة فريق إدارة الاشتراكات", "url": reverse("dashboard:subscription_dashboard")},
            ],
            "worklists": [
                "طلبات الترقية والاشتراكات",
                "متابعة حالات السداد",
                "بيانات حسابات المشتركين والتجديد والانتهاء",
            ],
        },
        {
            "key": "extras",
            "team": "فريق إدارة الخدمات الإضافية",
            "summary": "تشغيل الطلبات الإضافية وتحويلها للمسار التنفيذي المناسب.",
            "dashboards": [
                {"label": "لوحة فريق إدارة الخدمات الإضافية", "url": reverse("dashboard:extras_dashboard")},
            ],
            "worklists": [
                "طلبات الخدمات الإضافية",
                "توزيع المهام على الفرق المختصة",
                "متابعة الإغلاق ومعايير التسليم",
            ],
        },
    ]
CONTENT_REVIEW_TYPES = {SupportTicketType.SUGGEST, SupportTicketType.COMPLAINT}
CONTENT_EXCELLENCE_BADGE_CODES = [
    TOP_100_CLUB_BADGE_CODE,
    HIGH_ACHIEVEMENT_BADGE_CODE,
    FEATURED_SERVICE_BADGE_CODE,
]
CONTENT_EXCELLENCE_BADGE_TAB_ORDER = [
    TOP_100_CLUB_BADGE_CODE,
    HIGH_ACHIEVEMENT_BADGE_CODE,
    FEATURED_SERVICE_BADGE_CODE,
]


def _content_nav_items(active_key: str) -> list[dict]:
    items = [
        {
            "key": "home",
            "label": "لوحة فريق إدارة المحتوى",
            "description": "نقطة الدخول الرئيسية لوحدات إدارة المحتوى.",
            "url": reverse("dashboard:content_dashboard_home"),
        },
        {
            "key": "first_time",
            "label": "محتوى صفحة الدخول لأول مرة",
            "description": "تحرير النصوص الأساسية ورفع تصميم شاشة البداية.",
            "url": reverse("dashboard:content_first_time"),
        },
        {
            "key": "intro",
            "label": "محتوى صفحة بروفة التعريف بالتطبيق",
            "description": "إدارة تصميم شاشة بروفة التعريف مع معاينة مباشرة.",
            "url": reverse("dashboard:content_intro"),
        },
        {
            "key": "settings",
            "label": "تحديث ملفات الشروط والأحكام",
            "description": "تحديث ملفات الشروط والأحكام والخصوصية وروابط المنصة الرسمية.",
            "url": reverse("dashboard:content_settings"),
        },
        {
            "key": "reviews",
            "label": "إدارة التقييم والمراجعات",
            "description": "معالجة الطلبات، البلاغات، وتعليق الإدارة.",
            "url": reverse("dashboard:content_reviews_dashboard"),
        },
        {
            "key": "excellence",
            "label": "إدارة التميز",
            "description": "متابعة شارات التميز وتصدير القوائم المعتمدة.",
            "url": reverse("dashboard:content_excellence"),
        },
    ]
    for item in items:
        item["active"] = item["key"] == active_key
    return items


def _content_base_context(active_key: str) -> dict:
    nav_items = _content_nav_items(active_key)
    content_modules = [item for item in nav_items if item.get("key") != "home"]
    return {
        "nav_items": nav_items,
        "content_modules": content_modules,
        "managed_teams": CONTENT_MANAGED_TEAM_NAMES,
        "request_codes": _content_request_codes(),
    }


def _content_block_get_or_create(key: str, *, default_title: str, default_body: str = "") -> SiteContentBlock:
    block, _ = SiteContentBlock.objects.get_or_create(
        key=key,
        defaults={
            "title_ar": default_title,
            "body_ar": default_body,
            "is_active": True,
        },
    )
    return block


def _content_media_specs(media_field) -> str:
    if not media_field:
        return "لا يوجد ملف مرفوع."
    name = str(getattr(media_field, "name", "") or "").split("/")[-1]
    size = getattr(media_field, "size", None)
    if isinstance(size, int) and size > 0:
        size_mb = size / (1024 * 1024)
        return f"{name} - {size_mb:.2f} MB"
    return name or "ملف مرفوع"


def _save_content_block(
    *,
    block: SiteContentBlock,
    title: str | None = None,
    body: str | None = None,
    media_file=None,
    actor=None,
    request=None,
) -> SiteContentBlock:
    update_fields: list[str] = []
    if title is not None:
        sanitized_title = sanitize_text(title)[:255]
        if block.title_ar != sanitized_title:
            block.title_ar = sanitized_title
            update_fields.append("title_ar")
    if body is not None:
        sanitized_body = sanitize_multiline_text(body)
        if block.body_ar != sanitized_body:
            block.body_ar = sanitized_body
            update_fields.append("body_ar")
    if media_file is not None:
        block.media_file = media_file
        update_fields.append("media_file")
    if not block.is_active:
        block.is_active = True
        update_fields.append("is_active")
    if actor is not None and block.updated_by_id != getattr(actor, "id", None):
        block.updated_by = actor
        update_fields.append("updated_by")
    if update_fields:
        update_fields.append("updated_at")
        block.save(update_fields=update_fields)
        log_action(
            actor=actor,
            action=AuditAction.CONTENT_BLOCK_UPDATED,
            reference_type="content.block",
            reference_id=str(block.id),
            request=request,
            extra={
                "key": block.key,
                "updated_fields": update_fields,
            },
        )
    return block


@dashboard_staff_required
@require_dashboard_access("content")
def content_dashboard_home(request):
    inquiries_base_qs = _content_review_queryset_for_user(request.user)
    inquiry_q = (request.GET.get("inquiry_q") or "").strip()

    inquiries_qs = inquiries_base_qs
    if inquiry_q:
        inquiries_qs = inquiries_qs.filter(
            Q(code__icontains=inquiry_q)
            | Q(description__icontains=inquiry_q)
            | Q(requester__username__icontains=inquiry_q)
            | Q(requester__phone__icontains=inquiry_q)
        )
    inquiries = list(inquiries_qs.order_by("-created_at", "-id"))

    headers, rows = _content_review_export_rows(inquiries)
    if _want_csv(request):
        return _csv_response("content_inquiries.csv", headers, rows)
    if _want_xlsx(request):
        return xlsx_response("content_inquiries.xlsx", "content_inquiries", headers, rows)
    if _want_pdf(request):
        return pdf_response("content_inquiries.pdf", "لوحة إدارة المحتوى - قائمة الاستفسارات", headers, rows, landscape=True)

    selected_inquiry = None
    selected_inquiry_id_raw = (request.GET.get("inquiry") or "").strip()
    if selected_inquiry_id_raw.isdigit():
        selected_inquiry = inquiries_base_qs.filter(id=int(selected_inquiry_id_raw)).first()

    context = _content_base_context("home")
    context.update(
        {
            "hero_title": "لوحة فريق إدارة المحتوى",
            "hero_subtitle": "إدارة نصوص وتجارب الدخول، ضبط الإعدادات، متابعة التقييمات، وتشغيل التميز من لوحة موحدة.",
            "team_panels": _dashboard_team_panels(),
            "content_inquiries": _content_review_ticket_rows(inquiries),
            "content_inquiry_summary": _content_review_summary(inquiries),
            "content_filters": {
                "inquiry_q": inquiry_q,
            },
            "selected_content_inquiry": selected_inquiry,
        }
    )
    return render(request, "dashboard/content_dashboard_home.html", context)


@dashboard_staff_required
@require_dashboard_access("content")
def content_first_time(request):
    can_write = dashboard_allowed(request.user, "content", write=True)
    manage_policy = ContentManagePolicy.evaluate(request.user)
    can_manage = bool(can_write and manage_policy.allowed)

    intro_block = _content_block_get_or_create(
        ContentBlockKey.ONBOARDING_FIRST_TIME,
        default_title="مرحبًا بك في نوافذ",
        default_body="منصة موحدة لاكتشاف الخدمات باحترافية أعلى، مع تجربة أوضح منذ اللحظة الأولى.",
    )
    client_block = _content_block_get_or_create(
        ContentBlockKey.ONBOARDING_INTRO,
        default_title="للعملاء ومقدمي الخدمات",
        default_body="ابحث، قارن، وابدأ الطلب بثقة عبر تجربة مرئية أوضح وأكثر ترتيبًا.",
    )
    provider_block = _content_block_get_or_create(
        ContentBlockKey.ONBOARDING_GET_STARTED,
        default_title="ابدأ الآن",
        default_body="أنجز خطواتك الأولى بسرعة، ثم انتقل إلى بروفة التطبيق قبل تسجيل الدخول.",
    )

    slide_blocks = [
        {
            "code": "01",
            "name": "الشريحة الأولى",
            "block": intro_block,
            "title_field": "intro_title",
            "body_field": "intro_body",
            "file_field": "intro_design_file",
            "spec_field": "intro_file_specs",
        },
        {
            "code": "02",
            "name": "الشريحة الثانية",
            "block": client_block,
            "title_field": "client_title",
            "body_field": "client_body",
            "file_field": "client_design_file",
            "spec_field": "client_file_specs",
        },
        {
            "code": "03",
            "name": "الشريحة الثالثة",
            "block": provider_block,
            "title_field": "provider_title",
            "body_field": "provider_body",
            "file_field": "provider_design_file",
            "spec_field": "provider_file_specs",
        },
    ]

    text_form = ContentFirstTimeForm(
        initial={
            "intro_title": intro_block.title_ar,
            "intro_body": intro_block.body_ar,
            "client_title": client_block.title_ar,
            "client_body": client_block.body_ar,
            "provider_title": provider_block.title_ar,
            "provider_body": provider_block.body_ar,
        }
    )
    media_form = ContentFirstTimeMediaForm(
        initial={
            "intro_file_specs": _content_media_specs(intro_block.media_file),
            "client_file_specs": _content_media_specs(client_block.media_file),
            "provider_file_specs": _content_media_specs(provider_block.media_file),
        }
    )

    if request.method == "POST":
        if not can_manage:
            return HttpResponseForbidden("لا تملك صلاحية إدارة محتوى لوحة المحتوى.")
        action = (request.POST.get("action") or "").strip()

        if action == "save_text":
            text_form = ContentFirstTimeForm(request.POST)
            if text_form.is_valid():
                _save_content_block(
                    block=intro_block,
                    title=text_form.cleaned_data["intro_title"],
                    body=text_form.cleaned_data["intro_body"],
                    actor=request.user,
                    request=request,
                )
                _save_content_block(
                    block=client_block,
                    title=text_form.cleaned_data["client_title"],
                    body=text_form.cleaned_data["client_body"],
                    actor=request.user,
                    request=request,
                )
                _save_content_block(
                    block=provider_block,
                    title=text_form.cleaned_data["provider_title"],
                    body=text_form.cleaned_data["provider_body"],
                    actor=request.user,
                    request=request,
                )
                messages.success(request, "تم تحديث محتوى صفحة الدخول لأول مرة.")
                return redirect("dashboard:content_first_time")
            messages.error(request, "يرجى مراجعة حقول النصوص.")

        elif action == "upload_media":
            media_form = ContentFirstTimeMediaForm(request.POST, request.FILES)
            if media_form.is_valid():
                uploaded_any = False
                for slide in slide_blocks:
                    design_file = media_form.cleaned_data.get(slide["file_field"])
                    if design_file is None:
                        continue
                    _save_content_block(
                        block=slide["block"],
                        media_file=design_file,
                        actor=request.user,
                        request=request,
                    )
                    uploaded_any = True
                if not uploaded_any:
                    messages.error(request, "يرجى اختيار ملف واحد على الأقل قبل الحفظ.")
                else:
                    messages.success(request, "تم تحديث صور شرائح صفحة الدخول لأول مرة.")
                    return redirect("dashboard:content_first_time")
            else:
                messages.error(request, "تعذّر رفع ملفات الشرائح. راجع مواصفات الملفات.")

    slide_previews = []
    for slide in slide_blocks:
        field_name = slide["title_field"]
        body_name = slide["body_field"]
        slide_previews.append(
            {
                **slide,
                "title": text_form[field_name].value() or slide["block"].title_ar,
                "body": text_form[body_name].value() or slide["block"].body_ar,
                "media_file": slide["block"].media_file,
                "media_type": slide["block"].media_type,
                "file_specs": _content_media_specs(slide["block"].media_file),
            }
        )

    context = _content_base_context("first_time")
    context.update(
        {
            "hero_title": "محتوى صفحة الدخول لأول مرة",
            "hero_subtitle": "إدارة 3 شرائح مستقلة، لكل شريحة نص مختصر وصورة أو فيديو، قبل شاشة بروفة التطبيق ثم تسجيل الدخول.",
            "text_form": text_form,
            "media_form": media_form,
            "can_manage": can_manage,
            "can_write": can_write,
            "intro_block": intro_block,
            "client_block": client_block,
            "provider_block": provider_block,
            "slide_previews": slide_previews,
        }
    )
    return render(request, "dashboard/content_first_time.html", context)


@dashboard_staff_required
@require_dashboard_access("content")
def content_intro(request):
    can_write = dashboard_allowed(request.user, "content", write=True)
    manage_policy = ContentManagePolicy.evaluate(request.user)
    can_manage = bool(can_write and manage_policy.allowed)

    intro_preview_block = _content_block_get_or_create(
        ContentBlockKey.APP_INTRO_PREVIEW,
        default_title="بروفة التعريف بالتطبيق",
        default_body="",
    )
    upload_form = ContentDesignUploadForm(initial={"file_specs": _content_media_specs(intro_preview_block.media_file)})

    if request.method == "POST":
        if not can_manage:
            return HttpResponseForbidden("لا تملك صلاحية تعديل بروفة التعريف.")
        action = (request.POST.get("action") or "").strip()
        if action == "upload_design":
            upload_form = ContentDesignUploadForm(request.POST, request.FILES)
            if upload_form.is_valid():
                uploaded = upload_form.cleaned_data.get("design_file")
                if uploaded is None:
                    messages.error(request, "يرجى اختيار ملف التصميم قبل الحفظ.")
                else:
                    _save_content_block(
                        block=intro_preview_block,
                        media_file=uploaded,
                        actor=request.user,
                        request=request,
                    )
                    messages.success(request, "تم تحديث تصميم بروفة التعريف بنجاح.")
                    return redirect("dashboard:content_intro")
            else:
                messages.error(request, "الملف المرفوع غير صالح.")

    context = _content_base_context("intro")
    context.update(
        {
            "hero_title": "محتوى صفحة بروفة التعريف بالتطبيق",
            "hero_subtitle": "رفع صورة أو فيديو شاشة البروفة التي تظهر بعد الشرائح الثلاث مباشرة وقبل صفحة تسجيل الدخول.",
            "upload_form": upload_form,
            "intro_preview_block": intro_preview_block,
            "can_manage": can_manage,
            "can_write": can_write,
            "design_specs": _content_media_specs(intro_preview_block.media_file),
        }
    )
    return render(request, "dashboard/content_intro.html", context)


@dashboard_staff_required
@require_dashboard_access("content")
def content_settings(request):
    can_write = dashboard_allowed(request.user, "content", write=True)
    manage_policy = ContentManagePolicy.evaluate(request.user)
    can_manage = bool(can_write and manage_policy.allowed)

    selected_doc_type = (request.GET.get("doc_type") or request.POST.get("doc_type") or LegalDocumentType.TERMS).strip()
    valid_doc_types = {choice for choice, _ in LegalDocumentType.choices}
    if selected_doc_type not in valid_doc_types:
        selected_doc_type = LegalDocumentType.TERMS

    current_doc = (
        SiteLegalDocument.objects.filter(doc_type=selected_doc_type, is_active=True)
        .order_by("-published_at", "-id")
        .first()
    )
    legal_form = ContentSettingsLegalForm(
        initial={
            "doc_type": selected_doc_type,
            "body_ar": (current_doc.body_ar if current_doc else ""),
            "version": (current_doc.version if current_doc else "1.0"),
            "published_at": timezone.localtime(current_doc.published_at).strftime("%Y-%m-%dT%H:%M")
            if current_doc and current_doc.published_at
            else "",
        }
    )

    links_obj = SiteLinks.load()
    about_block = _content_block_get_or_create(
        ContentBlockKey.ABOUT_SECTION_ABOUT,
        default_title="حول منصة مختص",
        default_body="نص تعريفي مختصر عن المنصة.",
    )
    links_form = ContentSettingsLinksForm(
        initial={
            "about_text": about_block.body_ar,
            "website_url": links_obj.website_url if links_obj else "",
            "ios_store": links_obj.ios_store if links_obj else "",
            "android_store": links_obj.android_store if links_obj else "",
            "x_url": links_obj.x_url if links_obj else "",
            "instagram_url": links_obj.instagram_url if links_obj else "",
            "snapchat_url": links_obj.snapchat_url if links_obj else "",
            "tiktok_url": links_obj.tiktok_url if links_obj else "",
            "youtube_url": links_obj.youtube_url if links_obj else "",
            "whatsapp_url": links_obj.whatsapp_url if links_obj else "",
            "email": links_obj.email if links_obj else "",
        }
    )

    if request.method == "POST":
        if not can_manage:
            return HttpResponseForbidden("لا تملك صلاحية تعديل إعدادات المحتوى.")
        action = (request.POST.get("action") or "").strip()

        if action == "save_legal":
            legal_form = ContentSettingsLegalForm(request.POST, request.FILES)
            if legal_form.is_valid():
                doc_type = legal_form.cleaned_data["doc_type"]
                body_ar = sanitize_multiline_text(legal_form.cleaned_data.get("body_ar") or "")
                version = legal_form.cleaned_data["version"]
                published_at = legal_form.cleaned_data.get("published_at") or timezone.now()
                if timezone.is_naive(published_at):
                    published_at = timezone.make_aware(published_at, timezone.get_current_timezone())

                new_doc = SiteLegalDocument(
                    doc_type=doc_type,
                    body_ar=body_ar,
                    version=version,
                    published_at=published_at,
                    is_active=True,
                    uploaded_by=request.user,
                )
                uploaded_file = legal_form.cleaned_data.get("file")
                if uploaded_file is not None:
                    new_doc.file = uploaded_file
                new_doc.save()

                SiteLegalDocument.objects.filter(doc_type=doc_type).exclude(id=new_doc.id).update(is_active=False)
                log_action(
                    actor=request.user,
                    action=AuditAction.CONTENT_DOCUMENT_UPLOADED,
                    reference_type="content.legal_document",
                    reference_id=str(new_doc.id),
                    request=request,
                    extra={"doc_type": doc_type, "version": version},
                )
                messages.success(request, "تم تحديث مستند الإعدادات بنجاح.")
                return redirect(f"{reverse('dashboard:content_settings')}?doc_type={doc_type}")
            messages.error(request, "يرجى مراجعة بيانات المستند القانوني.")

        elif action == "save_links":
            links_form = ContentSettingsLinksForm(request.POST)
            if links_form.is_valid():
                links = links_obj or SiteLinks.load()
                links.website_url = links_form.cleaned_data.get("website_url") or ""
                links.ios_store = links_form.cleaned_data.get("ios_store") or ""
                links.android_store = links_form.cleaned_data.get("android_store") or ""
                links.x_url = links_form.cleaned_data.get("x_url") or ""
                links.instagram_url = links_form.cleaned_data.get("instagram_url") or ""
                links.snapchat_url = links_form.cleaned_data.get("snapchat_url") or ""
                links.tiktok_url = links_form.cleaned_data.get("tiktok_url") or ""
                links.youtube_url = links_form.cleaned_data.get("youtube_url") or ""
                links.whatsapp_url = links_form.cleaned_data.get("whatsapp_url") or ""
                links.email = links_form.cleaned_data.get("email") or ""
                links.updated_by = request.user
                links.save()
                links_obj = links

                _save_content_block(
                    block=about_block,
                    body=links_form.cleaned_data.get("about_text") or "",
                    actor=request.user,
                    request=request,
                )
                log_action(
                    actor=request.user,
                    action=AuditAction.CONTENT_LINKS_UPDATED,
                    reference_type="content.site_links",
                    reference_id=str(links.id),
                    request=request,
                    extra={"fields": ["website_url", "ios_store", "android_store", "x_url", "instagram_url", "snapchat_url", "tiktok_url", "youtube_url", "whatsapp_url", "email"]},
                )
                messages.success(request, "تم تحديث بيانات صفحة الإعدادات وروابط المنصة.")
                return redirect(f"{reverse('dashboard:content_settings')}?doc_type={selected_doc_type}")
            messages.error(request, "تعذر حفظ بيانات الروابط. تحقق من الصيغة.")

    legal_docs_index = {
        doc_type: SiteLegalDocument.objects.filter(doc_type=doc_type, is_active=True).order_by("-published_at", "-id").first()
        for doc_type, _ in LegalDocumentType.choices
    }

    context = _content_base_context("settings")
    context.update(
        {
            "hero_title": "تحديث معلومات صفحة الإعدادات",
            "hero_subtitle": "إدارة مستندات الشروط والخصوصية وروابط المنصة الرسمية من شاشة واحدة.",
            "can_manage": can_manage,
            "can_write": can_write,
            "selected_doc_type": selected_doc_type,
            "legal_form": legal_form,
            "links_form": links_form,
            "legal_docs_index": legal_docs_index,
            "current_doc": current_doc,
            "about_block": about_block,
        }
    )
    return render(request, "dashboard/content_settings.html", context)


def _content_review_queryset_for_user(user):
    return _support_queryset_for_user(user).filter(
        _support_ticket_dashboard_q("content", fallback_team_codes=["content"])
        | Q(assigned_team__isnull=True, ticket_type__in=CONTENT_REVIEW_TYPES)
    ).distinct()


def _content_ticket_team_label(ticket: SupportTicket) -> str:
    if ticket.assigned_team:
        mapped = CONTENT_TEAM_LABELS.get((ticket.assigned_team.code or "").strip().lower())
        if mapped:
            return mapped
        return ticket.assigned_team.name_ar
    return SUPPORT_TICKET_TYPE_TO_TEAM_LABEL.get(ticket.ticket_type, CONTENT_TEAM_LABELS["content"])


def _content_ticket_target_info(ticket: SupportTicket | None) -> dict:
    if ticket is None:
        return {"kind": "", "object_id": "", "label": "لا يوجد هدف مرتبط", "url": "", "reported_user": ""}

    kind = (ticket.reported_kind or "").strip().lower()
    object_id = (ticket.reported_object_id or "").strip()
    reported_user = ""
    if ticket.reported_user_id:
        reported_label = (ticket.reported_user.username or ticket.reported_user.phone or f"user-{ticket.reported_user_id}").strip()
        reported_user = reported_label if reported_label.startswith("@") else f"@{reported_label}"

    model_map = {
        "review": ("reviews", "review", "التقييم"),
        "message": ("messaging", "message", "الرسالة"),
        "thread": ("messaging", "thread", "المحادثة"),
        "portfolio_item": ("providers", "providerportfolioitem", "محتوى المعرض"),
        "spotlight_item": ("providers", "providerspotlightitem", "محتوى الواجهة"),
        "service": ("providers", "providerservice", "الخدمة"),
    }
    app_label, model_name, label = model_map.get(kind, ("", "", ticket.code or "الطلب"))
    target_url = ""
    if app_label and model_name and object_id:
        try:
            target_url = reverse(f"admin:{app_label}_{model_name}_change", args=[object_id])
        except Exception:
            target_url = ""

    return {
        "kind": kind,
        "object_id": object_id,
        "label": label,
        "url": target_url,
        "reported_user": reported_user,
    }


def _content_review_detail_payload(ticket: SupportTicket | None) -> dict:
    if ticket is None:
        return {
            "reporter_account": "-",
            "reported_account": "-",
            "complaint_subject": "-",
            "complaint_details": "-",
            "review_id": None,
            "request_id": None,
            "review_rating": None,
            "review_comment": "",
            "review_created_at": "-",
            "review_client": "-",
            "review_provider": "-",
            "review_provider_reply": "",
            "review_management_reply": "",
        }

    requester = ticket.requester
    requester_name = (
        getattr(requester, "username", "")
        or getattr(requester, "phone", "")
        or f"user-{getattr(requester, 'id', '-') }"
    )
    reporter_account = requester_name if str(requester_name).startswith("@") else f"@{requester_name}"

    target_info = _content_ticket_target_info(ticket)
    payload = {
        "reporter_account": reporter_account,
        "reported_account": target_info.get("reported_user") or "-",
        "complaint_subject": target_info.get("label") or "التقييم",
        "complaint_details": (ticket.description or "").strip() or "-",
        "review_id": None,
        "request_id": None,
        "review_rating": None,
        "review_comment": "",
        "review_created_at": "-",
        "review_client": "-",
        "review_provider": "-",
        "review_provider_reply": "",
        "review_management_reply": "",
    }

    review = _content_find_review_for_ticket(ticket)
    if review is None:
        return payload

    client_label = (
        getattr(review.client, "username", "")
        or getattr(review.client, "phone", "")
        or f"user-{review.client_id}"
    )
    provider_user = getattr(getattr(review.provider, "user", None), "username", "") or getattr(
        getattr(review.provider, "user", None), "phone", ""
    )
    provider_label = (
        getattr(review.provider, "display_name", "")
        or provider_user
        or f"provider-{review.provider_id}"
    )

    payload.update(
        {
            "review_id": review.id,
            "request_id": review.request_id,
            "review_rating": int(review.rating or 0),
            "review_comment": (review.comment or "").strip(),
            "review_created_at": _format_dt(review.created_at),
            "review_client": client_label if str(client_label).startswith("@") else f"@{client_label}",
            "review_provider": provider_label,
            "review_provider_reply": (review.provider_reply or "").strip(),
            "review_management_reply": (review.management_reply or "").strip(),
        }
    )
    return payload


def _content_review_ticket_rows(tickets: list[SupportTicket]) -> list[dict]:
    subscriptions_by_user_id = _effective_subscriptions_map_for_users(
        [getattr(ticket, "requester", None) for ticket in tickets]
    )
    rows = []
    for ticket in tickets:
        priority_number = _dashboard_priority_number_for_user(
            ticket.requester,
            subscriptions_by_user_id=subscriptions_by_user_id,
        )
        rows.append(
            {
                "id": ticket.id,
                "code": ticket.code or f"HD{ticket.id:04d}",
                "requester": _support_requester_label(ticket),
                "priority_number": priority_number,
                "priority_class": _dashboard_priority_class_for_user(
                    ticket.requester,
                    subscriptions_by_user_id=subscriptions_by_user_id,
                ),
                "ticket_type": ticket.get_ticket_type_display(),
                "created_at": _format_dt(ticket.created_at),
                "status": ticket.get_status_display(),
                "status_code": ticket.status,
                "team": _content_ticket_team_label(ticket),
                "assignee": _support_assignee_label(ticket),
                "assigned_at": _format_dt(ticket.assigned_at),
            }
        )
    return rows


def _content_review_summary(tickets: list[SupportTicket]) -> dict:
    by_status: dict[str, int] = {}
    complaints = 0
    suggestions = 0
    for ticket in tickets:
        by_status[ticket.status] = by_status.get(ticket.status, 0) + 1
        if ticket.ticket_type == SupportTicketType.COMPLAINT:
            complaints += 1
        if ticket.ticket_type == SupportTicketType.SUGGEST:
            suggestions += 1
    return {
        "total": len(tickets),
        "complaints": complaints,
        "suggestions": suggestions,
        "new": by_status.get(SupportTicketStatus.NEW, 0),
        "in_progress": by_status.get(SupportTicketStatus.IN_PROGRESS, 0),
        "returned": by_status.get(SupportTicketStatus.RETURNED, 0),
        "closed": by_status.get(SupportTicketStatus.CLOSED, 0),
    }


def _content_review_export_rows(tickets: list[SupportTicket]) -> tuple[list[str], list[list]]:
    headers = [
        "رقم الطلب",
        "اسم العميل",
        "الأولوية",
        "نوع الطلب",
        "تاريخ ووقت استلام الطلب",
        "حالة الطلب",
        "فريق الدعم",
        "المكلف بالطلب",
        "تاريخ ووقت التكليف",
    ]
    rows: list[list] = []
    for row in _content_review_ticket_rows(tickets):
        rows.append(
            [
                row["code"],
                row["requester"],
                row["priority_number"],
                row["ticket_type"],
                row["created_at"],
                row["status"],
                row["team"],
                row["assignee"],
                row["assigned_at"],
            ]
        )
    return headers, rows


def _content_find_review_for_ticket(ticket: SupportTicket):
    if (ticket.reported_kind or "").strip().lower() != "review":
        return None
    object_id = (ticket.reported_object_id or "").strip()
    if not object_id.isdigit():
        return None
    return Review.objects.select_related("provider", "provider__user", "client").filter(id=int(object_id)).first()


def _content_apply_review_moderation(
    *,
    ticket: SupportTicket,
    action: str,
    management_reply: str,
    note: str,
    request,
) -> str:
    review = _content_find_review_for_ticket(ticket)
    if review is None:
        raise ValueError("التقييم المرتبط بالطلب غير موجود.")

    status_map = {
        ContentReviewActionForm.MODERATION_ACTION_APPROVE_REVIEW: ReviewModerationStatus.APPROVED,
        ContentReviewActionForm.MODERATION_ACTION_HIDE_REVIEW: ReviewModerationStatus.HIDDEN,
        ContentReviewActionForm.MODERATION_ACTION_REJECT_REVIEW: ReviewModerationStatus.REJECTED,
    }
    action_name_map = {
        ContentReviewActionForm.MODERATION_ACTION_APPROVE_REVIEW: "approve",
        ContentReviewActionForm.MODERATION_ACTION_HIDE_REVIEW: "hide",
        ContentReviewActionForm.MODERATION_ACTION_REJECT_REVIEW: "reject",
    }
    desired_status = status_map.get(action)
    action_name = action_name_map.get(action, "hide")
    update_fields = []

    if desired_status and review.moderation_status != desired_status:
        review.moderation_status = desired_status
        update_fields.append("moderation_status")
    moderation_note = (note or "").strip()[:500]
    if review.moderation_note != moderation_note:
        review.moderation_note = moderation_note
        update_fields.append("moderation_note")
    review.moderated_by = request.user
    review.moderated_at = timezone.now()
    update_fields.extend(["moderated_by", "moderated_at"])

    if management_reply:
        trimmed_reply = management_reply.strip()[:500]
        review.management_reply = trimmed_reply
        review.management_reply_by = request.user
        review.management_reply_at = timezone.now()
        update_fields.extend(["management_reply", "management_reply_by", "management_reply_at"])

    review.save(update_fields=list(dict.fromkeys(update_fields)))
    sync_review_to_unified(review=review, changed_by=request.user)
    sync_review_case(review=review, action_name=action_name, note=moderation_note, by_user=request.user, request=request)
    log_action(
        actor=request.user,
        action=AuditAction.REVIEW_MODERATED,
        reference_type="reviews.review",
        reference_id=str(review.id),
        request=request,
        extra={"ticket_id": ticket.id, "action": action_name, "status": review.moderation_status},
    )
    if management_reply:
        log_action(
            actor=request.user,
            action=AuditAction.REVIEW_RESPONSE_ADDED,
            reference_type="reviews.review",
            reference_id=str(review.id),
            request=request,
            extra={"ticket_id": ticket.id},
        )
    return f"تم تطبيق إجراء التقييم ({review.get_moderation_status_display()}) بنجاح."


def _content_delete_reported_target(*, ticket: SupportTicket, request, note: str) -> str:
    kind = (ticket.reported_kind or "").strip().lower()
    object_id = (ticket.reported_object_id or "").strip()

    if kind == "review":
        message = _content_apply_review_moderation(
            ticket=ticket,
            action=ContentReviewActionForm.MODERATION_ACTION_HIDE_REVIEW,
            management_reply="",
            note=note or "delete_target_review_hidden",
            request=request,
        )
        record_support_target_delete_case(ticket=ticket, by_user=request.user, request=request, note=note or "review_hidden")
        return message

    if not object_id.isdigit():
        raise ValueError("لا يمكن حذف الهدف المرتبط لعدم توفر معرف صالح.")

    object_pk = int(object_id)
    if kind == "portfolio_item":
        item = ProviderPortfolioItem.objects.select_related("provider", "provider__user").filter(id=object_pk).first()
        if item is None:
            raise ValueError("عنصر المعرض غير موجود.")
        record_content_action_case(
            item=item,
            content_kind="portfolio_item",
            action_name="delete",
            by_user=request.user,
            request=request,
            note=note or "content_dashboard_delete",
        )
        item.delete()
    elif kind == "spotlight_item":
        item = ProviderSpotlightItem.objects.select_related("provider", "provider__user").filter(id=object_pk).first()
        if item is None:
            raise ValueError("عنصر الواجهة غير موجود.")
        record_content_action_case(
            item=item,
            content_kind="spotlight_item",
            action_name="delete",
            by_user=request.user,
            request=request,
            note=note or "content_dashboard_delete",
        )
        item.delete()
    elif kind == "service":
        service = ProviderService.objects.select_related("provider", "provider__user").filter(id=object_pk).first()
        if service is None:
            raise ValueError("الخدمة المستهدفة غير موجودة.")
        if service.is_active:
            service.is_active = False
            service.save(update_fields=["is_active"])
        record_content_action_case(
            item=service,
            content_kind="service",
            action_name="hide",
            by_user=request.user,
            request=request,
            note=note or "service_deactivated",
        )
    elif kind == "message":
        message_obj = Message.objects.filter(id=object_pk).first()
        if message_obj is None:
            raise ValueError("الرسالة المستهدفة غير موجودة.")
        message_obj.delete()
    elif kind == "thread":
        thread_obj = Thread.objects.filter(id=object_pk).first()
        if thread_obj is None:
            raise ValueError("المحادثة المستهدفة غير موجودة.")
        thread_obj.delete()
    else:
        raise ValueError("نوع المحتوى المرتبط بالشكوى غير مدعوم للحذف من هذه الشاشة.")

    record_support_target_delete_case(ticket=ticket, by_user=request.user, request=request, note=note or "delete_target")
    log_action(
        actor=request.user,
        action=AuditAction.FIELD_CHANGED,
        reference_type="support.ticket",
        reference_id=str(ticket.id),
        request=request,
        extra={"operation": "delete_target", "reported_kind": kind, "reported_object_id": object_id},
    )
    return "تم تنفيذ إجراء حذف/إخفاء المحتوى محل الشكوى."


def _content_reviews_redirect_with_state(request, ticket_id: int | None = None):
    query = (request.POST.get("redirect_query") or request.GET.urlencode()).strip()
    if ticket_id is not None:
        base = reverse("dashboard:content_reviews_ticket_detail", args=[ticket_id])
    else:
        base = reverse("dashboard:content_reviews_dashboard")
    if not query:
        return redirect(base)
    return redirect(f"{base}?{query}")


@dashboard_staff_required
@require_dashboard_access("content")
def content_reviews_dashboard(request, ticket_id: int | None = None):
    base_qs = _content_review_queryset_for_user(request.user)
    status_filter = (request.GET.get("status") or "").strip()
    type_filter = (request.GET.get("type") or "").strip()
    priority_filter = (request.GET.get("priority") or "").strip()
    query_filter = (request.GET.get("q") or "").strip()

    tickets_qs = base_qs
    if status_filter:
        tickets_qs = tickets_qs.filter(status=status_filter)
    if type_filter:
        tickets_qs = tickets_qs.filter(ticket_type=type_filter)
    if priority_filter in {"1", "2", "3"}:
        reverse_map = {"1": SupportPriority.LOW, "2": SupportPriority.NORMAL, "3": SupportPriority.HIGH}
        tickets_qs = tickets_qs.filter(priority=reverse_map[priority_filter])
    if query_filter:
        tickets_qs = tickets_qs.filter(
            Q(code__icontains=query_filter)
            | Q(description__icontains=query_filter)
            | Q(requester__username__icontains=query_filter)
            | Q(requester__phone__icontains=query_filter)
        )

    tickets = list(tickets_qs)
    selected_ticket = _resolve_selected_ticket(base_qs, request, ticket_id)
    if selected_ticket is None and tickets:
        selected_ticket = tickets[0]

    team_choices = _support_team_choices()
    assignee_choices_by_team = _support_assignee_choices_by_team()
    assignee_map: dict[str, str] = {}
    for choices in assignee_choices_by_team.values():
        for value, label in choices:
            assignee_map[str(value)] = label
    assignee_choices = sorted(assignee_map.items(), key=lambda item: item[1].lower())

    can_write = dashboard_allowed(request.user, "content", write=True)
    can_manage_content = bool(can_write and ContentManagePolicy.evaluate(request.user).allowed)
    can_moderate_reviews = bool(can_write and ReviewModerationPolicy.evaluate(request.user).allowed)
    can_hide_delete = bool(can_write and ContentHideDeletePolicy.evaluate(request.user).allowed)

    review_form = ContentReviewActionForm(
        assignee_choices=assignee_choices,
        team_choices=team_choices,
        initial={
            "status": selected_ticket.status if selected_ticket else SupportTicketStatus.NEW,
            "assigned_team": str(selected_ticket.assigned_team_id or "") if selected_ticket else "",
            "assigned_to": str(selected_ticket.assigned_to_id or "") if selected_ticket else "",
            "description": selected_ticket.description if selected_ticket else "",
            "moderation_action": ContentReviewActionForm.MODERATION_ACTION_NONE,
        },
    )

    if request.method == "POST":
        if not can_manage_content:
            return HttpResponseForbidden("لا تملك صلاحية تعديل طلبات إدارة المحتوى.")

        raw_ticket_id = (request.POST.get("ticket_id") or "").strip()
        if not raw_ticket_id.isdigit():
            messages.error(request, "لا يمكن تحديد الطلب المطلوب تحديثه.")
            return _content_reviews_redirect_with_state(request)

        target_ticket = base_qs.filter(id=int(raw_ticket_id)).first()
        if target_ticket is None:
            messages.error(request, "الطلب المحدد غير متاح لهذا الحساب.")
            return _content_reviews_redirect_with_state(request)

        access_profile = active_access_profile_for_user(request.user)
        if access_profile and access_profile.level == AccessLevel.USER:
            if target_ticket.assigned_to_id and target_ticket.assigned_to_id != request.user.id:
                return HttpResponseForbidden("غير مصرح: الطلب ليس ضمن المهام المكلف بها.")

        post_form = ContentReviewActionForm(
            request.POST,
            request.FILES,
            assignee_choices=assignee_choices,
            team_choices=team_choices,
        )
        if not post_form.is_valid():
            review_form = post_form
            selected_ticket = target_ticket
            messages.error(request, "يرجى تصحيح أخطاء نموذج المعالجة.")
        else:
            action = (request.POST.get("action") or "save_ticket").strip()
            desired_status = post_form.cleaned_data.get("status")
            team_id_raw = (post_form.cleaned_data.get("assigned_team") or "").strip()
            assigned_to_raw = (post_form.cleaned_data.get("assigned_to") or "").strip()
            note = post_form.cleaned_data.get("assignee_comment") or ""
            new_description = post_form.cleaned_data.get("description") or target_ticket.description or ""
            management_reply = post_form.cleaned_data.get("management_reply") or ""
            moderation_action = (
                post_form.cleaned_data.get("moderation_action") or ContentReviewActionForm.MODERATION_ACTION_NONE
            ).strip()
            attachment = post_form.cleaned_data.get("attachment")

            if action == "close_ticket":
                desired_status = SupportTicketStatus.CLOSED
                has_reported_target = bool(
                    (target_ticket.reported_kind or "").strip() and (target_ticket.reported_object_id or "").strip()
                )
                if target_ticket.ticket_type == SupportTicketType.COMPLAINT and has_reported_target:
                    moderation_action = ContentReviewActionForm.MODERATION_ACTION_DELETE_TARGET
                else:
                    moderation_action = ContentReviewActionForm.MODERATION_ACTION_NONE
            elif action == "return_ticket":
                desired_status = SupportTicketStatus.RETURNED

            team_id = int(team_id_raw) if team_id_raw.isdigit() else target_ticket.assigned_team_id
            assigned_to_id = int(assigned_to_raw) if assigned_to_raw.isdigit() else target_ticket.assigned_to_id

            if team_id is not None and assigned_to_id is not None:
                allowed_assignees = {
                    int(value)
                    for value, _ in assignee_choices_by_team.get(str(team_id), [])
                    if str(value).isdigit()
                }
                if assigned_to_id not in allowed_assignees:
                    messages.error(request, "المكلف المختار غير مرتبط بفريق الدعم المحدد.")
                    return _content_reviews_redirect_with_state(request, ticket_id=target_ticket.id)

            if assigned_to_id is not None:
                assignee_dashboard_code = _support_team_dashboard_code(team_id) if team_id is not None else "content"
                assignee = dashboard_assignee_user(assigned_to_id, assignee_dashboard_code, write=True)
                if assignee is None:
                    messages.error(request, "المكلف المختار لا يملك صلاحية لوحة الفريق المحدد.")
                    return _content_reviews_redirect_with_state(request, ticket_id=target_ticket.id)
                if access_profile and access_profile.level == AccessLevel.USER and assignee.id != request.user.id:
                    return HttpResponseForbidden("لا يمكنك تعيين الطلب لمستخدم آخر.")

            if team_id is not None and not SupportTeam.objects.filter(id=team_id).exists():
                messages.error(request, "فريق الدعم المحدد غير صالح.")
                return _content_reviews_redirect_with_state(request, ticket_id=target_ticket.id)

            target_ticket = assign_ticket(
                ticket=target_ticket,
                team_id=team_id,
                user_id=assigned_to_id,
                by_user=request.user,
                note=note,
            )

            if new_description != (target_ticket.description or ""):
                target_ticket.description = new_description
                target_ticket.last_action_by = request.user
                target_ticket.save(update_fields=["description", "last_action_by", "updated_at"])

            if desired_status and desired_status != target_ticket.status:
                try:
                    target_ticket = change_ticket_status(
                        ticket=target_ticket,
                        new_status=desired_status,
                        by_user=request.user,
                        note=note,
                    )
                except ValueError as exc:
                    messages.error(request, str(exc))
                    return _content_reviews_redirect_with_state(request, ticket_id=target_ticket.id)

            if note:
                SupportComment.objects.create(
                    ticket=target_ticket,
                    text=note[:300],
                    is_internal=True,
                    created_by=request.user,
                )

            if attachment is not None:
                try:
                    attachment = _validate_and_optimize_dashboard_attachment(attachment, user=request.user)
                except DjangoValidationError as exc:
                    messages.error(request, str(exc))
                    return _content_reviews_redirect_with_state(request, ticket_id=target_ticket.id)
                SupportAttachment.objects.create(
                    ticket=target_ticket,
                    file=attachment,
                    uploaded_by=request.user,
                )

            try:
                if moderation_action in {
                    ContentReviewActionForm.MODERATION_ACTION_APPROVE_REVIEW,
                    ContentReviewActionForm.MODERATION_ACTION_HIDE_REVIEW,
                    ContentReviewActionForm.MODERATION_ACTION_REJECT_REVIEW,
                }:
                    if not can_moderate_reviews:
                        return HttpResponseForbidden("لا تملك صلاحية الإشراف على التقييمات.")
                    moderation_message = _content_apply_review_moderation(
                        ticket=target_ticket,
                        action=moderation_action,
                        management_reply=management_reply,
                        note=note,
                        request=request,
                    )
                    messages.success(request, moderation_message)
                elif moderation_action == ContentReviewActionForm.MODERATION_ACTION_DELETE_TARGET:
                    if not can_hide_delete:
                        return HttpResponseForbidden("لا تملك صلاحية حذف المحتوى محل الشكوى.")
                    delete_message = _content_delete_reported_target(ticket=target_ticket, request=request, note=note)
                    messages.success(request, delete_message)
                elif management_reply:
                    if not can_moderate_reviews:
                        return HttpResponseForbidden("لا تملك صلاحية إضافة رد الإدارة.")
                    review_obj = _content_find_review_for_ticket(target_ticket)
                    if review_obj is None:
                        messages.error(request, "لا يوجد تقييم مرتبط لإضافة رد الإدارة.")
                        return _content_reviews_redirect_with_state(request, ticket_id=target_ticket.id)
                    review_obj.management_reply = management_reply[:500]
                    review_obj.management_reply_by = request.user
                    review_obj.management_reply_at = timezone.now()
                    review_obj.save(update_fields=["management_reply", "management_reply_by", "management_reply_at"])
                    log_action(
                        actor=request.user,
                        action=AuditAction.REVIEW_RESPONSE_ADDED,
                        reference_type="reviews.review",
                        reference_id=str(review_obj.id),
                        request=request,
                        extra={"ticket_id": target_ticket.id},
                    )
                    messages.success(request, "تم حفظ رد الإدارة على التقييم.")
            except ValueError as exc:
                messages.error(request, str(exc))
                return _content_reviews_redirect_with_state(request, ticket_id=target_ticket.id)

            messages.success(request, f"تم تحديث الطلب {target_ticket.code or target_ticket.id} بنجاح.")
            return _content_reviews_redirect_with_state(request, ticket_id=target_ticket.id)

    headers, rows = _content_review_export_rows(tickets)
    if _want_csv(request):
        return _csv_response("content_reviews.csv", headers, rows)
    if _want_xlsx(request):
        return xlsx_response("content_reviews.xlsx", "content_reviews", headers, rows)
    if _want_pdf(request):
        return pdf_response("content_reviews.pdf", "لوحة إدارة التقييم والمراجعات", headers, rows, landscape=True)

    context = _content_base_context("reviews")
    context.update(
        {
            "hero_title": "إدارة استفسارات وبلاغات المحتوى",
            "hero_subtitle": "متابعة الاستفسارات القادمة من تواصل مع نوافذ والبلاغات المحوّلة إلى فريق المحتوى ومعالجتها تشغيليًا.",
            "tickets": _content_review_ticket_rows(tickets),
            "selected_ticket": selected_ticket,
            "review_form": review_form,
            "summary": _content_review_summary(tickets),
            "can_write": can_write,
            "can_manage_content": can_manage_content,
            "can_moderate_reviews": can_moderate_reviews,
            "can_hide_delete": can_hide_delete,
            "status_choices": SupportTicketStatus.choices,
            "ticket_type_choices": [
                (SupportTicketType.SUGGEST, dict(SupportTicketType.choices).get(SupportTicketType.SUGGEST)),
                (SupportTicketType.COMPLAINT, dict(SupportTicketType.choices).get(SupportTicketType.COMPLAINT)),
            ],
            "priority_choices": [("1", "1 - الأساسية"), ("2", "2 - الريادية"), ("3", "3 - الاحترافية")],
            "filters": {
                "status": status_filter,
                "type": type_filter,
                "priority": priority_filter,
                "q": query_filter,
            },
            "redirect_query": request.GET.urlencode(),
            "target_info": _content_ticket_target_info(selected_ticket),
            "detail_info": _content_review_detail_payload(selected_ticket),
            "selected_ticket_comments": list(selected_ticket.comments.order_by("-id")[:8]) if selected_ticket else [],
            "selected_ticket_attachments": _support_attachment_rows(selected_ticket) if selected_ticket else [],
            "team_assignee_map": assignee_choices_by_team,
        }
    )
    return render(request, "dashboard/content_reviews_dashboard.html", context)


def _content_excellence_rows(candidates: list[ExcellenceBadgeCandidate]) -> list[dict]:
    rows: list[dict] = []
    for candidate in candidates:
        provider = candidate.provider
        rows.append(
            {
                "candidate_id": candidate.id,
                "provider_name": provider.display_name or f"provider-{provider.id}",
                "provider_phone": getattr(getattr(provider, "user", None), "phone", "") or "-",
                "badge_code": candidate.badge_type.code,
                "badge_name": candidate.badge_type.name_ar,
                "rank_position": int(candidate.rank_position or 0),
                "followers_count": int(candidate.followers_count or 0),
                "completed_orders_count": int(candidate.completed_orders_count or 0),
                "rating_avg": float(candidate.rating_avg or 0),
                "rating_count": int(candidate.rating_count or 0),
                "category_name": getattr(candidate.category, "name", "—") or "—",
                "subcategory_name": getattr(candidate.subcategory, "name", "—") or "—",
                "status": candidate.get_status_display(),
                "cycle_end": candidate.evaluation_period_end.date().isoformat(),
            }
        )
    return rows


def _content_excellence_export_rows(rows: list[dict]) -> tuple[list[str], list[list]]:
    headers = [
        "اسم المختص",
        "رقم الجوال",
        "الشارة",
        "الترتيب",
        "عدد المتابعين",
        "عدد الطلبات المغلقة منذ سنة",
        "متوسط التقييم",
        "عدد التقييمات",
        "التصنيف الرئيسي",
        "التصنيف الفرعي",
        "الحالة",
        "نهاية الدورة",
    ]
    payload: list[list] = []
    for row in rows:
        payload.append(
            [
                row["provider_name"],
                row["provider_phone"],
                row["badge_name"],
                row["rank_position"],
                row["followers_count"],
                row["completed_orders_count"],
                row["rating_avg"],
                row["rating_count"],
                row["category_name"],
                row["subcategory_name"],
                row["status"],
                row["cycle_end"],
            ]
        )
    return headers, payload


def _content_excellence_payload(*, badge_filter: str = "", q: str = "") -> dict[str, object]:
    sync_badge_type_catalog()

    cycle_start, cycle_end = excellence_current_review_window()
    base_qs = ExcellenceBadgeCandidate.objects.select_related(
        "badge_type",
        "provider",
        "provider__user",
        "category",
        "subcategory",
    ).filter(
        badge_type__code__in=CONTENT_EXCELLENCE_BADGE_CODES,
        evaluation_period_start=cycle_start,
        evaluation_period_end=cycle_end,
    )

    if not base_qs.exists():
        latest_cycle_end = (
            ExcellenceBadgeCandidate.objects.filter(badge_type__code__in=CONTENT_EXCELLENCE_BADGE_CODES)
            .order_by("-evaluation_period_end")
            .values_list("evaluation_period_end", flat=True)
            .first()
        )
        if latest_cycle_end:
            base_qs = ExcellenceBadgeCandidate.objects.select_related(
                "badge_type",
                "provider",
                "provider__user",
                "category",
                "subcategory",
            ).filter(
                badge_type__code__in=CONTENT_EXCELLENCE_BADGE_CODES,
                evaluation_period_end=latest_cycle_end,
            )
            cycle_end = latest_cycle_end

    if q:
        base_qs = base_qs.filter(
            Q(provider__display_name__icontains=q)
            | Q(provider__user__phone__icontains=q)
            | Q(category__name__icontains=q)
            | Q(subcategory__name__icontains=q)
        )

    filtered_qs = base_qs
    if badge_filter:
        filtered_qs = filtered_qs.filter(badge_type__code=badge_filter)

    rows = _content_excellence_rows(list(filtered_qs.order_by("badge_type__sort_order", "rank_position", "provider_id")))

    badge_types = list(
        ExcellenceBadgeType.objects.filter(code__in=CONTENT_EXCELLENCE_BADGE_CODES, is_active=True).order_by("sort_order", "id")
    )
    badge_type_map = {badge.code: badge for badge in badge_types}

    badge_counts_qs = (
        base_qs.values("badge_type__code")
        .annotate(total=Count("id"))
        .order_by()
    )
    counts_by_badge: dict[str, int] = {
        str(row.get("badge_type__code") or ""): int(row.get("total") or 0)
        for row in badge_counts_qs
    }

    badge_tabs: list[dict[str, object]] = []
    for code in CONTENT_EXCELLENCE_BADGE_TAB_ORDER:
        badge = badge_type_map.get(code)
        if not badge:
            continue
        badge_tabs.append(
            {
                "code": badge.code,
                "name": badge.name_ar,
                "description": badge.description,
                "count": counts_by_badge.get(badge.code, 0),
            }
        )

    return {
        "cycle_end": cycle_end,
        "rows": rows,
        "badge_tabs": badge_tabs,
        "total_rows": len(rows),
    }


@dashboard_staff_required
@require_dashboard_access("content")
def content_excellence(request):
    badge_filter = (request.GET.get("badge") or "").strip()
    q = (request.GET.get("q") or "").strip()
    payload = _content_excellence_payload(badge_filter=badge_filter, q=q)
    rows = payload["rows"]

    headers, export_rows = _content_excellence_export_rows(rows)
    if _want_csv(request):
        return _csv_response("content_excellence.csv", headers, export_rows)
    if _want_xlsx(request):
        return xlsx_response("content_excellence.xlsx", "content_excellence", headers, export_rows)
    if _want_pdf(request):
        return pdf_response("content_excellence.pdf", "لوحة إدارة التميز", headers, export_rows, landscape=True)

    context = _content_base_context("excellence")
    context.update(
        {
            "hero_title": "إدارة التميز",
            "hero_subtitle": "قائمة من تنطبق عليه معايير التميز مع عرض فوري حسب نوع الشارة.",
            "rows": rows,
            "badge_tabs": payload["badge_tabs"],
            "badge_filter": badge_filter,
            "q": q,
            "cycle_end": payload["cycle_end"],
            "total_rows": payload["total_rows"],
        }
    )
    return render(request, "dashboard/content_excellence.html", context)


@dashboard_staff_required
@require_dashboard_access("content")
def content_excellence_api(request):
    badge_filter = (request.GET.get("badge") or "").strip()
    q = (request.GET.get("q") or "").strip()

    payload = _content_excellence_payload(badge_filter=badge_filter, q=q)
    cycle_end = payload["cycle_end"]
    cycle_end_str = cycle_end.date().isoformat() if hasattr(cycle_end, "date") else str(cycle_end)

    return JsonResponse(
        {
            "ok": True,
            "filters": {"badge": badge_filter, "q": q},
            "cycle_end": cycle_end_str,
            "total_rows": payload["total_rows"],
            "badge_tabs": payload["badge_tabs"],
            "rows": payload["rows"],
        },
        json_dumps_params={"ensure_ascii": False},
    )


@require_POST
def resend_otp_view(request):
    user_id = request.session.get(SESSION_LOGIN_USER_ID_KEY)
    user = get_user_model().objects.filter(id=user_id, is_active=True).first() if user_id else None
    if user is None:
        messages.error(request, "انتهت جلسة الدخول.")
        return redirect("dashboard:login")

    remaining = _otp_resend_remaining_seconds(user.id)
    if remaining > 0:
        messages.warning(request, f"يرجى الانتظار {remaining} ثانية قبل إعادة إرسال رمز جديد.")
        return redirect("dashboard:otp")

    if accept_any_otp_code():
        messages.info(request, "وضع الاختبار مفعّل: يمكنك إدخال أي رمز من 4 أرقام.")
    else:
        create_otp(user.phone or "", request)
        messages.success(request, "تم إرسال رمز تحقق جديد.")
    _activate_otp_resend_cooldown(user.id)
    return redirect("dashboard:otp")


# ---------------------------------------------------------------------------
# المالية – Finance Dashboard
# ---------------------------------------------------------------------------

_FINANCE_REFERENCE_TYPE_LABELS = {
    "subscription": "اشتراك",
    "verify_request": "توثيق",
    "promo_request": "ترويج",
    "extra_purchase": "خدمات إضافية",
    "extras_bundle_request": "حزمة إضافية",
}

_FINANCE_STATUS_LABELS = dict(InvoiceStatus.choices)


def _finance_reference_label(ref_type: str) -> str:
    return _FINANCE_REFERENCE_TYPE_LABELS.get(ref_type, ref_type or "غير مصنف")


@dashboard_staff_required
@require_dashboard_access("admin_control")
def finance_dashboard(request):
    """صفحة المالية – عرض جميع الفواتير مع فلترة وتصدير."""
    if not request.user.is_superuser:
        return HttpResponseForbidden("غير مصرح للوصول.")

    # ── Filters ──
    status_filter = (request.GET.get("status") or "").strip()
    ref_type_filter = (request.GET.get("ref_type") or "").strip()
    q_filter = (request.GET.get("q") or "").strip()
    start_date, end_date = _date_range_from_request(request)
    start_dt, end_dt = _to_aware_window(start_date, end_date)

    qs = (
        Invoice.objects
        .select_related("user", "created_by")
        .filter(created_at__range=(start_dt, end_dt))
        .order_by("-created_at")
    )

    if status_filter and status_filter in InvoiceStatus.values:
        qs = qs.filter(status=status_filter)
    if ref_type_filter:
        qs = qs.filter(reference_type=ref_type_filter)
    if q_filter:
        qs = qs.filter(
            Q(code__icontains=q_filter)
            | Q(title__icontains=q_filter)
            | Q(user__username__icontains=q_filter)
            | Q(user__phone__icontains=q_filter)
            | Q(reference_id__icontains=q_filter)
        )

    # ── Stats ──
    all_period_qs = Invoice.objects.filter(created_at__range=(start_dt, end_dt))
    stats = {
        "total": all_period_qs.count(),
        "paid": all_period_qs.filter(status=InvoiceStatus.PAID).count(),
        "pending": all_period_qs.filter(status=InvoiceStatus.PENDING).count(),
        "draft": all_period_qs.filter(status=InvoiceStatus.DRAFT).count(),
        "cancelled": all_period_qs.filter(status=InvoiceStatus.CANCELLED).count(),
        "failed": all_period_qs.filter(status=InvoiceStatus.FAILED).count(),
        "refunded": all_period_qs.filter(status=InvoiceStatus.REFUNDED).count(),
    }
    revenue = all_period_qs.filter(status=InvoiceStatus.PAID).aggregate(
        revenue=Sum("total"), vat_collected=Sum("vat_amount"),
    )
    stats["revenue"] = float(revenue["revenue"] or 0)
    stats["vat_collected"] = float(revenue["vat_collected"] or 0)

    # ── By-type breakdown ──
    by_type_rows = (
        all_period_qs
        .filter(status=InvoiceStatus.PAID)
        .values("reference_type")
        .annotate(count=Count("id"), amount=Sum("total"))
        .order_by("-amount")
    )
    by_type = [
        {
            "label": _finance_reference_label(r["reference_type"]),
            "count": r["count"],
            "amount": float(r["amount"] or 0),
        }
        for r in by_type_rows
    ]

    invoices = list(qs[:500])

    # ── CSV Export ──
    if _want_csv(request):
        headers = [
            "رقم الفاتورة", "العميل", "نوع الخدمة", "المبلغ الفرعي",
            "الضريبة", "الإجمالي", "الحالة", "تاريخ الإنشاء", "تاريخ الدفع", "المنشئ",
        ]
        rows = []
        for inv in invoices:
            rows.append([
                inv.code,
                getattr(inv.user, "username", "") or getattr(inv.user, "phone", ""),
                _finance_reference_label(inv.reference_type),
                str(inv.subtotal),
                str(inv.vat_amount),
                str(inv.total),
                _FINANCE_STATUS_LABELS.get(inv.status, inv.status),
                inv.created_at.strftime("%Y-%m-%d %H:%M") if inv.created_at else "",
                inv.paid_at.strftime("%Y-%m-%d %H:%M") if inv.paid_at else "",
                getattr(inv.created_by, "username", "") if inv.created_by else "تلقائي",
            ])
        return _csv_response("finance_invoices.csv", headers, rows)

    # ── Invoice detail ──
    selected_invoice = None
    selected_lines = []
    selected_attempts = []
    detail_id = (request.GET.get("invoice") or "").strip()
    if detail_id and detail_id.isdigit():
        selected_invoice = Invoice.objects.select_related("user", "created_by").filter(pk=int(detail_id)).first()
        if selected_invoice:
            selected_lines = list(selected_invoice.lines.order_by("sort_order"))
            selected_attempts = list(
                PaymentAttempt.objects.filter(invoice=selected_invoice).order_by("-created_at")[:20]
            )

    # ── Template rows ──
    invoice_rows = []
    for inv in invoices:
        invoice_rows.append({
            "id": inv.id,
            "code": inv.code,
            "user_display": getattr(inv.user, "username", "") or getattr(inv.user, "phone", ""),
            "reference_type": inv.reference_type,
            "reference_label": _finance_reference_label(inv.reference_type),
            "reference_id": inv.reference_id,
            "subtotal": inv.subtotal,
            "vat_amount": inv.vat_amount,
            "total": inv.total,
            "status": inv.status,
            "status_label": _FINANCE_STATUS_LABELS.get(inv.status, inv.status),
            "created_at": inv.created_at,
            "paid_at": inv.paid_at,
            "created_by_display": getattr(inv.created_by, "username", "") if inv.created_by else "",
        })

    filters = {
        "status": status_filter,
        "ref_type": ref_type_filter,
        "q": q_filter,
        "start": start_date.isoformat(),
        "end": end_date.isoformat(),
    }

    return render(request, "dashboard/finance_dashboard.html", {
        "invoice_rows": invoice_rows,
        "stats": stats,
        "by_type": by_type,
        "filters": filters,
        "status_choices": InvoiceStatus.choices,
        "ref_type_choices": [
            ("subscription", "اشتراك"),
            ("verify_request", "توثيق"),
            ("promo_request", "ترويج"),
            ("extra_purchase", "خدمات إضافية"),
            ("extras_bundle_request", "حزمة إضافية"),
        ],
        "selected_invoice": selected_invoice,
        "selected_lines": selected_lines,
        "selected_attempts": selected_attempts,
    })
