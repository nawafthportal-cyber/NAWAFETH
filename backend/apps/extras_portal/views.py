from __future__ import annotations

from datetime import datetime, time, timedelta

from django.core.cache import cache
from django.contrib import messages
from django.contrib.auth import authenticate, login, logout
from django.db.models import Count, Exists, OuterRef, Q, Sum
from django.http import HttpRequest, HttpResponse
from django.shortcuts import redirect, render
from django.utils import timezone
from django.utils.dateparse import parse_date, parse_datetime

from apps.accounts.models import OTP, User
from apps.accounts.otp import accept_any_otp_code, create_otp, verify_otp
from apps.analytics.models import AnalyticsEvent
from apps.dashboard.security import is_safe_redirect_url
from apps.dashboard.exports import pdf_response, xlsx_response
from apps.extras.option_catalog import (
    EXTRAS_REPORT_OPTIONS,
    UNAVAILABLE_CLIENT_OPTIONS,
    UNAVAILABLE_FINANCE_OPTIONS,
    option_label_for,
    section_title_for,
)
from apps.extras.services import (
    _extras_bundle_section_access_deadline,
    extras_bundle_invoice_for_request,
    extras_bundle_payload_for_request,
)
from apps.marketplace.models import PRE_EXECUTION_REQUEST_STATUSES, RequestStatus, ServiceRequest
from apps.messaging.models import Message, Thread
from apps.providers.models import (
    ProviderContentComment,
    ProviderContentShare,
    ProviderFollow,
    ProviderLike,
    ProviderPortfolioLike,
    ProviderProfile,
    ProviderSpotlightLike,
)
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
    ClientRecord,
    ExtrasPortalFinanceSettings,
    ExtrasPortalScheduledMessage,
    ExtrasPortalScheduledMessageRecipient,
    ExtrasPortalSubscription,
    ExtrasPortalSubscriptionStatus,
    LoyaltyMembership,
    LoyaltyProgram,
    ProviderPotentialClient,
    ReportDataSnapshot,
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
    for bundle_context in _portal_paid_bundle_contexts(provider):
        request_obj = bundle_context["request_obj"]
        bundle = bundle_context["bundle"]

        section_option_keys: dict[str, list[str]] = {}
        enabled_sections: list[dict[str, object]] = []
        for section_key in PORTAL_SECTION_ORDER:
            if not _portal_section_context_is_active(bundle_context, section_key):
                continue
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
            "invoice": bundle_context["invoice"],
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


def _portal_provider_identifiers(provider: ProviderProfile) -> list[str]:
    identifiers: list[str] = []
    for raw_value in (
        getattr(provider.user, "username", None),
        getattr(provider.user, "phone", None),
        getattr(provider, "display_name", None),
    ):
        value = str(raw_value or "").strip()
        if value and value not in identifiers:
            identifiers.append(value)
    return identifiers


def _portal_section_payload(section_context: dict[str, object] | None) -> dict[str, object]:
    payload = section_context.get("section_payload") if isinstance(section_context, dict) else None
    return payload if isinstance(payload, dict) else {}


def _portal_section_option_keys(section_context: dict[str, object] | None) -> list[str]:
    if not isinstance(section_context, dict):
        return []
    return [str(key or "").strip() for key in list(section_context.get("option_keys") or []) if str(key or "").strip()]


def _portal_section_has_option(section_context: dict[str, object] | None, option_key: str) -> bool:
    normalized = str(option_key or "").strip()
    if not normalized:
        return False
    return normalized in set(_portal_section_option_keys(section_context))


def _portal_safe_int(value, default: int = 0, *, minimum: int | None = None) -> int:
    try:
        parsed = int(value)
    except Exception:
        parsed = default
    if minimum is not None and parsed < minimum:
        return minimum
    return parsed


def _portal_bundle_requests_queryset(provider: ProviderProfile):
    identifiers = _portal_provider_identifiers(provider)
    return (
        UnifiedRequest.objects.select_related("metadata_record", "requester")
        .filter(
            request_type=UnifiedRequestType.EXTRAS,
            status="closed",
            source_model__in=["ExtrasBundleRequest", "ExtrasServiceRequest"],
        )
        .filter(
            Q(requester=provider.user)
            | Q(metadata_record__payload__specialist_identifier__in=identifiers)
            | Q(metadata_record__payload__specialist_label__in=identifiers)
        )
        .order_by("-updated_at", "-id")
    )


def _portal_paid_bundle_contexts(provider: ProviderProfile) -> list[dict[str, object]]:
    contexts: list[dict[str, object]] = []
    for request_obj in _portal_bundle_requests_queryset(provider):
        bundle = extras_bundle_payload_for_request(request_obj)
        if not bundle:
            continue

        invoice = extras_bundle_invoice_for_request(request_obj)
        if invoice is None or not invoice.is_payment_effective():
            continue

        effective_at = (
            getattr(invoice, "payment_confirmed_at", None)
            or getattr(invoice, "paid_at", None)
            or getattr(request_obj, "closed_at", None)
            or getattr(request_obj, "updated_at", None)
            or getattr(request_obj, "created_at", None)
        )
        contexts.append(
            {
                "request_obj": request_obj,
                "bundle": bundle,
                "invoice": invoice,
                "effective_at": effective_at,
            }
        )
    contexts.sort(
        key=lambda item: (
            item.get("effective_at") or timezone.make_aware(datetime.min, timezone.get_current_timezone()),
            getattr(item.get("request_obj"), "id", 0) or 0,
        ),
        reverse=True,
    )
    return contexts


def _portal_section_context_is_active(bundle_context: dict[str, object], section_key: str, *, now=None) -> bool:
    if not isinstance(bundle_context, dict):
        return False
    bundle = bundle_context.get("bundle") if isinstance(bundle_context.get("bundle"), dict) else {}
    section_payload = bundle.get(section_key) if isinstance(bundle.get(section_key), dict) else {}
    option_keys = [str(key or "").strip() for key in list(section_payload.get("options") or []) if str(key or "").strip()]
    if not option_keys:
        return False

    active_until = _extras_bundle_section_access_deadline(
        section_key,
        bundle,
        bundle_context.get("effective_at") or timezone.now(),
    )
    if active_until is None:
        return True
    return active_until > (now or timezone.now())


def _latest_portal_section_context(provider: ProviderProfile, section_key: str) -> dict[str, object]:
    for bundle_context in _portal_paid_bundle_contexts(provider):
        if not _portal_section_context_is_active(bundle_context, section_key):
            continue
        request_obj = bundle_context["request_obj"]
        bundle = bundle_context["bundle"]
        section_payload = bundle.get(section_key) if isinstance(bundle.get(section_key), dict) else {}
        option_keys = [
            str(key or "").strip()
            for key in list(section_payload.get("options") or [])
            if str(key or "").strip()
        ]
        if not option_keys:
            continue

        return {
            "request_obj": request_obj,
            "bundle": bundle,
            "invoice": bundle_context["invoice"],
            "effective_at": bundle_context.get("effective_at"),
            "section_key": section_key,
            "section_payload": section_payload,
            "option_keys": option_keys,
            "option_labels": [option_label_for(section_key, key) for key in option_keys],
            "section_label": section_title_for(section_key),
        }

    return {
        "request_obj": None,
        "bundle": {},
        "invoice": None,
        "effective_at": None,
        "section_key": section_key,
        "section_payload": {},
        "option_keys": [],
        "option_labels": [],
        "section_label": section_title_for(section_key),
    }


