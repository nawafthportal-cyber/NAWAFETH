from __future__ import annotations

from datetime import datetime, time, timedelta

from django.core.cache import cache
from django.contrib import messages
from django.contrib.auth import authenticate, login, logout
from django.db.models import Q, Sum
from django.http import HttpRequest, HttpResponse
from django.shortcuts import redirect, render
from django.utils import timezone
from django.utils.dateparse import parse_date, parse_datetime

from apps.accounts.models import OTP, User
from apps.accounts.otp import accept_any_otp_code, create_otp, verify_otp
from apps.analytics.models import ProviderDailyStats
from apps.dashboard.security import is_safe_redirect_url
from apps.dashboard.exports import pdf_response, xlsx_response
from apps.extras.option_catalog import EXTRAS_REPORT_OPTIONS, option_label_for, section_title_for
from apps.extras.services import extras_bundle_invoice_for_request, extras_bundle_payload_for_request
from apps.marketplace.models import RequestStatus, ServiceRequest
from apps.messaging.models import Message, Thread
from apps.providers.models import ProviderFollow, ProviderPortfolioLike, ProviderProfile
from apps.reviews.models import Review
from apps.unified_requests.models import UnifiedRequest, UnifiedRequestType

from .auth import (
    SESSION_PORTAL_LOGIN_USER_ID_KEY,
    SESSION_PORTAL_NEXT_URL_KEY,
    SESSION_PORTAL_OTP_VERIFIED_KEY,
    extras_portal_login_required,
)
from .forms import BulkMessageForm, FinanceSettingsForm, PortalLoginForm, PortalOTPForm
from .models import (
    ExtrasPortalFinanceSettings,
    ExtrasPortalScheduledMessage,
    ExtrasPortalScheduledMessageRecipient,
    ExtrasPortalSubscription,
    ExtrasPortalSubscriptionStatus,
)


PORTAL_OTP_RESEND_COOLDOWN_SECONDS = 60
PORTAL_SECTION_REPORTS = "reports"
PORTAL_SECTION_CLIENTS = "clients"
PORTAL_SECTION_FINANCE = "finance"
PORTAL_SECTION_ORDER: tuple[str, ...] = (
    PORTAL_SECTION_REPORTS,
    PORTAL_SECTION_CLIENTS,
    PORTAL_SECTION_FINANCE,
)
PORTAL_SECTION_URL_NAME = {
    PORTAL_SECTION_REPORTS: "extras_portal:reports",
    PORTAL_SECTION_CLIENTS: "extras_portal:clients",
    PORTAL_SECTION_FINANCE: "extras_portal:finance",
}


def _portal_accept_any_otp_code() -> bool:
    return accept_any_otp_code()


def _portal_otp_resend_cache_key(user_id: int) -> str:
    return f"extras_portal:otp:resend:cooldown:{int(user_id)}"


def _portal_otp_resend_remaining_seconds(user_id: int | None) -> int:
    if not user_id:
        return 0
    until_ts = cache.get(_portal_otp_resend_cache_key(int(user_id)))
    if not until_ts:
        return 0
    return max(0, int(until_ts) - int(timezone.now().timestamp()))


def _portal_activate_otp_resend_cooldown(user_id: int, seconds: int = PORTAL_OTP_RESEND_COOLDOWN_SECONDS) -> int:
    cooldown = max(1, int(seconds or PORTAL_OTP_RESEND_COOLDOWN_SECONDS))
    until_ts = int(timezone.now().timestamp()) + cooldown
    cache.set(_portal_otp_resend_cache_key(int(user_id)), until_ts, timeout=cooldown)
    return cooldown


def _client_ip(request: HttpRequest) -> str | None:
    from apps.accounts.otp import client_ip
    return client_ip(request)


def _get_provider_or_403(request: HttpRequest) -> ProviderProfile:
    user = request.user
    if not hasattr(user, "provider_profile"):
        raise PermissionError("not provider")
    return user.provider_profile


def _portal_subscription_is_active(subscription: ExtrasPortalSubscription | None) -> bool:
    if subscription is None:
        return False
    if subscription.status != ExtrasPortalSubscriptionStatus.ACTIVE:
        return False
    ends_at = getattr(subscription, "ends_at", None)
    return bool(ends_at is None or ends_at > timezone.now())


def _latest_portal_bundle_context(provider: ProviderProfile) -> dict[str, object]:
    bundle_requests = (
        UnifiedRequest.objects.select_related("metadata_record", "requester")
        .filter(
            request_type=UnifiedRequestType.EXTRAS,
            requester=provider.user,
            status="closed",
            source_model__in=["ExtrasBundleRequest", "ExtrasServiceRequest"],
        )
        .order_by("-updated_at", "-id")
    )

    for request_obj in bundle_requests:
        bundle = extras_bundle_payload_for_request(request_obj)
        if not bundle:
            continue

        section_option_keys: dict[str, list[str]] = {}
        enabled_sections: list[dict[str, object]] = []
        for section_key in PORTAL_SECTION_ORDER:
            section_payload = bundle.get(section_key) if isinstance(bundle.get(section_key), dict) else {}
            option_keys = [
                str(key or "").strip()
                for key in list(section_payload.get("options") or [])
                if str(key or "").strip()
            ]
            if not option_keys:
                continue
            section_option_keys[section_key] = option_keys
            enabled_sections.append(
                {
                    "key": section_key,
                    "label": section_title_for(section_key),
                    "option_count": len(option_keys),
                    "option_labels": [option_label_for(section_key, key) for key in option_keys],
                }
            )

        if not enabled_sections:
            continue

        return {
            "request_obj": request_obj,
            "bundle": bundle,
            "invoice": extras_bundle_invoice_for_request(request_obj),
            "section_option_keys": section_option_keys,
            "enabled_sections": enabled_sections,
        }

    return {
        "request_obj": None,
        "bundle": {},
        "invoice": None,
        "section_option_keys": {},
        "enabled_sections": [],
    }


