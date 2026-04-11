from __future__ import annotations

from datetime import datetime, time, timedelta
from decimal import Decimal
from urllib.parse import urlencode, urlsplit

from django.conf import settings
from django.contrib.auth import get_user_model
from django.db import transaction
from django.db.models import Q
from django.urls import reverse
from django.utils import timezone
from django.utils.dateparse import parse_date, parse_datetime

from apps.accounts.models import UserRole
from apps.billing.models import Invoice, InvoiceLineItem, InvoiceStatus, PaymentAttempt, PaymentProvider, money_round

from .models import ExtraPurchase, ExtraPurchaseStatus, ExtraType, ExtrasBundlePricingRule
from .option_catalog import build_summary_sections, option_label_for, section_title_for


def _extra_status_to_unified(status: str) -> str:
    if status == ExtraPurchaseStatus.ACTIVE:
        return "in_progress"
    if status in {
        ExtraPurchaseStatus.CONSUMED,
        ExtraPurchaseStatus.EXPIRED,
        ExtraPurchaseStatus.CANCELLED,
    }:
        return "completed"
    return "new"


def _sync_extra_to_unified(*, purchase: ExtraPurchase, changed_by=None):
    try:
        from apps.unified_requests.services import upsert_unified_request
        from apps.unified_requests.models import UnifiedRequestType
    except Exception:
        return

    upsert_unified_request(
        request_type=UnifiedRequestType.EXTRAS,
        requester=purchase.user,
        source_app="extras",
        source_model="ExtraPurchase",
        source_object_id=purchase.id,
        status=_extra_status_to_unified(purchase.status),
        priority="normal",
        summary=(purchase.title or purchase.sku or "")[:300],
        metadata={
            "purchase_id": purchase.id,
            "sku": purchase.sku,
            "extra_type": purchase.extra_type,
            "purchase_status": purchase.status,
            "invoice_id": purchase.invoice_id,
            "credits_total": purchase.credits_total,
            "credits_used": purchase.credits_used,
            "start_at": purchase.start_at.isoformat() if purchase.start_at else None,
            "end_at": purchase.end_at.isoformat() if purchase.end_at else None,
        },
        assigned_team_code="extras",
        assigned_team_name="الخدمات الإضافية",
        assigned_user=None,
        changed_by=changed_by,
    )


def get_extra_catalog() -> dict:
    """
    كتالوج الإضافات: DB first → fallback settings.EXTRA_SKUS.
    يفوّض إلى billing.pricing للمنطق المركزي.
    """
    from apps.billing.pricing import get_extras_catalog
    return get_extras_catalog()


def _platform_config():
    from apps.core.models import PlatformConfig

    return PlatformConfig.load()


def extras_currency() -> str:
    return str(_platform_config().extras_currency or "SAR").strip() or "SAR"


def sku_info(sku: str) -> dict:
    catalog = get_extra_catalog()
    if sku not in catalog:
        raise ValueError("SKU غير موجود.")
    return catalog[sku]


def infer_extra_type(sku: str) -> str:
    """
    تصنيف بسيط:
    - tickets_* => credits
    - غيره => time_based
    """
    if sku.startswith("tickets_"):
        return ExtraType.CREDIT_BASED
    return ExtraType.TIME_BASED


def infer_duration(sku: str) -> timedelta:
    """
    مدد افتراضية:
    - *_month => 30 يوم
    - *_7d => 7 أيام
    """
    if sku.endswith("_month"):
        return timedelta(days=int(_platform_config().extras_default_duration_days or 30))
    if sku.endswith("_7d"):
        return timedelta(days=int(_platform_config().extras_short_duration_days or 7))
    return timedelta(days=int(_platform_config().extras_default_duration_days or 30))


def infer_credits(sku: str) -> int:
    """
    tickets_100 => 100
    """
    if sku.startswith("tickets_"):
        n = sku.replace("tickets_", "").strip()
        try:
            return int(n)
        except Exception:
            return 0
    return 0


@transaction.atomic
def create_extra_purchase_checkout(*, user, sku: str) -> ExtraPurchase:
    from apps.billing.pricing import calculate_extras_price

    pricing = calculate_extras_price(sku)

    info = sku_info(sku)
    title = info.get("title", sku)
    etype = infer_extra_type(sku)

    purchase = ExtraPurchase.objects.create(
        user=user,
        sku=sku,
        title=title,
        extra_type=etype,
        subtotal=pricing["subtotal"],
        currency=pricing["currency"],
        status=ExtraPurchaseStatus.PENDING_PAYMENT,
    )

    # إعداد credits إن كانت credit-based
    if etype == ExtraType.CREDIT_BASED:
        purchase.credits_total = infer_credits(sku)
        purchase.save(update_fields=["credits_total", "updated_at"])

    inv = Invoice.objects.create(
        user=user,
        title="فاتورة إضافة مدفوعة",
        description=f"{title}",
        currency=pricing["currency"],
        subtotal=pricing["subtotal"],
        vat_percent=pricing["vat_percent"],
        reference_type="extra_purchase",
        reference_id=str(purchase.pk),
        status=InvoiceStatus.DRAFT,
    )
    inv.mark_pending()
    inv.save(update_fields=["status", "subtotal", "vat_percent", "vat_amount", "total", "updated_at"])

    purchase.invoice = inv
    purchase.save(update_fields=["invoice", "updated_at"])
    _sync_extra_to_unified(purchase=purchase, changed_by=user)
    try:
        from apps.analytics.tracking import safe_track_event

        safe_track_event(
            event_name="extras.checkout_created",
            channel="server",
            surface="extras.create_checkout",
            source_app="extras",
            object_type="ExtraPurchase",
            object_id=str(purchase.id),
            actor=user,
            dedupe_key=f"extras.checkout_created:{purchase.id}:{inv.id}",
            payload={
                "sku": purchase.sku,
                "invoice_id": inv.id,
                "status": purchase.status,
                "extra_type": purchase.extra_type,
            },
        )
    except Exception:
        pass
    return purchase


