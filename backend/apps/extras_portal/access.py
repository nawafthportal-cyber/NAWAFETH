from __future__ import annotations

from datetime import datetime

from django.db.models import Q
from django.utils import timezone

from apps.extras.option_catalog import EXTRAS_CLIENT_OPTION_ALIASES
from apps.extras.services import (
    _extras_bundle_section_access_deadline,
    extras_bundle_invoice_for_request,
    extras_bundle_payload_for_request,
)
from apps.providers.models import ProviderProfile
from apps.unified_requests.models import UnifiedRequest, UnifiedRequestType


PORTAL_SECTION_REPORTS = "reports"
PORTAL_SECTION_CLIENTS = "clients"
PORTAL_SECTION_FINANCE = "finance"


def provider_has_active_portal_option(provider: ProviderProfile | None, section_key: str, option_key: str) -> bool:
    if provider is None:
        return False
    normalized_section = str(section_key or "").strip().lower()
    normalized_option = str(option_key or "").strip()
    if not normalized_section or not normalized_option:
        return False

    for context in _paid_bundle_contexts(provider):
        if not _section_context_is_active(context, normalized_section):
            continue
        bundle = context.get("bundle") if isinstance(context.get("bundle"), dict) else {}
        section = bundle.get(normalized_section) if isinstance(bundle.get(normalized_section), dict) else {}
        option_keys = _section_option_keys(normalized_section, list(section.get("options") or []))
        if normalized_option in option_keys:
            return True
    return False


def provider_has_bank_qr_registration(provider: ProviderProfile | None) -> bool:
    return provider_has_active_portal_option(provider, PORTAL_SECTION_FINANCE, "bank_qr_registration")


def _provider_identifiers(provider: ProviderProfile) -> list[str]:
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


def _bundle_requests_queryset(provider: ProviderProfile):
    identifiers = _provider_identifiers(provider)
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


def _paid_bundle_contexts(provider: ProviderProfile) -> list[dict[str, object]]:
    contexts: list[dict[str, object]] = []
    for request_obj in _bundle_requests_queryset(provider):
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


def _section_context_is_active(bundle_context: dict[str, object], section_key: str, *, now=None) -> bool:
    if not isinstance(bundle_context, dict):
        return False
    bundle = bundle_context.get("bundle") if isinstance(bundle_context.get("bundle"), dict) else {}
    section_payload = bundle.get(section_key) if isinstance(bundle.get(section_key), dict) else {}
    option_keys = _section_option_keys(section_key, list(section_payload.get("options") or []))
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


def _section_option_keys(section_key: str, raw_values: list[object]) -> list[str]:
    aliases = EXTRAS_CLIENT_OPTION_ALIASES if section_key == PORTAL_SECTION_CLIENTS else {}
    option_keys: list[str] = []
    for raw_key in raw_values:
        key = str(raw_key or "").strip()
        if not key:
            continue
        key = aliases.get(key, key)
        if key not in option_keys:
            option_keys.append(key)
    return option_keys