def _portal_shell_context(provider: ProviderProfile, *, active_section: str) -> dict[str, object]:
    bundle_context = _latest_portal_bundle_context(provider)
    portal_subscription = getattr(provider, "extras_portal_subscription", None)
    portal_subscription_active = _portal_subscription_is_active(portal_subscription)
    nav_items = []
    for section in bundle_context.get("enabled_sections", []):
        section_key = str(section.get("key") or "").strip()
        url_name = PORTAL_SECTION_URL_NAME.get(section_key)
        if not url_name:
            continue
        nav_items.append(
            {
                "key": section_key,
                "label": section.get("label") or section_title_for(section_key),
                "option_count": int(section.get("option_count") or 0),
                "url_name": url_name,
                "active": section_key == active_section,
            }
        )

    return {
        "portal_bundle_context": bundle_context,
        "portal_nav_items": nav_items,
        "portal_subscription": portal_subscription,
        "portal_subscription_active": portal_subscription_active,
        "portal_active_section": active_section,
        "portal_has_enabled_sections": bool(nav_items),
    }


def _portal_first_enabled_section(provider: ProviderProfile) -> str:
    shell_context = _portal_shell_context(provider, active_section=PORTAL_SECTION_REPORTS)
    for item in shell_context.get("portal_nav_items", []):
        key = str(item.get("key") or "").strip()
        if key:
            return key
    return PORTAL_SECTION_REPORTS


def _portal_redirect_first_enabled_section(provider: ProviderProfile):
    return redirect(PORTAL_SECTION_URL_NAME.get(_portal_first_enabled_section(provider), "extras_portal:reports"))


def _portal_require_section(provider: ProviderProfile, section_key: str):
    shell_context = _portal_shell_context(provider, active_section=section_key)
    enabled_keys = {str(item.get("key") or "").strip() for item in shell_context.get("portal_nav_items", [])}
    if section_key in enabled_keys:
        return None
    if not enabled_keys and section_key == PORTAL_SECTION_REPORTS:
        return None
    return _portal_redirect_first_enabled_section(provider)


def _get_or_create_direct_thread(user_a: User, user_b: User) -> Thread:
    if user_a.id == user_b.id:
        raise ValueError("cannot chat self")
    thread = (
        Thread.objects.filter(is_direct=True)
        .filter(
            Q(participant_1=user_a, participant_2=user_b)
            | Q(participant_1=user_b, participant_2=user_a)
        )
        .first()
    )
    if thread:
        return thread
    return Thread.objects.create(is_direct=True, participant_1=user_a, participant_2=user_b)


def portal_home(request: HttpRequest) -> HttpResponse:
    if getattr(getattr(request, "user", None), "is_authenticated", False) and bool(
        request.session.get(SESSION_PORTAL_OTP_VERIFIED_KEY)
    ):
        try:
            provider = _get_provider_or_403(request)
        except PermissionError:
            return redirect("extras_portal:login")
        return _portal_redirect_first_enabled_section(provider)
    return redirect("extras_portal:login")


def portal_login(request: HttpRequest) -> HttpResponse:
    if getattr(getattr(request, "user", None), "is_authenticated", False) and bool(
        request.session.get(SESSION_PORTAL_OTP_VERIFIED_KEY)
    ):
        try:
            provider = _get_provider_or_403(request)
        except PermissionError:
            return redirect("extras_portal:login")
        return _portal_redirect_first_enabled_section(provider)

    form = PortalLoginForm(request.POST or None)
    if request.method == "POST" and form.is_valid():
        username = (form.cleaned_data.get("username") or "").strip()
        password = form.cleaned_data.get("password") or ""

        # Allow login by either `phone` (USERNAME_FIELD) or by `username`.
        user = authenticate(request, username=username, password=password)
        if user is None:
            candidate = User.objects.filter(username=username).order_by("id").first()
            if candidate:
                user = authenticate(request, username=candidate.phone, password=password)

        if user is None or not user.is_active:
            messages.error(request, "بيانات الدخول غير صحيحة")
            return render(request, "extras_portal/login.html", {"form": form})

        if not hasattr(user, "provider_profile"):
            messages.error(request, "هذا الحساب ليس مزود خدمة")
            return render(request, "extras_portal/login.html", {"form": form})

        request.session[SESSION_PORTAL_LOGIN_USER_ID_KEY] = user.id

        if not _portal_accept_any_otp_code():
            create_otp(user.phone, request)
            _portal_activate_otp_resend_cooldown(user.id)

        return redirect("extras_portal:otp")

    return render(
        request,
        "extras_portal/login.html",
        {
            "form": form,
            "portal_panel_label": "فريق الخدمات الإضافية",
        },
    )