@transaction.atomic
def activate_extra_after_payment(*, purchase: ExtraPurchase) -> ExtraPurchase:
    purchase = ExtraPurchase.objects.select_for_update().get(pk=purchase.pk)

    if not purchase.invoice or purchase.invoice.status != "paid":
        raise ValueError("الفاتورة غير مدفوعة بعد.")

    if purchase.status == ExtraPurchaseStatus.ACTIVE:
        return purchase

    now = timezone.now()

    if purchase.extra_type == ExtraType.TIME_BASED:
        dur = infer_duration(purchase.sku)
        purchase.start_at = now
        purchase.end_at = now + dur
        purchase.status = ExtraPurchaseStatus.ACTIVE
        purchase.save(update_fields=["start_at", "end_at", "status", "updated_at"])
        _sync_extra_to_unified(purchase=purchase, changed_by=purchase.user)
        try:
            from apps.analytics.tracking import safe_track_event

            safe_track_event(
                event_name="extras.activated",
                channel="server",
                surface="extras.activate_after_payment",
                source_app="extras",
                object_type="ExtraPurchase",
                object_id=str(purchase.id),
                actor=purchase.user,
                dedupe_key=f"extras.activated:{purchase.id}:{purchase.status}:{purchase.start_at.isoformat() if purchase.start_at else ''}",
                payload={
                    "sku": purchase.sku,
                    "status": purchase.status,
                    "start_at": purchase.start_at.isoformat() if purchase.start_at else None,
                    "end_at": purchase.end_at.isoformat() if purchase.end_at else None,
                },
            )
        except Exception:
            pass
        return purchase

    # credit based
    if purchase.extra_type == ExtraType.CREDIT_BASED:
        purchase.status = ExtraPurchaseStatus.ACTIVE
        purchase.save(update_fields=["status", "updated_at"])
        _sync_extra_to_unified(purchase=purchase, changed_by=purchase.user)
        try:
            from apps.analytics.tracking import safe_track_event

            safe_track_event(
                event_name="extras.activated",
                channel="server",
                surface="extras.activate_after_payment",
                source_app="extras",
                object_type="ExtraPurchase",
                object_id=str(purchase.id),
                actor=purchase.user,
                dedupe_key=f"extras.activated:{purchase.id}:{purchase.status}",
                payload={
                    "sku": purchase.sku,
                    "status": purchase.status,
                    "credits_total": purchase.credits_total,
                },
            )
        except Exception:
            pass
        return purchase

    _sync_extra_to_unified(purchase=purchase, changed_by=purchase.user)
    return purchase


@transaction.atomic
def consume_credit(*, user, sku: str, amount: int = 1) -> bool:
    """
    استهلاك رصيد من أحدث عملية شراء فعالة للـ SKU (credits)
    """
    if amount <= 0:
        return True

    p = ExtraPurchase.objects.select_for_update().filter(
        user=user,
        sku=sku,
        extra_type=ExtraType.CREDIT_BASED,
        status=ExtraPurchaseStatus.ACTIVE,
    ).order_by("-id").first()

    if not p:
        return False

    if p.credits_left() < amount:
        return False

    p.credits_used += amount
    if p.credits_left() == 0:
        p.status = ExtraPurchaseStatus.CONSUMED

    p.save(update_fields=["credits_used", "status", "updated_at"])
    _sync_extra_to_unified(purchase=p, changed_by=user)
    try:
        from apps.analytics.tracking import safe_track_event

        safe_track_event(
            event_name="extras.credit_consumed",
            channel="server",
            surface="extras.consume_credit",
            source_app="extras",
            object_type="ExtraPurchase",
            object_id=str(p.id),
            actor=user,
            payload={
                "sku": p.sku,
                "amount": amount,
                "credits_used": p.credits_used,
                "credits_left": p.credits_left(),
                "status": p.status,
            },
        )
    except Exception:
        pass
    return True


def user_has_active_extra(user, sku_prefix: str) -> bool:
    """
    فحص وجود Add-on فعال (زمني أو credits) حسب بادئة sku
    """
    now = timezone.now()
    qs = ExtraPurchase.objects.filter(
        user=user,
        sku__startswith=sku_prefix,
        status=ExtraPurchaseStatus.ACTIVE,
    )
    for p in qs.order_by("-id")[:20]:
        if p.extra_type == ExtraType.TIME_BASED:
            if p.start_at and p.end_at and p.start_at <= now < p.end_at:
                return True
        else:
            if p.credits_left() > 0:
                return True
    return False


EXTRAS_BUNDLE_INVOICE_REFERENCE_TYPE = "extras_bundle_request"
EXTRAS_BUNDLE_SYSTEM_THREAD_KEY = "extras_bundle"
EXTRAS_BUNDLE_SOURCE_MODELS = {"ExtrasBundleRequest", "ExtrasServiceRequest"}


def _extras_bundle_find_user_by_identifier(identifier: str):
    normalized_identifier = str(identifier or "").strip()
    if not normalized_identifier:
        return None

    User = get_user_model()
    return (
        User.objects.filter(
            Q(username__iexact=normalized_identifier)
            | Q(phone__iexact=normalized_identifier)
        )
        .order_by("id")
        .first()
    )


