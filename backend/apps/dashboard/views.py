from __future__ import annotations

import csv
from decimal import Decimal, InvalidOperation
from datetime import date, datetime, time, timedelta
from functools import wraps
from io import StringIO

from django.conf import settings
from django.contrib import messages
from django.contrib.auth import authenticate, get_user_model, login, logout
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db.models import Count, Q
from django.http import Http404, HttpResponse, HttpResponseForbidden
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
from apps.backoffice.models import AccessLevel, AccessPermission, Dashboard, UserAccessProfile
from apps.backoffice.policies import (
    ContentHideDeletePolicy,
    ContentManagePolicy,
    PromoQuoteActivatePolicy,
    ReviewModerationPolicy,
)
from apps.marketplace.models import RequestStatus, ServiceRequest
from apps.messaging.models import Message, Thread
from apps.moderation.integrations import record_content_action_case, record_support_target_delete_case, sync_review_case
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
from apps.support.models import (
    SupportAttachment,
    SupportComment,
    SupportPriority,
    SupportTeam,
    SupportTicket,
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
    PromoFrequency,
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
from apps.promo.services import (
    activate_after_payment,
    calc_promo_request_quote,
    ensure_default_pricing_rules,
    quote_and_create_invoice,
    reject_request,
    set_promo_ops_status,
    _sync_promo_to_unified,
)
from apps.excellence.selectors import (
    FEATURED_SERVICE_BADGE_CODE,
    HIGH_ACHIEVEMENT_BADGE_CODE,
    TOP_100_CLUB_BADGE_CODE,
    current_review_window as excellence_current_review_window,
)
from apps.excellence.services import sync_badge_type_catalog

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
    AccessProfileForm,
    ContentDesignUploadForm,
    ContentFirstTimeForm,
    ContentReviewActionForm,
    ContentSettingsLegalForm,
    ContentSettingsLinksForm,
    DashboardLoginForm,
    DashboardOTPForm,
    PromoInquiryActionForm,
    PromoModuleItemForm,
    PromoRequestActionForm,
    SupportDashboardActionForm,
)
from .security import is_safe_redirect_url


def _want_export(request, expected: str) -> bool:
    token = (request.GET.get("export") or request.GET.get("format") or "").strip().lower()
    return token == expected


def _want_csv(request) -> bool:
    return _want_export(request, "csv")


def _want_xlsx(request) -> bool:
    return _want_export(request, "xlsx")


def _want_pdf(request) -> bool:
    return _want_export(request, "pdf")


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
                {"form": form, "dev_accept_any": bypass_enabled, "phone": pending_user.phone},
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
        {"form": form, "dev_accept_any": bypass_enabled, "phone": pending_user.phone},
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
        if profile.level == AccessLevel.ADMIN:
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


def _upsert_access_profile(request, form: AccessProfileForm):
    profile_id = form.cleaned_data.get("profile_id")
    username = (form.cleaned_data.get("username") or "").strip()
    mobile = (form.cleaned_data.get("mobile_number") or "").strip()
    level = form.cleaned_data.get("level")
    dashboards = form.cleaned_data.get("dashboards") or []
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
    profile.granted_permissions.set(AccessPermission.objects.filter(code__in=permissions, is_active=True))

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
    section = (request.GET.get("section") or "access").strip().lower()
    if section not in {"access", "reports"}:
        section = "access"

    if request.method == "POST":
        action = (request.POST.get("action") or "").strip()
        if not dashboard_allowed(request.user, "admin_control", write=True):
            return HttpResponseForbidden("لا تملك صلاحية التعديل.")

        if action == "save_user":
            form = AccessProfileForm(request.POST)
            if form.is_valid():
                profile = _upsert_access_profile(request, form)
                if profile is not None:
                    return redirect(f"{request.path}?section=access&edit={profile.id}")
            messages.error(request, "يرجى تصحيح الأخطاء في النموذج.")
        elif action == "delete_user":
            _deactivate_access_profile(request)
            return redirect(f"{request.path}?section=access")
        elif action == "toggle_revoke":
            _toggle_revoke_access_profile(request)
            return redirect(f"{request.path}?section=access")

    edit_profile_id = request.GET.get("edit")
    edit_profile = None
    if edit_profile_id and str(edit_profile_id).isdigit():
        edit_profile = UserAccessProfile.objects.select_related("user").filter(id=int(edit_profile_id)).first()

    access_form = AccessProfileForm(initial=_profile_to_form_initial(edit_profile) if edit_profile else None)
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
    SupportTicketType.TECH: "فريق الدعم الفني",
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