def portal_otp(request: HttpRequest) -> HttpResponse:
    if bool(request.session.get(SESSION_PORTAL_OTP_VERIFIED_KEY)) and getattr(
        getattr(request, "user", None), "is_authenticated", False
    ):
        try:
            provider = _get_provider_or_403(request)
        except PermissionError:
            return redirect("extras_portal:login")
        return _portal_redirect_first_enabled_section(provider)

    user_id = request.session.get(SESSION_PORTAL_LOGIN_USER_ID_KEY)
    if not user_id:
        return redirect("extras_portal:login")

    portal_user = User.objects.filter(id=user_id).first()
    if not portal_user or not portal_user.is_active:
        return redirect("extras_portal:login")

    form = PortalOTPForm(request.POST or None)
    if request.method == "POST" and form.is_valid():
        code = form.cleaned_data["code"]

        if not _portal_accept_any_otp_code():
            if not verify_otp(portal_user.phone, code):
                messages.error(request, "الكود غير صحيح أو منتهي")
                return render(
                    request,
                    "extras_portal/otp.html",
                    {
                        "form": form,
                        "phone": portal_user.phone,
                        "dev_accept_any": False,
                        "otp_resend_cooldown_seconds": _portal_otp_resend_remaining_seconds(portal_user.id),
                        "otp_resend_default_cooldown_seconds": PORTAL_OTP_RESEND_COOLDOWN_SECONDS,
                    },
                )

        login(request, portal_user, backend="django.contrib.auth.backends.ModelBackend")
        request.session[SESSION_PORTAL_OTP_VERIFIED_KEY] = True

        next_url = (request.session.pop(SESSION_PORTAL_NEXT_URL_KEY, "") or "").strip()
        if is_safe_redirect_url(next_url):
            return redirect(next_url)
        provider = getattr(portal_user, "provider_profile", None)
        if provider is not None:
            return _portal_redirect_first_enabled_section(provider)
        return redirect("extras_portal:reports")

    return render(
        request,
        "extras_portal/otp.html",
        {
            "form": form,
            "phone": portal_user.phone,
            "dev_accept_any": _portal_accept_any_otp_code(),
            "otp_resend_cooldown_seconds": _portal_otp_resend_remaining_seconds(portal_user.id),
            "otp_resend_default_cooldown_seconds": PORTAL_OTP_RESEND_COOLDOWN_SECONDS,
        },
    )


def portal_resend_otp(request: HttpRequest) -> HttpResponse:
    user_id = request.session.get(SESSION_PORTAL_LOGIN_USER_ID_KEY)
    if not user_id:
        return redirect("extras_portal:login")

    portal_user = User.objects.filter(id=user_id, is_active=True).first()
    if portal_user is None:
        return redirect("extras_portal:login")

    if _portal_otp_resend_remaining_seconds(portal_user.id) > 0:
        return redirect("extras_portal:otp")

    if not _portal_accept_any_otp_code():
        create_otp(portal_user.phone, request)
    _portal_activate_otp_resend_cooldown(portal_user.id)
    return redirect("extras_portal:otp")


def portal_logout(request: HttpRequest) -> HttpResponse:
    try:
        request.session.pop(SESSION_PORTAL_OTP_VERIFIED_KEY, None)
        request.session.pop(SESSION_PORTAL_LOGIN_USER_ID_KEY, None)
        request.session.pop(SESSION_PORTAL_NEXT_URL_KEY, None)
    except Exception:
        pass
    logout(request)
    return redirect("extras_portal:login")


REPORT_OPTION_GROUPS: tuple[dict[str, object], ...] = (
    {
        "title": "مؤشرات وتقارير الأداء",
        "description": "الأرقام المباشرة والملخصات التنفيذية المرتبطة بالفترة المعتمدة.",
        "keys": (
            "platform_metrics",
            "platform_visits",
            "platform_favorites",
            "orders_breakdown",
            "platform_shares",
        ),
    },
    {
        "title": "قوائم المعرفات والجمهور",
        "description": "القوائم المفعلة للجمهور والعملاء والتفاعلات المرتبطة بحساب مزود الخدمة.",
        "keys": (
            "service_requesters",
            "potential_clients",
            "content_favoriters",
            "platform_followers",
            "content_sharers",
            "positive_reviewers",
            "content_commenters",
        ),
    },
)


def _parse_report_window_datetime(raw_value, *, end_of_day: bool = False):
    text = str(raw_value or "").strip()
    if not text:
        return None

    parsed_datetime = parse_datetime(text)
    if parsed_datetime is not None:
        if timezone.is_naive(parsed_datetime):
            return timezone.make_aware(parsed_datetime, timezone.get_current_timezone())
        return parsed_datetime

    parsed_date = parse_date(text)
    if parsed_date is None:
        return None

    naive_value = datetime.combine(parsed_date, time.max if end_of_day else time.min)
    return timezone.make_aware(naive_value, timezone.get_current_timezone())


def _format_report_window_label(raw_value) -> str:
    text = str(raw_value or "").strip()
    if not text:
        return "-"

    parsed_datetime = parse_datetime(text)
    if parsed_datetime is not None:
        if timezone.is_naive(parsed_datetime):
            parsed_datetime = timezone.make_aware(parsed_datetime, timezone.get_current_timezone())
        return timezone.localtime(parsed_datetime).strftime("%d/%m/%Y - %H:%M")

    parsed_date = parse_date(text)
    if parsed_date is not None:
        return parsed_date.strftime("%d/%m/%Y")
    return text


def _format_datetime_label(value) -> str:
    if value is None:
        return "-"
    localized = timezone.localtime(value) if timezone.is_aware(value) else value
    return localized.strftime("%d/%m/%Y - %H:%M")


def _apply_datetime_window(queryset, field_name: str, start_at=None, end_at=None):
    if start_at is not None:
        queryset = queryset.filter(**{f"{field_name}__gte": start_at})
    if end_at is not None:
        queryset = queryset.filter(**{f"{field_name}__lte": end_at})
    return queryset