def _extras_bundle_thread_mode_for_user(user) -> str:
    from apps.messaging.models import Thread

    if not user or not getattr(user, "id", None):
        return Thread.ContextMode.SHARED

    role_state = str(getattr(user, "role_state", "") or "").strip().lower()
    if role_state == UserRole.PROVIDER:
        return Thread.ContextMode.PROVIDER
    if role_state in {UserRole.CLIENT, UserRole.PHONE_ONLY}:
        return Thread.ContextMode.CLIENT

    try:
        if getattr(user, "provider_profile", None) is not None:
            return Thread.ContextMode.PROVIDER
    except Exception:
        pass
    return Thread.ContextMode.SHARED


def _extras_bundle_is_provider_user(user) -> bool:
    if not user or not getattr(user, "id", None):
        return False

    role_state = str(getattr(user, "role_state", "") or "").strip().lower()
    if role_state == UserRole.PROVIDER:
        return True

    try:
        return getattr(user, "provider_profile", None) is not None
    except Exception:
        return False


def _extras_bundle_specialist_user(request_obj):
    metadata = _extras_bundle_existing_metadata(request_obj)
    for raw_value in (metadata.get("specialist_identifier"), metadata.get("specialist_label")):
        user = _extras_bundle_find_user_by_identifier(str(raw_value or "").strip())
        if user is not None:
            return user
    return None


def _extras_bundle_invoice_user(request_obj):
    requester = getattr(request_obj, "requester", None)
    specialist = _extras_bundle_specialist_user(request_obj)
    return requester or specialist


def _extras_bundle_message_recipients(*, request_obj, invoice: Invoice | None = None) -> list:
    recipients_by_id: dict[int, object] = {}

    def add_recipient(user_obj) -> None:
        user_id = getattr(user_obj, "id", None)
        if user_id:
            recipients_by_id[int(user_id)] = user_obj

    add_recipient(getattr(invoice, "user", None) if invoice is not None else None)
    add_recipient(getattr(request_obj, "requester", None))
    add_recipient(_extras_bundle_specialist_user(request_obj))
    return list(recipients_by_id.values())


def _resolve_bundle_message_sender(*, request_obj, actor, recipient):
    recipient_id = getattr(recipient, "id", None)
    for candidate in (actor, getattr(request_obj, "assigned_user", None)):
        if candidate is None:
            continue
        candidate_id = getattr(candidate, "id", None)
        if candidate_id and candidate_id != recipient_id:
            return candidate

    User = get_user_model()
    return (
        User.objects.filter(is_active=True)
        .filter(Q(is_superuser=True) | Q(is_staff=True))
        .exclude(pk=recipient_id)
        .order_by("-is_superuser", "id")
        .first()
    )


def _extra_bundle_default_payment_provider() -> str:
    configured = str(getattr(settings, "BILLING_DEFAULT_PROVIDER", "") or "").strip().lower()
    if configured in PaymentProvider.values:
        return configured
    return PaymentProvider.MOCK


def _extras_bundle_existing_metadata(request_obj) -> dict:
    try:
        meta_record = request_obj.metadata_record
    except Exception:
        meta_record = None
    payload = getattr(meta_record, "payload", None)
    return dict(payload) if isinstance(payload, dict) else {}


def _extras_bundle_payload_from_metadata(metadata: dict | None) -> dict:
    raw_metadata = metadata if isinstance(metadata, dict) else {}
    bundle = raw_metadata.get("bundle")
    if isinstance(bundle, dict):
        return dict(bundle)

    extracted: dict = {}
    for key in ("reports", "clients", "finance"):
        value = raw_metadata.get(key)
        if isinstance(value, dict):
            extracted[key] = dict(value)
    if isinstance(raw_metadata.get("summary_sections"), list):
        extracted["summary_sections"] = list(raw_metadata.get("summary_sections") or [])
    notes = str(raw_metadata.get("notes") or "").strip()
    if notes:
        extracted["notes"] = notes
    return extracted


def extras_bundle_payload_for_request(request_obj) -> dict:
    if request_obj is None or str(getattr(request_obj, "source_model", "") or "") not in EXTRAS_BUNDLE_SOURCE_MODELS:
        return {}
    return _extras_bundle_payload_from_metadata(_extras_bundle_existing_metadata(request_obj))


def extras_bundle_invoice_for_request(request_obj) -> Invoice | None:
    metadata = _extras_bundle_existing_metadata(request_obj)
    raw_invoice_id = str(metadata.get("invoice_id") or "").strip()
    if raw_invoice_id.isdigit():
        invoice = Invoice.objects.filter(id=int(raw_invoice_id)).first()
        if invoice is not None:
            return invoice

    reference_code = str(getattr(request_obj, "code", "") or "").strip()
    if reference_code:
        return Invoice.objects.filter(reference_type=EXTRAS_BUNDLE_INVOICE_REFERENCE_TYPE, reference_id=reference_code).order_by("-id").first()
    return None


def extras_bundle_payment_access_url(*, request_obj, invoice: Invoice | None = None, checkout_url: str = "") -> str:
    payment_page_url = extras_bundle_payment_page_url(request_obj=request_obj, invoice=invoice)
    if payment_page_url:
        return payment_page_url

    invoice = invoice or extras_bundle_invoice_for_request(request_obj)
    if invoice is None:
        return str(checkout_url or "").strip()

    latest_attempt = (
        PaymentAttempt.objects.filter(invoice=invoice)
        .exclude(checkout_url="")
        .order_by("-created_at")
        .first()
    )
    if latest_attempt is None:
        return str(checkout_url or "").strip()

    access_path = reverse("extras:bundle_payment_link", kwargs={"attempt_id": latest_attempt.id})
    raw_checkout = str(checkout_url or getattr(latest_attempt, "checkout_url", "") or "").strip()
    parsed_checkout = urlsplit(raw_checkout)
    if parsed_checkout.scheme and parsed_checkout.netloc:
        return f"{parsed_checkout.scheme}://{parsed_checkout.netloc}{access_path}"
    return access_path