def _support_requester_label(ticket: SupportTicket) -> str:
    requester = ticket.requester
    label = (getattr(requester, "username", "") or requester.phone or f"user-{requester.id}").strip()
    if not label.startswith("@"):
        label = f"@{label}"
    return label


def _support_assignee_label(ticket: SupportTicket) -> str:
    if not ticket.assigned_to:
        return "غير مكلف"
    return (ticket.assigned_to.username or ticket.assigned_to.phone or f"user-{ticket.assigned_to.id}").strip()


def _support_team_label(ticket: SupportTicket) -> str:
    if ticket.assigned_team:
        return ticket.assigned_team.name_ar
    return SUPPORT_TICKET_TYPE_TO_TEAM_LABEL.get(ticket.ticket_type, "فريق الدعم والمساعدة")


def _support_queryset_for_user(user):
    qs = SupportTicket.objects.select_related("requester", "assigned_team", "assigned_to").order_by("-created_at", "-id")
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


def _support_team_choices() -> list[tuple[str, str]]:
    return [(str(team.id), team.name_ar) for team in SupportTeam.objects.filter(is_active=True).order_by("sort_order", "id")]


def _serialize_support_rows(tickets: list[SupportTicket]) -> list[dict]:
    rows = []
    for ticket in tickets:
        priority_number = _support_priority_number(ticket.priority)
        rows.append(
            {
                "id": ticket.id,
                "code": ticket.code or f"HD{ticket.id:04d}",
                "requester": _support_requester_label(ticket),
                "priority_number": priority_number,
                "priority_class": _support_priority_row_class(ticket.priority),
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
            | Q(requester__username__icontains=query_filter)
            | Q(requester__phone__icontains=query_filter)
        )

    tickets = list(tickets_qs)
    selected_ticket = _resolve_selected_ticket(base_qs, request, ticket_id)
    if selected_ticket is None and tickets:
        selected_ticket = tickets[0]

    assignee_choices = _support_assignee_choices()
    team_choices = _support_team_choices()
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

            if assigned_to_id is not None:
                assignee = dashboard_assignee_user(assigned_to_id, "support", write=True)
                if assignee is None:
                    messages.error(request, "المكلف المختار لا يملك صلاحية لوحة الدعم.")
                    return _support_redirect_with_state(request, ticket_id=target_ticket.id)
                if access_profile and access_profile.level == AccessLevel.USER and assignee.id != request.user.id:
                    return HttpResponseForbidden("لا يمكنك تعيين الطلب لمستخدم آخر.")

            if team_id is not None and not SupportTeam.objects.filter(id=team_id, is_active=True).exists():
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
                    from django.core.exceptions import ValidationError as DjangoValidationError
                    from apps.features.upload_limits import user_max_upload_mb
                    from apps.uploads.validators import validate_user_file_size

                    validate_user_file_size(attachment, user_max_upload_mb(request.user))
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
            "redirect_query": request.GET.urlencode(),
        },
    )


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
    items = [
        {
            "key": "home",
            "label": "لوحة فريق إدارة الترويج",
            "description": "قائمة الاستفسارات وطلبات الترويج التشغيلية.",
            "url": reverse("dashboard:promo_dashboard"),
        }
    ]
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
    return {
        "nav_items": _promo_nav_items(active_key),
        "request_codes": [
            {"code": "HD0001", "label": "استفسارات الترويج"},
            {"code": "MD0006", "label": "طلبات الترويج"},
        ],
    }


def _promo_inquiries_queryset_for_user(user):
    return _support_queryset_for_user(user).filter(ticket_type=SupportTicketType.ADS)


def _promo_requests_queryset_for_user(user):
    qs = (
        PromoRequest.objects.select_related("requester", "assigned_to", "invoice")
        .prefetch_related("items", "assets", "assets__uploaded_by", "assets__item")
        .order_by("-created_at", "-id")
    )
    access_profile = active_access_profile_for_user(user)
    if access_profile and access_profile.level == AccessLevel.USER:
        qs = qs.filter(Q(assigned_to=user) | Q(assigned_to__isnull=True))
    return qs


def _promo_requester_label(user_obj) -> str:
    label = (getattr(user_obj, "username", "") or getattr(user_obj, "phone", "") or f"user-{user_obj.id}").strip()
    if not label.startswith("@"):
        label = f"@{label}"
    return label


def _promo_assignee_label(promo_request: PromoRequest) -> str:
    if promo_request.assigned_to:
        return (promo_request.assigned_to.username or promo_request.assigned_to.phone or "").strip() or "غير مكلف"
    return "غير مكلف"