def _apply_date_window(queryset, field_name: str, start_at=None, end_at=None):
    if start_at is not None:
        queryset = queryset.filter(**{f"{field_name}__gte": start_at.date()})
    if end_at is not None:
        queryset = queryset.filter(**{f"{field_name}__lte": end_at.date()})
    return queryset


def _make_identity_entries(users, *, limit: int = 8) -> list[dict[str, str]]:
    entries: list[dict[str, str]] = []
    seen_ids: set[int] = set()
    for user in users:
        user_id = getattr(user, "id", None)
        if not user_id or user_id in seen_ids:
            continue
        seen_ids.add(user_id)
        username = str(getattr(user, "username", "") or "").strip()
        primary = f"@{username}" if username else f"المعرف #{user_id}"
        entries.append(
            {
                "primary": primary,
                "secondary": f"معرف المستخدم #{user_id}",
            }
        )
        if len(entries) >= limit:
            break
    return entries


def _list_card(*, key: str, label: str, entries: list[dict[str, str]], total_count: int, helper_text: str) -> dict[str, object]:
    return {
        "key": key,
        "title": label,
        "kind": "list",
        "badge": f"{max(0, int(total_count or 0))} عنصر",
        "badge_class": "bg-sky-100 text-sky-700",
        "accent_class": "bg-sky-100 text-sky-700",
        "wide": True,
        "entries": entries,
        "helper_text": helper_text,
        "empty_message": "لا توجد بيانات ظاهرة ضمن الفترة المحددة.",
    }


def _stats_card(*, key: str, label: str, stats: list[dict[str, str]], helper_text: str, wide: bool = False) -> dict[str, object]:
    return {
        "key": key,
        "title": label,
        "kind": "stats",
        "badge": "جاهز الآن",
        "badge_class": "bg-emerald-100 text-emerald-700",
        "accent_class": "bg-emerald-100 text-emerald-700",
        "wide": wide,
        "stats": stats,
        "helper_text": helper_text,
    }


def _placeholder_card(*, key: str, label: str, helper_text: str) -> dict[str, object]:
    return {
        "key": key,
        "title": label,
        "kind": "placeholder",
        "badge": "مفعّل",
        "badge_class": "bg-amber-100 text-amber-700",
        "accent_class": "bg-amber-100 text-amber-700",
        "wide": False,
        "placeholder_text": "الخيار مفعّل في اشتراكك، وسيظهر محتواه هنا تلقائيًا عند توفر بيانات مرتبطة به في النظام.",
        "helper_text": helper_text,
    }


def _latest_reports_bundle_context(provider: ProviderProfile) -> dict[str, object]:
    portal_bundle_context = _latest_portal_bundle_context(provider)
    request_obj = portal_bundle_context.get("request_obj")
    bundle = portal_bundle_context.get("bundle") if isinstance(portal_bundle_context.get("bundle"), dict) else {}
    reports_section = bundle.get(PORTAL_SECTION_REPORTS) if isinstance(bundle.get(PORTAL_SECTION_REPORTS), dict) else {}
    selected_option_keys = [
        key
        for key in list(portal_bundle_context.get("section_option_keys", {}).get(PORTAL_SECTION_REPORTS, []) or [])
        if key in dict(EXTRAS_REPORT_OPTIONS)
    ]
    if selected_option_keys:
        start_raw = reports_section.get("start_at")
        end_raw = reports_section.get("end_at")
        operator_comment = ""
        if request_obj is not None and hasattr(request_obj, "metadata_record"):
            operator_comment = str(getattr(request_obj.metadata_record, "payload", {}).get("operator_comment", "") or "").strip()
        return {
            "request_obj": request_obj,
            "bundle": bundle,
            "reports_section": reports_section,
            "invoice": portal_bundle_context.get("invoice"),
            "selected_option_keys": selected_option_keys,
            "selected_option_labels": [option_label_for(PORTAL_SECTION_REPORTS, key) for key in selected_option_keys],
            "start_at": _parse_report_window_datetime(start_raw, end_of_day=False),
            "end_at": _parse_report_window_datetime(end_raw, end_of_day=True),
            "start_label": _format_report_window_label(start_raw),
            "end_label": _format_report_window_label(end_raw),
            "operator_comment": operator_comment,
        }

    return {
        "request_obj": None,
        "bundle": {},
        "reports_section": {},
        "invoice": None,
        "selected_option_keys": [],
        "selected_option_labels": [],
        "start_at": None,
        "end_at": None,
        "start_label": "-",
        "end_label": "-",
        "operator_comment": "",
    }


def _report_requests_queryset(provider: ProviderProfile, bundle_context: dict[str, object]):
    qs = ServiceRequest.objects.filter(provider=provider).select_related("client")
    return _apply_datetime_window(
        qs,
        "created_at",
        bundle_context.get("start_at"),
        bundle_context.get("end_at"),
    )