def extras_bundle_payment_page_url(*, request_obj, invoice: Invoice | None = None) -> str:
    if request_obj is None:
        return ""

    query_params: dict[str, str] = {}
    request_id = getattr(request_obj, "id", None)
    if request_id:
        query_params["request_id"] = str(request_id)

    resolved_invoice = invoice or extras_bundle_invoice_for_request(request_obj)
    invoice_id = getattr(resolved_invoice, "id", None)
    if invoice_id:
        query_params["invoice_id"] = str(invoice_id)

    if not query_params:
        return ""

    try:
        base_path = reverse("additional_services_payment")
    except Exception:
        try:
            base_path = reverse("mobile_web:additional_services_payment")
        except Exception:
            base_path = "/additional-services/payment/"

    return f"{base_path}?{urlencode(query_params)}"


def extras_portal_reports_url() -> str:
    try:
        from django.urls import reverse

        return reverse("extras_portal:reports")
    except Exception:
        return "/portal/extras/reports/"


def _coerce_bundle_datetime(raw_value, *, end_of_day: bool = False):
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


def _extras_bundle_section_access_deadline(section_key: str, bundle: dict, activated_at):
    section = bundle.get(section_key) if isinstance(bundle.get(section_key), dict) else {}
    if not section:
        return None

    if section_key == "reports":
        minimum_deadline = activated_at + timedelta(days=365)
        report_end_at = _coerce_bundle_datetime(section.get("end_at"), end_of_day=True)
        if report_end_at is None:
            return minimum_deadline
        return max(minimum_deadline, report_end_at)

    if section_key in {"clients", "finance"}:
        years = max(1, int(section.get("subscription_years", 1) or 1))
        return activated_at + timedelta(days=365 * years)

    return None


def activate_bundle_portal_subscription_for_request(*, request_obj):
    subscription_user = _extras_bundle_invoice_user(request_obj)
    provider = getattr(subscription_user, "provider_profile", None)
    if provider is None:
        return None

    bundle = extras_bundle_payload_for_request(request_obj)
    if not bundle:
        return None

    enabled_sections: list[str] = []
    desired_deadlines = []
    for section_key in ("reports", "clients", "finance"):
        section = bundle.get(section_key) if isinstance(bundle.get(section_key), dict) else {}
        if not list(section.get("options") or []):
            continue
        enabled_sections.append(section_title_for(section_key))

    if not enabled_sections:
        return None

    invoice = extras_bundle_invoice_for_request(request_obj)
    activated_at = (
        getattr(invoice, "payment_confirmed_at", None)
        or getattr(invoice, "paid_at", None)
        or timezone.now()
    )

    for section_key in ("reports", "clients", "finance"):
        section = bundle.get(section_key) if isinstance(bundle.get(section_key), dict) else {}
        if not list(section.get("options") or []):
            continue
        deadline = _extras_bundle_section_access_deadline(section_key, bundle, activated_at)
        if deadline is not None:
            desired_deadlines.append(deadline)

    from apps.extras_portal.models import ExtrasPortalSubscription, ExtrasPortalSubscriptionStatus

    subscription, _ = ExtrasPortalSubscription.objects.get_or_create(provider=provider)
    update_fields: list[str] = []

    if subscription.status != ExtrasPortalSubscriptionStatus.ACTIVE:
        subscription.status = ExtrasPortalSubscriptionStatus.ACTIVE
        update_fields.append("status")

    plan_title = " / ".join(enabled_sections)
    if subscription.plan_title != plan_title:
        subscription.plan_title = plan_title
        update_fields.append("plan_title")

    if subscription.started_at is None or activated_at < subscription.started_at:
        subscription.started_at = activated_at
        update_fields.append("started_at")

    desired_ends_at = max(desired_deadlines) if desired_deadlines else None
    if desired_ends_at is not None:
        if subscription.ends_at is None or subscription.ends_at < desired_ends_at:
            subscription.ends_at = desired_ends_at
            update_fields.append("ends_at")

    notes = f"آخر تفعيل عبر الطلب {(request_obj.code or request_obj.id)}"
    if subscription.notes != notes:
        subscription.notes = notes
        update_fields.append("notes")

    if update_fields:
        subscription.save(update_fields=update_fields + ["updated_at"])
    return subscription


def _format_bundle_date(raw_value) -> str:
    text = str(raw_value or "").strip()
    if not text:
        return "-"

    parsed_datetime = parse_datetime(text)
    if parsed_datetime is not None:
        if timezone.is_naive(parsed_datetime):
            return parsed_datetime.strftime("%d/%m/%Y")
        return timezone.localtime(parsed_datetime).strftime("%d/%m/%Y")

    parsed_date = parse_date(text)
    if parsed_date is not None:
        return parsed_date.strftime("%d/%m/%Y")
    return text


def _bundle_duration_label(section_key: str, bundle: dict) -> str:
    section = bundle.get(section_key) if isinstance(bundle.get(section_key), dict) else {}
    if section_key == "reports":
        start_label = _format_bundle_date(section.get("start_at"))
        end_label = _format_bundle_date(section.get("end_at"))
        if start_label != "-" and end_label != "-":
            return f"من {start_label} إلى {end_label}"
        if start_label != "-":
            return f"من {start_label}"
        if end_label != "-":
            return f"حتى {end_label}"
        return "-"

    if section_key in {"clients", "finance"}:
        years = max(1, int(section.get("subscription_years", 1) or 1))
        return f"{years} سنة"

    return "-"