def _promo_inquiry_rows(tickets: list[SupportTicket]) -> list[dict]:
    rows: list[dict] = []
    for ticket in tickets:
        rows.append(
            {
                "id": ticket.id,
                "code": ticket.code or f"HD{ticket.id:06d}",
                "requester": _support_requester_label(ticket),
                "priority_number": _support_priority_number(ticket.priority),
                "priority_class": _support_priority_row_class(ticket.priority),
                "ticket_type": ticket.get_ticket_type_display(),
                "created_at": _format_dt(ticket.created_at),
                "status": ticket.get_status_display(),
                "team": _support_team_label(ticket),
                "assignee": _support_assignee_label(ticket),
                "assigned_at": _format_dt(ticket.assigned_at),
            }
        )
    return rows


def _promo_request_rows(requests: list[PromoRequest]) -> list[dict]:
    rows: list[dict] = []
    for promo_request in requests:
        service_labels: list[str] = []
        for item in promo_request.items.all():
            label = item.get_service_type_display()
            if label not in service_labels:
                service_labels.append(label)
        rows.append(
            {
                "id": promo_request.id,
                "code": promo_request.code or f"MD{promo_request.id:06d}",
                "requester": _promo_requester_label(promo_request.requester),
                "priority_number": 1,
                "created_at": _format_dt(promo_request.created_at),
                "status": promo_request.get_ops_status_display(),
                "team": "إدارة الترويج",
                "assignee": _promo_assignee_label(promo_request),
                "assigned_at": _format_dt(promo_request.assigned_at),
                "services_text": "، ".join(service_labels) if service_labels else promo_request.get_ad_type_display(),
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
        "الخدمات",
        "حالة التنفيذ",
        "حالة الفاتورة",
        "المكلف بالطلب",
        "تاريخ الإنشاء",
    ]
    rows: list[list] = []
    for row in _promo_request_rows(requests):
        rows.append(
            [
                row["code"],
                row["requester"],
                row["services_text"],
                row["status"],
                row["invoice_status"],
                row["assignee"],
                row["created_at"],
            ]
        )
    return headers, rows


def _promo_redirect_with_state(request, *, request_id: int | None = None, inquiry_id: int | None = None):
    query = (request.POST.get("redirect_query") or request.GET.urlencode()).strip()
    base = request.path
    if not query:
        params: list[str] = []
        if inquiry_id is not None:
            params.append(f"inquiry={inquiry_id}")
        if request_id is not None:
            params.append(f"request={request_id}")
        return redirect(f"{base}?{'&'.join(params)}") if params else redirect(base)
    if inquiry_id is not None and "inquiry=" not in query:
        query = f"{query}&inquiry={inquiry_id}"
    if request_id is not None and "request=" not in query:
        query = f"{query}&request={request_id}"
    return redirect(f"{base}?{query}")


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
    subtotal = Decimal(str(payload.get("subtotal") or "0.00")).quantize(Decimal("0.01"))
    vat_percent = Decimal(str(getattr(settings, "PROMO_VAT_PERCENT", 15)))
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

@dashboard_staff_required
@require_dashboard_access("promo")
def promo_dashboard(request, request_id: int | None = None):
    can_write = dashboard_allowed(request.user, "promo", write=True)
    access_profile = active_access_profile_for_user(request.user)
    assignee_choices = _dashboard_assignee_choices("promo")
    team_choices = _support_team_choices()

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
            | Q(requester__username__icontains=inquiry_q)
            | Q(requester__phone__icontains=inquiry_q)
        )
    inquiries = list(inquiries_qs.order_by("-created_at", "-id"))

    promo_requests_qs = promo_requests_base_qs
    if request_q:
        promo_requests_qs = promo_requests_qs.filter(
            Q(code__icontains=request_q)
            | Q(title__icontains=request_q)
            | Q(requester__username__icontains=request_q)
            | Q(requester__phone__icontains=request_q)
        )
    if ops_filter:
        promo_requests_qs = promo_requests_qs.filter(ops_status=ops_filter)
    promo_requests = list(promo_requests_qs)

    selected_inquiry_id_raw = (request.GET.get("inquiry") or "").strip()
    selected_inquiry = inquiries_base_qs.filter(id=int(selected_inquiry_id_raw)).first() if selected_inquiry_id_raw.isdigit() else None
    if selected_inquiry is None and inquiries:
        selected_inquiry = inquiries[0]

    selected_request = None
    if request_id is not None:
        selected_request = promo_requests_base_qs.filter(id=request_id).first()
    if selected_request is None:
        selected_request_id_raw = (request.GET.get("request") or "").strip()
        if selected_request_id_raw.isdigit():
            selected_request = promo_requests_base_qs.filter(id=int(selected_request_id_raw)).first()
    if selected_request is None and promo_requests:
        selected_request = promo_requests[0]

    linked_request_choices = [
        (str(row.id), f"{row.code or f'MD{row.id:06d}'} - {_promo_requester_label(row.requester)}")
        for row in promo_requests_base_qs[:200]
    ]

    inquiry_profile = getattr(selected_inquiry, "promo_profile", None) if selected_inquiry else None
    inquiry_form = PromoInquiryActionForm(
        initial={
            "status": selected_inquiry.status if selected_inquiry else SupportTicketStatus.NEW,
            "assigned_team": str(selected_inquiry.assigned_team_id or "") if selected_inquiry else "",
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
        },
        assignee_choices=assignee_choices,
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

            post_form = PromoInquiryActionForm(
                request.POST,
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

            team_id_raw = (post_form.cleaned_data.get("assigned_team") or "").strip()
            assigned_to_raw = (post_form.cleaned_data.get("assigned_to") or "").strip()
            team_id = int(team_id_raw) if team_id_raw.isdigit() else target_ticket.assigned_team_id
            assigned_to_id = int(assigned_to_raw) if assigned_to_raw.isdigit() else target_ticket.assigned_to_id

            if assigned_to_id is not None:
                assignee = dashboard_assignee_user(assigned_to_id, "promo", write=True)
                if assignee is None:
                    messages.error(request, "المكلف المختار لا يملك صلاحية لوحة الترويج.")
                    return _promo_redirect_with_state(request, inquiry_id=target_ticket.id)
                if access_profile and access_profile.level == AccessLevel.USER and assignee.id != request.user.id:
                    return HttpResponseForbidden("لا يمكنك تعيين الاستفسار لمستخدم آخر.")

            if team_id is not None and not SupportTeam.objects.filter(id=team_id, is_active=True).exists():
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
                    from apps.features.upload_limits import user_max_upload_mb
                    from apps.uploads.validators import validate_user_file_size

                    validate_user_file_size(attachment, user_max_upload_mb(request.user))
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

            post_form = PromoRequestActionForm(request.POST, assignee_choices=assignee_choices)
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
            if assigned_to_id != target_request.assigned_to_id:
                target_request.assigned_to = assignee
                target_request.assigned_at = timezone.now() if assignee else None
                updates.extend(["assigned_to", "assigned_at"])

            ops_note = post_form.cleaned_data.get("ops_note") or ""
            if action == "save_request":
                desired_ops_status = post_form.cleaned_data.get("ops_status") or target_request.ops_status
                if desired_ops_status != target_request.ops_status:
                    target_request = set_promo_ops_status(
                        pr=target_request,
                        new_status=desired_ops_status,
                        by_user=request.user,
                        note=ops_note,
                    )
                if ops_note:
                    target_request.quote_note = ops_note[:300]
                    updates.append("quote_note")

            elif action == "quote_request":
                policy = PromoQuoteActivatePolicy.evaluate_and_log(
                    request.user,
                    request=request,
                    reference_type="promo.request",
                    reference_id=str(target_request.id),
                    extra={"surface": "dashboard.promo.quote"},
                )
                if not policy.allowed:
                    return HttpResponseForbidden("لا تملك صلاحية اعتماد التسعير.")
                quote_note = post_form.cleaned_data.get("quote_note") or ""
                try:
                    target_request = quote_and_create_invoice(pr=target_request, by_user=request.user, quote_note=quote_note)
                except ValueError as exc:
                    messages.error(request, str(exc))
                    return _promo_redirect_with_state(request, request_id=target_request.id)

            elif action == "activate_request":
                policy = PromoQuoteActivatePolicy.evaluate_and_log(
                    request.user,
                    request=request,
                    reference_type="promo.request",
                    reference_id=str(target_request.id),
                    extra={"surface": "dashboard.promo.activate"},
                )
                if not policy.allowed:
                    return HttpResponseForbidden("لا تملك صلاحية تفعيل الطلب.")
                try:
                    target_request = activate_after_payment(pr=target_request)
                except ValueError as exc:
                    messages.error(request, str(exc))
                    return _promo_redirect_with_state(request, request_id=target_request.id)

            elif action == "complete_request":
                target_request = set_promo_ops_status(
                    pr=target_request,
                    new_status=PromoOpsStatus.COMPLETED,
                    by_user=request.user,
                    note=ops_note,
                )

            elif action == "reject_request":
                rejectable_statuses = {
                    PromoRequestStatus.NEW,
                    PromoRequestStatus.IN_REVIEW,
                    PromoRequestStatus.REJECTED,
                }
                if target_request.status not in rejectable_statuses:
                    messages.error(request, "يمكن رفض الطلب قبل التسعير فقط.")
                    return _promo_redirect_with_state(request, request_id=target_request.id)

                reject_reason = (post_form.cleaned_data.get("quote_note") or post_form.cleaned_data.get("ops_note") or "").strip()
                if not reject_reason:
                    messages.error(request, "اكتب سبب الرفض لإعادة الطلب للعميل.")
                    return _promo_redirect_with_state(request, request_id=target_request.id)

                target_request = reject_request(pr=target_request, reason=reject_reason, by_user=request.user)

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
    can_reject_selected_request = bool(
        selected_request
        and selected_request.status in {PromoRequestStatus.NEW, PromoRequestStatus.IN_REVIEW, PromoRequestStatus.REJECTED}
    )
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

    context = _promo_base_context("home")
    context.update(
        {
            "hero_title": "لوحة فريق إدارة الترويج",
            "hero_subtitle": "إدارة الاستفسارات، تحويلها لطلبات ترويج، تشغيل التنفيذ، ومتابعة التسعير والفوترة.",
            "can_write": can_write,
            "inquiries": _promo_inquiry_rows(inquiries),
            "promo_requests": _promo_request_rows(promo_requests),
            "inquiry_summary": _promo_inquiry_summary(inquiries),
            "request_summary": _promo_requests_summary(promo_requests),
            "selected_inquiry": selected_inquiry,
            "selected_request": selected_request,
            "can_reject_selected_request": can_reject_selected_request,
            "selected_request_items": selected_request_items,
            "selected_request_assets": selected_request_assets,
            "selected_request_quote": selected_request_quote,
            "selected_inquiry_attachments": selected_inquiry_attachments,
            "selected_inquiry_comments": selected_inquiry_comments,
            "inquiry_form": inquiry_form,
            "request_form": request_form,
            "filters": {
                "inquiry_q": inquiry_q,
                "request_q": request_q,
                "ops": ops_filter,
            },
            "redirect_query": request.GET.urlencode(),
        }
    )
    return render(request, "dashboard/promo_dashboard.html", context)


def _promo_module_rows(items: list[PromoRequestItem]) -> list[dict]:
    rows: list[dict] = []
    for item in items:
        promo_request = item.request
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
                "frequency": item.get_frequency_display() if item.frequency else "-",
                "search_scope": item.get_search_scope_display() if item.search_scope else "-",
                "search_position": item.get_search_position_display() if item.search_position else "-",
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
    return requests_base_qs.filter(filter_q).distinct().order_by("-created_at", "-id")


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
        (selected_request.requester.username or selected_request.requester.phone or "").strip()
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
        "frequency": (
            (selected_item.frequency if selected_item else "")
            or selected_request.frequency
            or ""
        ),
        "search_scope": (selected_item.search_scope if selected_item else "") or (search_scopes[0] if search_scopes else ""),
        "search_scopes": search_scopes,
        "search_position": (
            (selected_item.search_position if selected_item else "")
            or selected_request.position
            or ""
        ),
        "target_provider_id": target_provider_id,
        "target_category": (
            (selected_item.target_category if selected_item else "")
            or selected_request.target_category
            or ""
        ),
        "target_city": (
            (selected_item.target_city if selected_item else "")
            or selected_request.target_city
            or ""
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
    selected_request_module_assets = _promo_module_assets_for_selected_request(
        selected_request=selected_request,
        service_type=service_type,
    )

    module_items_qs = (
        PromoRequestItem.objects.select_related("request", "request__requester")
        .filter(request__in=requests_base_qs, service_type=service_type)
        .order_by("-created_at", "-id")
    )
    if query_filter:
        module_items_qs = module_items_qs.filter(
            Q(request__code__icontains=query_filter)
            | Q(title__icontains=query_filter)
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

    if request.method == "POST":
        posted_request_id_raw = (request.POST.get("request_id") or "").strip()
        if posted_request_id_raw.isdigit():
            selected_request = requests_base_qs.filter(id=int(posted_request_id_raw)).first() or selected_request
            selected_request_item = _promo_selected_request_item_for_service(
                selected_request,
                service_type=service_type,
            )
            selected_request_module_assets = _promo_module_assets_for_selected_request(
                selected_request=selected_request,
                service_type=service_type,
            )

        if not can_write:
            return HttpResponseForbidden("لا تملك صلاحية إدارة وحدات الترويج.")
        module_action = _promo_module_action(request)
        module_form = PromoModuleItemForm(request.POST, request.FILES, service_type=service_type)
        if module_form.is_valid():
            cleaned = module_form.cleaned_data
            request_id = cleaned.get("request_id")
            promo_request = requests_base_qs.filter(id=int(request_id)).first() if request_id else None
            if promo_request is None:
                module_form.add_error("request_id", "رقم طلب الترويج المحدد غير متاح.")

            target_provider = None
            target_provider_id = cleaned.get("target_provider_id")
            if target_provider_id:
                target_provider = ProviderProfile.objects.filter(id=int(target_provider_id)).first()
                if target_provider is None:
                    module_form.add_error("target_provider_id", "معرف المختص المستهدف غير صحيح.")

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
                    if (
                        target_provider is None
                        and getattr(promo_request.requester, "provider_profile", None) is not None
                        and service_type in PROMO_TARGETED_SERVICE_TYPES
                    ):
                        target_provider = promo_request.requester.provider_profile

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

                        next_sort = int(next_sort) + 10
                        created_items.append(
                            PromoRequestItem.objects.create(
                                request=promo_request,
                                service_type=service_type,
                                title=item_title,
                                start_at=cleaned.get("start_at"),
                                end_at=cleaned.get("end_at"),
                                send_at=cleaned.get("send_at"),
                                frequency=cleaned.get("frequency") or "",
                                search_scope=scope,
                                search_position=cleaned.get("search_position") or "",
                                target_provider=target_provider,
                                target_category=cleaned.get("target_category") or "",
                                target_city=cleaned.get("target_city") or "",
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
                                sort_order=next_sort,
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
                    if not promo_request.target_category and first_item.target_category:
                        promo_request.target_category = first_item.target_category
                    if not promo_request.target_city and first_item.target_city:
                        promo_request.target_city = first_item.target_city
                    if not promo_request.redirect_url and first_item.redirect_url:
                        promo_request.redirect_url = first_item.redirect_url
                    promo_request.save(
                        update_fields=[
                            "start_at",
                            "end_at",
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
            "selected_request_item": selected_request_item,
            "selected_request_module_assets": selected_request_module_assets,
            "selected_request_quote": _promo_quote_snapshot(selected_request) if selected_request else None,
            "preview_payload": preview_payload,
            "is_search_module": service_type == PromoServiceType.SEARCH_RESULTS,
            "is_messages_module": service_type == PromoServiceType.PROMO_MESSAGES,
            "is_sponsorship_module": service_type == PromoServiceType.SPONSORSHIP,
            "is_module_review_flow": service_type in {PromoServiceType.PROMO_MESSAGES, PromoServiceType.SPONSORSHIP},
        }
    )
    return render(request, "dashboard/promo_module.html", context)


@dashboard_staff_required
@require_dashboard_access("promo")
def promo_pricing(request):
    ensure_default_pricing_rules()
    pricing_rules = list(PromoPricingRule.objects.filter(is_active=True).order_by("sort_order", "id"))
    can_write = dashboard_allowed(request.user, "promo", write=True)

    if request.method == "POST":
        if not can_write:
            return HttpResponseForbidden("لا تملك صلاحية تعديل تسعيرات الترويج.")

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
CONTENT_REQUEST_CODES = [
    {"code": "HD0001", "label": "طلبات الدعم والمساعدة"},
    {"code": "MD0006", "label": "طلبات الإعلانات والترويج"},
    {"code": "AD0006", "label": "طلبات التوثيق"},
    {"code": "SD0006", "label": "طلبات الترقية والاشتراكات"},
    {"code": "P00006", "label": "طلبات الخدمات الإضافية"},
]
CONTENT_REVIEW_TYPES = {SupportTicketType.SUGGEST, SupportTicketType.COMPLAINT}
CONTENT_EXCELLENCE_BADGE_CODES = [
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
            "label": "تحديث معلومات صفحة الإعدادات",
            "description": "الشروط والخصوصية والروابط الرسمية للمنصة.",
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
    return {
        "nav_items": _content_nav_items(active_key),
        "managed_teams": CONTENT_MANAGED_TEAM_NAMES,
        "request_codes": CONTENT_REQUEST_CODES,
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
    context = _content_base_context("home")
    context.update(
        {
            "hero_title": "لوحة فريق إدارة المحتوى",
            "hero_subtitle": "إدارة نصوص وتجارب الدخول، ضبط الإعدادات، متابعة التقييمات، وتشغيل التميز من لوحة موحدة.",
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
        default_title="منصة مختص",
        default_body="المنصة الأشمل لربط مقدمي الخدمات المختلفة مع عملائهم.",
    )
    client_block = _content_block_get_or_create(
        ContentBlockKey.ONBOARDING_INTRO,
        default_title="كعميل",
        default_body="ابحث عن المختص المناسب لخدمتك وابدأ الطلب بثقة.",
    )
    provider_block = _content_block_get_or_create(
        ContentBlockKey.ONBOARDING_GET_STARTED,
        default_title="كمقدم خدمة",
        default_body="بوابة لتمكين المختصين من استثمار الخبرة والمهارة والتواصل مع العملاء.",
    )

    text_form = ContentFirstTimeForm(
        initial={
            "intro_title": intro_block.title_ar,
            "intro_body": intro_block.body_ar,
            "client_title": client_block.title_ar or "كعميل",
            "client_body": client_block.body_ar,
            "provider_title": provider_block.title_ar or "كمقدم خدمة",
            "provider_body": provider_block.body_ar,
        }
    )
    design_form = ContentDesignUploadForm(initial={"file_specs": _content_media_specs(intro_block.media_file)})

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

        elif action == "upload_design":
            design_form = ContentDesignUploadForm(request.POST, request.FILES)
            if design_form.is_valid():
                design_file = design_form.cleaned_data.get("design_file")
                if design_file is None:
                    messages.error(request, "يرجى اختيار ملف التصميم قبل الحفظ.")
                else:
                    _save_content_block(
                        block=intro_block,
                        media_file=design_file,
                        actor=request.user,
                        request=request,
                    )
                    messages.success(request, "تم رفع تصميم شاشة الدخول الأول بنجاح.")
                    return redirect("dashboard:content_first_time")
            else:
                messages.error(request, "تعذّر رفع ملف التصميم. راجع مواصفات الملف.")

    context = _content_base_context("first_time")
    context.update(
        {
            "hero_title": "محتوى صفحة الدخول لأول مرة",
            "hero_subtitle": "تعديل النصوص الأساسية وتحديث التصميم المعروض عند فتح التطبيق لأول مرة.",
            "text_form": text_form,
            "design_form": design_form,
            "can_manage": can_manage,
            "can_write": can_write,
            "intro_block": intro_block,
            "client_block": client_block,
            "provider_block": provider_block,
            "design_specs": _content_media_specs(intro_block.media_file),
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
        ContentBlockKey.ONBOARDING_INTRO,
        default_title="بروفة التعريف بالتطبيق",
        default_body="صفحة التعريف الأولى داخل التطبيق.",
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
            "hero_subtitle": "رفع التصميم، معاينته داخل إطار الجوال، واعتماد النسخة النهائية.",
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

    links_obj = SiteLinks.objects.order_by("-updated_at", "-id").first()
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
                links = links_obj or SiteLinks()
                links.website_url = links_form.cleaned_data.get("website_url") or ""
                links.ios_store = links_form.cleaned_data.get("ios_store") or ""
                links.android_store = links_form.cleaned_data.get("android_store") or ""
                links.x_url = links_form.cleaned_data.get("x_url") or ""
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
                    extra={"fields": ["website_url", "ios_store", "android_store", "x_url", "whatsapp_url", "email"]},
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
        Q(ticket_type__in=CONTENT_REVIEW_TYPES) | Q(assigned_team__code="content")
    )


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


def _content_review_ticket_rows(tickets: list[SupportTicket]) -> list[dict]:
    rows = []
    for ticket in tickets:
        priority_number = _support_priority_number(ticket.priority)
        rows.append(
            {
                "id": ticket.id,
                "code": ticket.code or f"HD{ticket.id:04d}",
                "requester": _support_requester_label(ticket),
                "priority_number": priority_number,
                "priority_class": _support_priority_row_class(ticket.priority),
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

    assignee_choices = _dashboard_assignee_choices("content")
    team_choices = _support_team_choices()

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
            elif action == "return_ticket":
                desired_status = SupportTicketStatus.RETURNED

            team_id = int(team_id_raw) if team_id_raw.isdigit() else target_ticket.assigned_team_id
            assigned_to_id = int(assigned_to_raw) if assigned_to_raw.isdigit() else target_ticket.assigned_to_id

            if assigned_to_id is not None:
                assignee = dashboard_assignee_user(assigned_to_id, "content", write=True)
                if assignee is None:
                    messages.error(request, "المكلف المختار لا يملك صلاحية لوحة إدارة المحتوى.")
                    return _content_reviews_redirect_with_state(request, ticket_id=target_ticket.id)
                if access_profile and access_profile.level == AccessLevel.USER and assignee.id != request.user.id:
                    return HttpResponseForbidden("لا يمكنك تعيين الطلب لمستخدم آخر.")

            if team_id is not None and not SupportTeam.objects.filter(id=team_id, is_active=True).exists():
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
                    from apps.features.upload_limits import user_max_upload_mb
                    from apps.uploads.validators import validate_user_file_size

                    validate_user_file_size(attachment, user_max_upload_mb(request.user))
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
            "hero_title": "إدارة التقييم والمراجعات",
            "hero_subtitle": "متابعة طلبات الاقتراحات والبلاغات ومعالجة الحالات التشغيلية والمحتوى محل الشكوى.",
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
            "selected_ticket_comments": list(selected_ticket.comments.order_by("-id")[:8]) if selected_ticket else [],
            "selected_ticket_attachments": list(selected_ticket.attachments.order_by("-id")[:8]) if selected_ticket else [],
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


@dashboard_staff_required
@require_dashboard_access("content")
def content_excellence(request):
    sync_badge_type_catalog()
    badge_filter = (request.GET.get("badge") or "").strip()
    q = (request.GET.get("q") or "").strip()

    cycle_start, cycle_end = excellence_current_review_window()
    candidates_qs = ExcellenceBadgeCandidate.objects.select_related(
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

    if not candidates_qs.exists():
        latest_cycle_end = (
            ExcellenceBadgeCandidate.objects.filter(badge_type__code__in=CONTENT_EXCELLENCE_BADGE_CODES)
            .order_by("-evaluation_period_end")
            .values_list("evaluation_period_end", flat=True)
            .first()
        )
        if latest_cycle_end:
            candidates_qs = ExcellenceBadgeCandidate.objects.select_related(
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

    if badge_filter:
        candidates_qs = candidates_qs.filter(badge_type__code=badge_filter)
    if q:
        candidates_qs = candidates_qs.filter(
            Q(provider__display_name__icontains=q)
            | Q(provider__user__phone__icontains=q)
            | Q(category__name__icontains=q)
            | Q(subcategory__name__icontains=q)
        )

    candidates = list(candidates_qs.order_by("badge_type__sort_order", "rank_position", "provider_id"))
    rows = _content_excellence_rows(candidates)

    headers, export_rows = _content_excellence_export_rows(rows)
    if _want_csv(request):
        return _csv_response("content_excellence.csv", headers, export_rows)
    if _want_xlsx(request):
        return xlsx_response("content_excellence.xlsx", "content_excellence", headers, export_rows)
    if _want_pdf(request):
        return pdf_response("content_excellence.pdf", "لوحة إدارة التميز", headers, export_rows, landscape=True)

    badge_types = list(
        ExcellenceBadgeType.objects.filter(code__in=CONTENT_EXCELLENCE_BADGE_CODES, is_active=True).order_by("sort_order", "id")
    )
    counts_by_badge: dict[str, int] = {badge.code: 0 for badge in badge_types}
    for row in rows:
        counts_by_badge[row["badge_code"]] = counts_by_badge.get(row["badge_code"], 0) + 1
    for badge in badge_types:
        badge.candidates_count = counts_by_badge.get(badge.code, 0)

    context = _content_base_context("excellence")
    context.update(
        {
            "hero_title": "إدارة التميز",
            "hero_subtitle": "مرشحو نادي المئة الكبار والإنجاز العالي والخدمة المتميزة مع تصدير فوري للتقارير.",
            "rows": rows,
            "badge_types": badge_types,
            "badge_filter": badge_filter,
            "q": q,
            "cycle_end": cycle_end,
            "total_rows": len(rows),
        }
    )
    return render(request, "dashboard/content_excellence.html", context)


@require_POST
def resend_otp_view(request):
    user_id = request.session.get(SESSION_LOGIN_USER_ID_KEY)
    user = get_user_model().objects.filter(id=user_id, is_active=True).first() if user_id else None
    if user is None:
        messages.error(request, "انتهت جلسة الدخول.")
        return redirect("dashboard:login")
    if accept_any_otp_code():
        messages.info(request, "وضع الاختبار مفعّل: يمكنك إدخال أي رمز من 4 أرقام.")
    else:
        create_otp(user.phone or "", request)
        messages.success(request, "تم إرسال رمز تحقق جديد.")
    return redirect("dashboard:otp")