def _build_reports_dashboard_context(provider: ProviderProfile) -> dict[str, object]:
    bundle_context = _latest_reports_bundle_context(provider)
    shell_context = _portal_shell_context(provider, active_section=PORTAL_SECTION_REPORTS)
    start_at = bundle_context.get("start_at")
    end_at = bundle_context.get("end_at")

    portal_subscription = getattr(provider, "extras_portal_subscription", None)
    subscription_is_active = bool(
        portal_subscription
        and portal_subscription.status == ExtrasPortalSubscriptionStatus.ACTIVE
        and (portal_subscription.ends_at is None or portal_subscription.ends_at > timezone.now())
    )

    requests_qs = _report_requests_queryset(provider, bundle_context)
    analytics_qs = _apply_date_window(
        ProviderDailyStats.objects.filter(provider=provider),
        "day",
        start_at,
        end_at,
    )
    follows_qs = _apply_datetime_window(
        ProviderFollow.objects.filter(provider=provider).select_related("user").order_by("-created_at"),
        "created_at",
        start_at,
        end_at,
    )
    likes_qs = _apply_datetime_window(
        ProviderPortfolioLike.objects.filter(item__provider=provider).select_related("user").order_by("-created_at"),
        "created_at",
        start_at,
        end_at,
    )
    reviews_qs = _apply_datetime_window(
        Review.objects.filter(provider=provider).select_related("client").order_by("-created_at"),
        "created_at",
        start_at,
        end_at,
    )
    messages_qs = _apply_datetime_window(
        Message.objects.filter(
            Q(thread__request__provider=provider)
            | Q(thread__is_direct=True, thread__participant_1=provider.user)
            | Q(thread__is_direct=True, thread__participant_2=provider.user)
        ),
        "created_at",
        start_at,
        end_at,
    )

    totals = {
        "total_requests": requests_qs.count(),
        "completed_requests": requests_qs.filter(status=RequestStatus.COMPLETED).count(),
        "in_progress_requests": requests_qs.filter(status=RequestStatus.IN_PROGRESS).count(),
        "received_amount": requests_qs.aggregate(v=Sum("received_amount"))["v"] or 0,
    }

    platform_visits = analytics_qs.aggregate(v=Sum("profile_views"))["v"] or 0
    followers_count = follows_qs.count()
    likes_count = likes_qs.count()
    messages_count = messages_qs.count()

    requesters_preview = _make_identity_entries([row.client for row in requests_qs[:20] if getattr(row, "client", None)])
    likes_preview = _make_identity_entries([row.user for row in likes_qs[:20] if getattr(row, "user", None)])
    followers_preview = _make_identity_entries([row.user for row in follows_qs[:20] if getattr(row, "user", None)])
    positive_reviews_qs = reviews_qs.filter(rating__gte=4)
    positive_reviewers_preview = _make_identity_entries(
        [row.client for row in positive_reviews_qs[:20] if getattr(row, "client", None)]
    )

    option_cards_by_key: dict[str, dict[str, object]] = {
        "platform_metrics": _stats_card(
            key="platform_metrics",
            label=option_label_for("reports", "platform_metrics"),
            wide=True,
            helper_text="ملخص تشغيلي مباشر للفترة المعتمدة في هذا الطلب.",
            stats=[
                {"label": "زيارات الملف", "value": str(platform_visits)},
                {"label": "المتابعات", "value": str(followers_count)},
                {"label": "إعجابات المحتوى", "value": str(likes_count)},
                {"label": "الرسائل", "value": str(messages_count)},
            ],
        ),
        "platform_visits": _stats_card(
            key="platform_visits",
            label=option_label_for("reports", "platform_visits"),
            helper_text="إجمالي زيارات ملف مزود الخدمة خلال الفترة المحددة.",
            stats=[{"label": "عدد الزيارات", "value": str(platform_visits)}],
        ),
        "platform_favorites": _stats_card(
            key="platform_favorites",
            label=option_label_for("reports", "platform_favorites"),
            helper_text="إجمالي التفضيلات المسجلة على عناصر المحتوى المرتبطة بمنصتك.",
            stats=[{"label": "عدد التفضيلات", "value": str(likes_count)}],
        ),
        "orders_breakdown": _stats_card(
            key="orders_breakdown",
            label=option_label_for("reports", "orders_breakdown"),
            wide=True,
            helper_text="توزيع طلبات الخدمة في الفترة نفسها حسب الحالة التشغيلية.",
            stats=[
                {"label": "جديدة", "value": str(requests_qs.filter(status=RequestStatus.NEW).count())},
                {"label": "تحت التنفيذ", "value": str(totals["in_progress_requests"])},
                {"label": "مكتملة", "value": str(totals["completed_requests"])},
                {"label": "ملغاة", "value": str(requests_qs.filter(status=RequestStatus.CANCELLED).count())},
            ],
        ),
        "platform_shares": _placeholder_card(
            key="platform_shares",
            label=option_label_for("reports", "platform_shares"),
            helper_text="لم يتم العثور على أحداث مشاركة محفوظة لهذا الخيار داخل قاعدة البيانات الحالية.",
        ),
        "service_requesters": _list_card(
            key="service_requesters",
            label=option_label_for("reports", "service_requesters"),
            entries=requesters_preview,
            total_count=requests_qs.exclude(client=None).values("client_id").distinct().count(),
            helper_text="أحدث المعرفات التي قدمت طلبات خدمة إلى مزود الخدمة خلال الفترة المحددة.",
        ),
        "potential_clients": _placeholder_card(
            key="potential_clients",
            label=option_label_for("reports", "potential_clients"),
            helper_text="الخيار مفعّل، لكن لا يوجد حاليًا سجل مخصص لوسم العملاء المحتملين داخل الباكند الحالي.",
        ),
        "content_favoriters": _list_card(
            key="content_favoriters",
            label=option_label_for("reports", "content_favoriters"),
            entries=likes_preview,
            total_count=likes_qs.exclude(user=None).values("user_id").distinct().count(),
            helper_text="معرفات المستخدمين الذين أضافوا محتوى المنصة إلى التفضيلات.",
        ),
        "platform_followers": _list_card(
            key="platform_followers",
            label=option_label_for("reports", "platform_followers"),
            entries=followers_preview,
            total_count=follows_qs.exclude(user=None).values("user_id").distinct().count(),
            helper_text="المتابعون الظاهرون لمنصتك خلال الفترة المحددة.",
        ),
        "content_sharers": _placeholder_card(
            key="content_sharers",
            label=option_label_for("reports", "content_sharers"),
            helper_text="الخيار مفعّل، لكن النظام الحالي لا يحتفظ بسجل منفصل لمعرفات المشاركين للمحتوى.",
        ),
        "positive_reviewers": _list_card(
            key="positive_reviewers",
            label=option_label_for("reports", "positive_reviewers"),
            entries=positive_reviewers_preview,
            total_count=positive_reviews_qs.exclude(client=None).values("client_id").distinct().count(),
            helper_text="معرفات أصحاب التقييمات الإيجابية (4 نجوم فأعلى) لخدمات مزود الخدمة.",
        ),
        "content_commenters": _placeholder_card(
            key="content_commenters",
            label=option_label_for("reports", "content_commenters"),
            helper_text="الخيار مفعّل، لكن التعليقات على المحتوى لا تملك حاليًا نموذج بيانات مستقل لعرضها من هذه الصفحة.",
        ),
    }

    report_option_groups: list[dict[str, object]] = []
    for group in REPORT_OPTION_GROUPS:
        cards = [
            option_cards_by_key[key]
            for key in group["keys"]
            if key in bundle_context.get("selected_option_keys", []) and key in option_cards_by_key
        ]
        if cards:
            report_option_groups.append(
                {
                    "title": group["title"],
                    "description": group["description"],
                    "cards": cards,
                }
            )

    invoice = bundle_context.get("invoice")
    payment_confirmed_at = (
        getattr(invoice, "payment_confirmed_at", None)
        or getattr(invoice, "paid_at", None)
        or getattr(bundle_context.get("request_obj"), "updated_at", None)
    )
    provider_identifier = str(getattr(provider.user, "username", "") or "").strip()
    if provider_identifier:
        provider_identifier = f"@{provider_identifier}"
    else:
        provider_identifier = provider.display_name

    overview_cards = [
        {"title": "إجمالي الطلبات", "value": totals["total_requests"], "tone": "from-violet-500 to-fuchsia-500"},
        {"title": "طلبات مكتملة", "value": totals["completed_requests"], "tone": "from-emerald-500 to-teal-500"},
        {"title": "زيارات المنصة", "value": platform_visits, "tone": "from-sky-500 to-cyan-500"},
        {"title": "رسائل وتفاعلات", "value": messages_count, "tone": "from-amber-500 to-orange-500"},
    ]

    selected_option_rows = [
        {
            "key": key,
            "label": option_label_for(PORTAL_SECTION_REPORTS, key),
            "status": "جاهز للعرض",
            "status_class": "bg-emerald-100 text-emerald-700",
            "summary": "تم تفعيل هذا البند داخل اشتراك التقارير الحالي ويجري عرضه وفق الفترة الزمنية المعتمدة.",
        }
        for key in bundle_context.get("selected_option_keys", [])
    ]

    return {
        **shell_context,
        "provider": provider,
        "bundle_context": bundle_context,
        "report_option_groups": report_option_groups,
        "overview_cards": overview_cards,
        "selected_option_rows": selected_option_rows,
        "totals": totals,
        "followers_count": followers_count,
        "likes_count": likes_count,
        "messages_count": messages_count,
        "provider_identifier": provider_identifier,
        "payment_confirmed_label": _format_datetime_label(payment_confirmed_at),
        "subscription_end_label": _format_datetime_label(getattr(portal_subscription, "ends_at", None)),
        "portal_subscription": portal_subscription,
        "portal_subscription_active": subscription_is_active,
        "selected_option_count": len(bundle_context.get("selected_option_keys", [])),
        "request_code": getattr(bundle_context.get("request_obj"), "code", "") or "-",
        "payment_note": (
            f"تمت عملية سداد رسوم التفعيل بنجاح بتاريخ { _format_datetime_label(payment_confirmed_at) }"
            if invoice is not None and payment_confirmed_at is not None
            else "هذه الصفحة مرتبطة بآخر طلب تقارير مكتمل داخل الخدمات الإضافية."
        ),
        "system_note": bundle_context.get("operator_comment")
        or "رسالة النظام: يتم عرض البيانات هنا وفق الفترة والخيارات المعتمدة في آخر طلب تقارير مكتمل.",
    }