def extras_bundle_detail_sections(bundle: dict | None) -> list[dict]:
    normalized_bundle = bundle if isinstance(bundle, dict) else {}
    sections: list[dict] = []
    for section_key in ("reports", "clients", "finance"):
        section = normalized_bundle.get(section_key) if isinstance(normalized_bundle.get(section_key), dict) else {}
        selected_options = list(section.get("options") or [])
        if not selected_options:
            continue
        duration_label = _bundle_duration_label(section_key, normalized_bundle)
        items = [
            {
                "title": option_label_for(section_key, option_key),
                "duration": duration_label,
            }
            for option_key in selected_options
        ]
        meta_lines: list[str] = []
        if section_key == "clients":
            bulk_count = max(0, int(section.get("bulk_message_count", 0) or 0))
            if bulk_count:
                meta_lines.append(f"عدد الرسائل الجماعية: {bulk_count}")
        if section_key == "finance":
            qr_first_name = str(section.get("qr_first_name", "") or "").strip()
            qr_last_name = str(section.get("qr_last_name", "") or "").strip()
            iban = str(section.get("iban", "") or "").strip()
            if qr_first_name:
                meta_lines.append(f"الاسم الأول: {qr_first_name}")
            if qr_last_name:
                meta_lines.append(f"الاسم الثاني: {qr_last_name}")
            if iban:
                meta_lines.append(f"IBAN: {iban}")
        notes = []
        for value in section.get("notes", []) or []:
            text = str(value or "").strip()
            if text:
                notes.append(text)
        meta_lines.extend(notes)
        sections.append(
            {
                "key": section_key,
                "title": section_title_for(section_key),
                "items": items,
                "meta_lines": meta_lines,
            }
        )
    return sections


def extras_bundle_detail_sections_for_request(request_obj) -> list[dict]:
    return extras_bundle_detail_sections(extras_bundle_payload_for_request(request_obj))


def extras_bundle_requested_service_lines(bundle: dict | None) -> list[str]:
    lines: list[str] = []
    for section in extras_bundle_detail_sections(bundle):
        lines.append(f"{section['title']}:")
        for item in section.get("items", []):
            duration = str(item.get("duration") or "-").strip()
            suffix = f" - المدة: {duration}" if duration and duration != "-" else ""
            lines.append(f"- {item.get('title')}{suffix}")
        for meta_line in section.get("meta_lines", []):
            lines.append(f"- {meta_line}")
    return lines


def _extras_bundle_pricing_preview(bundle: dict) -> dict:
    selected_pairs: list[tuple[str, str]] = []
    for section_key in ("reports", "clients", "finance"):
        section = bundle.get(section_key) if isinstance(bundle.get(section_key), dict) else {}
        for option_key in section.get("options") or []:
            selected_pairs.append((section_key, str(option_key or "").strip()))

    if not selected_pairs:
        return {"lines": [], "currency": "SAR", "subtotal": Decimal("0.00"), "missing_labels": []}

    rules = {
        (rule.section_key, rule.option_key): rule
        for rule in ExtrasBundlePricingRule.objects.filter(
            is_active=True,
            section_key__in=[pair[0] for pair in selected_pairs],
            option_key__in=[pair[1] for pair in selected_pairs],
        )
    }

    currency = ""
    missing_labels: list[str] = []
    line_rows: list[dict] = []
    subtotal = Decimal("0.00")

    for section_key, option_key in selected_pairs:
        rule = rules.get((section_key, option_key))
        label = option_label_for(section_key, option_key)
        if rule is None:
            missing_labels.append(f"{section_title_for(section_key)} - {label}")
            continue

        fee = money_round(Decimal(rule.fee or 0))
        if fee <= Decimal("0.00"):
            missing_labels.append(f"{section_title_for(section_key)} - {label}")
            continue

        if currency and currency != rule.currency:
            raise ValueError("عملة تسعير بنود باقة الخدمات الإضافية يجب أن تكون موحدة داخل الفاتورة الواحدة.")
        if not currency:
            currency = rule.currency or "SAR"

        multiplier = 1
        if rule.apply_year_multiplier and section_key in {"clients", "finance"}:
            section = bundle.get(section_key) if isinstance(bundle.get(section_key), dict) else {}
            multiplier = max(1, int(section.get("subscription_years", 1) or 1))

        amount = money_round(fee * Decimal(multiplier))
        title = label
        duration = _bundle_duration_label(section_key, bundle)
        if rule.apply_year_multiplier and multiplier > 1:
            title = f"{label} ({duration})"
        elif section_key == "reports" and duration != "-":
            title = f"{label} ({duration})"

        line_rows.append(
            {
                "section_key": section_key,
                "option_key": option_key,
                "item_code": f"extras_bundle:{section_key}:{option_key}",
                "title": title,
                "amount": amount,
            }
        )
        subtotal += amount

    return {
        "lines": line_rows,
        "currency": currency or extras_currency(),
        "subtotal": money_round(subtotal),
        "missing_labels": missing_labels,
    }