def _portal_shell_context(provider: ProviderProfile, *, active_section: str) -> dict[str, object]:
    section_contexts = {
        section_key: _latest_portal_section_context(provider, section_key)
        for section_key in PORTAL_SECTION_ORDER
    }
    bundle_context = _latest_portal_bundle_context(provider)
    active_section_context = section_contexts.get(active_section) or {
        "request_obj": None,
        "option_keys": [],
        "option_labels": [],
        "section_label": section_title_for(active_section),
    }
    portal_subscription = getattr(provider, "extras_portal_subscription", None)
    portal_subscription_active = _portal_subscription_is_active(portal_subscription)
    nav_items = []
    enabled_sections = []
    section_option_keys: dict[str, list[str]] = {}
    for section_key in PORTAL_SECTION_ORDER:
        section_context = section_contexts[section_key]
        option_keys = list(section_context.get("option_keys") or [])
        if not option_keys:
            continue
        section_option_keys[section_key] = option_keys
        enabled_sections.append(
            {
                "key": section_key,
                "label": section_context.get("section_label") or section_title_for(section_key),
                "option_count": len(option_keys),
                "option_labels": list(section_context.get("option_labels") or []),
            }
        )
        url_name = PORTAL_SECTION_URL_NAME.get(section_key)
        if not url_name:
            continue
        nav_items.append(
            {
                "key": section_key,
                "label": section_context.get("section_label") or section_title_for(section_key),
                "option_count": len(option_keys),
                "url_name": url_name,
                "active": section_key == active_section,
            }
        )

    if enabled_sections:
        bundle_context["enabled_sections"] = enabled_sections
        bundle_context["section_option_keys"] = section_option_keys

    current_request_obj = active_section_context.get("request_obj") or bundle_context.get("request_obj")

    return {
        "portal_bundle_context": bundle_context,
        "portal_section_contexts": section_contexts,
        "portal_current_section_context": active_section_context,
        "portal_current_request_obj": current_request_obj,
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

        login(request, user, backend="django.contrib.auth.backends.ModelBackend")
        request.session[SESSION_PORTAL_OTP_VERIFIED_KEY] = True

        next_url = (request.session.pop(SESSION_PORTAL_NEXT_URL_KEY, "") or "").strip()
        if is_safe_redirect_url(next_url):
            return redirect(next_url)
        return _portal_redirect_first_enabled_section(user.provider_profile)

    return render(
        request,
        "extras_portal/login.html",
        {"form": form},
    )


def portal_otp(request: HttpRequest) -> HttpResponse:
    """OTP is no longer required — redirect to login or home."""
    if getattr(getattr(request, "user", None), "is_authenticated", False):
        try:
            provider = _get_provider_or_403(request)
        except PermissionError:
            return redirect("extras_portal:login")
        return _portal_redirect_first_enabled_section(provider)
    return redirect("extras_portal:login")


def portal_resend_otp(request: HttpRequest) -> HttpResponse:
    """OTP is no longer required — redirect to login."""
    return redirect("extras_portal:login")


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
    {
        "title": "تفاصيل طلبات الخدمة",
        "description": "القائمة التفصيلية لطلبات الخدمة المقدمة خلال الفترة المعتمدة.",
        "keys": (
            "service_orders_detail",
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
        "badge": "قيد التطوير",
        "badge_class": "bg-amber-100 text-amber-700",
        "accent_class": "bg-amber-100 text-amber-700",
        "wide": False,
        "placeholder_text": "هذا الخيار قيد التطوير وسيتم إتاحته قريباً. لن يتم احتساب رسوم عليه حتى يصبح جاهزاً.",
        "helper_text": helper_text,
    }


def _detail_list_card(*, key: str, label: str, rows: list[dict[str, str]], total_count: int, helper_text: str, columns: list[dict[str, str]]) -> dict[str, object]:
    table_rows = []
    for row in rows:
        table_rows.append([row.get(col["key"], "") for col in columns])
    return {
        "key": key,
        "title": label,
        "kind": "detail_list",
        "badge": f"{max(0, int(total_count or 0))} طلب",
        "badge_class": "bg-purple-100 text-purple-700",
        "accent_class": "bg-purple-100 text-purple-700",
        "wide": True,
        "table_rows": table_rows,
        "columns": columns,
        "total_count": total_count,
        "helper_text": helper_text,
        "empty_message": "لا توجد طلبات خدمة ضمن الفترة المحددة.",
    }


def _build_service_orders_detail_rows(requests_qs) -> list[dict[str, str]]:
    rows = []
    for r in requests_qs[:500]:
        client_name = ""
        if getattr(r, "client", None):
            first = str(getattr(r.client, "first_name", "") or "").strip()
            last = str(getattr(r.client, "last_name", "") or "").strip()
            username = str(getattr(r.client, "username", "") or "").strip()
            client_name = " ".join(part for part in [first, last] if part).strip() or (f"@{username}" if username else f"#{r.client_id}")
        rows.append({
            "client_name": client_name,
            "created_at": r.created_at.strftime("%Y-%m-%d %H:%M") if r.created_at else "-",
            "title": str(r.title or ""),
            "expected_delivery_at": r.expected_delivery_at.strftime("%Y-%m-%d %H:%M") if getattr(r, "expected_delivery_at", None) else "-",
            "estimated_service_amount": str(getattr(r, "estimated_service_amount", None) or "-"),
            "received_amount": str(getattr(r, "received_amount", None) or "-"),
            "remaining_amount": str(getattr(r, "remaining_amount", None) or "-"),
            "status": str(r.get_status_display() if hasattr(r, "get_status_display") else r.status),
            "delivered_at": r.delivered_at.strftime("%Y-%m-%d %H:%M") if getattr(r, "delivered_at", None) else "-",
            "actual_service_amount": str(getattr(r, "actual_service_amount", None) or "-"),
            "canceled_at": r.canceled_at.strftime("%Y-%m-%d %H:%M") if getattr(r, "canceled_at", None) else "-",
            "cancel_reason": str(getattr(r, "cancel_reason", "") or "-"),
        })
    return rows


SERVICE_ORDERS_DETAIL_COLUMNS = [
    {"key": "client_name", "label": "اسم العميل"},
    {"key": "created_at", "label": "تاريخ الطلب"},
    {"key": "title", "label": "عنوان الطلب"},
    {"key": "expected_delivery_at", "label": "موعد التسليم المتوقع"},
    {"key": "estimated_service_amount", "label": "قيمة الخدمة المقدرة"},
    {"key": "received_amount", "label": "المبلغ المستلم"},
    {"key": "remaining_amount", "label": "المبلغ المتبقي"},
    {"key": "status", "label": "حالة الطلب"},
    {"key": "delivered_at", "label": "موعد التسليم الفعلي"},
    {"key": "actual_service_amount", "label": "قيمة الخدمة الفعلية"},
    {"key": "canceled_at", "label": "تاريخ الإلغاء"},
    {"key": "cancel_reason", "label": "سبب الإلغاء"},
]


def _reports_bundle_context_from_section_context(section_context: dict[str, object] | None) -> dict[str, object]:
    section_context = section_context if isinstance(section_context, dict) else {}
    request_obj = section_context.get("request_obj")
    bundle = section_context.get("bundle") if isinstance(section_context.get("bundle"), dict) else {}
    reports_section = section_context.get("section_payload") if isinstance(section_context.get("section_payload"), dict) else {}
    selected_option_keys = [
        key
        for key in list(section_context.get("option_keys", []) or [])
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
            "invoice": section_context.get("invoice"),
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


def _all_reports_bundle_contexts(provider: ProviderProfile) -> list[dict[str, object]]:
    contexts: list[dict[str, object]] = []
    for bundle_context in _portal_paid_bundle_contexts(provider):
        if not _portal_section_context_is_active(bundle_context, PORTAL_SECTION_REPORTS):
            continue
        reports_section = bundle_context["bundle"].get(PORTAL_SECTION_REPORTS)
        if not isinstance(reports_section, dict):
            continue
        option_keys = [
            str(key or "").strip()
            for key in list(reports_section.get("options") or [])
            if str(key or "").strip()
        ]
        if not option_keys:
            continue
        contexts.append(
            _reports_bundle_context_from_section_context(
                {
                    "request_obj": bundle_context["request_obj"],
                    "bundle": bundle_context["bundle"],
                    "invoice": bundle_context["invoice"],
                    "section_payload": reports_section,
                    "option_keys": option_keys,
                }
            )
        )
    return contexts


def _latest_reports_bundle_context(provider: ProviderProfile) -> dict[str, object]:
    contexts = _all_reports_bundle_contexts(provider)
    if contexts:
        return contexts[0]
    return _reports_bundle_context_from_section_context({})


def _report_bundle_context_for_request(provider: ProviderProfile, request_id_raw) -> dict[str, object]:
    contexts = _all_reports_bundle_contexts(provider)
    request_id_text = str(request_id_raw or "").strip()
    if request_id_text.isdigit():
        request_id = int(request_id_text)
        for context in contexts:
            if getattr(context.get("request_obj"), "id", None) == request_id:
                return context
    if contexts:
        return contexts[0]
    return _reports_bundle_context_from_section_context({})


def _report_option_card_catalog(provider: ProviderProfile, *, start_at=None, end_at=None) -> dict[str, object]:
    requests_qs = _apply_datetime_window(
        ServiceRequest.objects.filter(provider=provider).select_related("client"),
        "created_at",
        start_at,
        end_at,
    )
    profile_view_events_qs = _apply_datetime_window(
        AnalyticsEvent.objects.filter(
            event_name="provider.profile_view",
            object_id=str(getattr(provider, "pk", "") or ""),
        ),
        "occurred_at",
        start_at,
        end_at,
    )
    follows_qs = _apply_datetime_window(
        ProviderFollow.objects.filter(provider=provider).select_related("user").order_by("-created_at"),
        "created_at",
        start_at,
        end_at,
    )
    portfolio_likes_qs = _apply_datetime_window(
        ProviderPortfolioLike.objects.filter(item__provider=provider).select_related("user").order_by("-created_at"),
        "created_at",
        start_at,
        end_at,
    )
    provider_likes_qs = _apply_datetime_window(
        ProviderLike.objects.filter(provider=provider).select_related("user").order_by("-created_at"),
        "created_at",
        start_at,
        end_at,
    )
    spotlight_likes_qs = _apply_datetime_window(
        ProviderSpotlightLike.objects.filter(item__provider=provider).select_related("user").order_by("-created_at"),
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
        ).exclude(
            is_system_generated=True,
        ).exclude(
            sender=provider.user,
        ),
        "created_at",
        start_at,
        end_at,
    )

    totals = {
        "total_requests": requests_qs.count(),
        "new_requests": requests_qs.filter(status__in=PRE_EXECUTION_REQUEST_STATUSES).count(),
        "completed_requests": requests_qs.filter(status=RequestStatus.COMPLETED).count(),
        "in_progress_requests": requests_qs.filter(status=RequestStatus.IN_PROGRESS).count(),
        "cancelled_requests": requests_qs.filter(status=RequestStatus.CANCELLED).count(),
        "received_amount": requests_qs.aggregate(v=Sum("received_amount"))["v"] or 0,
    }
    platform_visits = profile_view_events_qs.count()
    followers_count = follows_qs.count()
    likes_count = portfolio_likes_qs.count() + provider_likes_qs.count() + spotlight_likes_qs.count()
    messages_count = messages_qs.count()

    requesters_preview = _make_identity_entries([row.client for row in requests_qs[:20] if getattr(row, "client", None)])
    likes_preview = _make_identity_entries(
        [row.user for row in portfolio_likes_qs[:20] if getattr(row, "user", None)]
        + [row.user for row in provider_likes_qs[:20] if getattr(row, "user", None)]
        + [row.user for row in spotlight_likes_qs[:20] if getattr(row, "user", None)]
    )
    followers_preview = _make_identity_entries([row.user for row in follows_qs[:20] if getattr(row, "user", None)])
    positive_reviews_qs = reviews_qs.filter(rating__gte=4)
    positive_reviewers_preview = _make_identity_entries(
        [row.client for row in positive_reviews_qs[:20] if getattr(row, "client", None)]
    )

    shares_qs = _apply_datetime_window(
        ProviderContentShare.objects.filter(provider=provider).select_related("user").order_by("-created_at"),
        "created_at",
        start_at,
        end_at,
    )
    shares_count = shares_qs.count()
    sharers_preview = _make_identity_entries(
        [row.user for row in shares_qs[:20] if getattr(row, "user", None)]
    )
    sharers_distinct_count = shares_qs.exclude(user=None).values("user_id").distinct().count()

    potential_clients_qs = _apply_datetime_window(
        ProviderPotentialClient.objects.filter(provider=provider).select_related("user").order_by("-created_at"),
        "created_at",
        start_at,
        end_at,
    )
    potential_clients_preview = _make_identity_entries(
        [row.user for row in potential_clients_qs[:20] if getattr(row, "user", None)]
    )
    potential_clients_distinct_count = potential_clients_qs.exclude(user=None).values("user_id").distinct().count()

    comments_qs = _apply_datetime_window(
        ProviderContentComment.objects.filter(provider=provider, is_approved=True).select_related("user").order_by("-created_at"),
        "created_at",
        start_at,
        end_at,
    )
    commenters_preview = _make_identity_entries(
        [row.user for row in comments_qs[:20] if getattr(row, "user", None)]
    )
    commenters_distinct_count = comments_qs.exclude(user=None).values("user_id").distinct().count()

    favoriters_user_ids = set(
        portfolio_likes_qs.exclude(user=None).values_list("user_id", flat=True).distinct()
    ) | set(
        provider_likes_qs.exclude(user=None).values_list("user_id", flat=True).distinct()
    ) | set(
        spotlight_likes_qs.exclude(user=None).values_list("user_id", flat=True).distinct()
    )
    favoriters_distinct_count = len(favoriters_user_ids)

    option_cards_by_key: dict[str, dict[str, object]] = {
        "platform_metrics": _stats_card(
            key="platform_metrics",
            label=option_label_for("reports", "platform_metrics"),
            wide=True,
            helper_text="ملخص مؤشرات منصتك الأساسية للفترة المعتمدة في هذا الطلب وفق التنسيق التشغيلي المعتمد.",
            stats=[
                {"label": "زيارات منصتي", "value": str(platform_visits)},
                {"label": "عدد التفضيلات لمحتوى منصتي", "value": str(likes_count)},
                {"label": "عدد مرات مشاركة منصتي", "value": str(shares_count)},
                {"label": "عدد الطلبات الجديدة", "value": str(totals["new_requests"])},
                {"label": "عدد الطلبات تحت التنفيذ", "value": str(totals["in_progress_requests"])},
                {"label": "عدد الطلبات المكتملة", "value": str(totals["completed_requests"])},
                {"label": "عدد الطلبات الملغية", "value": str(totals["cancelled_requests"])},
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
                {"label": "جديدة", "value": str(totals["new_requests"])},
                {"label": "تحت التنفيذ", "value": str(totals["in_progress_requests"])},
                {"label": "مكتملة", "value": str(totals["completed_requests"])},
                {"label": "ملغاة", "value": str(totals["cancelled_requests"])},
            ],
        ),
        "platform_shares": _stats_card(
            key="platform_shares",
            label=option_label_for("reports", "platform_shares"),
            helper_text="إجمالي عمليات مشاركة ملف مزود الخدمة أو محتواه خلال الفترة المحددة.",
            stats=[{"label": "عدد المشاركات", "value": str(shares_count)}],
        ),
        "service_requesters": _list_card(
            key="service_requesters",
            label=option_label_for("reports", "service_requesters"),
            entries=requesters_preview,
            total_count=requests_qs.exclude(client=None).values("client_id").distinct().count(),
            helper_text="أحدث المعرفات التي قدمت طلبات خدمة إلى مزود الخدمة خلال الفترة المحددة.",
        ),
        "potential_clients": _list_card(
            key="potential_clients",
            label=option_label_for("reports", "potential_clients"),
            entries=potential_clients_preview,
            total_count=potential_clients_distinct_count,
            helper_text="معرفات المستخدمين الذين تم وسمهم كعملاء محتملين لمزود الخدمة خلال الفترة المحددة.",
        ),
        "content_favoriters": _list_card(
            key="content_favoriters",
            label=option_label_for("reports", "content_favoriters"),
            entries=likes_preview,
            total_count=favoriters_distinct_count,
            helper_text="معرفات المستخدمين الذين أضافوا محتوى المنصة إلى التفضيلات.",
        ),
        "platform_followers": _list_card(
            key="platform_followers",
            label=option_label_for("reports", "platform_followers"),
            entries=followers_preview,
            total_count=follows_qs.exclude(user=None).values("user_id").distinct().count(),
            helper_text="المتابعون الظاهرون لمنصتك خلال الفترة المحددة.",
        ),
        "content_sharers": _list_card(
            key="content_sharers",
            label=option_label_for("reports", "content_sharers"),
            entries=sharers_preview,
            total_count=sharers_distinct_count,
            helper_text="معرفات المستخدمين الذين قاموا بمشاركة ملف مزود الخدمة أو محتواه.",
        ),
        "positive_reviewers": _list_card(
            key="positive_reviewers",
            label=option_label_for("reports", "positive_reviewers"),
            entries=positive_reviewers_preview,
            total_count=positive_reviews_qs.exclude(client=None).values("client_id").distinct().count(),
            helper_text="معرفات أصحاب التقييمات الإيجابية (4 نجوم فأعلى) لخدمات مزود الخدمة.",
        ),
        "content_commenters": _list_card(
            key="content_commenters",
            label=option_label_for("reports", "content_commenters"),
            entries=commenters_preview,
            total_count=commenters_distinct_count,
            helper_text="معرفات المستخدمين الذين علقوا على محتوى منصة مزود الخدمة.",
        ),
        "service_orders_detail": _detail_list_card(
            key="service_orders_detail",
            label=option_label_for("reports", "service_orders_detail"),
            rows=_build_service_orders_detail_rows(requests_qs),
            total_count=requests_qs.count(),
            helper_text="القائمة التفصيلية لجميع طلبات الخدمة تتضمن: اسم العميل، تاريخ الطلب، عنوان الطلب، موعد التسليم المتوقع، قيمة الخدمة المقدرة، المبلغ المستلم، المبلغ المتبقي، حالة الطلب، موعد التسليم الفعلي، قيمة الخدمة الفعلية، تاريخ الإلغاء، سبب الإلغاء.",
            columns=SERVICE_ORDERS_DETAIL_COLUMNS,
        ),
    }

    return {
        "option_cards_by_key": option_cards_by_key,
        "totals": totals,
        "platform_visits": platform_visits,
        "followers_count": followers_count,
        "likes_count": likes_count,
        "messages_count": messages_count,
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
    report_bundle_contexts = _all_reports_bundle_contexts(provider)
    bundle_context = report_bundle_contexts[0] if report_bundle_contexts else _reports_bundle_context_from_section_context({})
    shell_context = _portal_shell_context(provider, active_section=PORTAL_SECTION_REPORTS)
    start_at = bundle_context.get("start_at")
    end_at = bundle_context.get("end_at")

    portal_subscription = getattr(provider, "extras_portal_subscription", None)
    subscription_is_active = bool(
        portal_subscription
        and portal_subscription.status == ExtrasPortalSubscriptionStatus.ACTIVE
        and (portal_subscription.ends_at is None or portal_subscription.ends_at > timezone.now())
    )

    latest_option_catalog = _report_option_card_catalog(provider, start_at=start_at, end_at=end_at)
    totals = latest_option_catalog["totals"]
    platform_visits = latest_option_catalog["platform_visits"]
    followers_count = latest_option_catalog["followers_count"]
    likes_count = latest_option_catalog["likes_count"]
    messages_count = latest_option_catalog["messages_count"]
    platform_metrics_stats = latest_option_catalog["option_cards_by_key"]["platform_metrics"]["stats"]

    report_request_summaries: list[dict[str, object]] = []
    report_request_groups: list[dict[str, object]] = []
    selected_option_rows: list[dict[str, object]] = []

    visible_report_contexts = report_bundle_contexts[:1]

    for report_context in visible_report_contexts:
        request_obj = report_context.get("request_obj")
        request_id = getattr(request_obj, "id", None)
        request_code = getattr(request_obj, "code", "") or "-"
        invoice = report_context.get("invoice")
        payment_confirmed_at = (
            getattr(invoice, "payment_confirmed_at", None)
            or getattr(invoice, "paid_at", None)
            or getattr(request_obj, "updated_at", None)
        )

        report_request_summaries.append(
            {
                "request_id": request_id,
                "request_code": request_code,
                "payment_confirmed_label": _format_datetime_label(payment_confirmed_at),
                "start_label": report_context.get("start_label", "-"),
                "end_label": report_context.get("end_label", "-"),
                "option_count": len(report_context.get("selected_option_keys", [])),
                "option_labels": list(report_context.get("selected_option_labels", [])),
            }
        )

        option_catalog = _report_option_card_catalog(
            provider,
            start_at=report_context.get("start_at"),
            end_at=report_context.get("end_at"),
        )
        option_cards_by_key = option_catalog["option_cards_by_key"]

        try:
            _save_report_snapshots(provider, report_context, option_catalog)
        except Exception:
            pass

        option_groups: list[dict[str, object]] = []
        for group in REPORT_OPTION_GROUPS:
            cards = [
                option_cards_by_key[key]
                for key in group["keys"]
                if key in report_context.get("selected_option_keys", []) and key in option_cards_by_key
            ]
            if cards:
                option_groups.append(
                    {
                        "title": group["title"],
                        "description": group["description"],
                        "cards": cards,
                    }
                )

        report_request_groups.append(
            {
                "request_id": request_id,
                "request_code": request_code,
                "payment_confirmed_label": _format_datetime_label(payment_confirmed_at),
                "start_label": report_context.get("start_label", "-"),
                "end_label": report_context.get("end_label", "-"),
                "option_groups": option_groups,
            }
        )

        for key in report_context.get("selected_option_keys", []):
            card = option_cards_by_key.get(key, {})
            card_kind = str(card.get("kind") or "")
            is_ready = card_kind in {"stats", "list", "detail_list"}
            is_placeholder = card_kind == "placeholder"
            if is_ready:
                row_status = "جاهز للعرض"
                row_status_class = "bg-emerald-100 text-emerald-700"
                row_summary = "تم تفعيل هذا البند داخل اشتراك التقارير الحالي ويجري عرضه وفق الفترة الزمنية المعتمدة."
                row_can_export = True
            elif is_placeholder:
                row_status = "قيد التطوير"
                row_status_class = "bg-amber-100 text-amber-700"
                row_summary = "هذا الخيار قيد التطوير وسيتم إتاحته قريباً. لن يتم احتساب رسوم عليه حتى يصبح جاهزاً."
                row_can_export = False
            else:
                row_status = "مفعّل"
                row_status_class = "bg-sky-100 text-sky-700"
                row_summary = str(card.get("helper_text") or "الخيار مفعّل داخل الاشتراك الحالي.")
                row_can_export = False
            selected_option_rows.append(
                {
                    "key": key,
                    "request_id": request_id,
                    "request_code": request_code,
                    "label": option_label_for(PORTAL_SECTION_REPORTS, key),
                    "status": row_status,
                    "status_class": row_status_class,
                    "summary": row_summary,
                    "can_export": row_can_export,
                    "start_label": report_context.get("start_label", "-"),
                    "end_label": report_context.get("end_label", "-"),
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

    overview_tones = [
        "from-sky-500 to-cyan-500",
        "from-rose-500 to-pink-500",
        "from-amber-500 to-orange-500",
        "from-indigo-500 to-blue-500",
        "from-violet-500 to-fuchsia-500",
        "from-emerald-500 to-teal-500",
        "from-slate-500 to-slate-700",
    ]
    overview_cards = [
        {
            "title": str(stat.get("label") or "-"),
            "value": str(stat.get("value") or "0"),
            "tone": overview_tones[index] if index < len(overview_tones) else "from-slate-500 to-slate-700",
        }
        for index, stat in enumerate(platform_metrics_stats)
    ]

    return {
        **shell_context,
        "provider": provider,
        "bundle_context": bundle_context,
        "report_option_groups": report_request_groups[0]["option_groups"] if report_request_groups else [],
        "report_request_groups": report_request_groups,
        "report_request_summaries": report_request_summaries,
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
        "selected_option_count": len(selected_option_rows),
        "report_request_count": len(report_request_groups),
        "request_code": getattr(bundle_context.get("request_obj"), "code", "") or "-",
        "payment_note": (
            f"تمت آخر عملية سداد رسوم التفعيل بنجاح بتاريخ { _format_datetime_label(payment_confirmed_at) }"
            if invoice is not None and payment_confirmed_at is not None
            else "هذه الصفحة تعرض طلبات التقارير المكتملة والمدفوعة داخل الخدمات الإضافية."
        ),
        "system_note": bundle_context.get("operator_comment")
        or "رسالة النظام: يتم عرض البيانات هنا وفق الطلبات المدفوعة والمغلقة لكل بند تقارير تم تفعيله.",
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
    bundle_context = _report_bundle_context_for_request(provider, request.GET.get("request"))
    qs = (
        _report_requests_queryset(provider, bundle_context).order_by("-id")[:_limit]
        if bundle_context.get("request_obj")
        else ServiceRequest.objects.none()
    )

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
    bundle_context = _report_bundle_context_for_request(provider, request.GET.get("request"))
    qs = (
        _report_requests_queryset(provider, bundle_context).order_by("-id")[:_limit]
        if bundle_context.get("request_obj")
        else ServiceRequest.objects.none()
    )
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


def _save_report_snapshots(provider: ProviderProfile, bundle_context: dict, option_catalog: dict) -> None:
    """Persist a snapshot of each option card's data for the given bundle request."""
    request_obj = bundle_context.get("request_obj")
    if not request_obj:
        return
    unified_request_id = getattr(request_obj, "id", None)
    request_code = str(getattr(request_obj, "code", "") or "")
    start_at = bundle_context.get("start_at")
    end_at = bundle_context.get("end_at")
    option_cards = option_catalog.get("option_cards_by_key", {})

    import json as _json

    for option_key, card in option_cards.items():
        if option_key not in bundle_context.get("selected_option_keys", []):
            continue
        snapshot_data = {}
        kind = card.get("kind")
        if kind == "stats":
            snapshot_data = {"stats": card.get("stats", [])}
        elif kind == "list":
            entries = card.get("entries", [])
            badge_text = str(card.get("badge") or "0")
            try:
                total_count = int(badge_text.split()[0])
            except (ValueError, IndexError):
                total_count = 0
            snapshot_data = {
                "entries": entries,
                "total_count": total_count,
            }
        elif kind == "detail_list":
            snapshot_data = {
                "table_rows": card.get("table_rows", []),
                "columns": card.get("columns", []),
                "total_count": card.get("total_count", 0),
            }
        ReportDataSnapshot.objects.update_or_create(
            provider=provider,
            unified_request_id=unified_request_id,
            option_key=option_key,
            defaults={
                "request_code": request_code,
                "section_key": PORTAL_SECTION_REPORTS,
                "data_json": snapshot_data,
                "start_at": start_at,
                "end_at": end_at,
            },
        )


def _get_option_export_data(provider: ProviderProfile, option_key: str, bundle_context: dict) -> dict:
    """Return export-ready data for a specific option key."""
    start_at = bundle_context.get("start_at")
    end_at = bundle_context.get("end_at")
    catalog = _report_option_card_catalog(provider, start_at=start_at, end_at=end_at)
    card = catalog["option_cards_by_key"].get(option_key, {})
    return card


OPTION_EXPORT_HEADERS_MAP = {
    "service_requesters": (["المعرف", "معرف المستخدم"], lambda e: [e.get("primary", ""), e.get("secondary", "")]),
    "potential_clients": (["المعرف", "معرف المستخدم"], lambda e: [e.get("primary", ""), e.get("secondary", "")]),
    "content_favoriters": (["المعرف", "معرف المستخدم"], lambda e: [e.get("primary", ""), e.get("secondary", "")]),
    "platform_followers": (["المعرف", "معرف المستخدم"], lambda e: [e.get("primary", ""), e.get("secondary", "")]),
    "content_sharers": (["المعرف", "معرف المستخدم"], lambda e: [e.get("primary", ""), e.get("secondary", "")]),
    "positive_reviewers": (["المعرف", "معرف المستخدم"], lambda e: [e.get("primary", ""), e.get("secondary", "")]),
    "content_commenters": (["المعرف", "معرف المستخدم"], lambda e: [e.get("primary", ""), e.get("secondary", "")]),
}


def _get_full_identity_entries(provider, option_key, start_at, end_at):
    """Return full (un-truncated) identity entries for a list-type option."""
    FULL_LIMIT = 5000
    if option_key == "service_requesters":
        qs = _apply_datetime_window(ServiceRequest.objects.filter(provider=provider).select_related("client"), "created_at", start_at, end_at)
        return _make_identity_entries([r.client for r in qs[:FULL_LIMIT] if getattr(r, "client", None)], limit=FULL_LIMIT)
    if option_key == "potential_clients":
        qs = _apply_datetime_window(ProviderPotentialClient.objects.filter(provider=provider).select_related("user").order_by("-created_at"), "created_at", start_at, end_at)
        return _make_identity_entries([r.user for r in qs[:FULL_LIMIT] if getattr(r, "user", None)], limit=FULL_LIMIT)
    if option_key == "content_favoriters":
        portfolio = _apply_datetime_window(ProviderPortfolioLike.objects.filter(item__provider=provider).select_related("user").order_by("-created_at"), "created_at", start_at, end_at)
        provider_l = _apply_datetime_window(ProviderLike.objects.filter(provider=provider).select_related("user").order_by("-created_at"), "created_at", start_at, end_at)
        spotlight_l = _apply_datetime_window(ProviderSpotlightLike.objects.filter(item__provider=provider).select_related("user").order_by("-created_at"), "created_at", start_at, end_at)
        users = [r.user for r in portfolio[:FULL_LIMIT] if getattr(r, "user", None)]
        users += [r.user for r in provider_l[:FULL_LIMIT] if getattr(r, "user", None)]
        users += [r.user for r in spotlight_l[:FULL_LIMIT] if getattr(r, "user", None)]
        return _make_identity_entries(users, limit=FULL_LIMIT)
    if option_key == "platform_followers":
        qs = _apply_datetime_window(ProviderFollow.objects.filter(provider=provider).select_related("user").order_by("-created_at"), "created_at", start_at, end_at)
        return _make_identity_entries([r.user for r in qs[:FULL_LIMIT] if getattr(r, "user", None)], limit=FULL_LIMIT)
    if option_key == "content_sharers":
        qs = _apply_datetime_window(ProviderContentShare.objects.filter(provider=provider).select_related("user").order_by("-created_at"), "created_at", start_at, end_at)
        return _make_identity_entries([r.user for r in qs[:FULL_LIMIT] if getattr(r, "user", None)], limit=FULL_LIMIT)
    if option_key == "positive_reviewers":
        qs = _apply_datetime_window(Review.objects.filter(provider=provider, rating__gte=4).select_related("client").order_by("-created_at"), "created_at", start_at, end_at)
        return _make_identity_entries([r.client for r in qs[:FULL_LIMIT] if getattr(r, "client", None)], limit=FULL_LIMIT)
    if option_key == "content_commenters":
        qs = _apply_datetime_window(ProviderContentComment.objects.filter(provider=provider, is_approved=True).select_related("user").order_by("-created_at"), "created_at", start_at, end_at)
        return _make_identity_entries([r.user for r in qs[:FULL_LIMIT] if getattr(r, "user", None)], limit=FULL_LIMIT)
    return []


@extras_portal_login_required
def portal_report_option_export_xlsx(request: HttpRequest, option_key: str) -> HttpResponse:
    provider = _get_provider_or_403(request)
    section_response = _portal_require_section(provider, PORTAL_SECTION_REPORTS)
    if section_response is not None:
        return section_response

    bundle_context = _report_bundle_context_for_request(provider, request.GET.get("request"))
    if not bundle_context.get("request_obj"):
        return HttpResponse("لا يوجد طلب تقارير مفعّل.", status=404)

    selected_keys = bundle_context.get("selected_option_keys", [])
    if option_key not in selected_keys:
        return HttpResponse("هذا الخيار غير مفعّل في طلبك.", status=403)

    start_at = bundle_context.get("start_at")
    end_at = bundle_context.get("end_at")
    label = option_label_for(PORTAL_SECTION_REPORTS, option_key)

    if option_key == "service_orders_detail":
        qs = _report_requests_queryset(provider, bundle_context).order_by("-id")[:5000]
        detail_rows = _build_service_orders_detail_rows(qs)
        headers = [c["label"] for c in SERVICE_ORDERS_DETAIL_COLUMNS]
        rows = [[r.get(c["key"], "") for c in SERVICE_ORDERS_DETAIL_COLUMNS] for r in detail_rows]
        return xlsx_response(
            filename=f"report-{option_key}-provider-{provider.id}.xlsx",
            sheet_name=label[:31],
            headers=headers,
            rows=rows,
        )

    if option_key in OPTION_EXPORT_HEADERS_MAP:
        hdrs, row_fn = OPTION_EXPORT_HEADERS_MAP[option_key]
        entries = _get_full_identity_entries(provider, option_key, start_at, end_at)
        rows = [row_fn(e) for e in entries]
        return xlsx_response(
            filename=f"report-{option_key}-provider-{provider.id}.xlsx",
            sheet_name=label[:31],
            headers=hdrs,
            rows=rows,
        )

    # Stats-type cards (platform_metrics, platform_visits, etc.)
    card = _get_option_export_data(provider, option_key, bundle_context)
    if card and card.get("kind") == "stats":
        stats = card.get("stats", [])
        headers = ["المؤشر", "القيمة"]
        rows = [[s.get("label", ""), s.get("value", "")] for s in stats]
        return xlsx_response(
            filename=f"report-{option_key}-provider-{provider.id}.xlsx",
            sheet_name=label[:31],
            headers=headers,
            rows=rows,
        )

    return HttpResponse("لا يمكن تصدير هذا الخيار.", status=400)


@extras_portal_login_required
def portal_report_option_export_pdf(request: HttpRequest, option_key: str) -> HttpResponse:
    provider = _get_provider_or_403(request)
    section_response = _portal_require_section(provider, PORTAL_SECTION_REPORTS)
    if section_response is not None:
        return section_response

    bundle_context = _report_bundle_context_for_request(provider, request.GET.get("request"))
    if not bundle_context.get("request_obj"):
        return HttpResponse("لا يوجد طلب تقارير مفعّل.", status=404)

    selected_keys = bundle_context.get("selected_option_keys", [])
    if option_key not in selected_keys:
        return HttpResponse("هذا الخيار غير مفعّل في طلبك.", status=403)

    start_at = bundle_context.get("start_at")
    end_at = bundle_context.get("end_at")
    label = option_label_for(PORTAL_SECTION_REPORTS, option_key)

    if option_key == "service_orders_detail":
        qs = _report_requests_queryset(provider, bundle_context).order_by("-id")[:2000]
        detail_rows = _build_service_orders_detail_rows(qs)
        headers = [c["label"] for c in SERVICE_ORDERS_DETAIL_COLUMNS]
        rows = [[r.get(c["key"], "") for c in SERVICE_ORDERS_DETAIL_COLUMNS] for r in detail_rows]
        return pdf_response(
            filename=f"report-{option_key}-provider-{provider.id}.pdf",
            title=label,
            headers=headers,
            rows=rows,
            landscape=True,
        )

    if option_key in OPTION_EXPORT_HEADERS_MAP:
        hdrs, row_fn = OPTION_EXPORT_HEADERS_MAP[option_key]
        entries = _get_full_identity_entries(provider, option_key, start_at, end_at)
        rows = [row_fn(e) for e in entries]
        return pdf_response(
            filename=f"report-{option_key}-provider-{provider.id}.pdf",
            title=label,
            headers=hdrs,
            rows=rows,
            landscape=False,
        )

    # Stats-type cards (platform_metrics, platform_visits, etc.)
    card = _get_option_export_data(provider, option_key, bundle_context)
    if card and card.get("kind") == "stats":
        stats = card.get("stats", [])
        headers = ["المؤشر", "القيمة"]
        rows = [[s.get("label", ""), s.get("value", "")] for s in stats]
        return pdf_response(
            filename=f"report-{option_key}-provider-{provider.id}.pdf",
            title=label,
            headers=headers,
            rows=rows,
            landscape=False,
        )

    return HttpResponse("لا يمكن تصدير هذا الخيار.", status=400)


@extras_portal_login_required
def portal_clients(request: HttpRequest) -> HttpResponse:
    provider = _get_provider_or_403(request)
    section_response = _portal_require_section(provider, PORTAL_SECTION_CLIENTS)
    if section_response is not None:
        return section_response
    provider_user = provider.user
    section_context = _latest_portal_section_context(provider, PORTAL_SECTION_CLIENTS)
    clients_payload = _portal_section_payload(section_context)
    clients_option_keys = _portal_section_option_keys(section_context)
    clients_option_labels = [
        {
            "text": option_label_for(PORTAL_SECTION_CLIENTS, key),
            "unavailable": key in UNAVAILABLE_CLIENT_OPTIONS,
        }
        for key in clients_option_keys
    ]
    clients_subscription_years = _portal_safe_int(clients_payload.get("subscription_years", 1), default=1, minimum=1)
    bulk_message_limit = _portal_safe_int(clients_payload.get("bulk_message_count", 0), default=0, minimum=0)
    clients_supports_bulk_messages = _portal_section_has_option(section_context, "bulk_messages")

    # ── Date scope from bundle activation ──
    _clients_effective_at = section_context.get("effective_at")
    _clients_deadline = (
        (_clients_effective_at + timedelta(days=365 * clients_subscription_years))
        if _clients_effective_at else None
    )

    # ── Handle POST: save client data OR send bulk message ──
    if request.method == "POST":
        post_action = request.POST.get("action", "")

        # ── Save Data action ──
        if post_action == "save_data":
            _save_client_records(request, provider)
            messages.success(request, "تم حفظ البيانات بنجاح")
            return redirect("extras_portal:clients")

        # ── Loyalty message action ──
        if post_action == "send_loyalty":
            _send_loyalty_message(request, provider, provider_user)
            return redirect("extras_portal:clients")

        # ── Bulk message action (default POST) ──
        if not clients_supports_bulk_messages:
            messages.error(request, "إرسال الرسائل الجماعية غير مفعّل في طلب الخدمات الإضافية الحالي.")
            return redirect("extras_portal:clients")

        form = BulkMessageForm(request.POST, request.FILES)
        if form.is_valid():
            selected_ids = request.POST.getlist("client_ids")
            recipient_ids = [int(i) for i in selected_ids if str(i).isdigit()]

            if not recipient_ids:
                messages.error(request, "اختر عميل واحد على الأقل")
                return redirect("extras_portal:clients")

            recipients = list(
                User.objects.filter(
                    id__in=recipient_ids,
                    requests__provider=provider,
                ).distinct()
            )
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
    else:
        form = BulkMessageForm()

    # ── Build enriched client rows ──
    follower_user_ids = set(
        ProviderFollow.objects.filter(provider=provider).values_list("user_id", flat=True)
    )
    potential_user_ids = set(
        ProviderPotentialClient.objects.filter(provider=provider).values_list("user_id", flat=True)
    )

    # Scope to requests within the subscription date window
    _scoped_requests_qs = ServiceRequest.objects.filter(provider=provider)
    _scoped_requests_qs = _apply_datetime_window(
        _scoped_requests_qs, "created_at", _clients_effective_at, _clients_deadline,
    )

    _scoped_request_filter = Q(requests__provider=provider)
    if _clients_effective_at:
        _scoped_request_filter &= Q(requests__created_at__gte=_clients_effective_at)
    if _clients_deadline:
        _scoped_request_filter &= Q(requests__created_at__lte=_clients_deadline)

    _scoped_count_filter = Q(requests__provider=provider)
    if _clients_effective_at:
        _scoped_count_filter &= Q(requests__created_at__gte=_clients_effective_at)
    if _clients_deadline:
        _scoped_count_filter &= Q(requests__created_at__lte=_clients_deadline)

    clients_qs = (
        User.objects.filter(_scoped_request_filter)
        .distinct()
        .annotate(request_count=Count("requests", filter=_scoped_count_filter))
        .order_by("-id")
    )
    clients_total_count = clients_qs.count()
    clients_with_phone_count = clients_qs.exclude(phone__isnull=True).exclude(phone="").count()
    clients_list = list(clients_qs[:500])
    client_user_ids = [c.id for c in clients_list]

    # Load existing ClientRecord data keyed by user_id
    records_map: dict[int, ClientRecord] = {
        rec.user_id: rec
        for rec in ClientRecord.objects.filter(provider=provider, user_id__in=client_user_ids)
    }

    # Check which clients were previously served (have completed orders in the window)
    _served_qs = ServiceRequest.objects.filter(
        provider=provider,
        status=RequestStatus.COMPLETED,
        client_id__in=client_user_ids,
    )
    _served_qs = _apply_datetime_window(
        _served_qs, "created_at", _clients_effective_at, _clients_deadline,
    )
    served_user_ids = set(
        _served_qs.values_list("client_id", flat=True).distinct()
    )

    enriched_clients = []
    for idx, client in enumerate(clients_list, start=1):
        rec = records_map.get(client.id)
        enriched_clients.append({
            "row_num": idx,
            "user": client,
            "name": _client_display_name(client),
            "previously_served": client.id in served_user_ids,
            "is_follower": client.id in follower_user_ids,
            "is_potential": client.id in potential_user_ids,
            "request_count": getattr(client, "request_count", 0),
            "classification": rec.classification if rec else "",
            "reminder_text": rec.reminder_text if rec else "",
            "reminder_date": str(rec.reminder_date) if rec and rec.reminder_date else "",
            "reminder_time": rec.reminder_time.strftime("%H:%M") if rec and rec.reminder_time else "",
            "reminder_sent": rec.reminder_sent if rec else False,
            "reminder_sent_at": rec.reminder_sent_at if rec else None,
            "loyalty_points_added": rec.loyalty_points_added if rec else 0,
        })

    # ── Messages summary ──
    recent_scheduled_messages_qs = (
        ExtrasPortalScheduledMessage.objects.filter(provider=provider)
        .prefetch_related("recipients")
        .order_by("-created_at")
    )
    sent_messages_count = recent_scheduled_messages_qs.filter(status="sent").count()
    remaining_messages = max(bulk_message_limit - sent_messages_count, 0)

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
        for scheduled in recent_scheduled_messages_qs[:5]
    ]

    # ── Loyalty program ──
    clients_supports_loyalty = _portal_section_has_option(section_context, "loyalty_program")
    loyalty_program = None
    if clients_supports_loyalty:
        loyalty_program, _lp_created = LoyaltyProgram.objects.get_or_create(
            provider=provider,
            defaults={"name": "برنامج الولاء", "points_per_completed_request": 10, "is_active": True},
        )

    # ── Loyalty summary ──
    clients_supports_points = _portal_section_has_option(section_context, "loyalty_points")
    loyalty_summary: dict[str, int] = {"members": 0, "total_earned": 0, "total_redeemed": 0}
    if clients_supports_points and loyalty_program:
        memberships_qs = LoyaltyMembership.objects.filter(program=loyalty_program)
        agg = memberships_qs.aggregate(
            total_earned=Sum("total_earned"),
            total_redeemed=Sum("total_redeemed"),
        )
        loyalty_summary = {
            "members": memberships_qs.count(),
            "total_earned": agg["total_earned"] or 0,
            "total_redeemed": agg["total_redeemed"] or 0,
        }

    # ── Subscription info ──
    subscription = getattr(provider, "extras_portal_subscription", None)
    subscription_end = subscription.ends_at if subscription else None

    return render(
        request,
        "extras_portal/clients.html",
        {
            **_portal_shell_context(provider, active_section=PORTAL_SECTION_CLIENTS),
            "provider": provider,
            "clients_section_context": section_context,
            "clients_option_keys": clients_option_keys,
            "clients_option_labels": clients_option_labels,
            "clients_subscription_years": clients_subscription_years,
            "bulk_message_limit": bulk_message_limit,
            "remaining_messages": remaining_messages,
            "sent_messages_count": sent_messages_count,
            "clients_supports_bulk_messages": clients_supports_bulk_messages,
            "enriched_clients": enriched_clients,
            "clients_total_count": clients_total_count,
            "clients_with_phone_count": clients_with_phone_count,
            "recent_message_rows": recent_message_rows,
            "form": form,
            # loyalty
            "clients_supports_loyalty": clients_supports_loyalty,
            "loyalty_program": loyalty_program,
            "clients_supports_points": clients_supports_points,
            "loyalty_summary": loyalty_summary,
            # subscription
            "subscription_end": subscription_end,
        },
    )


def _client_display_name(user: User) -> str:
    """Return best available display name for a client user."""
    full = f"{user.first_name or ''} {user.last_name or ''}".strip()
    return full or getattr(user, "username", "") or str(user.id)


def _save_client_records(request: HttpRequest, provider: ProviderProfile) -> None:
    """Bulk save classification, reminders and loyalty points from POST."""
    client_ids = request.POST.getlist("record_client_ids")
    for cid_str in client_ids:
        if not cid_str.isdigit():
            continue
        cid = int(cid_str)
        classification = request.POST.get(f"classification_{cid}", "").strip()[:120]
        reminder_text = request.POST.get(f"reminder_text_{cid}", "").strip()[:500]
        reminder_date_str = request.POST.get(f"reminder_date_{cid}", "").strip()
        reminder_time_str = request.POST.get(f"reminder_time_{cid}", "").strip()
        loyalty_pts_str = request.POST.get(f"loyalty_points_{cid}", "0").strip()

        reminder_date = None
        if reminder_date_str:
            parsed = parse_date(reminder_date_str)
            if parsed:
                reminder_date = parsed

        reminder_time = None
        if reminder_time_str:
            try:
                parts = reminder_time_str.split(":")
                reminder_time = time(int(parts[0]), int(parts[1]))
            except (ValueError, IndexError):
                pass

        loyalty_points = 0
        if loyalty_pts_str.isdigit():
            loyalty_points = int(loyalty_pts_str)

        ClientRecord.objects.update_or_create(
            provider=provider,
            user_id=cid,
            defaults={
                "classification": classification,
                "reminder_text": reminder_text,
                "reminder_date": reminder_date,
                "reminder_time": reminder_time,
                "reminder_sent": False,
                "reminder_sent_at": None,
                "loyalty_points_added": loyalty_points,
            },
        )


def _send_loyalty_message(request: HttpRequest, provider: ProviderProfile, provider_user: User) -> None:
    """Send loyalty program message to all clients with loyalty points."""
    loyalty_body = request.POST.get("loyalty_body", "").strip()
    if not loyalty_body:
        messages.error(request, "أدخل نص رسالة الولاء")
        return
    loyalty_send_at_str = request.POST.get("loyalty_send_at", "").strip()
    loyalty_send_at = None
    if loyalty_send_at_str:
        loyalty_send_at = parse_datetime(loyalty_send_at_str)

    # Find clients with loyalty points > 0
    records_with_points = ClientRecord.objects.filter(
        provider=provider,
        loyalty_points_added__gt=0,
    ).select_related("user")
    if not records_with_points.exists():
        messages.error(request, "لا يوجد عملاء بنقاط ولاء")
        return

    recipients = [rec.user for rec in records_with_points]
    scheduled = ExtrasPortalScheduledMessage.objects.create(
        provider=provider,
        body=loyalty_body,
        send_at=loyalty_send_at,
        created_by=request.user,
    )
    ExtrasPortalScheduledMessageRecipient.objects.bulk_create(
        [ExtrasPortalScheduledMessageRecipient(scheduled_message=scheduled, user=u) for u in recipients],
        ignore_conflicts=True,
    )

    if not loyalty_send_at:
        now = timezone.now()
        try:
            for u in recipients:
                thread = _get_or_create_direct_thread(provider_user, u)
                Message.objects.create(
                    thread=thread,
                    sender=provider_user,
                    body=scheduled.body,
                    attachment_type="",
                    attachment_name="",
                    created_at=now,
                )
            scheduled.status = "sent"
            scheduled.sent_at = now
            scheduled.save(update_fields=["status", "sent_at"])
            messages.success(request, "تم إرسال رسالة الولاء")
        except Exception as e:
            scheduled.status = "failed"
            scheduled.error = str(e)[:255]
            scheduled.save(update_fields=["status", "error"])
            messages.error(request, "تعذر إرسال رسالة الولاء")
    else:
        messages.success(request, "تمت جدولة رسالة الولاء")


@extras_portal_login_required
def portal_finance(request: HttpRequest) -> HttpResponse:
    provider = _get_provider_or_403(request)
    section_response = _portal_require_section(provider, PORTAL_SECTION_FINANCE)
    if section_response is not None:
        return section_response
    section_context = _latest_portal_section_context(provider, PORTAL_SECTION_FINANCE)
    finance_payload = _portal_section_payload(section_context)
    finance_option_keys = _portal_section_option_keys(section_context)
    finance_option_labels = [
        {
            "text": option_label_for(PORTAL_SECTION_FINANCE, key),
            "unavailable": key in UNAVAILABLE_FINANCE_OPTIONS,
        }
        for key in finance_option_keys
    ]
    finance_subscription_years = _portal_safe_int(finance_payload.get("subscription_years", 1), default=1, minimum=1)
    supports_bank_qr_registration = _portal_section_has_option(section_context, "bank_qr_registration")
    supports_financial_statement = _portal_section_has_option(section_context, "financial_statement")
    supports_finance_export = _portal_section_has_option(section_context, "finance_export")
    supports_electronic_payments = _portal_section_has_option(section_context, "electronic_payments")
    supports_electronic_invoices = _portal_section_has_option(section_context, "electronic_invoices")

    # Requested account info from the extras bundle payment (operator filled)
    requested_first_name = str(finance_payload.get("qr_first_name") or "").strip()
    requested_last_name = str(finance_payload.get("qr_last_name") or "").strip()
    requested_account_name = " ".join(part for part in [requested_first_name, requested_last_name] if part).strip()
    requested_iban = str(finance_payload.get("iban") or "").strip()

    settings_obj = ExtrasPortalFinanceSettings.objects.filter(provider=provider).first()

    form = FinanceSettingsForm(request.POST or None, request.FILES or None, initial={
        "bank_name": getattr(settings_obj, "bank_name", ""),
        "account_holder_first_name": getattr(settings_obj, "account_holder_first_name", "") or requested_first_name,
        "account_holder_last_name": getattr(settings_obj, "account_holder_last_name", "") or requested_last_name,
        "account_name": getattr(settings_obj, "account_name", "") or requested_account_name,
        "account_number": getattr(settings_obj, "account_number", ""),
        "iban": getattr(settings_obj, "iban", "") or requested_iban,
    })

    if request.method == "POST" and not supports_bank_qr_registration:
        messages.error(request, "بيانات QR والبنك ليست ضمن البنود المفعّلة في طلب الخدمات الإضافية الحالي.")
        return redirect("extras_portal:finance")

    if request.method == "POST" and form.is_valid():
        if not settings_obj:
            settings_obj = ExtrasPortalFinanceSettings(provider=provider)
        settings_obj.bank_name = form.cleaned_data.get("bank_name") or ""
        settings_obj.account_holder_first_name = form.cleaned_data.get("account_holder_first_name") or ""
        settings_obj.account_holder_last_name = form.cleaned_data.get("account_holder_last_name") or ""
        settings_obj.account_name = form.cleaned_data.get("account_name") or ""
        settings_obj.account_number = form.cleaned_data.get("account_number") or ""
        settings_obj.iban = form.cleaned_data.get("iban") or ""
        if form.cleaned_data.get("qr_image") is not None:
            settings_obj.qr_image = form.cleaned_data.get("qr_image")
        settings_obj.save()
        messages.success(request, "تم حفظ الإعدادات")
        return redirect("extras_portal:finance")

    # ── Subscription info ──
    portal_subscription = getattr(provider, "extras_portal_subscription", None)
    subscription_end = getattr(portal_subscription, "ends_at", None)

    # ── Date scope from bundle activation ──
    effective_at = section_context.get("effective_at")
    finance_deadline = (
        (effective_at + timedelta(days=365 * finance_subscription_years))
        if effective_at else None
    )

    # ── Account Statement (كشف حساب شامل) ──
    statement_qs = ServiceRequest.objects.none()
    if supports_financial_statement:
        statement_qs = (
            ServiceRequest.objects.filter(provider=provider)
            .select_related("client")
            .order_by("-created_at")
        )
        statement_qs = _apply_datetime_window(
            statement_qs, "created_at", effective_at, finance_deadline,
        )
    statement = list(statement_qs[:500])

    # Enrich statement rows with client display name
    statement_rows = []
    for r in statement:
        statement_rows.append({
            "id": r.id,
            "client_name": _finance_client_name(r.client),
            "client_phone": getattr(r.client, "phone", "") if r.client else "",
            "created_at": r.created_at,
            "estimated_service_amount": r.estimated_service_amount,
            "received_amount": r.received_amount,
            "remaining_amount": r.remaining_amount,
            "actual_service_amount": r.actual_service_amount,
            "status": r.status,
            "status_display": r.get_status_display(),
            "delivered_at": r.delivered_at,
            "canceled_at": r.canceled_at,
            "cancel_reason": r.cancel_reason or "",
        })

    totals = statement_qs.aggregate(
        received=Sum("received_amount"),
        remaining=Sum("remaining_amount"),
        estimated=Sum("estimated_service_amount"),
        actual=Sum("actual_service_amount"),
    )

    # ── Profile completion ──
    settings_fields = [
        bool(getattr(settings_obj, "bank_name", "").strip()) if settings_obj else False,
        bool(getattr(settings_obj, "account_holder_first_name", "").strip()) if settings_obj else False,
        bool(getattr(settings_obj, "account_holder_last_name", "").strip()) if settings_obj else False,
        bool(getattr(settings_obj, "account_name", "").strip()) if settings_obj else False,
        bool(getattr(settings_obj, "account_number", "").strip()) if settings_obj else False,
        bool(getattr(settings_obj, "iban", "").strip()) if settings_obj else False,
        bool(getattr(settings_obj, "qr_image", None)) if settings_obj else False,
    ]
    finance_profile_completion = int((sum(1 for v in settings_fields if v) / len(settings_fields)) * 100)

    finance_display_values = {
        "bank_name": getattr(settings_obj, "bank_name", "") or "",
        "account_holder_first_name": getattr(settings_obj, "account_holder_first_name", "") or requested_first_name,
        "account_holder_last_name": getattr(settings_obj, "account_holder_last_name", "") or requested_last_name,
        "account_name": getattr(settings_obj, "account_name", "") or requested_account_name,
        "account_number": getattr(settings_obj, "account_number", "") or "",
        "iban": getattr(settings_obj, "iban", "") or requested_iban,
        "qr_image": getattr(settings_obj, "qr_image", None),
    }

    provider_identifier = str(getattr(provider.user, "username", "") or "").strip()
    if provider_identifier:
        provider_identifier = f"@{provider_identifier}"
    else:
        provider_identifier = provider.display_name or str(provider.user.id)

    return render(
        request,
        "extras_portal/finance.html",
        {
            **_portal_shell_context(provider, active_section=PORTAL_SECTION_FINANCE),
            "provider": provider,
            "provider_identifier": provider_identifier,
            "finance_option_labels": finance_option_labels,
            "finance_subscription_years": finance_subscription_years,
            "subscription_end": subscription_end,
            "supports_bank_qr_registration": supports_bank_qr_registration,
            "supports_financial_statement": supports_financial_statement,
            "supports_finance_export": supports_finance_export,
            "supports_electronic_payments": supports_electronic_payments,
            "supports_electronic_invoices": supports_electronic_invoices,
            "finance_display_values": finance_display_values,
            "finance_settings": settings_obj,
            "finance_profile_completion": finance_profile_completion,
            "form": form,
            "statement_rows": statement_rows,
            "statement_count": statement_qs.count(),
            "totals": totals,
        },
    )


def _finance_client_name(client) -> str:
    """Return client display name for finance tables."""
    if not client:
        return "—"
    fn = getattr(client, "first_name", "") or ""
    ln = getattr(client, "last_name", "") or ""
    full = f"{fn} {ln}".strip()
    if full:
        return full
    username = getattr(client, "username", "") or ""
    if username:
        return f"@{username}"
    return getattr(client, "phone", "") or "—"


@extras_portal_login_required
def portal_finance_export_xlsx(request: HttpRequest) -> HttpResponse:
    provider = _get_provider_or_403(request)
    section_response = _portal_require_section(provider, PORTAL_SECTION_FINANCE)
    if section_response is not None:
        return section_response
    section_context = _latest_portal_section_context(provider, PORTAL_SECTION_FINANCE)
    if not _portal_section_has_option(section_context, "finance_export"):
        messages.error(request, "تصدير البيانات المالية غير مفعّل في طلب الخدمات الإضافية الحالي.")
        return redirect("extras_portal:finance")
    from apps.core.models import PlatformConfig
    _limit = PlatformConfig.load().export_xlsx_max_rows

    # ── Date scope from bundle activation ──
    finance_payload = _portal_section_payload(section_context)
    finance_subscription_years = _portal_safe_int(finance_payload.get("subscription_years", 1), default=1, minimum=1)
    effective_at = section_context.get("effective_at")
    finance_deadline = (
        (effective_at + timedelta(days=365 * finance_subscription_years))
        if effective_at else None
    )

    qs = ServiceRequest.objects.filter(provider=provider).select_related("client").order_by("-created_at")
    qs = _apply_datetime_window(qs, "created_at", effective_at, finance_deadline)
    qs = qs[:_limit]

    rows = []
    for r in qs:
        client_name = _finance_client_name(r.client)
        rows.append(
            [
                client_name,
                r.created_at,
                r.estimated_service_amount or 0,
                r.received_amount or 0,
                r.remaining_amount or 0,
                r.actual_service_amount or 0,
                r.get_status_display(),
            ]
        )

    return xlsx_response(
        filename=f"extras-portal-finance-provider-{provider.id}.xlsx",
        sheet_name="كشف حساب شامل",
        headers=[
            "اسم العميل",
            "الوقت والتاريخ",
            "قيمة الخدمة المقدرة",
            "المبلغ المستلم",
            "المبلغ المتبقي",
            "قيمة الخدمة الفعلية",
            "حالة الطلب",
        ],
        rows=rows,
    )


@extras_portal_login_required
def portal_finance_export_pdf(request: HttpRequest) -> HttpResponse:
    provider = _get_provider_or_403(request)
    section_response = _portal_require_section(provider, PORTAL_SECTION_FINANCE)
    if section_response is not None:
        return section_response
    section_context = _latest_portal_section_context(provider, PORTAL_SECTION_FINANCE)
    if not _portal_section_has_option(section_context, "finance_export"):
        messages.error(request, "تصدير البيانات المالية غير مفعّل في طلب الخدمات الإضافية الحالي.")
        return redirect("extras_portal:finance")
    from apps.core.models import PlatformConfig
    _limit = PlatformConfig.load().export_pdf_max_rows

    # ── Date scope from bundle activation ──
    finance_payload = _portal_section_payload(section_context)
    finance_subscription_years = _portal_safe_int(finance_payload.get("subscription_years", 1), default=1, minimum=1)
    effective_at = section_context.get("effective_at")
    finance_deadline = (
        (effective_at + timedelta(days=365 * finance_subscription_years))
        if effective_at else None
    )

    qs = ServiceRequest.objects.filter(provider=provider).select_related("client").order_by("-created_at")
    qs = _apply_datetime_window(qs, "created_at", effective_at, finance_deadline)
    qs = qs[:_limit]

    rows = []
    for r in qs:
        client_name = _finance_client_name(r.client)
        rows.append(
            [
                client_name,
                r.created_at,
                r.estimated_service_amount or 0,
                r.received_amount or 0,
                r.remaining_amount or 0,
                r.actual_service_amount or 0,
                r.get_status_display(),
            ]
        )

    return pdf_response(
        filename=f"extras-portal-finance-provider-{provider.id}.pdf",
        title="كشف حساب شامل",
        headers=[
            "اسم العميل",
            "الوقت والتاريخ",
            "قيمة الخدمة المقدرة",
            "المبلغ المستلم",
            "المبلغ المتبقي",
            "قيمة الخدمة الفعلية",
            "حالة الطلب",
        ],
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