@extras_portal_login_required
def portal_reports(request: HttpRequest) -> HttpResponse:
    provider = _get_provider_or_403(request)
    section_response = _portal_require_section(provider, PORTAL_SECTION_REPORTS)
    if section_response is not None:
        return section_response

    return render(
        request,
        "extras_portal/reports.html",
        _build_reports_dashboard_context(provider),
    )


@extras_portal_login_required
def portal_reports_export_xlsx(request: HttpRequest) -> HttpResponse:
    provider = _get_provider_or_403(request)
    section_response = _portal_require_section(provider, PORTAL_SECTION_REPORTS)
    if section_response is not None:
        return section_response
    from apps.core.models import PlatformConfig

    _limit = PlatformConfig.load().export_xlsx_max_rows
    bundle_context = _latest_reports_bundle_context(provider)
    qs = _report_requests_queryset(provider, bundle_context).order_by("-id")[:_limit]

    rows = []
    for r in qs:
        rows.append(
            [
                r.id,
                r.title,
                r.get_status_display(),
                getattr(r.client, "phone", ""),
                r.created_at,
                r.received_amount,
                r.remaining_amount,
            ]
        )

    return xlsx_response(
        filename=f"extras-portal-reports-provider-{provider.id}.xlsx",
        sheet_name="التقارير",
        headers=["رقم", "العنوان", "الحالة", "جوال العميل", "التاريخ", "المستلم", "المتبقي"],
        rows=rows,
    )