def create_manual_extras_invoice(
    *,
    request_obj,
    by_user,
    line_items,
    invoice_title: str = "",
    invoice_description: str = "",
):
    """Create an invoice for an extras request using manually entered line items.

    ``line_items`` is a list of dicts, each with ``title`` (str) and ``amount``
    (Decimal-compatible).  At least one item with a positive amount is required.
    If the request already has a paid invoice, this is a no-op that returns the
    existing invoice and latest payment attempt.
    """
    if not line_items:
        raise ValueError("يجب إدخال بند واحد على الأقل لإنشاء الفاتورة.")

    cleaned_lines = []
    subtotal = Decimal("0.00")
    for idx, raw in enumerate(line_items, start=1):
        title = str(raw.get("title") or "").strip()
        if not title:
            raise ValueError(f"عنوان البند رقم {idx} مطلوب.")
        amount = money_round(Decimal(str(raw.get("amount") or "0")))
        if amount <= Decimal("0.00"):
            raise ValueError(f"مبلغ البند «{title}» يجب أن يكون أكبر من صفر.")
        cleaned_lines.append({"title": title, "amount": amount, "sort_order": idx})
        subtotal += amount

    invoice = extras_bundle_invoice_for_request(request_obj)
    if invoice is not None and invoice.is_payment_effective():
        latest_attempt = (
            PaymentAttempt.objects.filter(invoice=invoice)
            .exclude(checkout_url="")
            .order_by("-created_at")
            .first()
        )
        return invoice, latest_attempt

    currency = extras_currency()
    vat_percent = Decimal(str(_platform_config().extras_vat_percent))
    invoice_user = _extras_bundle_invoice_user(request_obj) or request_obj.requester

    resolved_title = str(invoice_title or "").strip()[:160] or "فاتورة طلب خدمات إضافية"
    resolved_description = (
        str(invoice_description or "").strip()[:300]
        or (request_obj.summary or request_obj.code or "طلب خدمات إضافية")[:300]
    )

    if invoice is None:
        invoice = Invoice.objects.create(
            user=invoice_user,
            title=resolved_title,
            description=resolved_description,
            currency=currency,
            subtotal=subtotal,
            vat_percent=vat_percent,
            reference_type=EXTRAS_BUNDLE_INVOICE_REFERENCE_TYPE,
            reference_id=(request_obj.code or str(request_obj.id)),
            status=InvoiceStatus.DRAFT,
        )
    else:
        invoice.user = invoice_user
        invoice.title = resolved_title
        invoice.description = resolved_description
        invoice.currency = currency
        invoice.vat_percent = vat_percent
        invoice.status = InvoiceStatus.DRAFT if not invoice.is_payment_effective() else invoice.status
        invoice.save(update_fields=["user", "title", "description", "currency", "vat_percent", "status", "updated_at"])
        invoice.lines.all().delete()

    InvoiceLineItem.objects.bulk_create(
        [
            InvoiceLineItem(
                invoice=invoice,
                item_code=f"extras_manual:{idx}",
                title=line["title"],
                amount=line["amount"],
                sort_order=line["sort_order"],
            )
            for idx, line in enumerate(cleaned_lines, start=1)
        ]
    )
    invoice.refresh_from_db()
    invoice.mark_pending()
    invoice.save(update_fields=["status", "subtotal", "vat_percent", "vat_amount", "total", "updated_at"])

    latest_attempt = (
        PaymentAttempt.objects.filter(invoice=invoice)
        .exclude(checkout_url="")
        .order_by("-created_at")
        .first()
    )
    if latest_attempt is None:
        from apps.billing.services import init_payment

        latest_attempt = init_payment(
            invoice=invoice,
            provider=_extra_bundle_default_payment_provider(),
            by_user=by_user or request_obj.requester,
            idempotency_key=f"extras-manual-{invoice.id}",
        )

    return invoice, latest_attempt


def ensure_bundle_request_invoice(*, request_obj, by_user):
    bundle = extras_bundle_payload_for_request(request_obj)
    if not bundle:
        raise ValueError("هذا الطلب لا يحتوي على بنود باقة قابلة للتسعير.")

    preview = _extras_bundle_pricing_preview(bundle)
    if preview["missing_labels"]:
        raise ValueError(
            "تعذر إنشاء فاتورة الطلب لأن تسعير البنود التالية غير مضبوط في إدارة الخدمات الإضافية: "
            + "، ".join(preview["missing_labels"])
        )

    invoice = extras_bundle_invoice_for_request(request_obj)
    if invoice is not None and invoice.is_payment_effective():
        latest_attempt = PaymentAttempt.objects.filter(invoice=invoice).exclude(checkout_url="").order_by("-created_at").first()
        return invoice, latest_attempt

    invoice_user = _extras_bundle_invoice_user(request_obj) or request_obj.requester

    if invoice is None:
        invoice = Invoice.objects.create(
            user=invoice_user,
            title="فاتورة طلب خدمات إضافية",
            description=(request_obj.summary or request_obj.code or "طلب خدمات إضافية")[:300],
            currency=preview["currency"],
            subtotal=preview["subtotal"],
            vat_percent=Decimal(str(_platform_config().extras_vat_percent)),
            reference_type=EXTRAS_BUNDLE_INVOICE_REFERENCE_TYPE,
            reference_id=(request_obj.code or str(request_obj.id)),
            status=InvoiceStatus.DRAFT,
        )
    else:
        invoice.user = invoice_user
        invoice.title = "فاتورة طلب خدمات إضافية"
        invoice.description = (request_obj.summary or request_obj.code or "طلب خدمات إضافية")[:300]
        invoice.currency = preview["currency"]
        invoice.vat_percent = Decimal(str(_platform_config().extras_vat_percent))
        invoice.status = InvoiceStatus.DRAFT if not invoice.is_payment_effective() else invoice.status
        invoice.save(update_fields=["user", "title", "description", "currency", "vat_percent", "status", "updated_at"])
        invoice.lines.all().delete()

    InvoiceLineItem.objects.bulk_create(
        [
            InvoiceLineItem(
                invoice=invoice,
                item_code=line["item_code"],
                title=line["title"],
                amount=line["amount"],
                sort_order=index,
            )
            for index, line in enumerate(preview["lines"], start=1)
        ]
    )
    invoice.refresh_from_db()
    invoice.mark_pending()
    invoice.save(update_fields=["status", "subtotal", "vat_percent", "vat_amount", "total", "updated_at"])

    latest_attempt = (
        PaymentAttempt.objects.filter(invoice=invoice)
        .exclude(checkout_url="")
        .order_by("-created_at")
        .first()
    )
    if latest_attempt is None:
        from apps.billing.services import init_payment

        latest_attempt = init_payment(
            invoice=invoice,
            provider=_extra_bundle_default_payment_provider(),
            by_user=by_user or request_obj.requester,
            idempotency_key=f"extras-bundle-{invoice.id}",
        )

    return invoice, latest_attempt


