from __future__ import annotations

from datetime import timedelta

from django.contrib import messages
from django.contrib.auth import authenticate, login, logout
from django.db.models import Q, Sum
from django.http import HttpRequest, HttpResponse
from django.shortcuts import redirect, render
from django.utils import timezone

from apps.accounts.models import OTP, User
from apps.accounts.otp import accept_any_otp_code, create_otp, verify_otp
from apps.dashboard.security import is_safe_redirect_url
from apps.dashboard.exports import pdf_response, xlsx_response
from apps.marketplace.models import RequestStatus, ServiceRequest
from apps.messaging.models import Message, Thread
from apps.providers.models import ProviderFollow, ProviderPortfolioLike, ProviderProfile

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
)


def _portal_accept_any_otp_code() -> bool:
    return accept_any_otp_code()


def _client_ip(request: HttpRequest) -> str | None:
    from apps.accounts.otp import client_ip
    return client_ip(request)


def _get_provider_or_403(request: HttpRequest) -> ProviderProfile:
    user = request.user
    if not hasattr(user, "provider_profile"):
        raise PermissionError("not provider")
    return user.provider_profile


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
        return redirect("extras_portal:reports")
    return redirect("extras_portal:login")


def portal_login(request: HttpRequest) -> HttpResponse:
    if getattr(getattr(request, "user", None), "is_authenticated", False) and bool(
        request.session.get(SESSION_PORTAL_OTP_VERIFIED_KEY)
    ):
        return redirect("extras_portal:reports")

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

        return redirect("extras_portal:otp")

    return render(request, "extras_portal/login.html", {"form": form})


def portal_otp(request: HttpRequest) -> HttpResponse:
    if bool(request.session.get(SESSION_PORTAL_OTP_VERIFIED_KEY)) and getattr(
        getattr(request, "user", None), "is_authenticated", False
    ):
        return redirect("extras_portal:reports")

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
                    {"form": form, "phone": portal_user.phone, "dev_accept_any": False},
                )

        login(request, portal_user, backend="django.contrib.auth.backends.ModelBackend")
        request.session[SESSION_PORTAL_OTP_VERIFIED_KEY] = True

        next_url = (request.session.pop(SESSION_PORTAL_NEXT_URL_KEY, "") or "").strip()
        if is_safe_redirect_url(next_url):
            return redirect(next_url)
        return redirect("extras_portal:reports")

    return render(
        request,
        "extras_portal/otp.html",
        {"form": form, "phone": portal_user.phone, "dev_accept_any": _portal_accept_any_otp_code()},
    )


def portal_logout(request: HttpRequest) -> HttpResponse:
    try:
        request.session.pop(SESSION_PORTAL_OTP_VERIFIED_KEY, None)
        request.session.pop(SESSION_PORTAL_LOGIN_USER_ID_KEY, None)
        request.session.pop(SESSION_PORTAL_NEXT_URL_KEY, None)
    except Exception:
        pass
    logout(request)
    return redirect("extras_portal:login")


@extras_portal_login_required
def portal_reports(request: HttpRequest) -> HttpResponse:
    provider = _get_provider_or_403(request)

    qs = ServiceRequest.objects.filter(provider=provider)
    totals = {
        "total_requests": qs.count(),
        "completed_requests": qs.filter(status=RequestStatus.COMPLETED).count(),
        "in_progress_requests": qs.filter(status=RequestStatus.IN_PROGRESS).count(),
        "received_amount": qs.aggregate(v=Sum("received_amount"))["v"] or 0,
    }

    followers_count = ProviderFollow.objects.filter(provider=provider).count()
    likes_count = ProviderPortfolioLike.objects.filter(item__provider=provider).count()

    messages_count = Message.objects.filter(
        Q(thread__request__provider=provider)
        | Q(thread__is_direct=True, thread__participant_1=provider.user)
        | Q(thread__is_direct=True, thread__participant_2=provider.user)
    ).count()

    return render(
        request,
        "extras_portal/reports.html",
        {
            "provider": provider,
            "totals": totals,
            "followers_count": followers_count,
            "likes_count": likes_count,
            "messages_count": messages_count,
        },
    )


@extras_portal_login_required
def portal_reports_export_xlsx(request: HttpRequest) -> HttpResponse:
    provider = _get_provider_or_403(request)
    from apps.core.models import PlatformConfig
    _limit = PlatformConfig.load().export_xlsx_max_rows
    qs = ServiceRequest.objects.filter(provider=provider).select_related("client").order_by("-id")[:_limit]

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
    from apps.core.models import PlatformConfig
    _limit = PlatformConfig.load().export_pdf_max_rows
    qs = ServiceRequest.objects.filter(provider=provider).select_related("client").order_by("-id")[:_limit]
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
    provider_user = provider.user

    clients_qs = (
        User.objects.filter(requests__provider=provider)
        .distinct()
        .order_by("-id")
    )
    clients = list(clients_qs[:500])

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
            "provider": provider,
            "clients": clients,
            "form": form,
        },
    )


@extras_portal_login_required
def portal_finance(request: HttpRequest) -> HttpResponse:
    provider = _get_provider_or_403(request)

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

    return render(
        request,
        "extras_portal/finance.html",
        {
            "provider": provider,
            "finance_settings": settings_obj,
            "form": form,
            "statement": statement,
            "since_days": since_days,
            "totals": totals,
        },
    )


@extras_portal_login_required
def portal_finance_export_xlsx(request: HttpRequest) -> HttpResponse:
    provider = _get_provider_or_403(request)
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
    sr = ServiceRequest.objects.filter(pk=pk, provider=provider).select_related("client", "subcategory").first()
    if sr is None:
        from django.http import Http404
        raise Http404
    return render(
        request,
        "extras_portal/invoice_detail.html",
        {"provider": provider, "sr": sr},
    )