@extras_portal_login_required
def portal_reports_export_pdf(request: HttpRequest) -> HttpResponse:
    provider = _get_provider_or_403(request)
    section_response = _portal_require_section(provider, PORTAL_SECTION_REPORTS)
    if section_response is not None:
        return section_response
    from apps.core.models import PlatformConfig

    _limit = PlatformConfig.load().export_pdf_max_rows
    bundle_context = _latest_reports_bundle_context(provider)
    qs = _report_requests_queryset(provider, bundle_context).order_by("-id")[:_limit]
    rows = []
    for r in qs:
        rows.append([r.id, r.title, r.get_status_display(), getattr(r.client, "phone", ""), r.created_at])

    return pdf_response(
        filename=f"extras-portal-reports-provider-{provider.id}.pdf",
        title="التقارير",
        headers=["رقم", "العنوان", "الحالة", "جوال العميل", "التاريخ"],
        rows=rows,
        landscape=True,
    )


@extras_portal_login_required
def portal_clients(request: HttpRequest) -> HttpResponse:
    provider = _get_provider_or_403(request)
    section_response = _portal_require_section(provider, PORTAL_SECTION_CLIENTS)
    if section_response is not None:
        return section_response
    provider_user = provider.user

    clients_qs = (
        User.objects.filter(requests__provider=provider)
        .distinct()
        .order_by("-id")
    )
    clients_total_count = clients_qs.count()
    clients = list(clients_qs[:500])
    clients_with_phone_count = clients_qs.exclude(phone__isnull=True).exclude(phone="").count()

    recent_scheduled_messages_qs = (
        ExtrasPortalScheduledMessage.objects.filter(provider=provider)
        .prefetch_related("recipients")
        .order_by("-created_at")
    )
    recent_scheduled_messages = list(recent_scheduled_messages_qs[:5])
    message_summary = {
        "total": recent_scheduled_messages_qs.count(),
        "pending": recent_scheduled_messages_qs.filter(status="pending").count(),
        "sent": recent_scheduled_messages_qs.filter(status="sent").count(),
        "failed": recent_scheduled_messages_qs.filter(status="failed").count(),
    }
    recent_message_rows = [
        {
            "id": scheduled.id,
            "body_preview": str(scheduled.body or "").strip()[:120],
            "status": scheduled.get_status_display(),
            "status_key": str(scheduled.status or "").strip().lower(),
            "recipient_count": scheduled.recipients.count(),
            "send_at": scheduled.send_at,
            "created_at": scheduled.created_at,
            "sent_at": scheduled.sent_at,
            "has_attachment": bool(getattr(scheduled, "attachment", None)),
        }
        for scheduled in recent_scheduled_messages
    ]

    form = BulkMessageForm(request.POST or None, request.FILES or None)
    if request.method == "POST" and form.is_valid():
        selected_ids = request.POST.getlist("client_ids")
        recipient_ids = [int(i) for i in selected_ids if str(i).isdigit()]

        if not recipient_ids:
            messages.error(request, "اختر عميل واحد على الأقل")
            return redirect("extras_portal:clients")

        recipients = list(User.objects.filter(id__in=recipient_ids))
        if not recipients:
            messages.error(request, "لا يوجد عملاء صالحون")
            return redirect("extras_portal:clients")

        send_at = form.cleaned_data.get("send_at")
        scheduled = ExtrasPortalScheduledMessage.objects.create(
            provider=provider,
            body=form.cleaned_data["body"],
            attachment=form.cleaned_data.get("attachment"),
            send_at=send_at,
            created_by=request.user,
        )
        ExtrasPortalScheduledMessageRecipient.objects.bulk_create(
            [
                ExtrasPortalScheduledMessageRecipient(
                    scheduled_message=scheduled,
                    user=u,
                )
                for u in recipients
            ],
            ignore_conflicts=True,
        )

        # If no schedule, send immediately.
        if not send_at:
            now = timezone.now()
            try:
                for u in recipients:
                    thread = _get_or_create_direct_thread(provider_user, u)
                    Message.objects.create(
                        thread=thread,
                        sender=provider_user,
                        body=scheduled.body,
                        attachment=scheduled.attachment,
                        attachment_type="",
                        attachment_name="",
                        created_at=now,
                    )
                scheduled.status = "sent"
                scheduled.sent_at = now
                scheduled.save(update_fields=["status", "sent_at"])
                messages.success(request, "تم إرسال الرسالة")
            except Exception as e:
                scheduled.status = "failed"
                scheduled.error = str(e)[:255]
                scheduled.save(update_fields=["status", "error"])
                messages.error(request, "تعذر إرسال الرسالة")
        else:
            messages.success(request, "تمت جدولة الرسالة")

        return redirect("extras_portal:clients")

    return render(
        request,
        "extras_portal/clients.html",
        {
            **_portal_shell_context(provider, active_section=PORTAL_SECTION_CLIENTS),
            "provider": provider,
            "clients": clients,
            "clients_total_count": clients_total_count,
            "clients_with_phone_count": clients_with_phone_count,
            "message_summary": message_summary,
            "recent_message_rows": recent_message_rows,
            "form": form,
        },
    )