def _get_or_create_bundle_direct_thread(*, user_a, user_b):
    from apps.messaging.models import Thread

    if not user_a or not user_b or user_a.id == user_b.id:
        return None

    user_a_mode = _extras_bundle_thread_mode_for_user(user_a)
    user_b_mode = _extras_bundle_thread_mode_for_user(user_b)

    thread = (
        Thread.objects.filter(
            is_direct=True,
            is_system_thread=True,
            system_thread_key=EXTRAS_BUNDLE_SYSTEM_THREAD_KEY,
        )
        .filter(Q(participant_1=user_a, participant_2=user_b) | Q(participant_1=user_b, participant_2=user_a))
        .order_by("-id")
        .first()
    )
    if thread is not None:
        if thread.participant_1_id == getattr(user_a, "id", None):
            thread.set_participant_modes(
                participant_1_mode=user_a_mode,
                participant_2_mode=user_b_mode,
                save=True,
            )
        elif thread.participant_1_id == getattr(user_b, "id", None):
            thread.set_participant_modes(
                participant_1_mode=user_b_mode,
                participant_2_mode=user_a_mode,
                save=True,
            )
        return thread

    return Thread.objects.create(
        is_direct=True,
        is_system_thread=True,
        system_thread_key=EXTRAS_BUNDLE_SYSTEM_THREAD_KEY,
        context_mode=user_a_mode,
        participant_1=user_a,
        participant_2=user_b,
        participant_1_mode=user_a_mode,
        participant_2_mode=user_b_mode,
    )


def _send_bundle_system_message(*, request_obj, sender, recipient, body: str):
    from apps.messaging.models import create_system_message
    from apps.messaging.views import _unarchive_for_participants

    thread = _get_or_create_bundle_direct_thread(user_a=sender, user_b=recipient)
    if thread is None:
        return None

    create_system_message(
        thread=thread,
        sender=sender,
        body=(body or "")[:2000],
        sender_team_name="فريق إدارة الخدمات الإضافية",
        system_thread_key=EXTRAS_BUNDLE_SYSTEM_THREAD_KEY,
        reply_restricted_to=recipient,
        reply_restriction_reason="الردود مغلقة على الرسائل الآلية من فريق إدارة الخدمات الإضافية.",
        created_at=timezone.now(),
    )
    _unarchive_for_participants(thread)
    return thread


def notify_bundle_payment_requested(*, request_obj, actor, invoice: Invoice, checkout_url: str) -> None:
    invoice_owner = invoice.user
    request_code = (request_obj.code or str(request_obj.id)).strip()
    bundle = extras_bundle_payload_for_request(request_obj)
    payment_access_url = extras_bundle_payment_access_url(
        request_obj=request_obj,
        invoice=invoice,
        checkout_url=checkout_url,
    )
    message_lines = [
        f"رسالة آلية من فريق إدارة الخدمات الإضافية بخصوص الطلب {request_code}.",
        "تمت مراجعة طلبك والبدء في معالجته.",
        "الخدمات المطلوبة:",
        *extras_bundle_requested_service_lines(bundle),
        f"رقم الفاتورة: {invoice.code}",
        f"إجمالي الفاتورة: {money_round(Decimal(invoice.total or 0))} {invoice.currency}",
        f"للدفع اضغط على الرابط التالي: {payment_access_url or ''}",
    ]
    message_body = "\n".join(message_lines)
    threads_by_recipient_id: dict[int, object] = {}
    for recipient in _extras_bundle_message_recipients(request_obj=request_obj, invoice=invoice):
        sender = _resolve_bundle_message_sender(
            request_obj=request_obj,
            actor=actor,
            recipient=recipient,
        )
        if sender is None:
            continue
        try:
            thread = _send_bundle_system_message(
                request_obj=request_obj,
                sender=sender,
                recipient=recipient,
                body=message_body,
            )
        except Exception:
            thread = None
        if thread is not None and getattr(recipient, "id", None):
            threads_by_recipient_id[int(recipient.id)] = thread

    thread = threads_by_recipient_id.get(getattr(invoice_owner, "id", 0))

    try:
        from apps.notifications.models import EventType
        from apps.notifications.services import create_notification

        create_notification(
            user=invoice_owner,
            title="استكمال دفع طلب الخدمات الإضافية",
            body=f"تمت مراجعة طلب الخدمات الإضافية ({request_code}) وإصدار فاتورة بانتظار الدفع.",
            kind="request_status_change",
            url=str(payment_access_url or "").strip() or (f"/chat/{thread.id}/" if thread is not None else "/additional-services/"),
            actor=actor,
            event_type=EventType.STATUS_CHANGED,
            request_id=request_obj.id,
            meta={
                "extras_request_id": request_obj.id,
                "extras_request_code": request_code,
                "invoice_id": invoice.id,
                "invoice_code": invoice.code,
                "thread_id": getattr(thread, "id", None),
                "status": request_obj.status,
            },
            pref_key="request_status_change",
            audience_mode="provider",
        )
    except Exception:
        pass


