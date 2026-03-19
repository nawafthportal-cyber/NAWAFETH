"""
طبقة التسعير المركزية — Phase 5.

جميع الدوال تُرجع dict موحد بالشكل:
{
    "subtotal": Decimal,
    "vat_percent": Decimal,
    "vat_amount": Decimal,
    "total": Decimal,
    "currency": str,
    "meta": dict,
}

القاعدة: DB first → fallback للسلوك الحالي.
"""
from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP
from typing import Any


def _money(val) -> Decimal:
    return (Decimal(str(val)) if val else Decimal("0.00")).quantize(
        Decimal("0.01"), rounding=ROUND_HALF_UP,
    )


def _platform_config():
    from apps.core.models import PlatformConfig
    return PlatformConfig.load()


def apply_vat(subtotal: Decimal, vat_percent: Decimal) -> dict[str, Decimal]:
    """حساب الضريبة وإرجاع subtotal / vat_amount / total."""
    st = _money(subtotal)
    vp = Decimal(str(vat_percent))
    va = _money((st * vp) / Decimal("100"))
    return {"subtotal": st, "vat_percent": vp, "vat_amount": va, "total": _money(st + va)}


def _pricing_result(
    subtotal: Decimal,
    vat_percent: Decimal,
    currency: str = "SAR",
    meta: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """بناء نتيجة التسعير الموحدة."""
    vat = apply_vat(subtotal, vat_percent)
    return {
        **vat,
        "currency": currency or "SAR",
        "meta": meta or {},
    }


# ─────────────────────────────────────────────
# Extras pricing
# ─────────────────────────────────────────────

def get_extras_catalog() -> dict[str, dict[str, Any]]:
    """
    كتالوج الإضافات: DB first → fallback settings.EXTRA_SKUS.
    """
    from apps.extras.models import ServiceCatalog
    from django.conf import settings

    db_items = list(ServiceCatalog.objects.filter(is_active=True).order_by("sort_order", "sku"))
    if db_items:
        return {
            item.sku: {
                "title": item.title,
                "price": item.price,
                "currency": item.currency,
                "source": "db",
            }
            for item in db_items
        }
    # fallback
    raw = getattr(settings, "EXTRA_SKUS", {}) or {}
    return {
        sku: {**info, "source": "settings"}
        for sku, info in raw.items()
    }


def calculate_extras_price(sku: str) -> dict[str, Any]:
    """
    تسعير خدمة إضافية واحدة.
    """
    catalog = get_extras_catalog()
    if sku not in catalog:
        raise ValueError("SKU غير موجود.")
    info = catalog[sku]
    price = Decimal(str(info.get("price", 0)))
    if price <= 0:
        raise ValueError("سعر الإضافة غير صحيح.")

    cfg = _platform_config()
    vat_pct = Decimal(str(cfg.extras_vat_percent))
    currency = str(info.get("currency") or cfg.extras_currency or "SAR")

    return _pricing_result(
        subtotal=price,
        vat_percent=vat_pct,
        currency=currency,
        meta={
            "sku": sku,
            "title": info.get("title", sku),
            "source": info.get("source", "unknown"),
        },
    )


# ─────────────────────────────────────────────
# Verification pricing
# ─────────────────────────────────────────────

def calculate_verification_price(badge_type: str) -> dict[str, Any]:
    """
    تسعير التوثيق: VerificationPricingRule → SubscriptionPlan fallback.
    التوثيق tax-inclusive (vat_percent=0).
    """
    from apps.verification.models import VerificationPricingRule, VerificationBadgeType

    # DB first
    try:
        rule = VerificationPricingRule.objects.get(badge_type=badge_type, is_active=True)
        fee = Decimal(str(rule.fee))
        currency = rule.currency or "SAR"
        source = "db"
    except VerificationPricingRule.DoesNotExist:
        # fallback to canonical plan
        from apps.verification.services import _fee_for_badge, _get_verification_currency
        fee = _fee_for_badge(badge_type)
        currency = _get_verification_currency() or "SAR"
        source = "plan_fallback"

    bt_label = dict(VerificationBadgeType.choices).get(badge_type, badge_type)
    return _pricing_result(
        subtotal=fee,
        vat_percent=Decimal("0.00"),  # tax-inclusive
        currency=currency,
        meta={
            "badge_type": badge_type,
            "badge_label": bt_label,
            "source": source,
            "tax_policy": "inclusive",
        },
    )


# ─────────────────────────────────────────────
# Promo pricing — delegation فقط
# ─────────────────────────────────────────────

def calculate_promo_price(*, promo_request) -> dict[str, Any]:
    """
    Delegation إلى المنطق الحالي في promo.
    لا نعيد كتابة المنطق — نلفّه فقط بصيغة موحدة.
    promo_request: PromoRequest instance
    """
    from apps.promo.services import calc_promo_quote

    result = calc_promo_quote(pr=promo_request)
    subtotal = Decimal(str(result.get("subtotal", 0)))
    vat_pct = Decimal(str(_platform_config().promo_vat_percent))

    return _pricing_result(
        subtotal=subtotal,
        vat_percent=vat_pct,
        currency="SAR",
        meta={
            "ad_type": getattr(promo_request, "ad_type", ""),
            "days": result.get("days", 0),
            "source": "promo_engine",
        },
    )


# ─────────────────────────────────────────────
# Utility
# ─────────────────────────────────────────────

def get_vat_percent(domain: str = "default") -> Decimal:
    """
    نسبة الضريبة حسب المجال.
    domain: 'default' | 'extras' | 'promo' | 'verification'
    """
    cfg = _platform_config()
    if domain == "extras":
        return Decimal(str(cfg.extras_vat_percent))
    if domain == "promo":
        return Decimal(str(cfg.promo_vat_percent))
    if domain == "verification":
        return Decimal("0.00")
    return Decimal(str(cfg.vat_percent))