@extras_portal_login_required
def portal_finance(request: HttpRequest) -> HttpResponse:
    provider = _get_provider_or_403(request)
    section_response = _portal_require_section(provider, PORTAL_SECTION_FINANCE)
    if section_response is not None:
        return section_response

    settings_obj = ExtrasPortalFinanceSettings.objects.filter(provider=provider).first()

    form = FinanceSettingsForm(request.POST or None, request.FILES or None, initial={
        "bank_name": getattr(settings_obj, "bank_name", ""),
        "account_name": getattr(settings_obj, "account_name", ""),
        "iban": getattr(settings_obj, "iban", ""),
    })

    if request.method == "POST" and form.is_valid():
        if not settings_obj:
            settings_obj = ExtrasPortalFinanceSettings(provider=provider)
        settings_obj.bank_name = form.cleaned_data.get("bank_name") or ""
        settings_obj.account_name = form.cleaned_data.get("account_name") or ""
        settings_obj.iban = form.cleaned_data.get("iban") or ""
        if form.cleaned_data.get("qr_image") is not None:
            settings_obj.qr_image = form.cleaned_data.get("qr_image")
        settings_obj.save()
        messages.success(request, "تم حفظ الإعدادات")
        return redirect("extras_portal:finance")

    since_days = 30
    since = timezone.now() - timedelta(days=since_days)
    statement_qs = (
        ServiceRequest.objects.filter(provider=provider, created_at__gte=since)
        .select_related("client")
        .order_by("-id")
    )
    statement = list(statement_qs[:500])

    totals = statement_qs.aggregate(
        received=Sum("received_amount"),
        remaining=Sum("remaining_amount"),
        estimated=Sum("estimated_service_amount"),
    )
    settings_fields = [
        bool(getattr(settings_obj, "bank_name", "").strip()) if settings_obj else False,
        bool(getattr(settings_obj, "account_name", "").strip()) if settings_obj else False,
        bool(getattr(settings_obj, "iban", "").strip()) if settings_obj else False,
        bool(getattr(settings_obj, "qr_image", None)) if settings_obj else False,
    ]
    finance_profile_completion = int((sum(1 for value in settings_fields if value) / len(settings_fields)) * 100)
    finance_summary = {
        "statement_count": statement_qs.count(),
        "received_requests": statement_qs.exclude(received_amount__isnull=True).exclude(received_amount=0).count(),
        "outstanding_requests": statement_qs.exclude(remaining_amount__isnull=True).exclude(remaining_amount=0).count(),
        "finance_profile_completion": finance_profile_completion,
    }

    return render(
        request,
        "extras_portal/finance.html",
        {
            **_portal_shell_context(provider, active_section=PORTAL_SECTION_FINANCE),
            "provider": provider,
            "finance_settings": settings_obj,
            "form": form,
            "statement": statement,
            "since_days": since_days,
            "totals": totals,
            "finance_summary": finance_summary,
        },
    )


@extras_portal_login_required
def portal_finance_export_xlsx(request: HttpRequest) -> HttpResponse:
    provider = _get_provider_or_403(request)
    section_response = _portal_require_section(provider, PORTAL_SECTION_FINANCE)
    if section_response is not None:
        return section_response
    from apps.core.models import PlatformConfig
    _limit = PlatformConfig.load().export_xlsx_max_rows
    qs = ServiceRequest.objects.filter(provider=provider).select_related("client").order_by("-id")[:_limit]

    rows = []
    for r in qs:
        rows.append(
            [
                r.id,
                getattr(r.client, "phone", ""),
                r.get_status_display(),
                r.created_at,
                r.estimated_service_amount,
                r.received_amount,
                r.remaining_amount,
                r.actual_service_amount,
            ]
        )

    return xlsx_response(
        filename=f"extras-portal-finance-provider-{provider.id}.xlsx",
        sheet_name="المالية",
        headers=[
            "رقم الطلب",
            "جوال العميل",
            "الحالة",
            "التاريخ",
            "المقدر",
            "المستلم",
            "المتبقي",
            "الفعلي",
        ],
        rows=rows,
    )


@extras_portal_login_required
def portal_finance_export_pdf(request: HttpRequest) -> HttpResponse:
    provider = _get_provider_or_403(request)
    section_response = _portal_require_section(provider, PORTAL_SECTION_FINANCE)
    if section_response is not None:
        return section_response
    from apps.core.models import PlatformConfig
    _limit = PlatformConfig.load().export_pdf_max_rows
    qs = ServiceRequest.objects.filter(provider=provider).select_related("client").order_by("-id")[:_limit]

    rows = []
    for r in qs:
        rows.append(
            [
                r.id,
                getattr(r.client, "phone", ""),
                r.get_status_display(),
                r.created_at,
                r.received_amount,
            ]
        )

    return pdf_response(
        filename=f"extras-portal-finance-provider-{provider.id}.pdf",
        title="كشف الحساب",
        headers=["رقم الطلب", "جوال العميل", "الحالة", "التاريخ", "المستلم"],
        rows=rows,
        landscape=True,
    )


@extras_portal_login_required
def portal_invoice_detail(request: HttpRequest, pk: int) -> HttpResponse:
    """تفاصيل طلب / فاتورة واحدة."""
    provider = _get_provider_or_403(request)
    section_response = _portal_require_section(provider, PORTAL_SECTION_FINANCE)
    if section_response is not None:
        return section_response
    sr = ServiceRequest.objects.filter(pk=pk, provider=provider).select_related("client", "subcategory").first()
    if sr is None:
        from django.http import Http404
        raise Http404
    return render(
        request,
        "extras_portal/invoice_detail.html",
        {
            **_portal_shell_context(provider, active_section=PORTAL_SECTION_FINANCE),
            "provider": provider,
            "sr": sr,
        },
    )