def notify_bundle_completed(*, request_obj, actor) -> None:
    primary_user = _extras_bundle_invoice_user(request_obj) or request_obj.requester
    request_code = (request_obj.code or str(request_obj.id)).strip()
    bundle = extras_bundle_payload_for_request(request_obj)
    service_lines = extras_bundle_requested_service_lines(bundle)
    portal_url = extras_portal_reports_url() if hasattr(getattr(primary_user, "provider_profile", None), "id") else ""
    message_lines = [
        f"رسالة آلية من فريق إدارة الخدمات الإضافية بخصوص الطلب {request_code}.",
        "تهانينا، اكتملت عملية تفعيل الخدمات الإضافية المطلوبة بنجاح.",
        "الخدمات المفعلة:",
        *service_lines,
    ]
    if portal_url:
        message_lines.extend(
            [
                "تم تفعيل صفحة التقارير الخاصة بك داخل بوابة الخدمات الإضافية.",
                "رابط الدخول المباشر:",
                portal_url,
                "يمكنك تسجيل الدخول باستخدام حساب مزود الخدمة الحالي ثم إكمال التحقق برمز الجوال.",
            ]
        )

    message_body = "\n".join(message_lines)
    threads_by_recipient_id: dict[int, object] = {}
    for recipient in _extras_bundle_message_recipients(request_obj=request_obj):
        sender = _resolve_bundle_message_sender(
            request_obj=request_obj,
            actor=actor,
            recipient=recipient,
        )
        if sender is None:
            continue
        try:
            thread = _send_bundle_system_message(
                request_obj=request_obj,
                sender=sender,
                recipient=recipient,
                body=message_body,
            )
        except Exception:
            thread = None
        if thread is not None and getattr(recipient, "id", None):
            threads_by_recipient_id[int(recipient.id)] = thread

    thread = threads_by_recipient_id.get(getattr(primary_user, "id", 0))

    try:
        from apps.notifications.models import EventType
        from apps.notifications.services import create_notification

        create_notification(
            user=primary_user,
            title="اكتمل تفعيل الخدمات الإضافية",
            body=f"تهانينا، تم تفعيل طلب الخدمات الإضافية ({request_code}) بنجاح.",
            kind="request_status_change",
            url=portal_url or (f"/chat/{thread.id}/" if thread is not None else "/additional-services/"),
            actor=actor,
            event_type=EventType.STATUS_CHANGED,
            request_id=request_obj.id,
            meta={
                "extras_request_id": request_obj.id,
                "extras_request_code": request_code,
                "thread_id": getattr(thread, "id", None),
                "status": getattr(request_obj, "status", ""),
                "completed": True,
                "portal_url": portal_url,
            },
            pref_key="request_status_change",
            audience_mode="provider",
        )
    except Exception:
        pass


def _persist_bundle_request_metadata(*, request_obj, metadata: dict, changed_by=None) -> None:
    from apps.unified_requests.services import upsert_unified_request

    upsert_unified_request(
        request_type=getattr(request_obj, "request_type", "extras"),
        requester=request_obj.requester,
        source_app=request_obj.source_app,
        source_model=request_obj.source_model,
        source_object_id=request_obj.source_object_id,
        status=request_obj.status,
        priority=request_obj.priority or "normal",
        summary=request_obj.summary,
        metadata=metadata,
        assigned_team_code=request_obj.assigned_team_code,
        assigned_team_name=request_obj.assigned_team_name,
        assigned_user=request_obj.assigned_user,
        changed_by=changed_by or request_obj.assigned_user or request_obj.requester,
    )


def sync_bundle_request_payment_state_from_invoice(*, invoice: Invoice) -> None:
    if invoice.reference_type != EXTRAS_BUNDLE_INVOICE_REFERENCE_TYPE:
        return

    from apps.unified_requests.models import UnifiedRequest, UnifiedRequestType

    reference_code = str(invoice.reference_id or "").strip()
    if not reference_code:
        return

    request_obj = (
        UnifiedRequest.objects.select_related("requester", "assigned_user", "metadata_record")
        .filter(request_type=UnifiedRequestType.EXTRAS, code=reference_code)
        .first()
    )
    if request_obj is None:
        return

    metadata = _extras_bundle_existing_metadata(request_obj)
    metadata["invoice_id"] = invoice.id
    metadata["invoice_code"] = invoice.code
    metadata["invoice_status"] = invoice.status
    metadata["payment_effective"] = bool(invoice.is_payment_effective())
    metadata["payment_confirmed_at"] = invoice.payment_confirmed_at.isoformat() if invoice.payment_confirmed_at else None

    latest_attempt = (
        PaymentAttempt.objects.filter(invoice=invoice)
        .exclude(checkout_url="")
        .order_by("-created_at")
        .first()
    )
    if latest_attempt is not None:
        metadata["checkout_url"] = extras_bundle_payment_access_url(
            request_obj=request_obj,
            invoice=invoice,
            checkout_url=latest_attempt.checkout_url,
        )
        metadata["payment_attempt_id"] = str(latest_attempt.id)

    _persist_bundle_request_metadata(request_obj=request_obj, metadata=metadata, changed_by=request_obj.assigned_user or request_obj.requester)
